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
        lock.lock()

        referenceHolder = referenceHolder
            .filter { $0.object != nil }
            .filter { $0.object?.id != object.id }
            + [.init(object: object)]

        let shouldStartDisplayLink = !referenceHolder.isEmpty
        lock.unlock()

        if shouldStartDisplayLink { startDisplayLink() }
    }

    final func remove(_ object: DisplayLinkDriver) {
        lock.lock()
        defer { lock.unlock() }

        referenceHolder = referenceHolder.filter { $0.object?.id != object.id }
    }

    final func reclaimComputeResourceIfPossible() {
        lock.lock()
        referenceHolder = referenceHolder.filter { $0.object != nil }
        let shouldStop = referenceHolder.isEmpty
        lock.unlock()

        if shouldStop { stopDisplayLink() }
    }

    final func dispatchUpdate() {
        lock.lock()
        for box in referenceHolder {
            box.object?.synchronize()
        }
        lock.unlock()
        reclaimComputeResourceIfPossible()
    }

    func startDisplayLink() {
        fatalError("Subclasses need to implement the `startDisplayLink()` method.")
    }

    func stopDisplayLink() {
        fatalError("Subclasses need to implement the `stopDisplayLink()` method.")
    }
}
