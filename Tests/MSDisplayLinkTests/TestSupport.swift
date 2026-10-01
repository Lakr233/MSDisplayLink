//
//  TestSupport.swift
//  MSDisplayLink
//

@testable import MSDisplayLink
import XCTest

/// Records every tick it receives. Thread-safe so the off-main paths can
/// share it.
final class TickRecorder: DisplayLinkDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedContexts: [DisplayLinkCallbackContext] = []
    private var recordedOffMainThread = false

    /// Runs after the tick is recorded, on the thread that delivered it.
    var onTick: ((DisplayLinkCallbackContext) -> Void)?

    var count: Int { lock.withLock { recordedContexts.count } }
    var contexts: [DisplayLinkCallbackContext] { lock.withLock { recordedContexts } }
    var calledOffMainThread: Bool { lock.withLock { recordedOffMainThread } }

    func synchronization(context: DisplayLinkCallbackContext) {
        lock.withLock {
            recordedContexts.append(context)
            if !Thread.isMainThread { recordedOffMainThread = true }
        }
        onTick?(context)
    }
}

/// Base class for tests that touch the shared platform link. The helper is a
/// process-wide singleton, so a test that leaks a driver would make every
/// later assertion about it meaningless.
class DisplayLinkTestCase: XCTestCase {
    var helper: DisplayLinkDriverHelper { .shared }

    var liveDriverCount: Int {
        helper.referenceHolder.compactMap(\.object).count
    }

    override func tearDown() {
        // Let queued main-thread hops (off-main deinit, CVDisplayLink ticks) land.
        spinMainRunLoop(for: 0.05)
        XCTAssertFalse(helper.hasLiveDrivers, "the test leaked a DisplayLink")
        XCTAssertFalse(helper.isDisplayLinkRunning, "the platform link outlived its last driver")
        super.tearDown()
    }

    func spinMainRunLoop(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Spins the main run loop until `condition` holds or `timeout` passes.
    @discardableResult
    func spinMainRunLoop(
        timeout: TimeInterval = 5,
        until condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return true
    }

    /// Waits for `recorder` to receive `ticks` more callbacks.
    func waitForTicks(
        _ ticks: Int = 1,
        on recorder: TickRecorder,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let target = recorder.count + ticks
        let arrived = spinMainRunLoop(timeout: timeout) { recorder.count >= target }
        XCTAssertTrue(arrived, "expected \(ticks) more tick(s), got \(recorder.count - target + ticks)", file: file, line: line)
    }

    /// Asserts `recorder` receives nothing for a while.
    func assertNoTicks(
        on recorder: TickRecorder,
        for seconds: TimeInterval = 0.2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Anything the link already queued for this runloop turn may still land.
        spinMainRunLoop(for: 0.05)
        let before = recorder.count
        spinMainRunLoop(for: seconds)
        XCTAssertEqual(recorder.count, before, "ticked while it should be quiet", file: file, line: line)
    }
}
