//
//  FrameRateRangeTests.swift
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
            DisplayLinkFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        )
    }

    func testUnionNeverSlowsAnyCaller() {
        let low = DisplayLinkFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        let high = DisplayLinkFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        XCTAssertEqual(
            low.union(high),
            DisplayLinkFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        )
        XCTAssertEqual(low.union(high), high.union(low))
        XCTAssertEqual(low.union(low), low)
    }

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
        // All zero is the system default and passes through untouched.
        XCTAssertEqual(
            DisplayLinkFrameRateRange(minimum: 0, maximum: 0, preferred: 0).normalized,
            DisplayLinkFrameRateRange(minimum: 0, maximum: 0, preferred: 0)
        )
        // "No floor" becomes the smallest rate Core Animation accepts.
        XCTAssertEqual(
            DisplayLinkFrameRateRange(minimum: 0, maximum: 120, preferred: 120).normalized,
            DisplayLinkFrameRateRange(minimum: 1, maximum: 120, preferred: 120)
        )
        XCTAssertEqual(DisplayLinkFrameRateRange.default.normalized, .default)
    }

    func testNormalizedSatisfiesCoreAnimationInvariants() {
        for range in Self.edgeCaseRanges {
            let normalized = range.normalized
            XCTAssertEqual(normalized.normalized, normalized, "not idempotent for \(range)")
            if normalized == .init(minimum: 0, maximum: 0, preferred: 0) { continue }
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

    /// Every edge case goes through a live `DisplayLink` and the shared
    /// link keeps ticking.
    func testLiveLinkTicksWithEveryEdgeCaseRange() {
        let recorder = TickRecorder()
        let link = DisplayLink()
        link.delegatingObject(recorder)
        for range in Self.edgeCaseRanges {
            link.preferredFrameRateRange = range
            waitForTicks(on: recorder)
        }
        withExtendedLifetime(link) {}
    }

    func testSharedRangeIsDefaultWithoutDrivers() {
        XCTAssertEqual(helper.resolvedFrameRateRange(), .default)
    }

    /// Requests are normalized before they are combined, so one caller's
    /// out-of-range preferred cannot lift the shared rate.
    func testSharedRangeNormalizesEachRequestFirst() {
        let a = DisplayLink(preferredFrameRateRange: .init(minimum: 10, maximum: 30))
        let b = DisplayLink(preferredFrameRateRange: .init(minimum: 10, maximum: 60, preferred: 30))
        XCTAssertEqual(
            helper.resolvedFrameRateRange(),
            DisplayLinkFrameRateRange(minimum: 10, maximum: 60, preferred: 30)
        )
        withExtendedLifetime((a, b)) {}
    }

    func testSharedRangeFollowsChangesAndReleases() {
        let low = DisplayLinkFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        let high = DisplayLinkFrameRateRange(minimum: 80, maximum: 120, preferred: 120)

        let a = DisplayLink(preferredFrameRateRange: low)
        XCTAssertEqual(a.preferredFrameRateRange, low)
        XCTAssertEqual(helper.resolvedFrameRateRange(), low)

        var b: DisplayLink? = DisplayLink(preferredFrameRateRange: low)
        b?.preferredFrameRateRange = high
        XCTAssertEqual(b?.preferredFrameRateRange, high)
        XCTAssertEqual(helper.resolvedFrameRateRange(), low.union(high))

        b = nil
        XCTAssertEqual(helper.resolvedFrameRateRange(), low, "a released link still votes")

        a.preferredFrameRateRange = .default
        XCTAssertEqual(helper.resolvedFrameRateRange(), .default)
        withExtendedLifetime(a) {}
    }
}
