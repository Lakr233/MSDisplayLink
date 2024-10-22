import Foundation

#if !canImport(UIKit) && canImport(AppKit)
    import AppKit

    typealias DisplayLinkDriverHelper = CVDisplayLinkDriverHelper

    class CVDisplayLinkDriverHelper: DisplayLinkDriverHelperBase {
        static let shared = CVDisplayLinkDriverHelper()

        private var displayLink: CVDisplayLink?

        override func startDisplayLink() {
            lock.lock()
            defer { lock.unlock() }

            guard displayLink == nil else { return }
            CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
            guard let displayLink else { return }
            CVDisplayLinkSetOutputCallback(displayLink, { _, _, _, _, _, _ -> CVReturn in
                autoreleasepool { CVDisplayLinkDriverHelper.shared.dispatchUpdate() }
                return kCVReturnSuccess
            }, nil)
            CVDisplayLinkStart(displayLink)
        }

        override func stopDisplayLink() {
            lock.lock()
            defer { lock.unlock() }

            if let displayLink { CVDisplayLinkStop(displayLink) }
            displayLink = nil
        }
    }
#endif
