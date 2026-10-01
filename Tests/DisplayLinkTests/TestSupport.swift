//
//  TestSupport.swift
//  DisplayLink
//

@testable import DisplayLink
import XCTest
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Records every frame it receives.
@MainActor
final class FrameRecorder: DisplayLinkDelegate {
    private(set) var frames: [DisplayLinkFrame] = []
    private(set) var calledOffMainThread = false
    /// Runs after the frame is recorded.
    var onFrame: ((DisplayLink, DisplayLinkFrame) -> Void)?

    var count: Int { frames.count }

    func displayLink(_ displayLink: DisplayLink, didUpdate frame: DisplayLinkFrame) {
        if !Thread.isMainThread { calledOffMainThread = true }
        frames.append(frame)
        onFrame?(displayLink, frame)
    }
}

/// Base class for tests that touch the shared display links. They are
/// process-wide, so a test that leaks one would make every later assertion
/// about them meaningless.
class DisplayLinkTestCase: XCTestCase {
    override func tearDown() {
        // Let queued main-thread work (CVDisplayLink frames) land.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let leaked = MainActor.assumeIsolated { !SharedDisplayLink.links.isEmpty }
        XCTAssertFalse(leaked, "the test leaked a display link")
        super.tearDown()
    }

    @MainActor
    func spinMainRunLoop(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Spins the main run loop until `condition` holds or `timeout` passes.
    @MainActor
    @discardableResult
    func spinMainRunLoop(timeout: TimeInterval = 5, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        return true
    }

    @MainActor
    func waitForFrames(_ frames: Int = 1, on recorder: FrameRecorder, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let target = recorder.count + frames
        let arrived = spinMainRunLoop(timeout: timeout) { recorder.count >= target }
        XCTAssertTrue(arrived, "expected \(frames) more frame(s), got \(recorder.count - target + frames)", file: file, line: line)
    }

    @MainActor
    func assertNoFrames(on recorder: FrameRecorder, for seconds: TimeInterval = 0.2, file: StaticString = #filePath, line: UInt = #line) {
        spinMainRunLoop(for: 0.05)
        let before = recorder.count
        spinMainRunLoop(for: seconds)
        XCTAssertEqual(recorder.count, before, "received frames while it should be quiet", file: file, line: line)
    }

    /// A window on screen, and a view inside it. Throws XCTSkip where the test
    /// process cannot show windows (a bare xctest with UIKit has no app).
    @MainActor
    func makeWindow() throws -> TestWindow {
        try TestWindow()
    }
}

/// A real window for context tests, closed by `close()`.
@MainActor
final class TestWindow {
    #if canImport(UIKit)
        let window: UIWindow

        init() throws {
            guard let application = (UIApplication.self as AnyObject).value(forKey: "sharedApplication") as? UIApplication,
                  let scene = application.connectedScenes.first as? UIWindowScene
            else { throw XCTSkip("needs an app-hosted test run") }
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
            window.isHidden = false
        }

        var contentView: UIView { window }

        func close() {
            window.isHidden = true
            window.subviews.forEach { $0.removeFromSuperview() }
        }
    #else
        let window: NSWindow

        init() throws {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSView()
            window.orderFront(nil)
        }

        var contentView: NSView { window.contentView! }

        func close() {
            contentView.subviews.forEach { $0.removeFromSuperview() }
            window.orderOut(nil)
        }
    #endif
}
