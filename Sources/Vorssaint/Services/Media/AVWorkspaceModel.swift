// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import Combine

final class AVWorkspaceModel: ObservableObject {
    let tool: AVFileTool
    @Published private(set) var inputs: [URL]
    @Published private(set) var edit = AVFileEdit()
    @Published private(set) var info: AVFileInfo?
    @Published private(set) var preview: CGImage?
    @Published private(set) var busy = false
    @Published private(set) var completed = 0
    @Published private(set) var failures: [URL: String] = [:]
    @Published private(set) var outputs: [URL] = []
    @Published private(set) var message: String?
    @Published private(set) var normalization: AVFileResult?
    @Published private(set) var processedPreview: URL?
    @Published private(set) var previewStart = 0.0
    private var previewDirectory: URL?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    private struct State { let edit: AVFileEdit; let inputs: [URL] }
    private var state: State { State(edit: edit, inputs: inputs) }
    private var undoStack: [State] = [], redoStack: [State] = []
    private var batches = FileDragBatchSession()
    private var previewBatch = FileDragBatch()
    private var previewVersion = 0
    private let queue = DispatchQueue(label: "com.vorssaint.media.av-preview", qos: .userInitiated)
    private let engines: MediaEngineBundle
    private let available: () -> Bool
    private let publish: ([URL]) -> Void
    init(inputs: [URL], tool: AVFileTool, engines: MediaEngineBundle, available: @escaping () -> Bool = { AppFeature.mediaTools.isAvailable }, publish: @escaping ([URL]) -> Void = { _ in }) throws {
        guard !inputs.isEmpty, inputs.count <= 100, tool != .videoJoin || inputs.count > 1 else { throw CocoaError(.validationMissingMandatoryProperty) }
        self.inputs = inputs; self.tool = tool; self.engines = engines; self.available = available; self.publish = publish
        refreshPreview()
    }
    var isAvailable: Bool { available() }
    func change(_ mutate: (inout AVFileEdit) -> Void) {
        guard isAvailable, !busy else { return }; var next = edit; mutate(&next); guard next != edit else { return }
        remember(); edit = next
    }
    private func remember() { undoStack.append(state); if undoStack.count > 60 { undoStack.removeFirst() }; redoStack.removeAll(); history() }
    private func history() { canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty }
    func undo() { guard isAvailable, !busy, let old = undoStack.popLast() else { return }; redoStack.append(state); edit = old.edit; inputs = old.inputs; history() }
    func redo() { guard isAvailable, !busy, let next = redoStack.popLast() else { return }; undoStack.append(state); edit = next.edit; inputs = next.inputs; history() }
    func moveInput(_ index: Int, offset: Int) {
        guard isAvailable, !busy, tool == .videoJoin, inputs.indices.contains(index), inputs.indices.contains(index+offset) else { return }
        remember(); let url = inputs.remove(at: index); inputs.insert(url, at: index+offset); refreshPreview()
    }
    func refreshPreview(time: Double = 0) {
        previewBatch.cancel(); previewBatch = FileDragBatch(); previewVersion += 1
        let batch = previewBatch, version = previewVersion, input = inputs[0], engines = engines
        queue.async { [weak self] in
            let result = Result { () -> (AVFileInfo, CGImage) in
                let info = try AVFileTools.info(input, engines: engines, batch: batch)
                return (info, try AVFileTools.preview(input, info: info, engines: engines, batch: batch, time: time))
            }
            DispatchQueue.main.async {
                guard let self, version == self.previewVersion, !batch.isCancelled, self.isAvailable else { return }
                switch result {
                case .success(let (info,image)):
                    self.info = info; self.preview = image; self.message = nil
                    if self.edit.end == 0 { self.edit.end = info.duration }
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
    }
    func save(retryFailures: Bool = false) {
        guard isAvailable, info != nil, let batch = batches.begin() else { return }
        previewBatch.cancel(); busy = true; completed = 0; message = nil
        let inputs = retryFailures ? inputs.filter { failures[$0] != nil } : inputs, edit = edit, tool = tool, engines = engines
        guard !inputs.isEmpty else { _ = batches.finish(batch, featureAvailable: true, enabled: true); busy = false; return }
        failures = [:]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var results: [AVFileResult] = [], errors: [URL: String] = [:]
            let jobs = tool == .videoJoin ? [inputs] : inputs.map { [$0] }
            for (index,job) in jobs.enumerated() {
                guard !batch.isCancelled else { break }
                do { results.append(try AVFileTools.save(job, tool: tool, edit: edit, engines: engines, batch: batch)) }
                catch { if !batch.isCancelled { for url in job { errors[url] = error.localizedDescription } } }
                DispatchQueue.main.async { [weak self] in guard !batch.isCancelled else { return }; self?.completed = index+1 }
            }
            let saved = results, failures = errors
            DispatchQueue.main.async {
                guard let self else { return }
                let completion = self.batches.finish(batch, featureAvailable: self.isAvailable, enabled: self.isAvailable)
                guard completion != .obsolete else { return }; self.busy = false
                guard completion == .publish else { return }
                self.outputs = saved.map(\.output); self.failures = failures
                self.normalization = saved.last { $0.inputLoudness != nil }
                self.message = self.outputs.map(\.lastPathComponent).joined(separator: ", ")
                if !self.outputs.isEmpty { self.publish(self.outputs) }
            }
        }
    }
    func detectSilence() {
        guard isAvailable, let info, let batch = batches.begin() else { return }
        busy = true; message = nil; let input = inputs[0], engines = engines
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result = Result { try AVFileTools.silenceEndpoints(input,info:info,engines:engines,batch:batch) }
            DispatchQueue.main.async {
                guard let self else { return }
                let completion = self.batches.finish(batch,featureAvailable:self.isAvailable,enabled:self.isAvailable)
                guard completion != .obsolete else { return }; self.busy = false; guard completion == .publish else { return }
                switch result {
                case .success(let range): self.change { $0.start = range.lowerBound; $0.end = range.upperBound }
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
    }
    func previewProcessed(editOverride: AVFileEdit? = nil) {
        guard isAvailable, let info, ![.videoJoin,.videoSplit,.videoFrames,.videoCompress,.audioVisualizer].contains(tool), let batch = batches.begin() else { return }
        previewBatch.cancel(); busy = true; message = nil
        let folder = previewDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-av-preview-\(UUID().uuidString)")
        previewDirectory = folder
        let source = inputs[0], edit = editOverride ?? edit, tool = tool, engines = engines
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result = Result { () -> (URL,Double) in
                defer { if batch.isCancelled { try? FileManager.default.removeItem(at:folder) } }
                guard !batch.isCancelled else { throw CancellationError() }
                if FileManager.default.fileExists(atPath:folder.path) { try FileManager.default.removeItem(at:folder) }
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                var clip = AVFileEdit()
                if tool == .audioTrim || tool == .videoTrim { clip.start = edit.start; clip.end = min(edit.end == 0 ? info.duration : edit.end,edit.start+30) }
                else { clip.start = min(edit.areas.first?.start ?? 0,max(0,info.duration-0.001)); clip.end = min(info.duration,clip.start+30) }
                let trimmed = try AVFileTools.save([source],tool:tool.isVideo ? .videoTrim : .audioTrim,edit:clip,engines:engines,batch:batch,outputDirectory:folder).output
                if tool == .audioTrim || tool == .videoTrim { return (trimmed,clip.start) }
                var options = edit; options.start = 0; options.end = 0
                options.areas = edit.areas.compactMap { area in
                    let start = max(clip.start,area.start), end = min(clip.end,area.end)
                    guard end > start else { return nil }; var next = area; next.start = start-clip.start; next.end = end-clip.start; return next
                }
                return (try AVFileTools.save([trimmed],tool:tool,edit:options,engines:engines,batch:batch,outputDirectory:folder).output,clip.start)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                let completion = self.batches.finish(batch,featureAvailable:self.isAvailable,enabled:self.isAvailable)
                guard completion != .obsolete else { return }; self.busy = false; guard completion == .publish else { return }
                switch result { case .success(let (url,start)): self.processedPreview = url; self.previewStart = start; case .failure(let error): self.message = error.localizedDescription }
            }
        }
    }
    func cancel() {
        batches.cancel(); previewBatch.cancel(); previewVersion += 1
        if let folder = previewDirectory { try? FileManager.default.removeItem(at:folder); previewDirectory = nil }
    }

}
