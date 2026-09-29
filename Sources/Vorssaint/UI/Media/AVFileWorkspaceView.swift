// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import SwiftUI
import AVKit
import UniformTypeIdentifiers

final class AVFileToolController: NSObject, NSWindowDelegate {
    static let shared = AVFileToolController()
    private var panel: FileToolPanel?
    private var model: AVWorkspaceModel?
    func chooseInputs(tool: AVFileTool) {
        guard AppFeature.mediaTools.isAvailable, MediaEngineBundle.bundled != nil else { return }
        let picker = NSOpenPanel(); picker.allowedContentTypes = tool.isVideo ? [.movie, .video] : [.audio]; picker.allowsMultipleSelection = true
        picker.begin { [weak self] result in if result == .OK { self?.open(inputs: picker.urls, tool: tool) } }
    }
    func open(inputs: [URL], tool: AVFileTool, requiresDragEnabled: Bool = false) {
        let available = { AppFeature.mediaTools.isAvailable && (!requiresDragEnabled || UserDefaults.standard.bool(forKey: DefaultsKey.mediaDragConvertEnabled)) }
        guard available(), let engines = MediaEngineBundle.bundled else { return }
        if model?.busy == true { panel?.makeKeyAndOrderFront(nil); return }
        do {
            let next = try AVWorkspaceModel(inputs: inputs, tool: tool, engines: engines, available: available, publish: { [weak self] urls in
                if self?.model?.failures.isEmpty == true { self?.panel?.close() }
                NSWorkspace.shared.activateFileViewerSelecting(urls)
                QuickToolHUD.show(icon: "checkmark.circle", message: urls.map(\.lastPathComponent).joined(separator: ", "))
            })
            model?.cancel(); model = next
            let panel = panel ?? FileToolPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
            panel.title = AVFileToolStrings.localized(L10n.shared.language).label(tool)
            panel.delegate = self; panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.level = .floating; panel.hasShadow = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentMinSize = NSSize(width: 680, height: 460)
            let host = NSHostingController(rootView: AVFileWorkspaceView(model: next, close: { [weak self] in self?.panel?.close() }))
            host.sizingOptions = []; panel.contentViewController = host
            let pointer = NSEvent.mouseLocation, frame = (NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0,y: 0,width: 1200,height: 800)
            let size = CGSize(width: min(960,frame.width-24),height: min(700,frame.height-24))
            panel.setFrame(CGRect(x: min(max(pointer.x-size.width/2,frame.minX+12),frame.maxX-size.width-12),y: min(max(pointer.y-size.height/2,frame.minY+12),frame.maxY-size.height-12),width: size.width,height: size.height),display: false)
            self.panel = panel; panel.makeKeyAndOrderFront(nil)
        } catch { QuickToolHUD.show(icon: "exclamationmark.triangle", message: error.localizedDescription) }
    }
    func syncWithPreferences() { if let model, !model.isAvailable { model.cancel(); panel?.close() } }
    func windowWillClose(_ notification: Notification) { model?.cancel() }
}

private struct AVFileWorkspaceView: View {
    @ObservedObject var model: AVWorkspaceModel
    let close: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @State private var player = AVPlayer()
    @State private var playResult = false
    @State private var frameTime = 0.0
    @State private var usePreview = false
    @State private var timeValidity: [String:Bool] = [:]
    private var strings: AVFileToolStrings { .localized(l10n.language) }
    private var shared: PDFToolStrings { .localized(l10n.language) }
    private var image: ImageFileToolStrings { .localized(l10n.language) }
    private func binding<T>(_ key: WritableKeyPath<AVFileEdit,T>) -> Binding<T> { Binding(get: { model.edit[keyPath: key] },set: { value in model.change { $0[keyPath: key] = value } }) }
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                FileToolPanelDragHandle()
                Text(strings.label(model.tool)).font(.system(size: 22,weight: .semibold)).allowsHitTesting(false)
                HStack {
                    Button(action: close) { Image(systemName: "xmark").frame(width: 32,height: 32) }.buttonStyle(.plain)
                        .overlay(Circle().stroke(FileToolAppearance.accent.opacity(0.6),lineWidth: 2)).accessibilityLabel(shared[.cancel]).keyboardShortcut(.cancelAction)
                    Spacer()
                }.padding(.horizontal,18)
            }.frame(height: 64)
            Divider()
            HStack(alignment: .top,spacing: 18) {
                VStack(spacing: 12) {
                    HStack {
                        Text(model.inputs[0].lastPathComponent).lineLimit(1); Spacer()
                        Button(image[.undo]) { model.undo() }.disabled(!model.canUndo).keyboardShortcut("z",modifiers: .command)
                        Button(image[.redo]) { model.redo() }.disabled(!model.canRedo).keyboardShortcut("z",modifiers: [.command,.shift])
                    }
                    if model.tool.isVideo {
                        VideoPlayer(player: player).frame(minHeight: 140)
                    }
                    if !model.tool.isVideo || [.videoCrop,.videoRedact,.videoFrames].contains(model.tool) {
                        if let preview = model.preview {
                            if [.videoCrop,.videoRedact].contains(model.tool) {
                                AVImageSelection(image:preview,crop:model.tool == .videoCrop ? model.edit.crop : nil,regions:model.edit.areas.filter { $0.start <= frameTime && $0.end >= frameTime && $0.rect.width > 0 && $0.rect.height > 0 },commit:{ id,rect in
                                    model.change { edit in
                                        if model.tool == .videoCrop { edit.crop = rect }
                                        else if let id, let index = edit.areas.firstIndex(where:{ $0.id == id }) { edit.areas[index].rect = rect }
                                        else { edit.areas.append(AVTimedArea(start:frameTime,end:model.info?.duration ?? 1,rect:rect)) }
                                    }
                                }).accessibilityLabel(image[.selectArea])
                            } else if [.audioTrim,.audioBleep].contains(model.tool), let info = model.info {
                                let trimEnd = model.edit.end == 0 ? info.duration : model.edit.end
                                let valid = model.tool == .audioTrim ? (model.edit.start >= 0 && trimEnd > model.edit.start && trimEnd <= info.duration ? [AVTimedArea(start:model.edit.start,end:trimEnd)] : []) : model.edit.areas.filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && $0.end <= info.duration }
                                AVWaveformSelection(image:preview,duration:info.duration,regions:valid,commit:{ id,range in model.change { edit in
                                    if model.tool == .audioTrim { edit.start = range.lowerBound; edit.end = range.upperBound }
                                    else if let id, let index = edit.areas.firstIndex(where:{ $0.id == id }) { edit.areas[index].start = range.lowerBound; edit.areas[index].end = range.upperBound }
                                    else { edit.areas.append(AVTimedArea(start:range.lowerBound,end:range.upperBound)) }
                                } }).accessibilityLabel(strings[.range])
                            } else { Image(decorative:preview,scale:1).resizable().scaledToFit().frame(maxHeight:model.tool.isVideo ? 160 : 240) }
                        } else { ProgressView(strings[.preparing]).frame(maxWidth: .infinity,maxHeight: .infinity) }
                    }
                    if !model.tool.isVideo { VideoPlayer(player: player).frame(height: 70) }
                    if !model.outputs.isEmpty || model.processedPreview != nil, model.tool != .videoFrames, model.tool != .videoSplit {
                        Picker(strings[.result],selection: $playResult) {
                            Text(strings[.original]).tag(false); Text(strings[.result]).tag(true)
                        }.pickerStyle(.segmented)
                    }
                    if let info = model.info {
                        Text(String(format: "%.3f %@ · %d × %d · %d",locale:l10n.language.formattingLocale(),info.duration,strings[.seconds],info.width,info.height,info.channels)).font(.caption).foregroundStyle(.secondary)
                        if model.tool.isVideo {
                            Slider(value: $frameTime,in: 0...max(0.001,info.duration-0.001),onEditingChanged: { editing in
                                if !editing { player.seek(to: CMTime(seconds: frameTime,preferredTimescale: 600)); model.refreshPreview(time: frameTime); if model.tool == .videoFrames { model.change { $0.frameTime = frameTime } } }
                            }).accessibilityLabel(strings[.frame])
                            HStack {
                                Button { stepFrame(-1) } label: { Image(systemName:"backward.frame") }.accessibilityLabel(FileToolExtraStrings.localized(l10n.language)[.previousFrame])
                                Text(frameTime,format:.number.precision(.fractionLength(3))).font(.caption).monospacedDigit()
                                Button { stepFrame(1) } label: { Image(systemName:"forward.frame") }.accessibilityLabel(FileToolExtraStrings.localized(l10n.language)[.nextFrame])
                            }
                        }
                    }
                    if model.inputs.count > 1 {
                        ScrollView { VStack(spacing: 6) {
                            ForEach(Array(model.inputs.enumerated()),id: \.offset) { index,url in
                                HStack {
                                    Text("\(index+1)").foregroundStyle(FileToolAppearance.accent); Text(url.lastPathComponent).lineLimit(1); Spacer()
                                    if model.tool == .videoJoin {
                                        Button { model.moveInput(index,offset: -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0).accessibilityLabel(shared[.moveUp])
                                        Button { model.moveInput(index,offset: 1) } label: { Image(systemName: "chevron.down") }.disabled(index == model.inputs.count-1).accessibilityLabel(shared[.moveDown])
                                    }
                                }.padding(8).background(FileToolAppearance.card,in: RoundedRectangle(cornerRadius: 10))
                            }
                        } }.frame(maxHeight: 100)
                    }
                }
                ScrollView { controls }.frame(width: 285)
            }.padding(18).disabled(model.busy || !model.isAvailable)
            Divider()
            HStack {
                VStack(alignment: .leading,spacing: 4) {
                    Text(shared[.originals]).font(.caption).foregroundStyle(.secondary)
                    if model.busy { ProgressView(value: Double(model.completed),total: Double(model.tool == .videoJoin ? 1 : model.inputs.count)) }
                    if let message = model.message { Text(message).font(.caption).lineLimit(2).textSelection(.enabled) }
                    if !model.failures.isEmpty { ScrollView { ForEach(model.inputs.filter { model.failures[$0] != nil },id: \.self) { url in Text(url.lastPathComponent+": "+(model.failures[url] ?? "")).font(.caption).foregroundStyle(.red).textSelection(.enabled) } }.frame(maxHeight: 70) }
                    if let measurement = model.normalization, let input = measurement.inputLoudness, let output = measurement.outputLoudness {
                        Text(String(format: "%@: %.1f LUFS / %.1f dBTP / %.1f LU → %@: %.1f LUFS / %.1f dBTP / %.1f LU",locale:l10n.language.formattingLocale(),strings[.original],input.integrated,input.peak,input.range,strings[.result],output.integrated,output.peak,output.range)).font(.caption).textSelection(.enabled)
                    }
                }
                Spacer()
                if model.busy { Button(shared[.cancel]) { model.cancel() } }
                else {
                    if !model.failures.isEmpty { Button(image[.retry]) { model.save(retryFailures: true) } }
                    if ![.videoJoin,.videoSplit,.videoFrames,.videoCompress,.audioVisualizer].contains(model.tool) {
                        Button(strings[.preview]) { player.pause(); player.replaceCurrentItem(with:nil); model.previewProcessed() }.disabled(model.info == nil || timeValidity.values.contains(false))
                    }
                    Button(shared[.save]) { player.pause(); model.save() }.buttonStyle(.plain).padding(.horizontal,18).padding(.vertical,10)
                        .background(FileToolAppearance.accent,in: RoundedRectangle(cornerRadius: 9)).disabled(!model.isAvailable || model.info == nil || timeValidity.values.contains(false))
                }
            }.padding(18)
        }.foregroundStyle(.white).background(FileToolAppearance.base,in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.18),lineWidth: 1)).preferredColorScheme(.dark)
            .onAppear { updatePlayer() }.onDisappear { player.pause() }
            .onChange(of: playResult) { _,_ in updatePlayer() }
            .onChange(of: model.inputs) { _,_ in updatePlayer() }
            .onChange(of: model.outputs) { _,_ in usePreview = false; if playResult { updatePlayer() } }
            .onChange(of: model.processedPreview) { _,_ in usePreview = true; playResult = true; updatePlayer() }
    }
    private func previewChannel(left: Bool) {
        var options = model.edit; options.mono = false
        options.leftGain = left ? 1 : 0; options.rightGain = left ? 0 : 1
        player.pause(); player.replaceCurrentItem(with:nil); model.previewProcessed(editOverride:options)
    }
    private func stepFrame(_ direction: Int) {
        guard let info = model.info, let time = AVTimeInputs.step(frameTime,direction:direction,fps:info.fps,duration:info.duration) else { return }
        player.pause(); frameTime = time; player.seek(to:CMTime(seconds:time,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)
        model.refreshPreview(time:time); if model.tool == .videoFrames { model.change { $0.frameTime = time } }
    }
    private func updatePlayer() {
        player.pause()
        let result = usePreview ? model.processedPreview : model.outputs.last
        player.replaceCurrentItem(with:AVPlayerItem(url:playResult ? (result ?? model.inputs[0]) : model.inputs[0]))
        if !playResult && usePreview { player.seek(to:CMTime(seconds:model.previewStart,preferredTimescale:600)) }
    }
    private func timeInput(_ label: String,id: String,value: Binding<Double>) -> some View {
        AVTimecodeField(label:label,value:value,fps:model.tool.isVideo ? model.info?.fps : nil,hint:strings[.timecode],validity: { timeValidity[id] = $0 })
    }
    private func number(_ title: String,value: Binding<Double>) -> some View {
        HStack { Text(title); Spacer(); TextField(title,value: value,format: .number).frame(width: 90).textFieldStyle(.roundedBorder).accessibilityLabel(title) }
    }
    private func integer(_ title: String,value: Binding<Int>) -> some View {
        HStack { Text(title); Spacer(); TextField(title,value: value,format: .number).frame(width: 90).textFieldStyle(.roundedBorder).accessibilityLabel(title) }
    }
    private func rectControl(_ label: String,key: WritableKeyPath<CGRect,CGFloat>,areaID: UUID? = nil) -> some View {
        let dimension = key == \.origin.x || key == \.size.width ? Double(model.info?.width ?? 1) : Double(model.info?.height ?? 1)
        return number(label,value: Binding(get: { Double((areaID.flatMap { id in model.edit.areas.first { $0.id == id }?.rect } ?? model.edit.crop)[keyPath: key])*dimension },set: { value in
            guard value.isFinite, dimension > 0 else { return }
            model.change { edit in if let areaID { if let index = edit.areas.firstIndex(where: { $0.id == areaID }) { edit.areas[index].rect[keyPath: key] = value/dimension } } else { edit.crop[keyPath: key] = value/dimension } }
        }))
    }
    private func rangeBinding<T>(id: UUID,key: WritableKeyPath<AVTimedArea,T>,fallback: T) -> Binding<T> {
        Binding(get: { model.edit.areas.first { $0.id == id }?[keyPath: key] ?? fallback },set: { value in
            model.change { edit in guard let index = edit.areas.firstIndex(where: { $0.id == id }) else { return }; edit.areas[index][keyPath: key] = value }
        })
    }
    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading,spacing: 14) {
            if model.tool == .videoTrim || model.tool == .audioTrim {
                timeInput(strings[.start],id:"start",value:binding(\.start)); timeInput(strings[.end],id:"end",value:binding(\.end))
                if model.tool == .audioTrim { Button(strings[.detectSilence]) { player.pause(); model.detectSilence() }.disabled(model.info == nil) }
            }
            if model.tool == .videoSpeed { number(strings[.speed]+" ×",value: binding(\.speed)) }
            if model.tool == .videoCrop {
                rectControl(image[.left],key: \.origin.x); rectControl(image[.top],key: \.origin.y)
                rectControl(image[.width],key: \.size.width); rectControl(MediaImageConverterStrings.localized(l10n.language).height,key: \.size.height)
            }
            if model.tool == .videoSplit {
                integer(strings[.parts],value: binding(\.splitCount)); Text(strings[.cuts]).font(.caption)
                TextField(strings[.cuts],text: binding(\.splitTimes)).textFieldStyle(.roundedBorder)
            }
            if model.tool == .videoFrames { Toggle(strings[.allFrames],isOn: binding(\.allFrames)); if !model.edit.allFrames { timeInput(strings[.frame],id:"frame",value:binding(\.frameTime)) } }
            if model.tool == .videoCompress {
                number(l10n.s.mediaSizingFileSize+" (MB)",value: Binding(get: { Double(model.edit.targetBytes)/1_000_000 },set: { value in guard value.isFinite, value >= 0, value <= 10000 else { return }; model.change { $0.targetBytes = Int64(value*1_000_000) } }))
                integer(image[.width]+" / "+MediaImageConverterStrings.localized(l10n.language).height,value: binding(\.maxDimension))
            }
            if model.tool == .audioNormalize {
                number(strings[.loudness],value: binding(\.loudness)); number(strings[.peak],value: binding(\.truePeak)); number(strings[.range],value: binding(\.loudnessRange))
            }
            if model.tool == .audioChannels {
                Toggle(strings[.mono],isOn:binding(\.mono)); number(strings[.leftGain],value:binding(\.leftGain)); number(strings[.rightGain],value:binding(\.rightGain))
                HStack {
                    Button(strings[.preview]+" · "+strings[.leftGain]) { previewChannel(left:true) }
                    Button(strings[.preview]+" · "+strings[.rightGain]) { previewChannel(left:false) }
                }.disabled(model.info == nil)
            }
            if model.tool == .audioVisualizer {
                integer(image[.width],value: binding(\.visualWidth)); integer(MediaImageConverterStrings.localized(l10n.language).height,value: binding(\.visualHeight))
                Button(strings[.still]) {
                    let picker = NSOpenPanel(); picker.allowedContentTypes = [.image]
                    picker.begin { result in if result == .OK { model.change { $0.stillImage = picker.url } } }
                }
                if let image = model.edit.stillImage { Text(image.lastPathComponent).lineLimit(1); Button(strings[.waveform]) { model.change { $0.stillImage = nil } } }
            }
            if model.tool == .videoRedact || model.tool == .audioBleep {
                Button(strings[.addRange]) { model.change { $0.areas.append(AVTimedArea(start: 0,end: min(model.info?.duration ?? 1,1))) } }
                ForEach(Array(model.edit.areas.enumerated()),id: \.element.id) { _,region in
                    VStack(alignment: .leading,spacing: 8) {
                        timeInput(strings[.start],id:region.id.uuidString+"start",value:rangeBinding(id:region.id,key:\.start,fallback:region.start))
                        timeInput(strings[.end],id:region.id.uuidString+"end",value:rangeBinding(id:region.id,key:\.end,fallback:region.end))
                        if model.tool == .videoRedact {
                            Picker(image[.redact],selection: rangeBinding(id: region.id,key: \.style,fallback: region.style)) {
                                Text(image[.solid]).tag(ImageRedactionStyle.solid); Text(image[.blur]).tag(ImageRedactionStyle.blur); Text(image[.pixelate]).tag(ImageRedactionStyle.pixelate)
                            }
                            rectControl(image[.left],key: \.origin.x,areaID: region.id); rectControl(image[.top],key: \.origin.y,areaID: region.id)
                            rectControl(image[.width],key: \.size.width,areaID: region.id); rectControl(MediaImageConverterStrings.localized(l10n.language).height,key: \.size.height,areaID: region.id)
                        }
                        Button(shared[.remove]) { model.change { $0.areas.removeAll { $0.id == region.id } } }
                    }.padding(10).background(FileToolAppearance.card,in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

private struct AVTimecodeField: View {
    let label: String
    @Binding var value: Double
    let fps: Double?
    let hint: String
    let validity: (Bool) -> Void
    @State private var text: String
    init(label: String,value: Binding<Double>,fps: Double?,hint: String,validity: @escaping (Bool) -> Void) {
        self.label = label; self._value = value; self.fps = fps; self.hint = hint; self.validity = validity
        self._text = State(initialValue:String(value.wrappedValue))
    }
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            HStack { Text(label); Spacer(); TextField(hint,text:$text).frame(width:130).textFieldStyle(.roundedBorder).accessibilityLabel(label+" · "+hint) }
            if AVTimeInputs.parse(text,fps:fps) == nil { Text(hint).font(.caption).foregroundStyle(.red) }
        }.onChange(of:text) { _,next in
            if let parsed = AVTimeInputs.parse(next,fps:fps) { validity(true); value = parsed } else { validity(false) }
        }.onChange(of:value) { _,next in
            if AVTimeInputs.parse(text,fps:fps) != next { text = String(next) }
        }.onChange(of:fps) { _,next in validity(AVTimeInputs.parse(text,fps:next) != nil) }.onAppear { validity(AVTimeInputs.parse(text,fps:fps) != nil) }.onDisappear { validity(true) }
    }
}
