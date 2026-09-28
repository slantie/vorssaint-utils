// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

final class ImageWorkspaceModel: ObservableObject {
    let tool: ImageFileTool
    @Published private(set) var inputs: [URL]
    @Published private(set) var edit = ImageFileEdit()
    @Published private(set) var preview: CGImage?
    @Published private(set) var busy = false
    @Published private(set) var completed = 0
    @Published private(set) var message: String?
    @Published private(set) var failures: [URL: String] = [:]
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    let sourceSize: CGSize
    private struct State { let edit: ImageFileEdit; let inputs: [URL] }
    private var undoStack: [State] = [], redoStack: [State] = []
    private var state: State { State(edit: edit, inputs: inputs) }
    private var previewWork: DispatchWorkItem?
    private var previewBatch = FileDragBatch()
    private let previewQueue = DispatchQueue(label: "com.vorssaint.media.image-preview", qos: .userInitiated)
    private var previewVersion = 0
    private var editingGroup = false
    private var batches = FileDragBatchSession()
    private let available: () -> Bool
    private let publish: ([URL]) -> Void
    init(inputs: [URL], tool: ImageFileTool, available: @escaping () -> Bool = { AppFeature.mediaTools.isAvailable },
         publish: @escaping ([URL]) -> Void = { _ in }) throws {
        try ImageFileTools.validate(inputs)
        guard tool != .collage || inputs.count > 1 else { throw CocoaError(.validationMissingMandatoryProperty) }
        self.inputs = inputs; self.tool = tool; self.available = available; self.publish = publish
        guard let size = MediaSupport.imageDisplaySize(at: inputs[0]) else { throw CocoaError(.fileReadCorruptFile) }
        sourceSize = size
        if tool == .compress { edit.format = .jpeg }
        if tool == .background { edit.width = Int(sourceSize.width) }
        if tool == .collage { edit.width = 1600; edit.height = 1200 }
        refreshPreview()
    }
    var isAvailable: Bool { available() }
    func change(_ mutate: (inout ImageFileEdit) -> Void, recordUndo: Bool = true) {
        guard isAvailable, !busy else { return }
        var next = edit; mutate(&next); guard next != edit else { return }
        if recordUndo || !editingGroup { undoStack.append(state); if undoStack.count > 60 { undoStack.removeFirst() }; redoStack.removeAll() }
        edit = next; historyState(); refreshPreview()
    }
    func beginEditing() {
        guard isAvailable, !busy else { return }
        undoStack.append(state); if undoStack.count > 60 { undoStack.removeFirst() }; redoStack.removeAll(); historyState(); editingGroup = true
    }
    func endEditing() { editingGroup = false }
    func undo() { guard isAvailable, !busy, let state = undoStack.popLast() else { return }; redoStack.append(self.state); edit = state.edit; inputs = state.inputs; historyState(); refreshPreview() }
    func redo() { guard isAvailable, !busy, let state = redoStack.popLast() else { return }; undoStack.append(self.state); edit = state.edit; inputs = state.inputs; historyState(); refreshPreview() }
    private func historyState() { canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty }
    func moveInput(_ index: Int, offset: Int) {
        guard isAvailable, !busy, tool == .pdf || tool == .collage, inputs.indices.contains(index), inputs.indices.contains(index + offset) else { return }
        undoStack.append(state); if undoStack.count > 60 { undoStack.removeFirst() }; redoStack.removeAll(); historyState()
        let url = inputs.remove(at: index); inputs.insert(url, at: index + offset); refreshPreview()
    }
    private func refreshPreview() {
        previewVersion += 1; previewWork?.cancel(); previewBatch.cancel(); previewBatch = FileDragBatch()
        let version = previewVersion, input = inputs[0], urls = inputs, edit = edit, tool = tool, batch = previewBatch
        let work = DispatchWorkItem { [weak self] in
            let result = Result { () -> CGImage in
                guard !batch.isCancelled else { throw CancellationError() }
                if tool == .collage { return try ImageFileTools.collage(urls, edit: edit, preview: true, batch: batch) }
                // Crop and redaction use the source canvas for precise area selection.
                let image = try ImageFileTools.load(input, preview: true)
                return tool == .crop || tool == .pdf ? image : try ImageFileTools.render(image, edit: edit, tool: tool, preview: true, batch: batch)
            }
            DispatchQueue.main.async {
                guard let self, version == self.previewVersion, self.isAvailable else { return }
                switch result { case .success(let image): self.preview = image; self.message = nil
                case .failure(let error): self.message = error.localizedDescription }
            }
        }
        previewWork = work; previewQueue.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    func save(retryFailures: Bool = false) {
        guard isAvailable, let batch = batches.begin() else { return }
        busy = true; completed = 0; message = nil
        let urls = retryFailures ? inputs.filter { failures[$0] != nil } : inputs
        failures = [:]
        let tool = tool, edit = edit
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var outputs: [URL] = [], failures: [URL: String] = [:]
            let jobs = tool == .pdf || tool == .collage ? [urls] : urls.map { [$0] }
            for (index, job) in jobs.enumerated() {
                guard !batch.isCancelled else { break }
                do { outputs += try ImageFileTools.save(job, tool: tool, edit: edit, batch: batch) }
                catch { if !batch.isCancelled { for url in job { failures[url] = error.localizedDescription } } }
                DispatchQueue.main.async { [weak self] in guard let self, !batch.isCancelled else { return }; self.completed = index + 1 }
            }
            let saved = outputs, errors = failures
            DispatchQueue.main.async {
                guard let self else { return }
                let completion = self.batches.finish(batch, featureAvailable: self.isAvailable, enabled: self.isAvailable)
                guard completion != .obsolete else { return }
                self.busy = false
                guard completion == .publish else { self.message = nil; return }
                self.failures = errors
                self.message = saved.map(\.lastPathComponent).joined(separator: ", ")
                if !saved.isEmpty { self.publish(saved) }
            }
        }
    }
    func cancel() { batches.cancel(); previewBatch.cancel(); previewVersion += 1; previewWork?.cancel() }
}
