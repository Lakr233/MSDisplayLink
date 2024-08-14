//
//  ContentView.swift
//  DLExample
//
//  Created by 秋星桥 on 2024/8/14.
//

import MSDisplayLink
import SwiftUI

struct ContentView: View {
    @State var frame: Int = 0
    var body: some View {
        VStack {
            Text("MSDisplayLink Trigger: \(frame)")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .animation(.interactiveSpring, value: frame)
        .modifier(DisplayLinkModifier(scheduleToMainThread: true) {
            frame += 1
        })
        .padding()
    }
}
