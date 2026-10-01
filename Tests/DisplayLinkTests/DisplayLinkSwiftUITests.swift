//
//  DisplayLinkSwiftUITests.swift
//  DisplayLink
//

@testable import DisplayLink
import SwiftUI
import XCTest

/// Observed by the hosted view; every frame bumps `frame`, so the view
/// re-renders (and rebuilds the modifier) once per refresh.
@MainActor
private final class Probe: ObservableObject {
    @Published var frame = 0
    @Published var isPaused = false
    @Published var range = DisplayLinkFrameRateRange.default
    var renders = 0
    var maxSubscribers = 0
}

private struct ProbeView: View {
    @ObservedObject var probe: Probe

    var body: some View {
        probe.renders += 1
        return Text("\(probe.frame)")
            .onDisplayLink(preferredFrameRateRange: probe.range, isPaused: probe.isPaused) { _ in
                let subscribers = SharedDisplayLink.links.values.map(\.subscriberCount).reduce(0, +)
                probe.maxSubscribers = max(probe.maxSubscribers, subscribers)
                probe.frame += 1
            }
    }
}

@MainActor
final class DisplayLinkSwiftUITests: DisplayLinkTestCase {
    func testKeepsOneLinkAcrossRendersAndStopsWhenRemoved() throws {
        let window = try makeWindow()
        defer { window.close() }
        let probe = Probe()
        let host = host(ProbeView(probe: probe), in: window)

        XCTAssertTrue(spinMainRunLoop { probe.frame >= 30 }, "the action did not drive the view")
        XCTAssertGreaterThan(probe.renders, 10, "the view did not re-render per frame")
        XCTAssertEqual(probe.maxSubscribers, 1, "re-rendering created extra links")

        host.removeFromSuperview()
        XCTAssertTrue(spinMainRunLoop { SharedDisplayLink.links.isEmpty }, "the link outlived the view")
        let stopped = probe.frame
        spinMainRunLoop(for: 0.2)
        XCTAssertEqual(probe.frame, stopped, "ticked after the view went away")
    }

    func testIsPausedAndRangeReachTheLink() throws {
        let window = try makeWindow()
        defer { window.close() }
        let probe = Probe()
        _ = host(ProbeView(probe: probe), in: window)
        XCTAssertTrue(spinMainRunLoop { probe.frame >= 3 })

        probe.isPaused = true
        XCTAssertTrue(spinMainRunLoop { SharedDisplayLink.links.isEmpty }, "pausing keeps the link subscribed")
        let paused = probe.frame
        spinMainRunLoop(for: 0.2)
        XCTAssertEqual(probe.frame, paused)

        let range = DisplayLinkFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        probe.range = range
        probe.isPaused = false
        XCTAssertTrue(spinMainRunLoop { probe.frame > paused })
        XCTAssertEqual(SharedDisplayLink.links.values.first?.key.frameRateRange, range)
    }

    private func host(_ view: some View, in window: TestWindow) -> PlatformView {
        #if canImport(UIKit)
            let host = UIHostingController(rootView: view).view!
        #else
            let host = NSHostingView(rootView: view)
        #endif
        host.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        window.contentView.addSubview(host)
        return host
    }
}
