//
//  DisplayLinkDriver.swift
//  MSDisplayLink
//
//  Created by 秋星桥 on 2024/8/13.
//

@preconcurrency import Combine
import Foundation

/// Its owning `DisplayLink` is `Sendable`, so a driver can be created and
/// released on any thread. The shared helper is main-thread only; every call
/// into it hops there first.
class DisplayLinkDriver: Identifiable, @unchecked Sendable {
    let id: UUID = .init()

    typealias SynchornizationPublisher = PassthroughSubject<
        DisplayLinkCallbackContext,
        Never
    >
    let synchronizationPublisher: SynchornizationPublisher

    /// This driver's vote on the shared link's rate — see
    /// ``DisplayLink/preferredFrameRateRange``.
    var preferredFrameRateRange: DisplayLinkFrameRateRange = .default {
        didSet {
            guard preferredFrameRateRange != oldValue else { return }
            Self.onMainThread { DisplayLinkDriverHelper.shared.frameRatePreferencesDidChange() }
        }
    }

    init() {
        synchronizationPublisher = .init()
        Self.onMainThread { [weak self] in
            guard let self else { return }
            DisplayLinkDriverHelper.shared.delegate(self)
        }
    }

    deinit {
        let id = id
        Self.onMainThread { DisplayLinkDriverHelper.shared.remove(id: id) }
    }

    private static func onMainThread(_ work: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func synchronize(context: DisplayLinkCallbackContext) {
        synchronizationPublisher.send(context)
    }
}
