// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import SwiftUI
final class FileMetadataToolController: NSObject, NSWindowDelegate {
    static let shared = FileMetadataToolController()
    private var panel: FileToolPanel?
    private var model: FileMetadataWorkspaceModel?
    func chooseInput() {
        guard AppFeature.mediaTools.isAvailable else { return }
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.image,.audio,.movie,.video]
        picker.begin { [weak self] result in if result == .OK, let url = picker.url { self?.open(input:url) } }
    }
    func open(input: URL, requiresDragEnabled: Bool = false) {
        let available = { AppFeature.mediaTools.isAvailable && (!requiresDragEnabled || UserDefaults.standard.bool(forKey:DefaultsKey.mediaDragConvertEnabled)) }
        guard available() else { return }; if model?.busy == true { panel?.makeKeyAndOrderFront(nil); return }
        model?.cancel()
        let next = FileMetadataWorkspaceModel(input:input,available:available,publish: { [weak self] outputs in
            self?.panel?.close()
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }); model = next
        let panel = panel ?? FileToolPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel,.resizable],backing:.buffered,defer:false)
        panel.title = FileMetadataStrings.localized(L10n.shared.language)[.title]; panel.delegate = self
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.level = .floating; panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace,.fullScreenAuxiliary,.ignoresCycle]; panel.contentMinSize = NSSize(width:600,height:400)
        let host = NSHostingController(rootView:FileMetadataWorkspaceView(model:next,close:{ [weak self] in self?.panel?.close() })); host.sizingOptions = []; panel.contentViewController = host
        let pointer = NSEvent.mouseLocation, frame = (NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main)?.visibleFrame ?? CGRect(x:0,y:0,width:1200,height:800)
        let size = CGSize(width:min(760,frame.width-24),height:min(660,frame.height-24))
        panel.setFrame(CGRect(x:min(max(pointer.x-size.width/2,frame.minX+12),frame.maxX-size.width-12),y:min(max(pointer.y-size.height/2,frame.minY+12),frame.maxY-size.height-12),width:size.width,height:size.height),display:false)
        self.panel = panel; panel.makeKeyAndOrderFront(nil)
    }
    func syncWithPreferences() { if let model, !model.isAvailable { model.cancel(); panel?.close() } }
    func windowWillClose(_ notification: Notification) { model?.cancel() }
}
private struct FileMetadataWorkspaceView: View {
    @ObservedObject var model: FileMetadataWorkspaceModel
    let close: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var selectedSection = "file"
    @State private var inspect = false
    @State private var remove = false
    private var strings: FileMetadataStrings { .localized(l10n.language) }
    private var shared: PDFToolStrings { .localized(l10n.language) }
    private var image: ImageFileToolStrings { .localized(l10n.language) }
    private func title(_ section: FileMetadataSection) -> String {
        switch section.kind { case .file: return strings[.file]; case .track(let i): return strings[.track]+" \(i+1)"; case .chapter(let i): return strings[.chapter]+" \(i+1)" }
    }
    var body: some View {
        VStack(spacing:0) {
            ZStack {
                FileToolPanelDragHandle(); Text(strings[.title]).font(.system(size:22,weight:.semibold)).allowsHitTesting(false)
                HStack { Button(action:close) { Image(systemName:"xmark").frame(width:32,height:32) }.buttonStyle(.plain).overlay(Circle().stroke(FileToolAppearance.accent.opacity(0.6),lineWidth:2)).accessibilityLabel(shared[.cancel]).keyboardShortcut(.cancelAction); Spacer() }.padding(.horizontal,18)
            }.frame(height:64)
            Divider()
            HStack {
                Text(model.input.lastPathComponent).lineLimit(1); Spacer()
                Button(image[.undo]) { model.undo() }.disabled(!model.canUndo).keyboardShortcut("z",modifiers:.command)
                Button(image[.redo]) { model.redo() }.disabled(!model.canRedo).keyboardShortcut("z",modifiers:[.command,.shift])
            }.padding(18)
            Toggle(strings[.inspect],isOn:$inspect).padding(.horizontal,18)
            if let snapshot = model.snapshot {
                if inspect {
                    ScrollView { Text(snapshot.inspection).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(18) }
                } else {
                    Picker(strings[.title],selection:$selectedSection) { ForEach(snapshot.sections) { section in Text(title(section)).tag(section.id) } }.padding(.horizontal,18)
                    ScrollView { VStack(spacing:10) {
                        if let section = snapshot.sections.first(where: { $0.id == selectedSection }) {
                            ForEach(section.tags.keys.sorted(),id:\.self) { key in
                                HStack {
                                    Text(key).font(.caption).frame(width:160,alignment:.leading).textSelection(.enabled)
                                    TextField(strings[.value],text:Binding(get:{ model.snapshot?.sections.first { $0.id == section.id }?.tags[key] ?? "" },set:{ model.change(sectionID:section.id,key:key,value:$0) })).textFieldStyle(.roundedBorder).accessibilityLabel(key)
                                    Button { model.change(sectionID:section.id,key:key,value:nil) } label: { Image(systemName:"minus.circle") }.accessibilityLabel(shared[.remove]+" "+key)
                                }
                            }
                        }
                    }.padding(18) }
                    if snapshot.imageProperties == nil {
                        HStack { TextField(strings[.key],text:$newKey); TextField(strings[.value],text:$newValue); Button(strings[.add]) { model.change(sectionID:selectedSection,key:newKey,value:newValue); newKey = ""; newValue = "" }.disabled(newKey.isEmpty) }.textFieldStyle(.roundedBorder).padding(18)
                    }
                }
            } else if model.busy { ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity) } else { Spacer() }
            Divider()
            HStack {
                VStack(alignment:.leading,spacing:4) { Text(shared[.originals]).font(.caption).foregroundStyle(.secondary); if let message = model.message { Text(message).font(.caption).lineLimit(3).textSelection(.enabled) } }
                Spacer()
                if model.busy { Button(shared[.cancel]) { model.cancel() } }
                else { Toggle(strings[.remove],isOn:$remove); Button(shared[.save]) { model.save(remove:remove) }.buttonStyle(.plain).padding(.horizontal,18).padding(.vertical,10).background(FileToolAppearance.accent,in:RoundedRectangle(cornerRadius:9)).disabled(model.snapshot == nil || !model.isAvailable) }
            }.padding(18)
        }.foregroundStyle(.white).background(FileToolAppearance.base,in:RoundedRectangle(cornerRadius:26)).overlay(RoundedRectangle(cornerRadius:26).stroke(Color.white.opacity(0.18),lineWidth:1)).preferredColorScheme(.dark)
    }
}
