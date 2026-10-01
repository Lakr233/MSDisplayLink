//
//  DisplayLink+SwiftUI.swift
//  MSDisplayLink
//
//  Created by 秋星桥 on 2024/8/14.
//

import SwiftUI

@MainActor
public struct DisplayLinkModifier: ViewModifier {
    let scheduleToMainThread: Bool
    let preferredFrameRateRange: DisplayLinkFrameRateRange
    let callback: @Sendable (DisplayLinkCallbackContext) -> Void

    /// One link per view identity. The modifier itself is rebuilt on every
    /// body evaluation — often every frame, when the callback drives state —
    /// so the link cannot live on the struct.
    @State private var context = DisplayLinkModifierContext()

    public init(
        scheduleToMainThread: Bool = true,
        preferredFrameRateRange: DisplayLinkFrameRateRange = .default,
        _ callback: @escaping @Sendable (DisplayLinkCallbackContext) -> Void
    ) {
        self.scheduleToMainThread = scheduleToMainThread
        self.preferredFrameRateRange = preferredFrameRateRange
        self.callback = callback
    }

    public init(
        scheduleToMainThread: Bool = true,
        preferredFrameRateRange: DisplayLinkFrameRateRange = .default,
        _ callback: @escaping @Sendable () -> Void
    ) {
        self.init(
            scheduleToMainThread: scheduleToMainThread,
            preferredFrameRateRange: preferredFrameRateRange
        ) { _ in callback() }
    }

    public func body(content: Content) -> some View {
        context.update(
            scheduleToMainThread: scheduleToMainThread,
            preferredFrameRateRange: preferredFrameRateRange,
            callback: callback
        )
        return content
            .onAppear { context.start() }
            .onDisappear { context.stop() }
    }
}

/// Main-thread only: both platform drivers deliver `synchronization` on the
/// main thread, and SwiftUI calls everything else from there.
final class DisplayLinkModifierContext: DisplayLinkDelegate, @unchecked Sendable {
    private var link: DisplayLink?
    private var scheduleToMainThread = true
    private var preferredFrameRateRange: DisplayLinkFrameRateRange = .default
    private var callback: @Sendable (DisplayLinkCallbackContext) -> Void = { _ in }

    func update(
        scheduleToMainThread: Bool,
        preferredFrameRateRange: DisplayLinkFrameRateRange,
        callback: @escaping @Sendable (DisplayLinkCallbackContext) -> Void
    ) {
        self.scheduleToMainThread = scheduleToMainThread
        self.preferredFrameRateRange = preferredFrameRateRange
        self.callback = callback
        link?.preferredFrameRateRange = preferredFrameRateRange
    }

    func start() {
        guard link == nil else { return }
        let link = DisplayLink(preferredFrameRateRange: preferredFrameRateRange)
        link.delegatingObject(self)
        self.link = link
    }

    func stop() {
        link = nil
    }

    func synchronization(context: DisplayLinkCallbackContext) {
        let callback = callback
        if scheduleToMainThread {
            if Thread.isMainThread {
                callback(context)
            } else {
                DispatchQueue.main.async { callback(context) }
            }
        } else {
            if Thread.isMainThread {
                DispatchQueue.global().async { callback(context) }
            } else {
                callback(context)
            }
        }
    }
}
