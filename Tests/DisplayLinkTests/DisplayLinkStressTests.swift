//
//  DisplayLinkStressTests.swift
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
final class DisplayLinkStressTests: DisplayLinkTestCase {
    /// Every one of many links on one display gets every refresh.
    func testThousandLinksEachGetEveryFrame() {
        let recorders = (0 ..< 1000).map { _ in FrameRecorder() }
        let links = recorders.map { recorder in
            let link = DisplayLink()
            link.delegate = recorder
            return link
        }
        XCTAssertEqual(SharedDisplayLink.links.count, 1)
        XCTAssertEqual(links[0].subscription?.subscriberCount, 1000)

        waitForFrames(30, on: recorders[0])
        let reference = Set(recorders[0].frames.map(\.timestamp))
        for recorder in recorders.dropFirst() {
            // Links joined a few microseconds apart; compare the frames all of them saw.
            XCTAssertTrue(reference.isSuperset(of: recorder.frames.dropFirst().map(\.timestamp)))
            XCTAssertGreaterThanOrEqual(recorder.count, recorders[0].count - 1)
        }
    }

    /// Many links over a few rates: one system link per rate, each link on
    /// the one for its rate, and every link ticking.
    func testThousandLinksOverFourRates() {
        let rates: [Float] = [120, 60, 30, 20]
        let recorders = (0 ..< 1000).map { _ in FrameRecorder() }
        let links = recorders.enumerated().map { index, recorder in
            let rate = rates[index % rates.count]
            let link = DisplayLink(preferredFrameRateRange: .init(minimum: rate, maximum: rate, preferred: rate))
            link.delegate = recorder
            return link
        }
        XCTAssertEqual(SharedDisplayLink.links.count, rates.count)
        XCTAssertEqual(Set(SharedDisplayLink.links.values.map(\.subscriberCount)), [250])
        XCTAssertTrue(spinMainRunLoop { recorders.allSatisfy { $0.count >= 3 } }, "some links starved")
        withExtendedLifetime(links) {}
    }

    func testChurnLeavesNothingBehind() throws {
        let window = try? makeWindow()
        defer { window?.close() }
        let view = PlatformView()
        window?.contentView.addSubview(view)
        let recorder = FrameRecorder()
        let survivor = DisplayLink()
        survivor.delegate = recorder

        for index in 0 ..< 10000 {
            let link = DisplayLink(context: index.isMultiple(of: 2) ? .main : .view(view))
            link.delegate = recorder
            link.preferredFrameRateRange = .init(minimum: Float(index % 60), maximum: 120, preferred: Float(index % 121))
        }
        XCTAssertEqual(SharedDisplayLink.links.values.map(\.subscriberCount).reduce(0, +), 1, "churned links stayed subscribed")
        XCTAssertTrue(view.subviews.isEmpty, "churned links left anchors behind")
        waitForFrames(3, on: recorder)
    }

    func testRebindAndPauseStormEndsInTheRightState() throws {
        let window = try makeWindow()
        defer { window.close() }
        let view = PlatformView()
        window.contentView.addSubview(view)
        let recorder = FrameRecorder()
        let link = DisplayLink()
        link.delegate = recorder

        for index in 0 ..< 10000 {
            link.context = index.isMultiple(of: 3) ? .main : .view(view)
            link.isPaused = index.isMultiple(of: 7)
        }
        link.isPaused = false
        link.context = .view(view)
        XCTAssertEqual(view.subviews.count, 1, "exactly one anchor survives")
        XCTAssertEqual(SharedDisplayLink.links.count, 1)
        XCTAssertEqual(link.subscription?.subscriberCount, 1)
        waitForFrames(3, on: recorder)
    }

    func testManyViewsMoveBetweenWindowsTogether() throws {
        let first = try makeWindow()
        let second = try makeWindow()
        defer { first.close(); second.close() }
        let views = (0 ..< 200).map { _ in PlatformView() }
        let recorders = views.map { _ in FrameRecorder() }
        let links = zip(views, recorders).map { view, recorder in
            first.contentView.addSubview(view)
            let link = DisplayLink(context: .view(view))
            link.delegate = recorder
            return link
        }
        waitForFrames(3, on: recorders[0])

        views.forEach { second.contentView.addSubview($0) }
        let counts = recorders.map(\.count)
        XCTAssertTrue(spinMainRunLoop { zip(recorders, counts).allSatisfy { $0.count >= $1 + 3 } }, "some views stopped ticking after the move")
        XCTAssertEqual(links[0].subscription?.subscriberCount, 200)

        views.forEach { $0.removeFromSuperview() }
        XCTAssertTrue(SharedDisplayLink.links.isEmpty)
    }

    func testHundredStreamConsumers() async {
        var link: DisplayLink? = DisplayLink()
        let consumers = (0 ..< 100).map { _ in
            let frames = link!.frames
            return Task { @MainActor in
                var count = 0
                for await _ in frames { count += 1 }
                return count
            }
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        link = nil
        for consumer in consumers {
            let count = await consumer.value
            XCTAssertGreaterThan(count, 5, "a consumer starved")
        }
    }
}
