// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ImageFileToolController: NSObject, NSWindowDelegate {
    static let shared = ImageFileToolController()
    private var panel: FileToolPanel?
    private var model: ImageWorkspaceModel?
    func chooseInputs(tool: ImageFileTool) {
        guard AppFeature.mediaTools.isAvailable else { return }
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.image]; picker.allowsMultipleSelection = true
        picker.begin { [weak self] result in if result == .OK { self?.open(inputs: picker.urls, tool: tool) } }
    }
    func open(inputs: [URL], tool: ImageFileTool, requiresDragEnabled: Bool = false) {
        let available = { AppFeature.mediaTools.isAvailable && (!requiresDragEnabled || UserDefaults.standard.bool(forKey: DefaultsKey.mediaDragConvertEnabled)) }
        guard available() else { return }
        if model?.busy == true { panel?.makeKeyAndOrderFront(nil); return }
        do {
            let next = try ImageWorkspaceModel(inputs: inputs, tool: tool, available: available, publish: { [weak self] urls in
                if self?.model?.failures.isEmpty == true { self?.panel?.close() }
                NSWorkspace.shared.activateFileViewerSelecting(urls)
                QuickToolHUD.show(icon: "checkmark.circle", message: urls.map(\.lastPathComponent).joined(separator: ", "))
            })
            model?.cancel(); model = next
            let panel = panel ?? FileToolPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
            panel.title = ImageFileToolStrings.localized(L10n.shared.language).label(tool)
            panel.delegate = self; panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.level = .floating; panel.hasShadow = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentMinSize = NSSize(width: 680, height: 420)
            let host = NSHostingController(rootView: ImageFileWorkspaceView(model: next, close: { [weak self] in self?.panel?.close() }))
            host.sizingOptions = []; panel.contentViewController = host
            let pointer = NSEvent.mouseLocation
            let frame = (NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
            let size = CGSize(width: min(920, frame.width - 24), height: min(680, frame.height - 24))
            panel.setFrame(CGRect(x: min(max(pointer.x-size.width/2, frame.minX+12), frame.maxX-size.width-12),
                y: min(max(pointer.y-size.height/2, frame.minY+12), frame.maxY-size.height-12), width: size.width, height: size.height), display: false)
            self.panel = panel; panel.makeKeyAndOrderFront(nil)
        } catch { QuickToolHUD.show(icon: "exclamationmark.triangle", message: error.localizedDescription) }
    }
    func syncWithPreferences() { if let model, !model.isAvailable { model.cancel(); panel?.close() } }
    func windowWillClose(_ notification: Notification) { model?.cancel() }
}

private struct ImageFileWorkspaceView: View {
    @ObservedObject var model: ImageWorkspaceModel
    let close: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @State private var draft: CGRect?
    @State private var movingRedaction: UUID?
    @State private var redactionStyle = ImageRedactionStyle.solid
    private var strings: ImageFileToolStrings { .localized(l10n.language) }
    private var shared: PDFToolStrings { .localized(l10n.language) }
    private var imageStrings: MediaImageConverterStrings { .localized(l10n.language) }
    private func binding<T>(_ key: WritableKeyPath<ImageFileEdit, T>, recordUndo: Bool = true) -> Binding<T> { Binding(get: { model.edit[keyPath: key] }, set: { value in model.change({ $0[keyPath: key] = value }, recordUndo: recordUndo) }) }
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                FileToolPanelDragHandle()
                Text(strings.label(model.tool)).font(.system(size: 22, weight: .semibold)).allowsHitTesting(false)
                HStack {
                    Button(action: close) { Image(systemName: "xmark").frame(width: 32, height: 32) }.buttonStyle(.plain)
                        .overlay(Circle().stroke(FileToolAppearance.accent.opacity(0.6), lineWidth: 2)).accessibilityLabel(shared[.cancel]).keyboardShortcut(.cancelAction)
                    Spacer()
                }.padding(.horizontal, 18)
            }.frame(height: 64)
            Divider()
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    HStack {
                        Text(String(format: imageStrings.filesSelectedFormat, model.inputs.count)).foregroundStyle(.secondary)
                        Spacer()
                        Button(strings[.undo]) { model.undo() }.disabled(!model.canUndo).keyboardShortcut("z", modifiers: .command)
                        Button(strings[.redo]) { model.redo() }.disabled(!model.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
                    }
                    canvas
                    if model.tool == .crop || model.tool == .redact { Text(strings[.selectArea]).font(.caption).foregroundStyle(.secondary) }
                    if model.inputs.count > 1 {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(Array(model.inputs.enumerated()), id: \.offset) { index, url in
                                    HStack {
                                        Text("\(index + 1)").foregroundStyle(FileToolAppearance.accent)
                                        Text(url.lastPathComponent).lineLimit(1); Spacer()
                                        if model.tool == .pdf || model.tool == .collage {
                                        Button { model.moveInput(index, offset: -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0).accessibilityLabel(shared[.moveUp])
                                        Button { model.moveInput(index, offset: 1) } label: { Image(systemName: "chevron.down") }.disabled(index == model.inputs.count-1).accessibilityLabel(shared[.moveDown])
                                        }
                                    }.padding(8).background(FileToolAppearance.card, in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }.frame(maxHeight: 120)
                    }
                }
                ScrollView { controls }.frame(width: 260)
            }.padding(18).disabled(model.busy || !model.isAvailable)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(shared[.originals]).font(.caption).foregroundStyle(.secondary)
                    if model.busy { ProgressView(value: Double(model.completed), total: Double(max(1, model.tool == .collage || model.tool == .pdf ? 1 : model.inputs.count))) }
                    if let message = model.message, !message.isEmpty { Text(message).font(.caption).lineLimit(2).textSelection(.enabled) }
                    if !model.failures.isEmpty { ScrollView { ForEach(model.inputs.filter { model.failures[$0] != nil }, id: \.self) { url in Text(url.lastPathComponent + ": " + (model.failures[url] ?? "")).font(.caption).foregroundStyle(.red).textSelection(.enabled) } }.frame(maxHeight: 70) }
                }
                Spacer()
                if model.busy { Button(shared[.cancel]) { model.cancel() } }
                else {
                    if !model.failures.isEmpty { Button(strings[.retry]) { model.save(retryFailures: true) } }
                    Button(shared[.save]) { model.save() }.buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 10)
                        .background(FileToolAppearance.accent, in: RoundedRectangle(cornerRadius: 9)).disabled(!model.isAvailable || model.preview == nil)
                }
            }.padding(18)
        }.foregroundStyle(.white).background(FileToolAppearance.base, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.18), lineWidth: 1)).preferredColorScheme(.dark)
    }
    private var canvas: some View {
        GeometryReader { geometry in
            if let preview = model.preview {
                let scale = min(geometry.size.width / CGFloat(preview.width), geometry.size.height / CGFloat(preview.height))
                let size = CGSize(width: CGFloat(preview.width) * scale, height: CGFloat(preview.height) * scale)
                ZStack(alignment: .topLeading) {
                    Image(decorative: preview, scale: 1).resizable().frame(width: size.width, height: size.height)
                    if model.tool == .crop { outline(draft ?? model.edit.crop, size: size) }
                    if model.tool == .redact, let draft { outline(draft, size: size) }
                }.frame(width: size.width, height: size.height).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                        guard model.tool == .crop || model.tool == .redact else { return }
                        let start = CGPoint(x: value.startLocation.x/size.width, y: value.startLocation.y/size.height)
                        if model.tool == .redact, let area = model.edit.redactions.last(where: { $0.rect.contains(start) }) {
                            movingRedaction = area.id
                            draft = CGRect(x: min(max(0, area.rect.minX + (value.location.x-value.startLocation.x)/size.width), 1-area.rect.width),
                                y: min(max(0, area.rect.minY + (value.location.y-value.startLocation.y)/size.height), 1-area.rect.height), width: area.rect.width, height: area.rect.height)
                            return
                        }
                        let rect = CGRect(x: min(value.startLocation.x, value.location.x)/size.width, y: min(value.startLocation.y, value.location.y)/size.height,
                            width: abs(value.location.x-value.startLocation.x)/size.width, height: abs(value.location.y-value.startLocation.y)/size.height)
                        draft = try? ImageFileTools.normalized(rect)
                    }.onEnded { _ in
                        guard let rect = draft else { return }; draft = nil
                        let moved = movingRedaction; movingRedaction = nil
                        model.change { edit in
                            if model.tool == .crop { edit.crop = rect }
                            else if model.tool == .redact {
                                if let moved, let i = edit.redactions.firstIndex(where: { $0.id == moved }) { edit.redactions[i].rect = rect }
                                else { edit.redactions.append(ImageRedaction(rect: rect, style: redactionStyle)) }
                            }
                        }
                    })
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else { ProgressView().frame(width: geometry.size.width, height: geometry.size.height) }
        }.frame(minHeight: 180).background(FileToolAppearance.card, in: RoundedRectangle(cornerRadius: 12))
    }
    private func outline(_ rect: CGRect, size: CGSize) -> some View {
        Rectangle().fill(FileToolAppearance.accent.opacity(0.12)).overlay(Rectangle().stroke(FileToolAppearance.accent, lineWidth: 2))
            .frame(width: max(1, rect.width*size.width), height: max(1, rect.height*size.height)).offset(x: rect.minX*size.width, y: rect.minY*size.height).allowsHitTesting(false)
    }
    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.tool == .crop {
                cropControls
                Divider(); resizeControls
            }
            if model.tool == .compress {
                resizeControls
                slider(l10n.s.mediaQuality, value: binding(\.quality, recordUndo: false), range: 0.05...1)
                Toggle(l10n.s.mediaSizingFileSize, isOn: Binding(get: { model.edit.targetBytes > 0 }, set: { enabled in model.change { $0.targetBytes = enabled ? 10_000_000 : 0 } }))
                if model.edit.targetBytes > 0 { TextField("MB", value: Binding(get: { Double(model.edit.targetBytes)/1_000_000 }, set: { value in model.change { $0.targetBytes = value.isFinite && value >= 0 && value <= 10000 ? Int64(value*1_000_000) : 0 } }), format: .number).accessibilityLabel(l10n.s.mediaSizingFileSize) }
            }
            if model.tool == .edit {
                slider(strings[.exposure], value: binding(\.exposure, recordUndo: false), range: -3...3)
                slider(strings[.brightness], value: binding(\.brightness, recordUndo: false), range: -1...1)
                slider(strings[.contrast], value: binding(\.contrast, recordUndo: false), range: 0...3)
                slider(strings[.saturation], value: binding(\.saturation, recordUndo: false), range: 0...3)
                slider(strings[.sharpness], value: binding(\.sharpness, recordUndo: false), range: 0...2)
                slider(strings[.noise], value: binding(\.noiseReduction, recordUndo: false), range: 0...0.1)
                slider(strings[.dehaze], value: binding(\.dehaze, recordUndo: false), range: 0...1)
                slider(strings[.clarity], value: binding(\.clarity, recordUndo: false), range: 0...1)
                slider(strings[.grain], value: binding(\.grain, recordUndo: false), range: 0...1)
            }
            if model.tool == .redact {
                Picker(strings[.redact], selection: $redactionStyle) {
                    Text(strings[.solid]).tag(ImageRedactionStyle.solid); Text(strings[.blur]).tag(ImageRedactionStyle.blur); Text(strings[.pixelate]).tag(ImageRedactionStyle.pixelate)
                }
                ForEach(model.edit.redactions) { area in
                    VStack(alignment: .leading) {
                        HStack { Text(strings[area.style == .solid ? .solid : area.style == .blur ? .blur : .pixelate]); Spacer()
                            Button(shared[.remove]) { model.change { $0.redactions.removeAll { $0.id == area.id } } }
                        }
                        redactionField(strings[.left], area: area, key: \.origin.x)
                        redactionField(strings[.top], area: area, key: \.origin.y)
                        redactionField(strings[.width], area: area, key: \.size.width)
                        redactionField(imageStrings.height, area: area, key: \.size.height)
                    }.padding(10).background(FileToolAppearance.card, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            if model.tool == .background || model.tool == .collage {
                backgroundControls
                integer(strings[.corners], value: binding(\.corner))
                if model.tool == .background { integer(imageStrings.margin, value: binding(\.margin)); Toggle(strings[.shadow], isOn: binding(\.shadow)) }
                else { Toggle(strings[.featured], isOn: binding(\.featured)); integer(strings[.width], value: binding(\.width)); integer(imageStrings.height, value: binding(\.height)); integer(strings[.columns], value: binding(\.columns)); integer(strings[.spacing], value: binding(\.spacing)) }
            }
            if model.tool != .pdf {
                Picker(l10n.s.mediaOutput, selection: binding(\.format)) { ForEach(MediaImageFormat.allCases) { format in Text(format.fileExtension.uppercased()).tag(format) } }
            }
        }.textFieldStyle(.roundedBorder)
    }
    private func integer(_ label: String, value: Binding<Int>) -> some View { HStack { Text(label); Spacer(); TextField(label, value: value, format: .number).frame(width: 84) } }
    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(label); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(2))).foregroundStyle(.secondary) }
            Slider(value: value, in: range, onEditingChanged: { active in if active { model.beginEditing() } else { model.endEditing() } }).accessibilityLabel(label)
        }
    }
    private var resizeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(imageStrings.resize).font(.headline)
            integer(strings[.width], value: binding(\.width)); integer(imageStrings.height, value: binding(\.height))
            Toggle(strings[.aspect], isOn: binding(\.lockAspect))
        }
    }
    private var cropControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(strings[.preset], selection: Binding(get: { "custom" }, set: { value in
                guard let ratio = Double(value) else { return }
                let sourceRatio = model.sourceSize.width / model.sourceSize.height
                let width = min(1, ratio/sourceRatio), height = min(1, sourceRatio/ratio)
                model.change { $0.crop = CGRect(x: (1-width)/2, y: (1-height)/2, width: width, height: height) }
            })) { Text(imageStrings.resizeExact).tag("custom"); Text("1:1").tag("1"); Text("16:9").tag(String(16.0/9)); Text("4:3").tag(String(4.0/3)); Text("3:2").tag("1.5") }
            cropField(strings[.left], key: \.origin.x, dimension: model.sourceSize.width)
            cropField(strings[.top], key: \.origin.y, dimension: model.sourceSize.height)
            cropField(strings[.width], key: \.size.width, dimension: model.sourceSize.width)
            cropField(imageStrings.height, key: \.size.height, dimension: model.sourceSize.height)
        }
    }
    private func cropField(_ label: String, key: WritableKeyPath<CGRect, CGFloat>, dimension: CGFloat) -> some View {
        integer(label, value: Binding(get: { Int(round(model.edit.crop[keyPath: key]*dimension)) }, set: { value in model.change { $0.crop[keyPath: key] = CGFloat(value)/dimension } }))
    }
    private func redactionField(_ label: String, area: ImageRedaction, key: WritableKeyPath<CGRect, CGFloat>) -> some View {
        let dimension = key == \.origin.x || key == \.size.width ? model.sourceSize.width : model.sourceSize.height
        return integer(label, value: Binding(get: { Int(round(area.rect[keyPath: key]*dimension)) }, set: { value in model.change { edit in if let i = edit.redactions.firstIndex(where: { $0.id == area.id }) { edit.redactions[i].rect[keyPath: key] = CGFloat(value)/dimension } } }))
    }
    private var backgroundControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(imageStrings.background, selection: binding(\.background)) {
                Text(imageStrings.backgroundTransparent).tag(MediaImageBackground.transparent); Text(imageStrings.backgroundWhite).tag(MediaImageBackground.white); Text(imageStrings.backgroundBlack).tag(MediaImageBackground.black)
            }
            Button(l10n.s.mediaSelectFile) {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
                panel.begin { result in if result == .OK { model.change { $0.backgroundURL = panel.url } } }
            }
            if let url = model.edit.backgroundURL {
                HStack { Text(url.lastPathComponent).lineLimit(1); Button(shared[.remove]) { model.change { $0.backgroundURL = nil } } }
                slider(strings[.blur], value: binding(\.backgroundBlur, recordUndo: false), range: 0...100)
            }
        }
    }
}
