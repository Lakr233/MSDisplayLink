//
//  DisplayLink.swift
//  MSDisplayLink
//
//  Created by 秋星桥 on 2024/8/13.
//

@preconcurrency import Combine
import Foundation

public protocol DisplayLinkDelegate: AnyObject {
    func synchronization(context: DisplayLinkCallbackContext)
}

open class DisplayLink: @unchecked Sendable {
    private weak var delegatingObject: DisplayLinkDelegate?

    private var driver: DisplayLinkDriver?
    private var driverSubscription: Set<AnyCancellable> = .init()

    /// The frame rate this instance asks the display for. All live
    /// `DisplayLink` instances share one platform link, so the applied
    /// range is the union of every instance's request — one caller asking
    /// for 120 lifts the shared link to 120 without slowing anyone else.
    /// Set from the main thread.
    open var preferredFrameRateRange: DisplayLinkFrameRateRange {
        get { driver?.preferredFrameRateRange ?? .default }
        set { driver?.preferredFrameRateRange = newValue }
    }

    public init(preferredFrameRateRange: DisplayLinkFrameRateRange = .default) {
        let driver = DisplayLinkDriver()
        driver.preferredFrameRateRange = preferredFrameRateRange
        driver.synchronizationPublisher
            .sink { [weak self] output in self?.delegatingObject?.synchronization(context: output) }
            .store(in: &driverSubscription)
        self.driver = driver
    }

    deinit { teardown() }

    func teardown() {
        driverSubscription.forEach { $0.cancel() }
        driverSubscription.removeAll()
        driver = nil
    }

    open func delegatingObject(_ object: DisplayLinkDelegate?) {
        delegatingObject = object
    }
}
