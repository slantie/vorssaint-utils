// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import PDFKit
import UniformTypeIdentifiers

final class PDFWorkspaceModel: ObservableObject {
    @Published var tool: PDFTool { didSet { refreshMetadata() } }
    @Published private(set) var inputs: [URL]
    @Published var plan: PDFEditPlan {
        didSet { if !historySuspended && plan != oldValue { var previous = state; previous.plan = oldValue; record(previous) } }
    }
    @Published var metadata: PDFMetadata {
        didSet { if !historySuspended && metadata != oldValue { var previous = state; previous.metadata = oldValue; record(previous) } }
    }
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var splitRangeText = ""
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var qrResults: [String] = []
    @Published private(set) var qrScanned = false
    private struct State {
        var plan: PDFEditPlan
        var metadata: PDFMetadata
        var inputs: [URL]
        var resetInputs: [URL]
        var metadataSource: URL
    }
    private var undoStack: [State] = [], redoStack: [State] = []
    private var historySuspended = false
    private var state: State { State(plan: plan, metadata: metadata, inputs: inputs, resetInputs: resetInputs, metadataSource: metadataSource) }
    private func record(_ state: State) {
        guard !busy else { return }
        undoStack.append(state); if undoStack.count > 60 { undoStack.removeFirst() }; redoStack.removeAll(); historyFlags()
    }
    private func historyFlags() { canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty }
    private func grouped(_ change: () -> Void) { record(state); historySuspended = true; defer { historySuspended = false }; change() }
    private func restore(_ state: State) {
        historySuspended = true
        plan = state.plan; metadata = state.metadata; inputs = state.inputs; resetInputs = state.resetInputs; metadataSource = state.metadataSource
        historySuspended = false; message = nil; historyFlags()
    }
    func undo() { guard isAvailable, !busy, let previous = undoStack.popLast() else { return }; redoStack.append(state); restore(previous) }
    func redo() { guard isAvailable, !busy, let next = redoStack.popLast() else { return }; undoStack.append(state); restore(next) }
    private var batches = FileDragBatchSession()
    private let requiresDragEnabled: Bool
    private let featureAvailable: () -> Bool
    private let dragEnabled: () -> Bool
    private let publishOutputs: ([URL]) -> Void
    private var metadataSource: URL
    private var resetInputs: [URL]
    private var thumbnails: [String: NSImage] = [:]
    private var documents: [URL: PDFDocument] = [:]
    private var dropImportVersion = 0

    init(inputs: [URL], tool: PDFTool, requiresDragEnabled: Bool = false,
         featureAvailable: @escaping () -> Bool = { AppFeature.mediaTools.isAvailable },
         dragEnabled: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: DefaultsKey.mediaDragConvertEnabled) },
         publishOutputs: @escaping ([URL]) -> Void = { _ in }) throws {
        var unique: [URL] = []
        for input in inputs where !unique.contains(input) { unique.append(input) }
        self.inputs = unique; resetInputs = unique; self.tool = tool; self.requiresDragEnabled = requiresDragEnabled
        self.featureAvailable = featureAvailable; self.dragEnabled = dragEnabled; self.publishOutputs = publishOutputs
        plan = try PDFTools.plan(unique)
        metadata = try PDFTools.metadata(unique[0]); metadataSource = unique[0]
    }
    var isAvailable: Bool { featureAvailable() && (!requiresDragEnabled || dragEnabled()) }
    var requiresSingleDocument: Bool { tool == .metadata }
    var canSave: Bool {
        isAvailable && !busy && !plan.pages.isEmpty && (!requiresSingleDocument || inputs.count == 1) && tool != .readQR
            && (tool != .metadata || metadataSource == inputs.first)
    }
    func thumbnail(_ page: PDFPageEdit) -> NSImage? {
        let key = page.source.path + "#" + String(page.index)
        if let cached = thumbnails[key] { return cached }
        if documents[page.source] == nil { documents[page.source] = try? PDFTools.document(page.source) }
        guard let image = documents[page.source]?.page(at: page.index)?.thumbnail(of: NSSize(width: 144, height: 180), for: .mediaBox) else { return nil }
        if thumbnails.count >= 128 { thumbnails.removeAll() }
        thumbnails[key] = image
        return image
    }
    func reset() {
        guard isAvailable, !busy else { return }
        grouped {
            inputs = resetInputs
            orderPageGroups(originalPageOrder: true)
            message = nil; refreshMetadata()
        }
    }
    /// Validate the whole addition before committing state. Existing page
    /// instances keep their identifiers, order, rotations and removal history.
    func append(_ urls: [URL]) throws {
        guard isAvailable, !busy else { throw CancellationError() }
        var additions: [URL] = []
        for url in urls where !inputs.contains(url) && !additions.contains(url) { additions.append(url) }
        guard !additions.isEmpty else { return }
        let added = try PDFTools.plan(additions)
        guard plan.pages.count + added.pages.count <= PDFTools.maxPages else { throw CocoaError(.fileReadTooLarge) }
        grouped {
            plan.pages.append(contentsOf: added.pages)
            inputs.append(contentsOf: additions); resetInputs.append(contentsOf: additions)
            message = nil; refreshMetadata()
        }
    }

    /// Load Finder file URLs together before appending so one invalid file
    /// cannot partially alter the plan, and provider order stays intact.
    func importDroppedPDFs(_ providers: [NSItemProvider]) -> Bool {
        guard isAvailable, !busy, !requiresSingleDocument, !providers.isEmpty,
              providers.count <= PDFTools.maxPages,
              providers.allSatisfy({ $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        let version = dropImportVersion
        let group = DispatchGroup(), lock = NSLock()
        var loaded: [(offset: Int, url: URL)] = []
        for (offset, provider) in providers.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let value = item as? URL { url = value }
                else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let value = item as? String { url = URL(string: value) }
                else { url = nil }
                if let url, url.isFileURL {
                    lock.lock(); loaded.append((offset, url)); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, self.dropImportVersion == version, self.isAvailable, !self.busy else { return }
            do {
                guard loaded.count == providers.count else { throw CocoaError(.fileReadUnsupportedScheme) }
                try self.append(MediaSupport.urlsInProviderOrder(loaded))
                if self.tool == .readQR { self.scanQR() }
            } catch { self.report(error) }
        }
        return true
    }
    func moveDocument(_ index: Int, offset: Int) {
        guard inputs.indices.contains(index) else { return }
        moveDocument(inputs[index], to: index + offset)
    }
    func moveDocument(_ url: URL, to index: Int) {
        guard isAvailable, !busy, let current = inputs.firstIndex(of: url), inputs.indices.contains(index) else { return }
        grouped { inputs.remove(at: current); inputs.insert(url, at: index); orderPageGroups(); refreshMetadata() }
    }
    func sortDocuments() {
        guard isAvailable, !busy else { return }
        grouped {
            inputs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            orderPageGroups(); refreshMetadata()
        }
    }
    private func orderPageGroups(originalPageOrder: Bool = false) {
        let ranks = Dictionary(uniqueKeysWithValues: inputs.enumerated().map { ($0.element, $0.offset) })
        plan.pages = plan.pages.enumerated().sorted {
            let left = ranks[$0.element.source] ?? Int.max, right = ranks[$1.element.source] ?? Int.max
            if left != right { return left < right }
            if originalPageOrder && $0.element.index != $1.element.index { return $0.element.index < $1.element.index }
            return $0.offset < $1.offset
        }.map(\.element)
    }
    private func refreshMetadata() {
        guard inputs.count == 1, let source = inputs.first, source != metadataSource else { return }
        do { metadata = try PDFTools.metadata(source); metadataSource = source }
        catch { metadata = PDFMetadata(); message = error.localizedDescription }
    }
    func scanQR() {
        guard isAvailable, let batch = batches.begin() else { return }
        busy = true; message = nil; qrScanned = false
        let sources = inputs
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try PDFTools.readQR(sources, batch: batch) }
            DispatchQueue.main.async {
                guard let self else { return }
                let completion = self.batches.finish(batch, featureAvailable: self.featureAvailable(), enabled: self.isAvailable)
                guard completion != .obsolete else { return }
                self.busy = false
                guard completion == .publish else { return }
                self.qrScanned = true
                switch result {
                case .success(let codes): self.qrResults = codes
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
    }
    func removeDocument(_ index: Int) {
        guard isAvailable, !busy, inputs.indices.contains(index), inputs.count > 1 else { return }
        grouped {
            let removed = inputs.remove(at: index)
            plan.pages.removeAll { $0.source == removed }
            resetInputs.removeAll { $0 == removed }
            documents[removed] = nil; thumbnails = thumbnails.filter { !$0.key.hasPrefix(removed.path + "#") }
            refreshMetadata()
        }
    }
    func report(_ error: Error) { message = error.localizedDescription }
    func cancel() { dropImportVersion += 1; batches.cancel(); message = nil }
    func save() {
        guard canSave else { return }
        var prepared = plan
        if tool == .split {
            do { prepared.splitGroups = try PDFTools.splitGroups(splitRangeText, pageCount: plan.pages.count) }
            catch { report(error); return }
        }
        guard let batch = batches.begin() else { return }
        busy = true; message = nil
        let snapshot = prepared, tool = tool, metadata = metadata, inputs = inputs
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                if tool == .compress {
                    return try inputs.map { try PDFTools.save(PDFTools.plan([$0]), tool: .compress, batch: batch) }
                }
                return [try PDFTools.save(snapshot, tool: tool, metadata: metadata, batch: batch)]
            }
            DispatchQueue.main.async {
                guard let self else { return }
                let completion = self.batches.finish(batch, featureAvailable: self.featureAvailable(), enabled: self.isAvailable)
                guard completion != .obsolete else { return }
                self.busy = false
                guard completion == .publish else { self.message = nil; return }
                switch result {
                case .success(let outputs):
                    self.message = outputs.map(\.lastPathComponent).joined(separator: ", ")
                    self.publishOutputs(outputs)
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
    }
}
