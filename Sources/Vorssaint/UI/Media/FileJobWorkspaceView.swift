// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import SwiftUI
final class FileJobToolController: NSObject, NSWindowDelegate {
    static let shared = FileJobToolController()
    private var panel: FileToolPanel?
    private var model: FileJobWorkspaceModel?
    var isBusy: Bool { model?.busy == true }
    func open(inputs: [URL],action: FileDragAction,requiresDragEnabled: Bool = true) {
        let available = { AppFeature.mediaTools.isAvailable && (!requiresDragEnabled || UserDefaults.standard.bool(forKey:DefaultsKey.mediaDragConvertEnabled)) }
        guard available() else { return }; if isBusy { panel?.makeKeyAndOrderFront(nil); return }
        do {
            let next = try FileJobWorkspaceModel(inputs:inputs,action:action,available:available,
                publish:{ urls in NSWorkspace.shared.activateFileViewerSelecting(urls) },
                didFinishSuccessfully:{ [weak self] in self?.panel?.close() })
            model?.cancel(); model = next
            let panel = panel ?? FileToolPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel,.resizable],backing:.buffered,defer:false)
            panel.title = action.title(L10n.shared.language); panel.delegate = self; panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.level = .floating; panel.hasShadow = true; panel.hidesOnDeactivate = false; panel.collectionBehavior = [.moveToActiveSpace,.fullScreenAuxiliary,.ignoresCycle]; panel.contentMinSize = NSSize(width:600,height:320)
            let host = NSHostingController(rootView:FileJobWorkspaceView(model:next,close:{ [weak self] in self?.panel?.close() })); host.sizingOptions = []; panel.contentViewController = host
            let pointer = NSEvent.mouseLocation, frame = (NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main)?.visibleFrame ?? CGRect(x:0,y:0,width:1200,height:800)
            let size = CGSize(width:min(720,frame.width-24),height:min(480,frame.height-24))
            panel.setFrame(CGRect(x:min(max(pointer.x-size.width/2,frame.minX+12),frame.maxX-size.width-12),y:min(max(pointer.y-size.height/2,frame.minY+12),frame.maxY-size.height-12),width:size.width,height:size.height),display:false)
            self.panel = panel; panel.makeKeyAndOrderFront(nil); if !next.needsTiming { next.run() }
        } catch { QuickToolHUD.show(icon:"exclamationmark.triangle",message:error.localizedDescription) }
    }
    func syncWithPreferences() { if let model, !model.isAvailable { model.cancel(); panel?.close() } }
    func windowWillClose(_ notification: Notification) { model?.cancel() }
}
private struct FileJobWorkspaceView: View {
    @ObservedObject var model: FileJobWorkspaceModel
    let close: () -> Void
    @ObservedObject private var l10n = L10n.shared
    private var shared: PDFToolStrings { .localized(l10n.language) }
    private func timingField(_ key: FileToolExtraStrings.Key,value: Binding<Double>) -> some View {
        VStack(alignment:.leading) { Text(FileToolExtraStrings.localized(l10n.language)[key]).font(.caption); TextField("",value:value,format:.number).textFieldStyle(.roundedBorder).accessibilityLabel(FileToolExtraStrings.localized(l10n.language)[key]) }
    }
    var body: some View {
        VStack(spacing:0) {
            ZStack {
                FileToolPanelDragHandle()
                Text(model.action.title(l10n.language)).font(.system(size:22,weight:.semibold)).allowsHitTesting(false)
                HStack { Button(action:close) { Image(systemName:"xmark").frame(width:32,height:32) }.buttonStyle(.plain).overlay(Circle().stroke(FileToolAppearance.accent.opacity(0.6),lineWidth:2)).accessibilityLabel(shared[.cancel]).keyboardShortcut(.cancelAction); Spacer() }.padding(.horizontal,18)
            }.frame(height:64)
            Divider()
            if model.needsTiming {
                VStack(alignment:.leading,spacing:8) {
                    Text(FileToolExtraStrings.localized(l10n.language)[.timingHint]).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        timingField(.duration,value:$model.subtitleTiming.duration)
                        timingField(.offset,value:$model.subtitleTiming.offset)
                        timingField(.gap,value:$model.subtitleTiming.gap)
                    }
                }.padding(18).disabled(model.busy)
            }
            ScrollView { VStack(spacing:10) {
                ForEach(model.rows) { row in
                    HStack(alignment:.top,spacing:12) {
                        switch row.state {
                        case .pending: Image(systemName:"clock").foregroundStyle(.secondary)
                        case .processing: ProgressView().controlSize(.small)
                        case .cancelled: Image(systemName:"xmark.circle").foregroundStyle(.secondary)
                        case .done: Image(systemName:"checkmark.circle.fill").foregroundStyle(.green)
                        case .failed: Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.red)
                        }
                        VStack(alignment:.leading,spacing:5) {
                            Text(row.input.lastPathComponent).lineLimit(1)
                            switch row.state {
                            case .done(let output): Text(output.lastPathComponent).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            case .failed(let error): Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                            case .cancelled: Text(l10n.s.mediaCancelled).font(.caption).foregroundStyle(.secondary)
                            default: EmptyView()
                            }
                        }
                        Spacer()
                        if row.elapsed > 0 { Text(row.elapsed,format:.number.precision(.fractionLength(2)))+Text(" s") }
                    }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(FileToolAppearance.card,in:RoundedRectangle(cornerRadius:12))
                }
            }.padding(18) }
            Divider()
            HStack {
                VStack(alignment:.leading,spacing:6) {
                    Text(shared[.originals]).font(.caption).foregroundStyle(.secondary)
                    ProgressView(value:Double(model.completed),total:Double(max(1,model.total)))
                    Text("\(model.completed) / \(model.total)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { Button(shared[.cancel]) { model.cancel() } }
                else if model.completed == 0 && !model.hasFailures { Button(shared[.save]) { model.run() }.disabled(!model.isAvailable || model.needsTiming && !model.subtitleTiming.isValid) }
                else if model.hasFailures { Button(l10n.s.mediaRunAgain) { model.run(retryFailures:true) }.disabled(!model.isAvailable) }
            }.padding(18)
        }.foregroundStyle(.white).background(FileToolAppearance.base,in:RoundedRectangle(cornerRadius:26)).overlay(RoundedRectangle(cornerRadius:26).stroke(Color.white.opacity(0.18),lineWidth:1)).preferredColorScheme(.dark)
    }
}
