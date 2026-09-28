// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation
import Combine
final class FileMetadataWorkspaceModel: ObservableObject {
    let input: URL
    @Published private(set) var snapshot: FileMetadataSnapshot?
    @Published private(set) var busy = true
    @Published private(set) var message: String?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    private var undoStack: [[FileMetadataSection]] = [], redoStack: [[FileMetadataSection]] = []
    private var batches = FileDragBatchSession()
    private let available: () -> Bool
    private let engines: MediaEngineBundle?
    private let publish: ([URL]) -> Void
    init(input: URL, engines: MediaEngineBundle? = .bundled, available: @escaping () -> Bool = { AppFeature.mediaTools.isAvailable }, publish: @escaping ([URL]) -> Void = { _ in }) {
        self.input = input; self.engines = engines; self.available = available; self.publish = publish
        guard let batch = batches.begin() else { busy = false; return }
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result = Result { try FileMetadataTools.read(input,engines:engines,batch:batch) }
            DispatchQueue.main.async {
                guard let self else { return }
                let completion = self.batches.finish(batch,featureAvailable:self.isAvailable,enabled:self.isAvailable)
                guard completion != .obsolete else { return }; self.busy = false; guard completion == .publish else { return }
                switch result { case .success(let snapshot): self.snapshot = snapshot; case .failure(let error): self.message = error.localizedDescription }
            }
        }
    }
    var isAvailable: Bool { available() }
    func change(sectionID: String,key: String,value: String?) {
        guard isAvailable, !busy, var snapshot, let index = snapshot.sections.firstIndex(where: { $0.id == sectionID }), snapshot.sections[index].tags[key] != value else { return }
        undoStack.append(snapshot.sections); if undoStack.count > 60 { undoStack.removeFirst() }; redoStack.removeAll()
        snapshot.sections[index].tags[key] = value; self.snapshot = snapshot; history()
    }
    private func history() { canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty }
    func undo() { guard isAvailable, !busy, var snapshot, let prior = undoStack.popLast() else { return }; redoStack.append(snapshot.sections); snapshot.sections = prior; self.snapshot = snapshot; history() }
    func redo() { guard isAvailable, !busy, var snapshot, let next = redoStack.popLast() else { return }; undoStack.append(snapshot.sections); snapshot.sections = next; self.snapshot = snapshot; history() }
    func save(remove: Bool) {
        guard isAvailable, let snapshot, let batch = batches.begin() else { return }
        busy = true; message = nil; let input = input, engines = engines
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result = Result { try FileMetadataTools.save(input,snapshot:snapshot,remove:remove,engines:engines,batch:batch) }
            DispatchQueue.main.async {
                guard let self else { return }
                let completion = self.batches.finish(batch,featureAvailable:self.isAvailable,enabled:self.isAvailable)
                guard completion != .obsolete else { return }; self.busy = false; guard completion == .publish else { return }
                switch result { case .success(let url): self.message = url.lastPathComponent; self.publish([url]); case .failure(let error): self.message = error.localizedDescription }
            }
        }
    }
    func cancel() { batches.cancel() }
}
