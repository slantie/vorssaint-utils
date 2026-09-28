// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Small, local formats that can be produced by ImageIO or Apple's bundled
/// media converters. This is separate from saved image converter profiles.
/// A passive monitor notices file drags and presents a native drag destination.
/// No event is swallowed, and an ordinary drag without Shift is unaffected.
final class FileDragConversionService: ObservableObject {
    static let shared = FileDragConversionService()

    @Published private(set) var formats: [FileDragFormat] = []
    @Published private(set) var selected: FileDragFormat?
    @Published private(set) var status: String?
    @Published private(set) var inputCount = 0

    private var monitor: Any?
    private var panel: NSPanel?
    private var watchdog: Timer?
    private var dragBaseline = 0
    private var sawMouseDown = false
    private var isProcessing = false
    private var activeBatch: FileDragBatch?

    private init() {}

    func syncWithPreferences() {
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
                self.dragBaseline = NSPasteboard(name: .drag).changeCount
                self.sawMouseDown = true
            case .leftMouseUp:
                self.sawMouseDown = false
                self.dragBaseline = NSPasteboard(name: .drag).changeCount
                self.dismiss()
            case .leftMouseDragged:
                if !self.sawMouseDown {
                    self.sawMouseDown = true
                }
                guard event.modifierFlags.contains(.shift),
                      !event.modifierFlags.contains(.option) else {
                    self.dismiss()
                    return
                }
                self.considerDrag()
            default: break
            }
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        watchdog?.invalidate()
        watchdog = nil
        activeBatch?.cancel()
        dismiss()
    }

    private func considerDrag() {
        guard !isProcessing, panel?.isVisible != true else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragBaseline else { return }
        let urls = fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return }
        let kinds = urls.compactMap { url -> FileDragFormat.Kind? in
            guard let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType else { return nil }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .movie) || type.conforms(to: .video) {
                return ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) ? .video : nil
            }
            if type.conforms(to: .audio) {
                return ["mp3", "m4a", "wav", "aiff", "aif", "flac"].contains(url.pathExtension.lowercased()) ? .audio : nil
            }
            return nil
        }
        guard kinds.count == urls.count, let kind = kinds.first,
              kinds.allSatisfy({ $0 == kind }) else { return }
        inputCount = urls.count
        switch kind {
        case .image:
            let destinationTypes = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
            formats = FileDragFormat.availableImageFormats(destinationTypes: destinationTypes)
        case .video:
            formats = [.mp4, .mov]
        case .audio:
            formats = [.m4a, .wav, .aiff, .flac]
        }
        guard !formats.isEmpty else { return }
        show()
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
                self?.dismiss()
                return
            }
        }
    }

    private func dismiss() {
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        selected = nil
        watchdog?.invalidate()
        watchdog = nil
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
        let center = CGPoint(x: window.frame.width / 2, y: window.frame.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        guard hypot(dx, dy) > 36, !formats.isEmpty else {
            selected = nil
            return .copy
        }
        guard let index = RadialMenuGeometry.highlightedIndex(dx: dx, dyUp: dy,
                                                              deadZoneRadius: 36,
                                                              itemCount: formats.count) else {
            selected = nil
            return .copy
        }
        selected = formats[index]
        return .copy
    }

    fileprivate func accept(_ pasteboard: NSPasteboard) -> Bool {
        guard AppFeature.mediaTools.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.mediaDragConvertEnabled),
              let format = selected, formats.contains(format) else { return false }
        let urls = fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return false }
        dismiss()
        isProcessing = true
        let batch = FileDragBatch()
        activeBatch = batch
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = urls.map { url -> Result<URL, Error> in
                guard !batch.isCancelled else { return .failure(CancellationError()) }
                do { return .success(try FileDragConversionEngine.convert(url, to: format, batch: batch)) }
                catch { return .failure(error) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isProcessing = false
                if self.activeBatch === batch { self.activeBatch = nil }
                let outputs = results.compactMap { try? $0.get() }
                let failures = results.count - outputs.count
                let strings = FileDragStrings.localized(L10n.shared.language)
                self.status = failures == 0
                    ? String(format: strings.completedFormat, outputs.count)
                    : String(format: strings.partialFormat, outputs.count, failures)
                if !outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
                if failures == 0 {
                    QuickToolHUD.show(icon: "checkmark.circle", message: self.status ?? "")
                } else if !batch.isCancelled {
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
        FileDragConversionService.shared.selected != nil
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDragConversionService.shared.accept(sender.draggingPasteboard)
    }
}

private struct FileDragConversionWheel: View {
    @ObservedObject var service: FileDragConversionService
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassEnabled = false

    private var strings: FileDragStrings { .localized(l10n.language) }

    var body: some View {
        ZStack {
            disc
            if let selected = service.selected,
               let index = service.formats.firstIndex(of: selected) {
                RadialWedgeShape(centerAngle: 2 * .pi * Double(index) / Double(service.formats.count),
                                 sliceAngle: 2 * .pi / Double(service.formats.count),
                                 innerRadius: 39, outerRadius: 146)
                    .fill(RadialGradient(colors: [.accentColor.opacity(0.05), .accentColor.opacity(0.3)],
                                         center: .center, startRadius: 39, endRadius: 150))
                    .frame(width: 300, height: 300)
                    .animation(.easeOut(duration: 0.1), value: index)
            }
            ForEach(Array(service.formats.enumerated()), id: \.element.id) { index, format in
                let position = RadialMenuGeometry.unitPosition(index: index,
                                                               itemCount: service.formats.count)
                Text(format.title)
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
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                Text(service.selected?.title ?? strings.convert)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(String(format: strings.fileCountFormat, service.inputCount))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 82, height: 82)
            .background(PanelSurface.controlFill(for: colorScheme), in: Circle())
        }
        .frame(width: 332, height: 332)
        .accessibilityLabel(strings.dropHint)
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
