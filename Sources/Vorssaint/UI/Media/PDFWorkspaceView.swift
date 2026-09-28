// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

final class PDFToolController: NSObject, NSWindowDelegate {
    static let shared = PDFToolController()
    private var window: NSWindow?
    private var model: PDFWorkspaceModel?

    func chooseInputs(tool: PDFTool) {
        guard AppFeature.mediaTools.isAvailable else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = tool == .merge || tool == .organize || tool == .split
        panel.canChooseDirectories = false
        panel.begin { [weak self] result in
            guard result == .OK else { return }
            self?.open(inputs: panel.urls, tool: tool)
        }
    }

    func open(inputs: [URL], tool: PDFTool, requiresDragEnabled: Bool = false) {
        guard AppFeature.mediaTools.isAvailable,
              !requiresDragEnabled || UserDefaults.standard.bool(forKey: DefaultsKey.mediaDragConvertEnabled) else { return }
        if model?.busy == true { window?.makeKeyAndOrderFront(nil); return }
        do {
            let next = try PDFWorkspaceModel(inputs: inputs, tool: tool, requiresDragEnabled: requiresDragEnabled)
            model?.cancel()
            model = next
            let window = self.window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 830, height: 650),
                                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                                  backing: .buffered, defer: false)
            window.title = PDFToolStrings.localized(L10n.shared.language)[.tools]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentMinSize = NSSize(width: 680, height: 520)
            window.contentView = NSHostingView(rootView: PDFWorkspaceView(model: next, close: { [weak self] in self?.window?.close() }))
            if self.window == nil { window.center() }
            self.window = window
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        } catch {
            QuickToolHUD.show(icon: "exclamationmark.triangle", message: error.localizedDescription)
        }
    }

    func syncWithPreferences() {
        guard let model, !model.isAvailable else { return }
        model.cancel()
        window?.close()
    }
    func windowWillClose(_ notification: Notification) { model?.cancel() }
}

final class PDFWorkspaceModel: ObservableObject {
    @Published var tool: PDFTool
    @Published private(set) var inputs: [URL]
    @Published var plan: PDFEditPlan
    @Published var metadata: PDFMetadata
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private var batches = FileDragBatchSession()
    private let requiresDragEnabled: Bool
    private var resetInputs: [URL]
    private var thumbnails: [String: NSImage] = [:]
    private var documents: [URL: PDFDocument] = [:]

    init(inputs: [URL], tool: PDFTool, requiresDragEnabled: Bool) throws {
        self.inputs = inputs; resetInputs = inputs; self.tool = tool; self.requiresDragEnabled = requiresDragEnabled
        plan = try PDFTools.plan(inputs)
        metadata = try PDFTools.metadata(inputs[0])
    }
    var isAvailable: Bool {
        AppFeature.mediaTools.isAvailable && (!requiresDragEnabled || UserDefaults.standard.bool(forKey: DefaultsKey.mediaDragConvertEnabled))
    }
    var requiresSingleDocument: Bool { tool == .metadata || tool == .compress }
    var canSave: Bool {
        isAvailable && !busy && !plan.pages.isEmpty && (!requiresSingleDocument || inputs.count == 1)
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
        inputs = resetInputs
        rebuildPlan()
    }
    private func rebuildPlan() {
        do { plan = try PDFTools.plan(inputs); message = nil }
        catch { message = error.localizedDescription }
    }
    func moveDocument(_ index: Int, offset: Int) {
        guard isAvailable, !busy, inputs.indices.contains(index + offset) else { return }
        inputs.swapAt(index, index + offset); rebuildPlan()
    }
    func removeDocument(_ index: Int) {
        guard isAvailable, !busy, inputs.indices.contains(index), inputs.count > 1 else { return }
        inputs.remove(at: index); resetInputs.removeAll { !inputs.contains($0) }; rebuildPlan()
    }
    func add() {
        guard isAvailable, !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]; panel.allowsMultipleSelection = true
        panel.begin { [weak self] result in
            guard let self, result == .OK, self.isAvailable, !self.busy else { return }
            do {
                let added = self.inputs + panel.urls.filter { !self.inputs.contains($0) }
                let plan = try PDFTools.plan(added)
                self.resetInputs += added.filter { !self.resetInputs.contains($0) }; self.inputs = added; self.plan = plan; self.message = nil
            } catch { self.message = error.localizedDescription }
        }
    }
    func cancel() { batches.cancel(); message = nil }
    func save() {
        guard canSave, let batch = batches.begin() else { return }
        busy = true; message = nil
        let snapshot = plan, tool = tool, metadata = metadata
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try PDFTools.save(snapshot, tool: tool, metadata: metadata, batch: batch) }
            DispatchQueue.main.async {
                guard let self else { return }
                let completion = self.batches.finish(batch, featureAvailable: AppFeature.mediaTools.isAvailable, enabled: self.isAvailable)
                guard completion != .obsolete else { return }
                self.busy = false
                guard completion == .publish else { self.message = nil; return }
                switch result {
                case .success(let output):
                    self.message = output.lastPathComponent
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                    QuickToolHUD.show(icon: "checkmark.circle", message: output.lastPathComponent)
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
    }
}

private struct PDFWorkspaceView: View {
    @ObservedObject var model: PDFWorkspaceModel
    var close: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    private var strings: PDFToolStrings { .localized(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            Picker(strings[.tools], selection: $model.tool) {
                ForEach(PDFTool.allCases) { tool in Text(strings.label(tool)).tag(tool) }
            }
            .pickerStyle(.segmented).padding(16).disabled(model.busy || !model.isAvailable)
            Divider()
            HStack {
                Text(String(format: strings[.pages], model.plan.pages.count)).foregroundStyle(.secondary)
                Spacer()
                Button(strings[.add]) { model.add() }.disabled(model.requiresSingleDocument)
                Button(strings[.reset]) { model.reset() }
            }.padding(12).disabled(model.busy || !model.isAvailable)
            if model.tool == .merge || (model.requiresSingleDocument && model.inputs.count > 1) {
                documentList
            } else if model.tool == .metadata {
                metadataFields
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                        ForEach(Array(model.plan.pages.enumerated()), id: \.element.id) { index, page in
                            pageCard(page, index: index)
                        }
                    }.padding(16)
                }
            }
            Divider()
            if model.requiresSingleDocument && model.inputs.count > 1 {
                Text(strings[.singleDocument]).font(.caption).foregroundStyle(.secondary).padding(10)
            }
            if model.tool == .compress {
                Text(strings[.compressionHint]).font(.caption).foregroundStyle(.secondary).padding(10)
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(strings[.originals]).font(.caption).foregroundStyle(.secondary)
                    if let message = model.message { Text(message).font(.caption).textSelection(.enabled) }
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button(strings[.cancel]) { close() }.keyboardShortcut(.cancelAction)
                Button(strings[.save]) { model.save() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!model.canSave)
            }.padding(16)
        }
        .background(PanelSurface.baseFill(for: colorScheme))
    }

    private var documentList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(model.inputs.enumerated()), id: \.offset) { index, url in
                    HStack {
                        Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 24)
                        Image(systemName: "doc.richtext")
                        Text(url.lastPathComponent).lineLimit(2)
                        Spacer()
                        control("chevron.up", label: strings[.moveUp], disabled: index == 0) { model.moveDocument(index, offset: -1) }
                        control("chevron.down", label: strings[.moveDown], disabled: index + 1 == model.inputs.count) { model.moveDocument(index, offset: 1) }
                        control("minus.circle", label: strings[.remove], disabled: model.inputs.count == 1) { model.removeDocument(index) }
                    }.padding(14).background(PanelSurface.raisedFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(16)
        }.disabled(model.busy || !model.isAvailable)
    }

    private var metadataFields: some View {
        Form {
            Text(strings[.metadataHint]).foregroundStyle(.secondary)
            TextField(strings[.title], text: $model.metadata.title)
            TextField(strings[.author], text: $model.metadata.author)
            TextField(strings[.subject], text: $model.metadata.subject)
            TextField(strings[.keywords], text: $model.metadata.keywords)
            Button(strings[.clearFields]) { model.metadata = PDFMetadata() }
        }.formStyle(.grouped).disabled(model.busy || !model.isAvailable)
    }

    private func pageCard(_ page: PDFPageEdit, index: Int) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text("\(index + 1)").font(.caption.bold()).monospacedDigit()
                Spacer()
                control("rotate.right", label: strings[.rotate]) { model.plan.rotate(page.id) }
            }
            Group {
                if let image = model.thumbnail(page) {
                    Image(nsImage: image).resizable().scaledToFit().rotationEffect(.degrees(Double(page.quarterTurns * 90)))
                } else { Image(systemName: "doc.richtext").font(.largeTitle) }
            }.frame(width: 135, height: 180)
            Text(page.source.lastPathComponent).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                control("chevron.left", label: strings[.moveUp], disabled: index == 0) { model.plan.move(page.id, to: index - 1) }
                control("chevron.right", label: strings[.moveDown], disabled: index + 1 == model.plan.pages.count) { model.plan.move(page.id, to: index + 1) }
                control("plus.square.on.square", label: strings[.duplicate], disabled: model.plan.pages.count >= PDFTools.maxPages) { model.plan.duplicate(page.id) }
                control("trash", label: strings[.remove]) { model.plan.remove(page.id) }
            }
        }
        .padding(12).background(PanelSurface.raisedFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12))
        .disabled(model.busy || !model.isAvailable)
        .onDrag { NSItemProvider(object: page.id.uuidString as NSString) }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            guard !model.busy, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String, let id = UUID(uuidString: text) else { return }
                DispatchQueue.main.async {
                    guard !model.busy, model.isAvailable else { return }
                    model.plan.move(id, to: index)
                }
            }
            return true
        }
    }
    private func control(_ icon: String, label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 20, height: 20) }
            .buttonStyle(.borderless).help(label).accessibilityLabel(label).disabled(disabled)
    }
}
