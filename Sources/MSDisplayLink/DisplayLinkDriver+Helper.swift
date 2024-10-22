//
//  DisplayLinkDriver+Helper.swift
//
//
//  Created by 秋星桥 on 2024/8/29.
//

import Foundation

class DisplayLinkDriverHelperBase: Identifiable {
    final let id: UUID = .init()

    private(set) var referenceHolder: [WeakBox] = []
    final let lock = NSLock()

    struct WeakBox { weak var object: DisplayLinkDriver? }

    final func delegate(_ object: DisplayLinkDriver) {
        var shouldStartDisplayLink = false
        defer { if shouldStartDisplayLink { startDisplayLink() } }

        lock.lock()
        defer { lock.unlock() }

        referenceHolder = referenceHolder
            .filter { $0.object != nil }
            .filter { $0.object?.id != object.id }
            + [.init(object: object)]

        shouldStartDisplayLink = !referenceHolder.isEmpty
    }

    final func remove(_ object: DisplayLinkDriver) {
        lock.lock()
        defer { lock.unlock() }

        referenceHolder = referenceHolder.filter { $0.object?.id != object.id }
    }

    final func reclaimComputeResourceIfPossible() {
        var shouldStop = false
        defer { if shouldStop { stopDisplayLink() } }

        lock.lock()
        defer { lock.unlock() }

        referenceHolder = referenceHolder.filter { $0.object != nil }
        shouldStop = referenceHolder.isEmpty
    }

    final func dispatchUpdate() {
        defer { reclaimComputeResourceIfPossible() }

        lock.lock()
        defer { lock.unlock() }

        for box in referenceHolder {
            box.object?.synchronize()
        }
    }

    func startDisplayLink() {
        fatalError("Subclasses need to implement the `startDisplayLink()` method.")
    }

    func stopDisplayLink() {
        fatalError("Subclasses need to implement the `stopDisplayLink()` method.")
    }
}
