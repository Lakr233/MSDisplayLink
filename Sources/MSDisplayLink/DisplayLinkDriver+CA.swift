import Foundation

#if canImport(UIKit)
    import UIKit

    typealias DisplayLinkDriverHelper = CADisplayLinkDriverHelper

    class CADisplayLinkDriverHelper: DisplayLinkDriverHelperBase {
        static let shared = CADisplayLinkDriverHelper()

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
            lock.lock()
            defer { lock.unlock() }

            guard displayLink == nil else { return }
            displayLink = CADisplayLink(target: self, selector: #selector(displayLinkCallback))
            displayLink?.add(to: .main, forMode: .common)
        }

        override func stopDisplayLink() {
            lock.lock()
            defer { lock.unlock() }

            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func displayLinkCallback() {
            autoreleasepool { dispatchUpdate() }
        }

        @objc private func applicationDidEnterBackground(_: Notification) {
            stopDisplayLink()
        }

        @objc private func applicationWillEnterForeground(_: Notification) {
            startDisplayLink()
        }
    }
#endif
