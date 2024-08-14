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

    public init(scheduleToMainThread: Bool = true, _ callback: @escaping () -> Void) {
        link = .init()
        context = .init(scheduleToMainThread: scheduleToMainThread, callback: callback)
        link.delegatingObject(context)
    }

    public func body(content: Content) -> some View {
        content
            .onAppear { link.delegatingObject(context) }
            .onDisappear { link.delegatingObject(nil) }
    }
}

class DisplayLinkModifierContext: ObservableObject, DisplayLinkDelegate {
    let scheduleToMainThread: Bool
    var callback: () -> Void

    init(scheduleToMainThread: Bool, callback: @escaping () -> Void) {
        self.scheduleToMainThread = scheduleToMainThread
        self.callback = callback
    }

    func synchronization() {
        if scheduleToMainThread {
            DispatchQueue.main.async { self.callback() }
        } else {
            callback()
        }
    }
}
