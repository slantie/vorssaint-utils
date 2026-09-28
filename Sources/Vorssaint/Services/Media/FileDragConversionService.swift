// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A passive monitor notices file drags and presents a native drag destination.
/// No event is swallowed, and an ordinary drag without Shift is unaffected.
final class FileDragConversionService: ObservableObject {
    static let shared = FileDragConversionService()

    @Published private(set) var actions: [FileDragAction] = []
    @Published private(set) var selected: FileDragAction?
    @Published private(set) var status: String?
    @Published private(set) var inputCount = 0

    private var monitor: Any?
    private var panel: NSPanel?
    private var watchdog: Timer?
    private var dragBaseline = 0
    private var sawMouseDown = false
    private var batches = FileDragBatchSession()
    private var dropSession: FileDragDropSession<FileDragAction>?
    private var toolsMode = false
    private var releaseCleanup: DispatchWorkItem?

    private init() {}

    func syncWithPreferences() {
        PDFToolController.shared.syncWithPreferences()
        let wanted = AppFeature.mediaTools.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.mediaDragConvertEnabled)
        if wanted {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard monitor == nil else { return }
        dragBaseline = NSPasteboard(name: .drag).changeCount
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
            [weak self] event in
            guard let self else { return }
            switch event.type {
            case .leftMouseDown:
                self.dismiss()
                self.dragBaseline = NSPasteboard(name: .drag).changeCount
                self.sawMouseDown = true
            case .leftMouseUp:
                self.sawMouseDown = false
                self.dragBaseline = NSPasteboard(name: .drag).changeCount
                self.mouseReleased()
            case .leftMouseDragged:
                if !self.sawMouseDown {
                    self.sawMouseDown = true
                }
                guard event.modifierFlags.contains(.shift) else {
                    self.dismiss()
                    return
                }
                self.considerDrag(tools: event.modifierFlags.contains(.option))
            default: break
            }
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        watchdog?.invalidate()
        watchdog = nil
        batches.cancel()
        status = nil
        dismiss()
    }

    private func considerDrag(tools: Bool) {
        guard !batches.isProcessing else { return }
        let alreadyVisible = panel?.isVisible == true
        if alreadyVisible && toolsMode == tools { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard alreadyVisible || pasteboard.changeCount != dragBaseline else { return }
        let urls = dropSession?.inputs ?? fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return }
        let kinds = urls.compactMap { url -> FileDragFormat.Kind? in
            guard let kind = FileDragFormat.inputKind(for: url) else { return nil }
            if MediaEngineBundle.bundled == nil {
                if kind == .video && !["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) { return nil }
                if kind == .audio && !["mp3", "m4a", "wav", "aiff", "aif", "flac"].contains(url.pathExtension.lowercased()) { return nil }
            }
            return kind
        }
        guard kinds.count == urls.count, let kind = kinds.first,
              kinds.allSatisfy({ $0 == kind }) else { return }
        inputCount = urls.count
        var formats: [FileDragFormat]
        switch kind {
        case .image:
            let destinationTypes = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
            formats = FileDragFormat.availableImageFormats(destinationTypes: destinationTypes)
            if MediaEngineBundle.bundled != nil {
                for format in [FileDragFormat.webp, .avif] where !formats.contains(format) { formats.append(format) }
            }
        case .video:
            formats = MediaEngineBundle.bundled == nil ? [.mp4, .mov] : [.mp4, .mov, .mkv, .webm, .avi, .wmv, .gif, .mp3]
        case .audio:
            formats = MediaEngineBundle.bundled == nil ? [.m4a, .wav, .aiff, .flac] : [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma]
        case .document: formats = [.docx, .jpeg, .png, .txt]
        }
        actions = tools && kind == .document ? PDFTool.allCases.map { .pdfTool($0) }
            : (tools ? [] : formats.map { .convert($0) })
        guard !actions.isEmpty else { dismiss(); return }
        toolsMode = tools
        selected = nil
        dropSession = FileDragDropSession(inputs: urls, formats: actions)
        if !alreadyVisible { show() }
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        guard !pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil),
              let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return [] }
        guard urls.allSatisfy({ url in
            guard url.isFileURL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }) else { return [] }
        return urls
    }

    private func show() {
        let panel = ensurePanel()
        status = nil
        selected = nil
        let size = CGSize(width: 332, height: 332)
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let origin = CGPoint(x: min(max(pointer.x - size.width / 2, visible.minX), visible.maxX - size.width),
                             y: min(max(pointer.y - size.height / 2, visible.minY), visible.maxY - size.height))
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard CGEventSource.buttonState(.combinedSessionState, button: .left) else {
                self?.dragBaseline = NSPasteboard(name: .drag).changeCount
                self?.sawMouseDown = false
                self?.mouseReleased()
                return
            }
        }
    }

    private func dismiss() {
        releaseCleanup?.cancel()
        releaseCleanup = nil
        panel?.orderOut(nil)
        dropSession = nil
        selected = nil
        watchdog?.invalidate()
        watchdog = nil
    }

    private func mouseReleased() {
        guard dropSession != nil, releaseCleanup == nil else { return }
        dropSession?.releaseMouse()
        watchdog?.invalidate()
        watchdog = nil
        // A passive mouse-up callback (or the button-state watchdog) can run
        // before AppKit's prepare/perform callbacks. Keep the destination and
        // its selection alive for that handoff; an abandoned drag still closes.
        let cleanup = DispatchWorkItem { [weak self] in self?.dismiss() }
        releaseCleanup = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: cleanup)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = ConversionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.registerForDraggedTypes([.fileURL])
        panel.contentViewController = NSHostingController(rootView: FileDragConversionWheel(service: self))
        self.panel = panel
        return panel
    }

    fileprivate func updateSelection(at location: CGPoint, in window: NSWindow) -> NSDragOperation {
        dropSession?.select(format(at: location, in: window))
        selected = dropSession?.selected
        return .copy
    }

    private func format(at location: CGPoint, in window: NSWindow) -> FileDragAction? {
        let center = CGPoint(x: window.frame.width / 2, y: window.frame.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        guard hypot(dx, dy) > 36, !actions.isEmpty else {
            return nil
        }
        guard let index = RadialMenuGeometry.highlightedIndex(dx: dx, dyUp: dy,
                                                              deadZoneRadius: 36,
                                                              itemCount: actions.count) else {
            return nil
        }
        return actions[index]
    }

    fileprivate func prepareDrop(at location: CGPoint, in window: NSWindow) -> Bool {
        let prepared = dropSession?.prepare(formatAtDrop: format(at: location, in: window)) ?? false
        selected = dropSession?.selected
        return prepared
    }

    fileprivate func acceptDrop() -> Bool {
        guard AppFeature.mediaTools.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.mediaDragConvertEnabled),
              !batches.isProcessing,
              let drop = dropSession?.takeDrop() else { return false }
        let urls = drop.inputs
        dismiss()
        if case .pdfTool(let tool) = drop.format {
            PDFToolController.shared.open(inputs: urls, tool: tool, requiresDragEnabled: true)
            return true
        }
        guard case .convert(let format) = drop.format, let batch = batches.begin() else { return false }
        let strings = FileDragStrings.localized(L10n.shared.language)
        status = "\(strings.convert) · \(String(format: strings.fileCountFormat, urls.count))"
        QuickToolHUD.show(icon: "hourglass", message: status ?? "")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = urls.map { url -> Result<URL, Error> in
                guard !batch.isCancelled else { return .failure(CancellationError()) }
                do { return .success(try FileDragConversionEngine.convert(url, to: format, batch: batch)) }
                catch { return .failure(error) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                switch self.batches.finish(batch,
                                          featureAvailable: AppFeature.mediaTools.isAvailable,
                                          enabled: UserDefaults.standard.bool(forKey: DefaultsKey.mediaDragConvertEnabled)) {
                case .obsolete: return
                case .suppressed:
                    self.status = nil
                    return
                case .publish: break
                }
                let outputs = results.compactMap { try? $0.get() }
                let failures = results.count - outputs.count
                let strings = FileDragStrings.localized(L10n.shared.language)
                self.status = failures == 0
                    ? String(format: strings.completedFormat, outputs.count)
                    : String(format: strings.partialFormat, outputs.count, failures)
                if let error = results.compactMap({ result -> Error? in
                    if case .failure(let error) = result { return error }
                    return nil
                }).first {
                    self.status = "\(self.status ?? "") · \(error.localizedDescription)"
                }
                if !outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
                if failures == 0 {
                    QuickToolHUD.show(icon: "checkmark.circle", message: self.status ?? "")
                } else {
                    QuickToolHUD.show(icon: "exclamationmark.triangle",
                                      message: String(format: strings.failedFormat,
                                                      failures, results.count))
                }
            }
        }
        return true
    }
}

private final class ConversionPanel: NSPanel, NSDraggingDestination {
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileDragConversionService.shared.updateSelection(at: sender.draggingLocation, in: self)
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDragConversionService.shared.prepareDrop(at: sender.draggingLocation, in: self)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDragConversionService.shared.acceptDrop()
    }
}

private struct FileDragConversionWheel: View {
    @ObservedObject var service: FileDragConversionService
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassEnabled = false

    private var strings: FileDragStrings { .localized(l10n.language) }
    private var hasPDFTools: Bool { service.actions.contains { if case .pdfTool = $0 { return true }; return false } }
    private var pdfStrings: PDFToolStrings { .localized(l10n.language) }

    var body: some View {
        ZStack {
            disc
            if let selected = service.selected,
               let index = service.actions.firstIndex(of: selected) {
                RadialWedgeShape(centerAngle: 2 * .pi * Double(index) / Double(service.actions.count),
                                 sliceAngle: 2 * .pi / Double(service.actions.count),
                                 innerRadius: 39, outerRadius: 146)
                    .fill(RadialGradient(colors: [.accentColor.opacity(0.05), .accentColor.opacity(0.3)],
                                         center: .center, startRadius: 39, endRadius: 150))
                    .frame(width: 300, height: 300)
                    .animation(.easeOut(duration: 0.1), value: index)
            }
            ForEach(Array(service.actions.enumerated()), id: \.element.id) { index, format in
                let position = RadialMenuGeometry.unitPosition(index: index,
                                                               itemCount: service.actions.count)
                Text(format.title(l10n.language))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(service.selected == format ? Color.white : Color.primary)
                    .frame(minWidth: 50, minHeight: 32)
                    .padding(.horizontal, 5)
                    .background(service.selected == format
                                ? AnyShapeStyle(Color.accentColor)
                                : AnyShapeStyle(PanelSurface.raisedFill(for: colorScheme)),
                                in: Capsule())
                    .overlay(Capsule().strokeBorder(PanelSurface.raisedBorder(for: colorScheme),
                                                    lineWidth: 0.8))
                    .shadow(color: PanelSurface.raisedShadow(for: colorScheme), radius: 5, y: 2)
                    .offset(x: position.dx * 116, y: -position.dyUp * 116)
            }
            VStack(spacing: 4) {
                Image(systemName: hasPDFTools ? "doc.richtext" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                Text(service.selected?.title(l10n.language) ?? (hasPDFTools ? pdfStrings[.tools] : strings.convert))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(String(format: strings.fileCountFormat, service.inputCount))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 82, height: 82)
            .background(PanelSurface.controlFill(for: colorScheme), in: Circle())
        }
        .frame(width: 332, height: 332)
        .accessibilityLabel(hasPDFTools ? pdfStrings[.dragHint] : strings.dropHint)
    }

    @ViewBuilder private var disc: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), liquidGlassEnabled, !reduceTransparency {
            Circle().fill(Color.clear).glassEffect(.regular, in: Circle())
                .overlay(Circle().fill(PanelSurface.baseFill(for: colorScheme).opacity(0.4)))
                .modifier(DiscRim(colorScheme: colorScheme))
        } else {
            standardDisc
        }
#else
        standardDisc
#endif
    }

    private var standardDisc: some View {
        Circle().fill(reduceTransparency
                      ? AnyShapeStyle(colorScheme == .light ? Color.white : Color.black)
                      : AnyShapeStyle(.regularMaterial))
            .overlay(Circle().fill(PanelSurface.baseFill(for: colorScheme)))
            .modifier(DiscRim(colorScheme: colorScheme))
    }
}

private struct DiscRim: ViewModifier {
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .overlay(Circle().strokeBorder(PanelSurface.rimHighlight(for: colorScheme), lineWidth: 1.2))
            .overlay(Circle().strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8))
            .frame(width: 300, height: 300)
            .shadow(color: .black.opacity(colorScheme == .light ? 0.22 : 0.55), radius: 24, y: 8)
    }
}
