// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import SwiftUI

final class FileToolCatalogController: NSObject, NSWindowDelegate {
    static let shared = FileToolCatalogController()
    private var panel: FileToolPanel?
    private var requiresDragEnabled = false
    private var qrModel: ImageQRWorkspaceModel?
    private var available: Bool { AppFeature.mediaTools.isAvailable && (!requiresDragEnabled || UserDefaults.standard.bool(forKey:DefaultsKey.mediaDragConvertEnabled)) }
    func open(inputs: [URL], requiresDragEnabled: Bool = false) {
        self.requiresDragEnabled = requiresDragEnabled
        guard available else { return }
        let actions = FileToolCatalog.actions(for:inputs,enginesAvailable:MediaEngineBundle.bundled != nil)
        guard !actions.isEmpty else { return }
        qrModel?.cancel(); qrModel = nil
        show(title:FileToolExtraStrings.localized(L10n.shared.language)[.more],view:AnyView(FileToolCatalogView(inputs:inputs,actions:actions,select:{ [weak self] action in
            guard let self, self.available else { return }
            if action == .readImageQR { self.scan(inputs:inputs); return }
            self.panel?.close()
            switch action {
            case .imageTool(let tool): ImageFileToolController.shared.open(inputs:inputs,tool:tool,requiresDragEnabled:requiresDragEnabled)
            case .avTool(let tool): AVFileToolController.shared.open(inputs:inputs,tool:tool,requiresDragEnabled:requiresDragEnabled)
            case .pdfTool(let tool): PDFToolController.shared.open(inputs:inputs,tool:tool,requiresDragEnabled:requiresDragEnabled)
            case .metadata: if let input = inputs.first { FileMetadataToolController.shared.open(input:input,requiresDragEnabled:requiresDragEnabled) }
            default: break
            }
        },close:{ [weak self] in self?.panel?.close() })))
    }
    private func scan(inputs: [URL]) {
        let model = ImageQRWorkspaceModel(inputs:inputs,available:{ [weak self] in self?.available == true }); qrModel = model
        show(title:PDFToolStrings.localized(L10n.shared.language).label(.readQR),view:AnyView(ImageQRWorkspaceView(model:model,close:{ [weak self] in self?.panel?.close() })))
        model.scan()
    }
    private func show(title: String,view: AnyView) {
        let panel = panel ?? FileToolPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel,.resizable],backing:.buffered,defer:false)
        panel.title = title; panel.delegate = self; panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.level = .floating; panel.hasShadow = true; panel.hidesOnDeactivate = false; panel.collectionBehavior = [.moveToActiveSpace,.fullScreenAuxiliary,.ignoresCycle]; panel.contentMinSize = NSSize(width:520,height:340)
        let host = NSHostingController(rootView:view); host.sizingOptions = []; panel.contentViewController = host
        let point = NSEvent.mouseLocation, frame = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame ?? CGRect(x:0,y:0,width:1200,height:800)
        let size = CGSize(width:min(640,frame.width-24),height:min(520,frame.height-24))
        panel.setFrame(CGRect(x:min(max(point.x-size.width/2,frame.minX+12),frame.maxX-size.width-12),y:min(max(point.y-size.height/2,frame.minY+12),frame.maxY-size.height-12),width:size.width,height:size.height),display:false)
        self.panel = panel; panel.makeKeyAndOrderFront(nil)
    }
    func syncWithPreferences() { if !available { qrModel?.cancel(); panel?.close() } }
    func windowWillClose(_ notification: Notification) { qrModel?.cancel() }
}
private struct FileToolCatalogView: View {
    let inputs: [URL], actions: [FileDragAction]
    let select: (FileDragAction) -> Void
    let close: () -> Void
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        VStack(spacing:0) {
            FileCatalogHeader(title:FileToolExtraStrings.localized(l10n.language)[.more],close:close)
            Divider()
            Text(inputs.map(\.lastPathComponent).joined(separator:", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2).padding(18)
            ScrollView { LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                ForEach(actions) { action in Button(action.title(l10n.language)) { select(action) }.buttonStyle(.plain).padding(18).frame(maxWidth:.infinity,minHeight:64).background(FileToolAppearance.card,in:RoundedRectangle(cornerRadius:14)) }
            }.padding(18) }
        }.foregroundStyle(.white).background(FileToolAppearance.base,in:RoundedRectangle(cornerRadius:26)).overlay(RoundedRectangle(cornerRadius:26).stroke(Color.white.opacity(0.18),lineWidth:1)).preferredColorScheme(.dark)
    }
}
private struct FileCatalogHeader: View {
    let title: String, close: () -> Void
    var body: some View { ZStack { FileToolPanelDragHandle(); Text(title).font(.system(size:22,weight:.semibold)).allowsHitTesting(false)
        HStack { Button(action:close) { Image(systemName:"xmark").frame(width:32,height:32) }.buttonStyle(.plain).overlay(Circle().stroke(FileToolAppearance.accent.opacity(0.6),lineWidth:2)).accessibilityLabel(PDFToolStrings.localized(L10n.shared.language)[.cancel]).keyboardShortcut(.cancelAction); Spacer() }.padding(.horizontal,18)
    }.frame(height:64) }
}
private final class ImageQRWorkspaceModel: ObservableObject {
    let inputs: [URL], available: () -> Bool
    @Published var results: [String] = []
    @Published var message: String?
    @Published var busy = false
    private var batches = FileDragBatchSession()
    init(inputs:[URL],available:@escaping () -> Bool) { self.inputs = inputs; self.available = available }
    func scan() {
        guard available(), !busy, let batch = batches.begin() else { return }; busy = true
        let inputs = inputs
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result = Result { () -> [String] in
                try ImageFileTools.validate(inputs); var payloads: [String] = []
                for input in inputs { try autoreleasepool {
                    guard !batch.isCancelled else { throw CancellationError() }
                    for code in BarcodeDetector.decode(try ImageFileTools.load(input)) where !payloads.contains(code.payload) { payloads.append(code.payload) }
                } }
                return payloads
            }
            DispatchQueue.main.async {
                guard let self else { return }; let completion = self.batches.finish(batch,featureAvailable:self.available(),enabled:self.available())
                guard completion != .obsolete else { return }; self.busy = false; guard completion == .publish else { return }
                switch result { case .success(let values): self.results = values; case .failure(let error): self.message = error.localizedDescription }
            }
        }
    }
    func cancel() { batches.cancel() }
}
private struct ImageQRWorkspaceView: View {
    @ObservedObject var model: ImageQRWorkspaceModel
    let close: () -> Void
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        let strings = PDFToolStrings.localized(l10n.language)
        VStack(spacing:0) {
            FileCatalogHeader(title:strings.label(.readQR),close:close); Divider()
            if model.busy { ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity) }
            else { ScrollView { VStack(alignment:.leading,spacing:12) {
                if let message = model.message { Text(message).foregroundStyle(.red) }
                else if model.results.isEmpty { Text(strings[.noQR]).foregroundStyle(.secondary) }
                ForEach(model.results,id:\.self) { payload in HStack { Text(payload).textSelection(.enabled); Spacer(); Button(strings[.copy]) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(payload,forType:.string) } }.padding(14).background(FileToolAppearance.card,in:RoundedRectangle(cornerRadius:12)) }
            }.padding(18) } }
        }.foregroundStyle(.white).background(FileToolAppearance.base,in:RoundedRectangle(cornerRadius:26)).overlay(RoundedRectangle(cornerRadius:26).stroke(Color.white.opacity(0.18),lineWidth:1)).preferredColorScheme(.dark)
    }
}
