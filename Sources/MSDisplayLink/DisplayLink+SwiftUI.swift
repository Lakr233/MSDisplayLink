//
//  DisplayLink+SwiftUI.swift
//  MSDisplayLink
//
//  Created by 秋星桥 on 2024/8/14.
//

import SwiftUI

public struct DisplayLinkModifier: ViewModifier {
    let link: DisplayLink
    let context: DisplayLinkModifierContext

    public init(scheduleToMainThread: Bool = true, _ callback: @escaping (DisplayLinkCallbackContext) -> Void) {
        link = .init()
        context = .init(scheduleToMainThread: scheduleToMainThread, callback: callback)
        link.delegatingObject(context)
    }

    public init(scheduleToMainThread: Bool = true, _ callback: @escaping () -> Void) {
        self.init(scheduleToMainThread: scheduleToMainThread) { _ in callback() }
    }

    public func body(content: Content) -> some View {
        content
            .onAppear { link.delegatingObject(context) }
            .onDisappear { link.delegatingObject(nil) }
    }
}

class DisplayLinkModifierContext: ObservableObject, DisplayLinkDelegate {
    let scheduleToMainThread: Bool
    var callback: (DisplayLinkCallbackContext) -> Void

    init(scheduleToMainThread: Bool, callback: @escaping (DisplayLinkCallbackContext) -> Void) {
        self.scheduleToMainThread = scheduleToMainThread
        self.callback = callback
    }

    func synchronization(context: DisplayLinkCallbackContext) {
        if scheduleToMainThread {
            if Thread.isMainThread {
                callback(context)
            } else {
                DispatchQueue.main.async { self.callback(context) }
            }
        } else {
            if Thread.isMainThread {
                DispatchQueue.global().async { self.callback(context) }
            } else {
                callback(context)
            }
        }
    }
}
