//
//  DisplayLink.swift
//  MSDisplayLink
//
//  Created by 秋星桥 on 2024/8/13.
//

import Combine
import Foundation

public protocol DisplayLinkDelegate: AnyObject {
    func synchronization()
}

public class DisplayLink {
    private weak var delegatingObject: DisplayLinkDelegate?

    private var driver: DisplayLinkDriver?
    private var driverSubscription: Set<AnyCancellable> = .init()

    public init() {
        let driver = DisplayLinkDriver()
        driver.synchronizationPublisher
            .sink { [weak self] _ in self?.delegatingObject?.synchronization() }
            .store(in: &driverSubscription)
        self.driver = driver
    }

    deinit { teardown() }

    func teardown() {
        driverSubscription.forEach { $0.cancel() }
        driverSubscription.removeAll()
        driver = nil
    }

    public func delegatingObject(_ object: DisplayLinkDelegate?) {
        delegatingObject = object
    }
}
