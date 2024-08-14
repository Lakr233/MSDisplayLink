//
//  App.swift
//  DLExample
//
//  Created by 秋星桥 on 2024/8/14.
//

import SwiftUI

@main
struct App: SwiftUI.App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(macOS)
                .background(VisualEffectView().ignoresSafeArea())
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        #endif
    }
}

#if os(macOS)
    struct VisualEffectView: NSViewRepresentable {
        func makeNSView(context _: Context) -> NSVisualEffectView {
            let effectView = NSVisualEffectView()
            effectView.state = .active
            return effectView
        }

        func updateNSView(_: NSVisualEffectView, context _: Context) {}
    }
#endif
