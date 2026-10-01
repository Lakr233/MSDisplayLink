//
//  DisplayLinkModifierTests.swift
//  MSDisplayLink
//

@testable import MSDisplayLink
import SwiftUI
import XCTest

final class DisplayLinkModifierTests: DisplayLinkTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var storedValue = 0
        private var storedOffMainThread = false

        var value: Int { lock.withLock { storedValue } }
        var calledOffMainThread: Bool { lock.withLock { storedOffMainThread } }

        func bump() {
            lock.withLock {
                storedValue += 1
                if !Thread.isMainThread { storedOffMainThread = true }
            }
        }
    }

    private func waitForCount(_ counter: Counter, toExceed value: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(spinMainRunLoop { counter.value > value }, "callback never ran", file: file, line: line)
    }

    @MainActor
    func testContextTicksOnlyWhileStarted() {
        let counter = Counter()
        let context = DisplayLinkModifierContext()
        context.update(scheduleToMainThread: true, preferredFrameRateRange: .default) { _ in counter.bump() }

        spinMainRunLoop(for: 0.2)
        XCTAssertEqual(counter.value, 0, "ticked before start()")
        XCTAssertEqual(liveDriverCount, 0)

        context.start()
        waitForCount(counter, toExceed: 3)
        XCTAssertFalse(counter.calledOffMainThread)

        context.stop()
        XCTAssertEqual(liveDriverCount, 0)
        spinMainRunLoop(for: 0.05)
        let stopped = counter.value
        spinMainRunLoop(for: 0.2)
        XCTAssertEqual(counter.value, stopped, "ticked after stop()")
    }

    @MainActor
    func testRepeatedStartKeepsOneLink() {
        let context = DisplayLinkModifierContext()
        context.start()
        context.start()
        context.start()
        XCTAssertEqual(liveDriverCount, 1)
        context.stop()
        context.stop()
        XCTAssertEqual(liveDriverCount, 0)

        context.start()
        XCTAssertEqual(liveDriverCount, 1, "restarts after stop()")
        context.stop()
    }

    @MainActor
    func testBackgroundDeliveryWhenNotScheduledToMain() {
        let counter = Counter()
        let context = DisplayLinkModifierContext()
        context.update(scheduleToMainThread: false, preferredFrameRateRange: .default) { _ in counter.bump() }
        context.start()
        waitForCount(counter, toExceed: 3)
        XCTAssertTrue(counter.calledOffMainThread)
        context.stop()
        // Let callbacks already queued on the global queue finish.
        spinMainRunLoop(for: 0.1)
    }

    @MainActor
    func testUpdateSwapsCallbackAndRangeOnTheLiveLink() {
        let first = Counter()
        let second = Counter()
        let context = DisplayLinkModifierContext()
        context.update(scheduleToMainThread: true, preferredFrameRateRange: .default) { _ in first.bump() }
        context.start()
        waitForCount(first, toExceed: 0)

        let range = DisplayLinkFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        context.update(scheduleToMainThread: true, preferredFrameRateRange: range) { _ in second.bump() }
        XCTAssertEqual(helper.resolvedFrameRateRange(), range)
        spinMainRunLoop(for: 0.02)
        let firstStopped = first.value
        waitForCount(second, toExceed: 3)
        XCTAssertEqual(first.value, firstStopped, "the replaced callback still runs")
        XCTAssertEqual(liveDriverCount, 1, "update must not create another link")
        context.stop()
    }
}

// MARK: - Hosted in a real view hierarchy

/// Observed by the hosted view; the modifier's callback bumps `frame` on
/// every tick, so the view re-renders (and rebuilds the modifier) every frame.
private final class Probe: ObservableObject, @unchecked Sendable {
    @Published var frame = 0
    var appeared = false
    var renders = 0
    var maxLiveDrivers = 0
}

private struct ProbeView: View {
    @ObservedObject var probe: Probe

    var body: some View {
        probe.renders += 1
        return Text("\(probe.frame)")
            .modifier(DisplayLinkModifier { [probe] in
                probe.maxLiveDrivers = max(
                    probe.maxLiveDrivers,
                    DisplayLinkDriverHelper.shared.referenceHolder.compactMap(\.object).count
                )
                probe.frame += 1
            })
            .onAppear { probe.appeared = true }
    }
}

#if canImport(UIKit)
    import UIKit

    extension DisplayLinkModifierTests {
        @MainActor
        func testHostedModifierKeepsOneLinkAcrossRendersAndStopsWhenRemoved() throws {
            // A bare `xctest` process (SwiftPM, Mac Catalyst) has no app;
            // UIKit throws on the first window. Run app-hosted to cover this.
            // KVC returns nil here, where `UIApplication.shared` would trap.
            guard let application = (UIApplication.self as AnyObject)
                .value(forKey: "sharedApplication") as? UIApplication
            else {
                throw XCTSkip("needs an app-hosted test run")
            }
            let probe = Probe()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            if let scene = application.connectedScenes.first as? UIWindowScene {
                window.windowScene = scene
            }
            window.rootViewController = UIHostingController(rootView: ProbeView(probe: probe))
            window.makeKeyAndVisible()
            try assertHostedLifecycle(probe: probe) {
                window.rootViewController = nil
                window.isHidden = true
            }
        }
    }

#elseif canImport(AppKit)
    import AppKit

    extension DisplayLinkModifierTests {
        @MainActor
        func testHostedModifierKeepsOneLinkAcrossRendersAndStopsWhenRemoved() throws {
            let probe = Probe()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ProbeView(probe: probe))
            window.orderFront(nil)
            try assertHostedLifecycle(probe: probe) {
                window.contentView = nil
                window.orderOut(nil)
            }
        }
    }
#endif

extension DisplayLinkModifierTests {
    @MainActor
    private func assertHostedLifecycle(probe: Probe, remove: () -> Void) throws {
        guard spinMainRunLoop(timeout: 3, until: { probe.appeared }) else {
            throw XCTSkip("this test host cannot display a window, so onAppear never fires")
        }
        XCTAssertTrue(spinMainRunLoop { probe.frame >= 30 }, "the callback did not drive the view")
        XCTAssertGreaterThan(probe.renders, 10, "the view did not re-render per frame")
        XCTAssertEqual(probe.maxLiveDrivers, 1, "re-rendering created extra links")
        XCTAssertEqual(liveDriverCount, 1)

        remove()
        XCTAssertTrue(spinMainRunLoop { liveDriverCount == 0 }, "the link outlived the view")
        spinMainRunLoop(for: 0.05)
        let stopped = probe.frame
        spinMainRunLoop(for: 0.2)
        XCTAssertEqual(probe.frame, stopped, "ticked after the view went away")
    }
}
