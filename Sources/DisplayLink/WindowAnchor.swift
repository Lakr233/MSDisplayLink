//
//  WindowAnchor.swift
//  DisplayLink
//

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// An invisible subview that reports when its host view enters or leaves a
/// window. UIKit and AppKit only tell the view itself, so a link bound to a
/// view it does not own learns it through this subview.
@MainActor
final class WindowAnchor: PlatformView {
    private let onWindowChange: @MainActor () -> Void

    init(attachingTo host: PlatformView, onWindowChange: @escaping @MainActor () -> Void) {
        self.onWindowChange = onWindowChange
        super.init(frame: .zero)
        isHidden = true
        #if canImport(UIKit)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        #else
            setAccessibilityElement(false)
        #endif
        host.addSubview(self)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    #if canImport(UIKit)
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange()
        }
    #else
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange()
        }
    #endif
}
