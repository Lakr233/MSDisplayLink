import Foundation

#if !canImport(UIKit) && canImport(AppKit)
    import AppKit

    typealias DisplayLinkDriverHelper = CVDisplayLinkDriverHelper

    class CVDisplayLinkDriverHelper: DisplayLinkDriverHelperBase {
        nonisolated(unsafe) static let shared = CVDisplayLinkDriverHelper()

        private var displayLink: CVDisplayLink?

        override var isDisplayLinkRunning: Bool { displayLink != nil }

        override private init() {
            super.init()
            // With every display asleep (lid closed, screen saver, a headless
            // login) there is no active display to create a link for, and the
            // drivers that asked for one would wait forever. Retry once a
            // display is back.
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(displaysMayHaveChanged(_:)),
                name: NSWorkspace.screensDidWakeNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(displaysMayHaveChanged(_:)),
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
        }

        deinit {
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func displaysMayHaveChanged(_: Notification) {
            guard hasLiveDrivers, !isDisplayLinkRunning else { return }
            startDisplayLink()
        }

        override func startDisplayLink() {
            assert(Thread.isMainThread)
            guard displayLink == nil else { return }
            CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
            guard let displayLink else { return }

            CVDisplayLinkSetOutputCallback(displayLink, { _, inNow, inOutputTime, _, _, _ in
                let clockFrequency = CVGetHostClockFrequency()
                let context = DisplayLinkCallbackContext(
                    duration: TimeInterval(inNow.pointee.videoRefreshPeriod) / TimeInterval(inNow.pointee.videoTimeScale),
                    timestamp: TimeInterval(inNow.pointee.hostTime) / clockFrequency,
                    targetTimestamp: TimeInterval(inOutputTime.pointee.hostTime) / clockFrequency
                )
                assert(!Thread.isMainThread)
                DispatchQueue.main.async {
                    autoreleasepool {
                        CVDisplayLinkDriverHelper.shared.dispatchUpdate(context: context)
                    }
                }
                return kCVReturnSuccess
            }, nil)
            CVDisplayLinkStart(displayLink)
        }

        override func stopDisplayLink() {
            assert(Thread.isMainThread)
            if let displayLink { CVDisplayLinkStop(displayLink) }
            displayLink = nil
        }
    }
#endif
