//
//  DisplayLinkLifecycleTests.swift
//  MSDisplayLink
//

@testable import MSDisplayLink
import XCTest
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

final class DisplayLinkLifecycleTests: DisplayLinkTestCase {
    func testDelegateIsCalledOnMainThread() {
        let recorder = TickRecorder()
        let link = DisplayLink()
        link.delegatingObject(recorder)

        waitForTicks(3, on: recorder)
        XCTAssertFalse(recorder.calledOffMainThread)
        withExtendedLifetime(link) {}
    }

    func testCallbackContextDescribesRealFrames() {
        let recorder = TickRecorder()
        let link = DisplayLink()
        link.delegatingObject(recorder)
        waitForTicks(6, on: recorder)
        withExtendedLifetime(link) {}

        let contexts = recorder.contexts
        for context in contexts {
            XCTAssertGreaterThan(context.duration, 0)
            XCTAssertLessThan(context.duration, 1, "a frame longer than a second")
            XCTAssertGreaterThan(context.timestamp, 0)
            XCTAssertGreaterThanOrEqual(context.targetTimestamp, context.timestamp)
        }
        for (previous, next) in zip(contexts, contexts.dropFirst()) {
            XCTAssertGreaterThan(next.timestamp, previous.timestamp, "timestamps must move forward")
        }
    }

    func testPlatformLinkRunsOnlyWhileADriverIsAlive() {
        XCTAssertFalse(helper.isDisplayLinkRunning)
        var link: DisplayLink? = DisplayLink()
        XCTAssertTrue(helper.isDisplayLinkRunning)
        XCTAssertEqual(liveDriverCount, 1)

        link = nil
        XCTAssertFalse(helper.isDisplayLinkRunning, "stops as soon as the last link is released")
        XCTAssertEqual(liveDriverCount, 0)
        withExtendedLifetime(link) {}
    }

    func testLinksShareOnePlatformLink() {
        let first = TickRecorder()
        let second = TickRecorder()
        let a = DisplayLink()
        var b: DisplayLink? = DisplayLink()
        a.delegatingObject(first)
        b?.delegatingObject(second)
        XCTAssertEqual(liveDriverCount, 2)

        waitForTicks(3, on: first)
        waitForTicks(3, on: second)

        // Both are driven by the same tick, so they see the same frames.
        let shared = Set(first.contexts.map(\.timestamp))
            .intersection(second.contexts.map(\.timestamp))
        XCTAssertFalse(shared.isEmpty, "two links should observe the same frames")

        b = nil
        XCTAssertTrue(helper.isDisplayLinkRunning)
        assertNoTicks(on: second)
        waitForTicks(3, on: first)
        withExtendedLifetime((a, b)) {}
    }

    func testDetachingTheDelegateStopsCallbacks() {
        let recorder = TickRecorder()
        let link = DisplayLink()
        link.delegatingObject(recorder)
        waitForTicks(on: recorder)

        link.delegatingObject(nil)
        assertNoTicks(on: recorder)
        XCTAssertTrue(helper.isDisplayLinkRunning, "the link itself is still alive")

        link.delegatingObject(recorder)
        waitForTicks(on: recorder)
        withExtendedLifetime(link) {}
    }

    func testSwappingTheDelegateMovesCallbacks() {
        let first = TickRecorder()
        let second = TickRecorder()
        let link = DisplayLink()
        link.delegatingObject(first)
        waitForTicks(on: first)

        link.delegatingObject(second)
        waitForTicks(3, on: second)
        assertNoTicks(on: first)
        withExtendedLifetime(link) {}
    }

    func testDelegateIsHeldWeakly() {
        let link = DisplayLink()
        weak var released: TickRecorder?
        do {
            let recorder = TickRecorder()
            released = recorder
            link.delegatingObject(recorder)
            waitForTicks(on: recorder)
        }
        XCTAssertNil(released, "DisplayLink must not retain its delegate")
        // Ticking with a dead delegate must be harmless.
        spinMainRunLoop(for: 0.1)
        XCTAssertTrue(helper.isDisplayLinkRunning)
        withExtendedLifetime(link) {}
    }

    func testReleasingAndCreatingLinksInsideTheCallback() {
        final class Chain: @unchecked Sendable {
            var link: DisplayLink?
            var generations = 0
        }
        let chain = Chain()
        let recorder = TickRecorder()
        recorder.onTick = { [unowned recorder] _ in
            guard chain.generations < 20 else { return }
            chain.generations += 1
            // Drops the link that is delivering this very tick.
            let next = DisplayLink()
            next.delegatingObject(recorder)
            chain.link = next
        }
        chain.link = DisplayLink()
        chain.link?.delegatingObject(recorder)

        XCTAssertTrue(spinMainRunLoop { chain.generations == 20 })
        waitForTicks(3, on: recorder)
        XCTAssertEqual(liveDriverCount, 1)
        chain.link = nil
    }

    func testLinkCreatedAndReleasedOffMainThread() {
        let recorder = TickRecorder()
        nonisolated(unsafe) var link: DisplayLink?

        let created = expectation(description: "created")
        DispatchQueue.global().async {
            link = DisplayLink()
            link?.delegatingObject(recorder)
            created.fulfill()
        }
        wait(for: [created], timeout: 5)
        waitForTicks(on: recorder)
        XCTAssertFalse(recorder.calledOffMainThread)

        let released = expectation(description: "released")
        DispatchQueue.global().async {
            link = nil
            released.fulfill()
        }
        wait(for: [released], timeout: 5)
        XCTAssertTrue(spinMainRunLoop { !helper.hasLiveDrivers })
    }

    /// A link created and dropped before its main-thread registration runs
    /// must never register.
    func testLinkDroppedBeforeRegistrationNeverRegisters() {
        let done = expectation(description: "done")
        DispatchQueue.global().async {
            for _ in 0 ..< 100 { _ = DisplayLink() }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        spinMainRunLoop(for: 0.1)
        XCTAssertEqual(liveDriverCount, 0)
    }

    func testConcurrentChurnLeavesNoDrivers() {
        let recorder = TickRecorder()
        let survivor = DisplayLink()
        survivor.delegatingObject(recorder)

        let churned = expectation(description: "churned")
        DispatchQueue.global().async {
            DispatchQueue.concurrentPerform(iterations: 8) { worker in
                for index in 0 ..< 250 {
                    let link = DisplayLink(preferredFrameRateRange: .init(
                        minimum: Float(worker * 10 + 1),
                        maximum: 120,
                        preferred: Float(index % 120)
                    ))
                    link.delegatingObject(recorder)
                }
            }
            churned.fulfill()
        }
        // Keep the main thread busy ticking while the workers churn.
        wait(for: [churned], timeout: 30)
        XCTAssertTrue(spinMainRunLoop { liveDriverCount == 1 }, "churned links leaked")
        waitForTicks(3, on: recorder)
        XCTAssertFalse(recorder.calledOffMainThread)
        withExtendedLifetime(survivor) {}
    }

    #if !canImport(UIKit) && canImport(AppKit)
        /// Stands in for a link that could not be created because every
        /// display was asleep: the drivers are alive but nothing ticks.
        func testScreenWakeRestartsTheLinkForLiveDrivers() {
            let recorder = TickRecorder()
            let link = DisplayLink()
            link.delegatingObject(recorder)
            waitForTicks(on: recorder)

            helper.stopDisplayLink()
            assertNoTicks(on: recorder)

            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            XCTAssertTrue(helper.isDisplayLinkRunning)
            waitForTicks(3, on: recorder)
            withExtendedLifetime(link) {}
        }

        func testScreenWakeWithoutDriversDoesNotStartTheLink() {
            _ = helper // make sure the observers are registered
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            XCTAssertFalse(helper.isDisplayLinkRunning)
        }
    #endif

    #if canImport(UIKit)
        func testBackgroundStopsAndForegroundResumes() {
            let recorder = TickRecorder()
            let link = DisplayLink()
            link.delegatingObject(recorder)
            waitForTicks(on: recorder)

            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            XCTAssertFalse(helper.isDisplayLinkRunning)
            assertNoTicks(on: recorder)

            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
            XCTAssertTrue(helper.isDisplayLinkRunning)
            waitForTicks(3, on: recorder)
            withExtendedLifetime(link) {}
        }

        func testForegroundWithoutDriversDoesNotStartTheLink() {
            _ = helper // make sure the observers are registered
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
            XCTAssertFalse(helper.isDisplayLinkRunning)
        }
    #endif
}
