import Foundation

#if canImport(UIKit)
    import UIKit

    typealias DisplayLinkDriverHelper = CADisplayLinkDriverHelper

    class CADisplayLinkDriverHelper: DisplayLinkDriverHelperBase {
        nonisolated(unsafe) static let shared = CADisplayLinkDriverHelper()

        private var displayLink: CADisplayLink?

        override private init() {
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidEnterBackground(_:)),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationWillEnterForeground(_:)),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override func startDisplayLink() {
            assert(Thread.isMainThread)
            guard displayLink == nil else { return }
            displayLink = CADisplayLink(target: self, selector: #selector(displayLinkCallback(_:)))
            applyFrameRateRange()
            displayLink?.add(to: .main, forMode: .common)
        }

        override func stopDisplayLink() {
            assert(Thread.isMainThread)
            displayLink?.invalidate()
            displayLink = nil
        }

        override func frameRatePreferencesDidChange() {
            applyFrameRateRange()
        }

        /// Without this a CADisplayLink runs at the system's 60 fps default
        /// on ProMotion displays, whatever the display can do — mixing a
        /// 60 Hz animation into 120 Hz native scrolling. (On iPhone the
        /// host app must also set `CADisableMinimumFrameDurationOnPhone`.)
        private func applyFrameRateRange() {
            guard let displayLink else { return }
            let range = resolvedFrameRateRange()
            if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, *) {
                displayLink.preferredFrameRateRange = CAFrameRateRange(
                    minimum: range.minimum,
                    maximum: range.maximum,
                    preferred: range.preferred
                )
            } else {
                displayLink.preferredFramesPerSecond = Int(range.preferred.rounded())
            }
        }

        @objc private func displayLinkCallback(_ displayLink: CADisplayLink) {
            let context = DisplayLinkCallbackContext(
                duration: displayLink.duration,
                timestamp: displayLink.timestamp,
                targetTimestamp: displayLink.targetTimestamp
            )
            autoreleasepool { dispatchUpdate(context: context) }
        }

        @objc private func applicationDidEnterBackground(_: Notification) {
            stopDisplayLink()
        }

        @objc private func applicationWillEnterForeground(_: Notification) {
            startDisplayLink()
        }
    }
#endif
