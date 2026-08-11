//
//  DisplayLinkFrameRateRange.swift
//  MSDisplayLink
//
//  Created by 秋星桥 on 2026/8/11.
//

import Foundation

/// The frame rate a `DisplayLink` asks the display for, expressed in frames
/// per second. Platform-neutral on purpose: UIKit platforms hand it to
/// `CADisplayLink.preferredFrameRateRange` (iOS 15+), the CVDisplayLink
/// path on macOS always runs at the display's own rate and ignores it.
///
/// The library defaults to the full ProMotion range rather than the
/// system's 60 fps fallback — a display link exists to animate, and an
/// animation library that silently ticks at half the display's rate is how
/// 120 Hz scroll and 60 Hz animation end up mixed on one screen.
///
/// Note that a range is a request, not a guarantee: the system still clamps
/// it to what the hardware supports, and on iPhone the app must also declare
/// `CADisableMinimumFrameDurationOnPhone` in its Info.plist before any rate
/// above 60 is honored.
public struct DisplayLinkFrameRateRange: Sendable, Equatable {
    /// The slowest rate the caller can tolerate.
    public var minimum: Float
    /// The fastest rate worth ticking at.
    public var maximum: Float
    /// The rate the caller actually wants.
    public var preferred: Float

    public init(minimum: Float = 60, maximum: Float = 120, preferred: Float = 120) {
        self.minimum = minimum
        self.maximum = maximum
        self.preferred = preferred
    }

    /// Full ProMotion: 60 minimum, 120 preferred.
    public static let `default` = DisplayLinkFrameRateRange()

    /// The union of two requests — never slower than either caller asked
    /// for. This is what the shared display link applies when multiple
    /// `DisplayLink` instances disagree.
    public func union(_ other: DisplayLinkFrameRateRange) -> DisplayLinkFrameRateRange {
        DisplayLinkFrameRateRange(
            minimum: Swift.min(minimum, other.minimum),
            maximum: Swift.max(maximum, other.maximum),
            preferred: Swift.max(preferred, other.preferred)
        )
    }
}
