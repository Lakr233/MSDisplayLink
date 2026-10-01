//
//  FrameRateRangeTests.swift
//  DisplayLink
//

@testable import DisplayLink
import QuartzCore
import XCTest
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
final class FrameRateRangeTests: DisplayLinkTestCase {
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
        .init(minimum: 60, maximum: .nan, preferred: 90),
        .init(minimum: 30, maximum: .infinity, preferred: .infinity),
        .init(minimum: 30, maximum: 60, preferred: -.infinity),
        .init(minimum: 0, maximum: 0, preferred: 0),
        .init(minimum: 0, maximum: -1, preferred: 0),
        .init(minimum: 1000, maximum: 2000, preferred: 1500),
    ]

    func testDefaultIsFullProMotion() {
        XCTAssertEqual(
            DisplayLinkFrameRateRange.default,
            DisplayLinkFrameRateRange(minimum: 60, maximum: 120, preferred: 120),
        )
    }

    func testNormalizedHonorsTheRequest() {
        XCTAssertEqual(
            DisplayLinkFrameRateRange(maximum: 60).normalized,
            DisplayLinkFrameRateRange(minimum: 60, maximum: 60, preferred: 60),
        )
        // The maximum is a cap: it lowers the minimum rather than being raised.
        XCTAssertEqual(
            DisplayLinkFrameRateRange(maximum: 30).normalized,
            DisplayLinkFrameRateRange(minimum: 30, maximum: 30, preferred: 30),
        )
        // 0 keeps meaning "no preference".
        XCTAssertEqual(
            DisplayLinkFrameRateRange(minimum: 30, maximum: 60, preferred: 0).normalized,
            DisplayLinkFrameRateRange(minimum: 30, maximum: 60, preferred: 0),
        )
        // All zero is the system default and passes through untouched.
        XCTAssertEqual(
            DisplayLinkFrameRateRange(minimum: 0, maximum: 0, preferred: 0).normalized,
            DisplayLinkFrameRateRange(minimum: 0, maximum: 0, preferred: 0),
        )
        // "No floor" becomes the smallest rate Core Animation accepts.
        XCTAssertEqual(
            DisplayLinkFrameRateRange(minimum: 0, maximum: 120, preferred: 120).normalized,
            DisplayLinkFrameRateRange(minimum: 1, maximum: 120, preferred: 120),
        )
        XCTAssertEqual(DisplayLinkFrameRateRange.default.normalized, .default)
    }

    func testNormalizedSatisfiesCoreAnimationInvariants() {
        for range in Self.edgeCaseRanges {
            let normalized = range.normalized
            XCTAssertEqual(normalized.normalized, normalized, "not idempotent for \(range)")
            if normalized == .init(minimum: 0, maximum: 0, preferred: 0) {
                continue
            }
            XCTAssertGreaterThan(normalized.minimum, 0, "\(range)")
            XCTAssertLessThanOrEqual(normalized.minimum, normalized.maximum, "\(range)")
            XCTAssertTrue(normalized.maximum.isFinite, "\(range)")
            XCTAssertTrue(
                normalized.preferred == 0
                    || (normalized.minimum ... normalized.maximum).contains(normalized.preferred),
                "\(range)",
            )
        }
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
            for range in Self.edgeCaseRanges {
                let normalized = range.normalized
                link.preferredFrameRateRange = CAFrameRateRange(
                    minimum: normalized.minimum,
                    maximum: normalized.maximum,
                    preferred: normalized.preferred,
                )
            }
        }
    #endif

    /// Every edge case goes through a live link, which keeps ticking.
    func testLiveLinkTicksWithEveryEdgeCaseRange() {
        let recorder = FrameRecorder()
        let link = DisplayLink()
        link.delegate = recorder
        for range in Self.edgeCaseRanges {
            link.preferredFrameRateRange = range
            waitForFrames(on: recorder)
        }
    }

    func testSameRateOnOneDisplaySharesASystemLink() {
        // Equal once normalized: both ask for exactly 60.
        let a = DisplayLink(preferredFrameRateRange: .init(maximum: 60))
        let b = DisplayLink(preferredFrameRateRange: .init(minimum: 60, maximum: 60, preferred: 60))
        XCTAssertTrue(a.subscription === b.subscription)
        XCTAssertEqual(SharedDisplayLink.links.count, 1)
    }

    func testDifferentRatesGetTheirOwnSystemLinks() {
        let fast = DisplayLink()
        let slow = DisplayLink(preferredFrameRateRange: .init(minimum: 30, maximum: 30, preferred: 30))
        XCTAssertFalse(fast.subscription === slow.subscription)
        XCTAssertEqual(SharedDisplayLink.links.count, 2)
        XCTAssertEqual(slow.subscription?.key.frameRateRange, .init(minimum: 30, maximum: 30, preferred: 30))
    }

    func testChangingTheRateMovesOnlyThatLink() {
        let a = DisplayLink()
        let b = DisplayLink()
        let shared = a.subscription

        b.preferredFrameRateRange = .init(minimum: 30, maximum: 30, preferred: 30)
        XCTAssertTrue(a.subscription === shared)
        XCTAssertFalse(b.subscription === shared)
        XCTAssertEqual(shared?.subscriberCount, 1)

        b.preferredFrameRateRange = .default
        XCTAssertTrue(b.subscription === shared)
        XCTAssertEqual(SharedDisplayLink.links.count, 1, "the emptied 30 fps link is released")
    }

    /// A link asking for 30 gets 30, with each frame lasting a 30th of a
    /// second, whatever rate other links keep the display at.
    func testSlowLinkReceivesItsOwnRate() throws {
        let fastRecorder = FrameRecorder()
        let slowRecorder = FrameRecorder()
        let fast = DisplayLink()
        let slow = DisplayLink(preferredFrameRateRange: .init(minimum: 30, maximum: 30, preferred: 30))
        fast.delegate = fastRecorder
        slow.delegate = slowRecorder
        waitForFrames(12, on: slowRecorder)

        let intervals = zip(slowRecorder.frames, slowRecorder.frames.dropFirst()).map { $1.timestamp - $0.timestamp }
        let median = intervals.sorted()[intervals.count / 2]
        XCTAssertEqual(median, 1.0 / 30, accuracy: 0.004)
        XCTAssertEqual(try XCTUnwrap(slowRecorder.frames.last?.duration), 1.0 / 30, accuracy: 0.004)
        XCTAssertGreaterThan(fastRecorder.count, slowRecorder.count, "the fast link must not be slowed")
    }
}
