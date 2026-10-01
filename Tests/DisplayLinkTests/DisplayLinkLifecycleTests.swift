//
//  DisplayLinkLifecycleTests.swift
//  DisplayLink
//

@testable import DisplayLink
import XCTest
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
final class DisplayLinkLifecycleTests: DisplayLinkTestCase {
    func testDeliversRealFramesOnTheMainThread() {
        let recorder = FrameRecorder()
        let link = DisplayLink()
        link.delegate = recorder
        waitForFrames(6, on: recorder)

        XCTAssertFalse(recorder.calledOffMainThread)
        for frame in recorder.frames {
            XCTAssertGreaterThan(frame.duration, 0)
            XCTAssertLessThan(frame.duration, 1, "a frame longer than a second")
        }
        for (previous, next) in zip(recorder.frames, recorder.frames.dropFirst()) {
            XCTAssertGreaterThan(next.timestamp, previous.timestamp, "timestamps must move forward")
        }
    }

    func testSystemLinkExistsOnlyWhileALinkIsAlive() {
        var link: DisplayLink? = DisplayLink()
        XCTAssertEqual(link?.subscription?.isRunning, true)

        link = nil
        XCTAssertTrue(SharedDisplayLink.links.isEmpty, "released as soon as the last link is")
    }

    func testLinksOnOneDisplayShareOneSystemLink() {
        let first = FrameRecorder()
        let second = FrameRecorder()
        let a = DisplayLink()
        var b: DisplayLink? = DisplayLink()
        a.delegate = first
        b?.delegate = second
        XCTAssertTrue(a.subscription === b?.subscription)
        XCTAssertEqual(a.subscription?.subscriberCount, 2)

        waitForFrames(3, on: first)
        waitForFrames(3, on: second)
        let shared = Set(first.frames.map(\.timestamp)).intersection(second.frames.map(\.timestamp))
        XCTAssertFalse(shared.isEmpty, "both should see the same refreshes")

        b = nil
        assertNoFrames(on: second)
        waitForFrames(3, on: first)
        withExtendedLifetime(b) {}
    }

    /// Links on one system link are called in creation order, which pausing,
    /// resuming and rebinding do not change.
    func testCallsFollowCreationOrder() throws {
        var calls: [Int] = []
        let recorders = (0 ..< 5).map { _ in FrameRecorder() }
        let links = recorders.map { recorder in
            let link = DisplayLink()
            link.delegate = recorder
            return link
        }
        for (index, recorder) in recorders.enumerated() {
            recorder.onFrame = { _, _ in calls.append(index) }
        }
        // Rejoin out of order: the first link last, the middle one in between.
        links[0].isPaused = true
        links[2].context = .main
        links[2].isPaused = true
        links[2].isPaused = false
        links[0].isPaused = false

        calls.removeAll()
        waitForFrames(3, on: recorders[4])
        let perFrame = Array(calls.prefix(5))
        XCTAssertEqual(perFrame, [0, 1, 2, 3, 4])
    }

    func testPausingStopsFramesAndReleasesTheSubscription() {
        let recorder = FrameRecorder()
        let link = DisplayLink()
        link.delegate = recorder
        waitForFrames(on: recorder)

        link.isPaused = true
        XCTAssertNil(link.subscription)
        assertNoFrames(on: recorder)

        link.isPaused = false
        waitForFrames(on: recorder)
    }

    func testDelegateIsHeldWeakly() {
        let link = DisplayLink()
        weak var released: FrameRecorder?
        do {
            let recorder = FrameRecorder()
            released = recorder
            link.delegate = recorder
            waitForFrames(on: recorder)
        }
        XCTAssertNil(released)
        spinMainRunLoop(for: 0.05) // ticking with no delegate must be harmless
    }

    func testReleasingAndCreatingLinksInsideTheCallback() {
        var current: DisplayLink? = DisplayLink()
        var generations = 0
        let recorder = FrameRecorder()
        recorder.onFrame = { _, _ in
            guard generations < 20 else { return }
            generations += 1
            // Drops the link delivering this very frame.
            let next = DisplayLink()
            next.delegate = recorder
            current = next
        }
        current?.delegate = recorder

        XCTAssertTrue(spinMainRunLoop { generations == 20 })
        waitForFrames(3, on: recorder)
        XCTAssertEqual(current?.subscription?.subscriberCount, 1)
        current = nil
    }

    func testFramesStreamDeliversAndStopsWithItsConsumer() async {
        let link = DisplayLink()
        var received: [DisplayLinkFrame] = []
        for await frame in link.frames {
            received.append(frame)
            if received.count == 5 { break }
        }
        XCTAssertEqual(received.count, 5)
        XCTAssertTrue(zip(received, received.dropFirst()).allSatisfy { $0.timestamp < $1.timestamp })
    }

    func testFramesStreamFinishesWhenTheLinkIsReleased() async {
        var link: DisplayLink? = DisplayLink()
        let frames = link!.frames
        let consumer = Task { @MainActor in
            var count = 0
            for await _ in frames { count += 1 }
            return count
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        link = nil
        let count = await consumer.value
        XCTAssertGreaterThan(count, 0)
    }

    /// A consumer that falls behind sees only the newest frame, never a backlog.
    func testFramesStreamSkipsInsteadOfQueuing() async throws {
        let link = DisplayLink()
        var iterator = link.frames.makeAsyncIterator()
        _ = await iterator.next()
        // Frames keep arriving while the consumer is away for ~12 refreshes.
        try await Task.sleep(nanoseconds: 200_000_000)
        let next = await iterator.next()
        let frame = try XCTUnwrap(next)
        // A queued frame would be ~200 ms old; the newest is at most a refresh or two.
        XCTAssertLessThan(CACurrentMediaTime() - frame.timestamp, 0.05)
        withExtendedLifetime(link) {}
    }

    #if canImport(UIKit)
        func testBackgroundReleasesSystemLinksAndForegroundRestoresThem() {
            let recorder = FrameRecorder()
            let link = DisplayLink()
            link.delegate = recorder
            waitForFrames(on: recorder)

            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            XCTAssertEqual(link.subscription?.isRunning, false)
            assertNoFrames(on: recorder)

            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
            XCTAssertEqual(link.subscription?.isRunning, true)
            waitForFrames(3, on: recorder)
        }
    #else
        func testDisplayChangesKeepLinksOnTheirDisplay() {
            let recorder = FrameRecorder()
            let link = DisplayLink()
            link.delegate = recorder
            waitForFrames(on: recorder)
            let shared = link.subscription

            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            XCTAssertTrue(link.subscription === shared)
            XCTAssertEqual(link.subscription?.isRunning, true)
            waitForFrames(3, on: recorder)
        }
    #endif
}
