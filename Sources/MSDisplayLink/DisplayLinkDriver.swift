//
//  DisplayLinkDriver.swift
//  MSDisplayLink
//
//  Created by 秋星桥 on 2024/8/13.
//

import Combine
import Foundation

class DisplayLinkDriver: Identifiable {
    let id: UUID = .init()
    private let dispatchQueue = DispatchQueue(label: "wiki.qaq.vsync")

    private static let sharedLink = DisplayLinkDriverHelper.shared

    typealias SynchornizationSubject = PassthroughSubject<
        Void,
        Never
    >
    typealias SynchornizationPublisher = AnyPublisher<
        SynchornizationSubject.Output,
        SynchornizationSubject.Failure
    >

    let synchronizationSubject: SynchornizationSubject
    let synchronizationPublisher: SynchornizationPublisher

    init() {
        let subject = SynchornizationSubject()

        synchronizationSubject = subject
        synchronizationPublisher = subject
            .receive(on: dispatchQueue)
            .eraseToAnyPublisher()

        DisplayLinkDriverHelper.shared.delegate(self)
    }

    deinit {
        DisplayLinkDriverHelper.shared.remove(self)
    }

    func synchronize() { synchronizationSubject.send() }
}
