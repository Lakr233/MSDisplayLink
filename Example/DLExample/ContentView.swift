//
//  ContentView.swift
//  DLExample
//
//  Created by 秋星桥 on 2024/8/14.
//

import DisplayLink
import SwiftUI

struct ContentView: View {
    @State var frame: Int = 0
    var body: some View {
        VStack {
            Text("DisplayLink Trigger: \(frame)")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .animation(.interactiveSpring, value: frame)
        .onDisplayLink { _ in
            frame += 1
        }
        .padding()
    }
}
