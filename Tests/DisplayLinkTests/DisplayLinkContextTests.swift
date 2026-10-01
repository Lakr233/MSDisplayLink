//
//  DisplayLinkContextTests.swift
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
final class DisplayLinkContextTests: DisplayLinkTestCase {
    func testViewOutsideAWindowWaitsAndStartsWhenAdded() throws {
        let window = try makeWindow()
        defer { window.close() }
        let view = PlatformView()
        let recorder = FrameRecorder()
        let link = DisplayLink(context: .view(view))
        link.delegate = recorder

        XCTAssertNil(link.subscription, "a view outside any window has no display")
        assertNoFrames(on: recorder)

        window.contentView.addSubview(view)
        XCTAssertNotNil(link.subscription)
        waitForFrames(3, on: recorder)

        view.removeFromSuperview()
        XCTAssertNil(link.subscription)
        XCTAssertTrue(SharedDisplayLink.links.isEmpty)
        assertNoFrames(on: recorder)
    }

    func testAnchorCoversTheViewAndResizesWithIt() throws {
        let view = PlatformView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
        let link = DisplayLink(context: .view(view))
        let anchor = try XCTUnwrap(view.subviews.first as? WindowAnchor)
        XCTAssertEqual(anchor.frame, view.bounds)

        view.frame.size = CGSize(width: 300, height: 200)
        #if canImport(UIKit)
            view.layoutIfNeeded()
        #endif
        XCTAssertEqual(anchor.frame, view.bounds)
        withExtendedLifetime(link) {}
    }

    func testViewMovedBetweenWindowsKeepsTicking() throws {
        let first = try makeWindow()
        let second = try makeWindow()
        defer { first.close(); second.close() }
        let view = PlatformView()
        first.contentView.addSubview(view)
        let recorder = FrameRecorder()
        let link = DisplayLink(context: .view(view))
        link.delegate = recorder
        waitForFrames(on: recorder)

        second.contentView.addSubview(view)
        waitForFrames(3, on: recorder)
        XCTAssertEqual(link.subscription?.subscriberCount, 1)
    }

    func testBindingAWindowItself() throws {
        let window = try makeWindow()
        defer { window.close() }
        let recorder = FrameRecorder()
        #if canImport(UIKit)
            let link = DisplayLink(context: .view(window.window))
        #else
            let link = DisplayLink(context: .view(window.contentView))
        #endif
        link.delegate = recorder
        waitForFrames(3, on: recorder)
    }

    func testRebindingMovesTheSubscriptionAndTheAnchor() throws {
        let window = try makeWindow()
        defer { window.close() }
        let view = PlatformView()
        window.contentView.addSubview(view)
        let recorder = FrameRecorder()
        let link = DisplayLink(context: .view(view))
        link.delegate = recorder
        waitForFrames(on: recorder)
        XCTAssertEqual(view.subviews.count, 1, "the anchor")

        link.context = .main
        XCTAssertTrue(view.subviews.isEmpty, "rebinding removes the old anchor")
        waitForFrames(3, on: recorder)

        view.removeFromSuperview()
        waitForFrames(3, on: recorder) // no longer tied to the view
    }

    func testReleasedViewStopsItsLink() throws {
        let window = try makeWindow()
        defer { window.close() }
        let recorder = FrameRecorder()
        var view: PlatformView? = PlatformView()
        try window.contentView.addSubview(XCTUnwrap(view))
        let link = try DisplayLink(context: .view(XCTUnwrap(view)))
        link.delegate = recorder
        waitForFrames(on: recorder)

        view?.removeFromSuperview()
        view = nil
        XCTAssertNil(link.subscription)
        assertNoFrames(on: recorder)
    }

    func testReleasingTheLinkRemovesItsAnchor() {
        let view = PlatformView()
        var link: DisplayLink? = DisplayLink(context: .view(view))
        XCTAssertEqual(view.subviews.count, 1)
        link = nil
        XCTAssertTrue(view.subviews.isEmpty)
        withExtendedLifetime(link) {}
    }

    func testAnchorIsInvisibleToLayoutAndInput() {
        let view = PlatformView()
        let link = DisplayLink(context: .view(view))
        let anchor = view.subviews.first
        XCTAssertNotNil(anchor)
        XCTAssertEqual(anchor?.isHidden, true)
        XCTAssertEqual(anchor?.frame, .zero)
        #if canImport(UIKit)
            XCTAssertEqual(anchor?.isUserInteractionEnabled, false)
            XCTAssertEqual(anchor?.isAccessibilityElement, false)
        #else
            XCTAssertEqual(anchor?.isAccessibilityElement(), false)
        #endif
        withExtendedLifetime(link) {}
    }

    #if !os(visionOS)
        func testScreenContextTicks() {
            #if canImport(UIKit)
                let screen = UIScreen.main
            #else
                guard let screen = NSScreen.screens.first else { return }
            #endif
            let recorder = FrameRecorder()
            let link = DisplayLink(context: .screen(screen))
            link.delegate = recorder
            waitForFrames(3, on: recorder)
            let main = DisplayLink()
            XCTAssertTrue(link.subscription === main.subscription, "the primary screen is the main display")
        }
    #endif

    func testViewAndMainOnTheSameDisplayShareOneSystemLink() throws {
        let window = try makeWindow()
        defer { window.close() }
        let view = PlatformView()
        window.contentView.addSubview(view)
        let bound = DisplayLink(context: .view(view))
        let main = DisplayLink()
        // A single-display machine: both resolve to the same display.
        XCTAssertTrue(bound.subscription === main.subscription)
        XCTAssertEqual(SharedDisplayLink.links.count, 1)
    }
}
