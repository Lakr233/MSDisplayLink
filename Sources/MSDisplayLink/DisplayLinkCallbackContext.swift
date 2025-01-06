//
//  DisplayLinkCallbackContext.swift
//  MSDisplayLink
//
//  Created by 秋星桥 on 2025/1/6.
//

import Foundation

public struct DisplayLinkCallbackContext {
    /// The time interval between screen refresh updates.
    let duration: TimeInterval
    /// The time interval that represents when the last frame displayed.
    let timestamp: TimeInterval
    /// The time interval that represents when the next frame displays.
    let targetTimestamp: TimeInterval
}
