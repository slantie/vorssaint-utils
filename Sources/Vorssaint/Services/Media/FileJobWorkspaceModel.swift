// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation
import Combine

struct FileJobRow: Identifiable {
    enum State: Equatable { case pending, processing, cancelled, done(URL), failed(String) }
    let id = UUID()
    let input: URL
    var state = State.pending
    var elapsed = 0.0
}
final class FileJobWorkspaceModel: ObservableObject {
    let action: FileDragAction
    @Published private(set) var rows: [FileJobRow]
    @Published private(set) var busy = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published var subtitleTiming = SubtitleTiming()
    var needsTiming: Bool { if case .convert(let format) = action { return [.srt,.vtt].contains(format) && rows.contains { $0.input.pathExtension.lowercased() == "txt" } }; return false }
    private var batches = FileDragBatchSession()
    private let available: () -> Bool
    private let engines: MediaEngineBundle?
    private let publish: ([URL]) -> Void
    private let didFinishSuccessfully: () -> Void
    init(inputs: [URL],action: FileDragAction,engines: MediaEngineBundle? = .bundled,available: @escaping () -> Bool = { AppFeature.mediaTools.isAvailable },publish: @escaping ([URL]) -> Void = { _ in },didFinishSuccessfully: @escaping () -> Void = {}) throws {
        guard !inputs.isEmpty, inputs.count <= 500 else { throw CocoaError(.fileReadTooLarge) }
        switch action { case .convert,.extractArchive: break; default: throw CocoaError(.fileReadUnsupportedScheme) }
        rows = inputs.map { FileJobRow(input:$0) }; self.action = action; self.engines = engines; self.available = available; self.publish = publish
        self.didFinishSuccessfully = didFinishSuccessfully
    }
    var isAvailable: Bool { available() }
    var hasFailures: Bool { rows.contains { if case .failed = $0.state { return true }; return $0.state == .cancelled } }
    func run(retryFailures: Bool = false) {
        guard isAvailable, !busy, !needsTiming || subtitleTiming.isValid else { return }
        let jobs = rows.enumerated().filter { _,row in if !retryFailures { return true }; if case .failed = row.state { return true }; return row.state == .cancelled }
        guard !jobs.isEmpty, let batch = batches.begin() else { return }
        busy = true; completed = 0; total = jobs.count
        for (index,_) in jobs { rows[index].state = .pending; rows[index].elapsed = 0 }
        let action = action, engines = engines, timing = subtitleTiming
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            var outputs: [URL] = []
            for (number,job) in jobs.enumerated() {
                guard !batch.isCancelled else { break }
                DispatchQueue.main.async { [weak self] in guard !batch.isCancelled else { return }; self?.rows[job.offset].state = .processing }
                let start = Date()
                let result = Result { () -> URL in
                    switch action {
                    case .convert(let format): return try FileDragConversionEngine.convert(job.element.input,to:format,batch:batch,engines:engines,subtitleTiming:timing)
                    case .extractArchive: return try FileArchiveTools.extract(job.element.input,batch:batch)
                    default: throw CocoaError(.fileReadUnsupportedScheme)
                    }
                }
                if let output = try? result.get() { outputs.append(output) }
                let elapsed = Date().timeIntervalSince(start)
                DispatchQueue.main.async { [weak self] in
                    guard let self, !batch.isCancelled, self.isAvailable else { return }
                    switch result { case .success(let output): self.rows[job.offset].state = .done(output); case .failure(let error): self.rows[job.offset].state = .failed(error.localizedDescription) }
                    self.rows[job.offset].elapsed = elapsed; self.completed = number+1
                }
            }
            let saved = outputs
            DispatchQueue.main.async {
                guard let self else { return }
                let completion = self.batches.finish(batch,featureAvailable:self.isAvailable,enabled:self.isAvailable)
                guard completion != .obsolete else { return }; self.busy = false
                // Recheck ownership and availability after a partial batch, before
                // revealing anything. Completed files remain safely on disk.
                guard completion == .publish else { return }
                if !saved.isEmpty {
                    if self.rows.allSatisfy({ if case .done = $0.state { return true }; return false }) {
                        self.didFinishSuccessfully()
                    }
                    self.publish(saved)
                }
            }
        }
    }
    func cancel() {
        batches.cancel()
        for index in rows.indices where rows[index].state == .pending || rows[index].state == .processing { rows[index].state = .cancelled }
    }
}
