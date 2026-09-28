// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

final class PDFToolController: NSObject, NSWindowDelegate {
    static let shared = PDFToolController()
    private var window: PDFToolPanel?
    private var model: PDFWorkspaceModel?

    func chooseInputs(tool: PDFTool) {
        guard AppFeature.mediaTools.isAvailable else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = tool != .metadata
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
            let next = try PDFWorkspaceModel(inputs: inputs, tool: tool, requiresDragEnabled: requiresDragEnabled,
                publishOutputs: { outputs in
                    NSWorkspace.shared.activateFileViewerSelecting(outputs)
                    QuickToolHUD.show(icon: "checkmark.circle", message: outputs.map(\.lastPathComponent).joined(separator: ", "))
                })
            model?.cancel()
            model = next
            let window = self.window ?? PDFToolPanel(contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
            window.title = PDFToolStrings.localized(L10n.shared.language).label(tool)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.hidesOnDeactivate = false
            window.isMovableByWindowBackground = false
            window.level = .floating
            window.animationBehavior = .utilityWindow
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
            window.contentMinSize = NSSize(width: 480, height: 320)
            let host = NSHostingController(rootView: PDFWorkspaceView(model: next, close: { [weak self] in self?.window?.close() }))
            host.sizingOptions = []
            window.contentViewController = host
            let preferred: CGSize
            switch tool {
            case .merge: preferred = CGSize(width: 600, height: 510)
            case .organize: preferred = CGSize(width: 760, height: 810)
            case .split: preferred = CGSize(width: 700, height: 700)
            case .compress: preferred = CGSize(width: 580, height: 420)
            case .metadata, .readQR: preferred = CGSize(width: 580, height: 470)
            }
            let pointer = NSEvent.mouseLocation
            let visible = (NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main)?.visibleFrame
                ?? CGRect(x: 0, y: 0, width: 1000, height: 800)
            let size = CGSize(width: min(preferred.width, visible.width - 24), height: min(preferred.height, visible.height - 24))
            let origin = CGPoint(x: min(max(pointer.x - size.width / 2, visible.minX + 12), visible.maxX - size.width - 12),
                                 y: min(max(pointer.y - size.height / 2, visible.minY + 12), visible.maxY - size.height - 12))
            window.setFrame(CGRect(origin: origin, size: size), display: false)
            self.window = window
            // A non-activating key panel accepts editor input without bringing
            // Vorssaint's settings window forward or taking Finder's app focus.
            window.makeKeyAndOrderFront(nil)
            if tool == .readQR { next.scanQR() }
        } catch {
            QuickToolHUD.show(icon: "exclamationmark.triangle", message: error.localizedDescription)
        }
    }

    func addInputs(to model: PDFWorkspaceModel) {
        guard model.isAvailable, !model.busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]; panel.allowsMultipleSelection = true
        panel.begin { [weak model] result in
            guard let model, result == .OK else { return }
            do { try model.append(panel.urls) } catch { model.report(error) }
        }
    }

    func syncWithPreferences() {
        guard let model, !model.isAvailable else { return }
        model.cancel()
        window?.close()
    }
    func windowWillClose(_ notification: Notification) { model?.cancel() }
}

private final class PDFToolPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { close() }
}

enum FileToolAppearance {
    static let accent = Color(red: 1, green: 0.28, blue: 0)
    static let base = Color(white: 0.15)
    static let card = Color(white: 0.115)
}

private struct PDFPanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> Handle { Handle() }
    func updateNSView(_ view: Handle, context: Context) {}
    final class Handle: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

private struct PDFWorkspaceView: View {
    @ObservedObject var model: PDFWorkspaceModel
    var close: () -> Void
    @ObservedObject private var l10n = L10n.shared
    private var strings: PDFToolStrings { .localized(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PDFPanelDragHandle()
                Text(strings.label(model.tool)).font(.system(size: 22, weight: .semibold)).allowsHitTesting(false)
                HStack {
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 32, height: 32) }
                        .buttonStyle(.plain).background(Color.white.opacity(0.06), in: Circle())
                        .overlay(Circle().strokeBorder(FileToolAppearance.accent.opacity(0.6), lineWidth: 2))
                        .accessibilityLabel(strings[.cancel]).keyboardShortcut(.cancelAction)
                    Spacer()
                }.padding(.horizontal, 18)
            }.frame(height: 64)
            Divider()
            HStack {
                Text(model.tool == .merge ? strings[.documentOrder] : String(format: strings[.pages], model.plan.pages.count)).foregroundStyle(.secondary)
                Spacer()
                if model.tool != .readQR {
                    Button(strings[.add]) { PDFToolController.shared.addInputs(to: model) }.disabled(model.requiresSingleDocument)
                    if model.tool == .merge { Button(strings[.sortName]) { model.sortDocuments() }.controlSize(.small) }
                    else { Button(strings[.reset]) { model.reset() }.controlSize(.small) }
                }
            }.padding(12).disabled(model.busy || !model.isAvailable)
            if model.tool == .merge || model.tool == .compress || (model.requiresSingleDocument && model.inputs.count > 1) {
                documentList
            } else if model.tool == .readQR {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.qrScanned && model.qrResults.isEmpty && model.message == nil { Text(strings[.noQR]).foregroundStyle(.secondary) }
                        ForEach(model.qrResults, id: \.self) { payload in
                            HStack {
                                Text(payload).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                Button(strings[.copy]) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(payload, forType: .string) }
                            }.padding(14).background(FileToolAppearance.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.padding(16)
                }
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
            if model.tool == .organize {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    Toggle(strings[.sameWidth], isOn: $model.plan.normalizeWidths).toggleStyle(.checkbox)
                    Text(strings[.sameWidthHint]).font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 18).padding(.bottom, 14).disabled(model.busy || !model.isAvailable)
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
                if model.tool == .readQR {
                    Button(strings[.cancel], action: close).buttonStyle(.borderedProminent).tint(FileToolAppearance.accent)
                } else {
                Button(model.tool == .organize ? strings[.saveOrganized] : strings.label(model.tool)) { model.save() }
                    .buttonStyle(.borderedProminent).tint(FileToolAppearance.accent)
                    .keyboardShortcut(.defaultAction).disabled(!model.canSave)
                }
            }.padding(16)
        }
        .background(FileToolAppearance.base)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(PanelSurface.border(for: .dark), lineWidth: 1))
        .preferredColorScheme(.dark)
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
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).accessibilityHidden(true)
                    }.padding(14).background(FileToolAppearance.card, in: RoundedRectangle(cornerRadius: 18))
                    .onDrag { NSItemProvider(object: url.absoluteString as NSString) }
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        guard !model.busy, let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                            guard let text = object as? String, let source = URL(string: text) else { return }
                            DispatchQueue.main.async { model.moveDocument(source, to: index) }
                        }
                        return true
                    }
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
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12).fill(.white)
                Group {
                    if let image = model.thumbnail(page) {
                        Image(nsImage: image).resizable().scaledToFit().rotationEffect(.degrees(Double(page.quarterTurns * 90)))
                    } else { Image(systemName: "doc.richtext").font(.largeTitle).foregroundStyle(.gray) }
                }.frame(width: 150, height: 225).clipShape(RoundedRectangle(cornerRadius: 12))
                HStack {
                    Text("\(index + 1)").font(.caption.bold()).monospacedDigit().foregroundStyle(.white)
                        .frame(width: 26, height: 26).background(FileToolAppearance.accent, in: Circle())
                    Spacer()
                    control("rotate.right", label: strings[.rotate]) { model.plan.rotate(page.id) }
                        .foregroundStyle(.white).padding(3).background(Color(white: 0.35), in: Circle())
                }.padding(8)
            }.frame(width: 150, height: 225)
            HStack(spacing: 10) {
                control("chevron.left", label: strings[.moveUp], disabled: index == 0) { model.plan.move(page.id, to: index - 1) }
                control("chevron.right", label: strings[.moveDown], disabled: index + 1 == model.plan.pages.count) { model.plan.move(page.id, to: index + 1) }
                control("plus.square.on.square", label: strings[.duplicate], disabled: model.plan.pages.count >= PDFTools.maxPages) { model.plan.duplicate(page.id) }
                control("trash", label: strings[.remove]) { model.plan.remove(page.id) }
            }.foregroundStyle(.secondary)
        }
        .padding(8)
        .help(page.source.lastPathComponent)
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
