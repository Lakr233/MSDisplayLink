//
//  DisplayLinkTests.swift
//  MSDisplayLink
//

@testable import MSDisplayLink
import QuartzCore
import XCTest
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

final class DisplayLinkTests: XCTestCase {
    private final class Recorder: DisplayLinkDelegate, @unchecked Sendable {
        let expectation: XCTestExpectation
        private(set) var calledOffMainThread = false

        init(_ expectation: XCTestExpectation) {
            self.expectation = expectation
        }

        func synchronization(context _: DisplayLinkCallbackContext) {
            if !Thread.isMainThread { calledOffMainThread = true }
            expectation.fulfill()
        }
    }

    func testDelegateIsCalledOnMainThread() {
        let ticked = expectation(description: "ticked")
        ticked.assertForOverFulfill = false
        let recorder = Recorder(ticked)
        let link = DisplayLink()
        link.delegatingObject(recorder)

        wait(for: [ticked], timeout: 5)
        XCTAssertFalse(recorder.calledOffMainThread)
        withExtendedLifetime(link) {}
    }

    func testLinkCreatedAndReleasedOffMainThread() {
        let ticked = expectation(description: "ticked")
        ticked.assertForOverFulfill = false
        let recorder = Recorder(ticked)

        let created = expectation(description: "created")
        nonisolated(unsafe) var link: DisplayLink?
        DispatchQueue.global().async {
            link = DisplayLink()
            link?.delegatingObject(recorder)
            created.fulfill()
        }
        wait(for: [created, ticked], timeout: 5)

        let released = expectation(description: "released")
        DispatchQueue.global().async {
            link = nil
            released.fulfill()
        }
        wait(for: [released], timeout: 5)
        // Let any hop back to the main thread run.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(DisplayLinkDriverHelper.shared.hasLiveDrivers)
    }

    func testRangeWithPreferredAboveMaximumStillTicks() {
        let ticked = expectation(description: "ticked")
        ticked.assertForOverFulfill = false
        let recorder = Recorder(ticked)
        let link = DisplayLink(preferredFrameRateRange: .init(maximum: 60))
        link.delegatingObject(recorder)

        wait(for: [ticked], timeout: 5)
        withExtendedLifetime(link) {}
    }

    private static let edgeCaseRanges: [DisplayLinkFrameRateRange] = [
        .default,
        .init(maximum: 60),
        .init(maximum: 30),
        .init(minimum: 80, maximum: 30, preferred: 10),
        .init(minimum: 0, maximum: 120, preferred: 120),
        .init(minimum: 0, maximum: 120, preferred: 0),
        .init(minimum: -5, maximum: 120, preferred: 120),
        .init(minimum: .nan, maximum: 120, preferred: 120),
        .init(minimum: 60, maximum: 120, preferred: .nan),
        .init(minimum: 30, maximum: .infinity, preferred: .infinity),
        .init(minimum: 0, maximum: 0, preferred: 0),
        .init(minimum: 0, maximum: -1, preferred: 0),
    ]

    func testNormalizedHonorsTheRequest() {
        XCTAssertEqual(
            DisplayLinkFrameRateRange(maximum: 60).normalized,
            DisplayLinkFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        )
        // The maximum is a cap: it lowers the minimum rather than being raised.
        XCTAssertEqual(
            DisplayLinkFrameRateRange(maximum: 30).normalized,
            DisplayLinkFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        )
        // 0 keeps meaning "no preference".
        XCTAssertEqual(
            DisplayLinkFrameRateRange(minimum: 30, maximum: 60, preferred: 0).normalized,
            DisplayLinkFrameRateRange(minimum: 30, maximum: 60, preferred: 0)
        )
        XCTAssertEqual(DisplayLinkFrameRateRange.default.normalized, .default)
        for range in Self.edgeCaseRanges {
            let normalized = range.normalized
            XCTAssertEqual(normalized.normalized, normalized, "not idempotent for \(range)")
            let isSystemDefault = normalized == .init(minimum: 0, maximum: 0, preferred: 0)
            if !isSystemDefault {
                XCTAssertGreaterThan(normalized.minimum, 0, "\(range)")
                XCTAssertLessThanOrEqual(normalized.minimum, normalized.maximum, "\(range)")
                XCTAssertTrue(normalized.maximum.isFinite, "\(range)")
                XCTAssertTrue(
                    normalized.preferred == 0
                        || (normalized.minimum ... normalized.maximum).contains(normalized.preferred),
                    "\(range)"
                )
            }
        }
    }

    /// Requests are normalized before they are combined, so one caller's
    /// out-of-range preferred cannot lift the shared rate.
    @MainActor
    func testSharedRangeNormalizesEachRequestFirst() {
        let a = DisplayLink(preferredFrameRateRange: .init(minimum: 10, maximum: 30))
        let b = DisplayLink(preferredFrameRateRange: .init(minimum: 10, maximum: 60, preferred: 30))
        XCTAssertEqual(
            DisplayLinkDriverHelper.shared.resolvedFrameRateRange(),
            DisplayLinkFrameRateRange(minimum: 10, maximum: 60, preferred: 30)
        )
        withExtendedLifetime((a, b)) {}
    }

    #if canImport(UIKit) || canImport(AppKit)
        private final class Target: NSObject {
            @objc func tick(_: Any) {}
        }

        /// Hands every normalized edge case to a real `CADisplayLink`, which
        /// raises `NSInvalidArgumentException` on a range it rejects.
        @MainActor
        func testNormalizedRangesAreAcceptedByCoreAnimation() throws {
            let target = Target()
            #if canImport(UIKit)
                let link = CADisplayLink(target: target, selector: #selector(Target.tick(_:)))
            #else
                guard #available(macOS 14.0, *) else { throw XCTSkip("CADisplayLink needs macOS 14") }
                guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
                let link = screen.displayLink(target: target, selector: #selector(Target.tick(_:)))
            #endif
            defer { link.invalidate() }
            guard #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, *) else {
                throw XCTSkip("CAFrameRateRange needs iOS 15")
            }
            for range in Self.edgeCaseRanges {
                let normalized = range.normalized
                link.preferredFrameRateRange = CAFrameRateRange(
                    minimum: normalized.minimum,
                    maximum: normalized.maximum,
                    preferred: normalized.preferred
                )
            }
        }
    #endif

    @MainActor
    func testModifierContextTicksOnlyWhileStarted() {
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        let context = DisplayLinkModifierContext()
        context.update(scheduleToMainThread: true, preferredFrameRateRange: .default) { _ in
            counter.value += 1
        }

        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(counter.value, 0, "ticked before start()")

        context.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertGreaterThan(counter.value, 0)

        context.stop()
        // Drain anything the link already queued for this runloop turn.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let stopped = counter.value
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(counter.value, stopped, "ticked after stop()")
    }

    func testUnionNeverSlowsAnyCaller() {
        let low = DisplayLinkFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        let high = DisplayLinkFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        XCTAssertEqual(
            low.union(high),
            DisplayLinkFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        )
    }
}
