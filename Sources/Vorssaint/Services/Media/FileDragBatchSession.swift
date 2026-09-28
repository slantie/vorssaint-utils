// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Owned by the UI thread. Encoding can finish before its queued completion
/// runs, so presentation must use the current session and preferences.
struct FileDragBatchSession {
    enum Completion: Equatable { case obsolete, suppressed, publish }

    private var active: FileDragBatch?
    var isProcessing: Bool { active != nil }

    mutating func begin() -> FileDragBatch? {
        guard active == nil else { return nil }
        let batch = FileDragBatch()
        active = batch
        return batch
    }

    func cancel() {
        active?.cancel()
    }

    mutating func finish(_ batch: FileDragBatch, featureAvailable: Bool,
                         enabled: Bool) -> Completion {
        guard active === batch else { return .obsolete }
        active = nil
        guard !batch.isCancelled, featureAvailable, enabled else { return .suppressed }
        return .publish
    }
}
