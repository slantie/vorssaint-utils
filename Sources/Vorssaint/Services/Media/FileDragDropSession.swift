// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// AppKit delivers the destination callbacks separately from the passive
/// mouse monitor. Releasing the mouse must retain the highlighted format until
/// prepare/perform have captured the drop, regardless of callback order.
struct FileDragDropSession<Choice: Equatable> {
    struct Drop {
        let inputs: [URL]
        let format: Choice
    }

    let inputs: [URL]
    let formats: [Choice]
    private(set) var selected: Choice?
    private(set) var mouseReleased = false
    private var prepared: Drop?
    private var consumed = false

    // Keep construction available to callers on the oldest supported Swift
    // toolchain, where private state makes the synthesized initializer private.
    init(inputs: [URL], formats: [Choice]) {
        self.inputs = inputs
        self.formats = formats
        selected = nil
    }

    mutating func select(_ format: Choice?) {
        guard !mouseReleased, prepared == nil, !consumed else { return }
        selected = format.flatMap { formats.contains($0) ? $0 : nil }
    }

    mutating func releaseMouse() {
        mouseReleased = true
    }

    mutating func prepare(formatAtDrop: Choice?) -> Bool {
        guard !consumed, !inputs.isEmpty,
              let format = formatAtDrop, formats.contains(format) else {
            prepared = nil
            return false
        }
        selected = format
        prepared = Drop(inputs: inputs, format: format)
        return true
    }

    mutating func takeDrop() -> Drop? {
        guard !consumed, let drop = prepared else { return nil }
        consumed = true
        prepared = nil
        return drop
    }
}
