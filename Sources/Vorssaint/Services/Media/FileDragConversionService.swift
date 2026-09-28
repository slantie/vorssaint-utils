// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Small, local formats that can be produced by ImageIO or Apple's bundled
/// media converters. This is separate from saved image converter profiles.
enum FileDragFormat: String, CaseIterable, Identifiable {
    case jpeg = "jpg", png, heic, tiff, bmp, gif, webp, avif, pdf
    case mp4, mov, m4a, wav, aiff, flac

    enum Kind { case image, video, audio }

    var kind: Kind {
        switch self {
        case .jpeg, .png, .heic, .tiff, .bmp, .gif, .webp, .avif, .pdf: return .image
        case .mp4, .mov: return .video
        case .m4a, .wav, .aiff, .flac: return .audio
        }
    }

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    var typeIdentifier: String? {
        UTType(filenameExtension: rawValue)?.identifier
    }

    static func availableImageFormats(destinationTypes: Set<String>) -> [Self] {
        allCases.filter { format in
            guard format.kind == .image else { return false }
            guard let type = format.typeIdentifier else { return false }
            return destinationTypes.contains(type)
        }
    }

    static func uniqueOutputURL(for input: URL, format: Self,
                                fileManager: FileManager = .default) -> URL {
        let parent = input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        let ext = format.rawValue
        var candidate = parent.appendingPathComponent(stem + "-converted").appendingPathExtension(ext)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(stem)-converted-\(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }
}

/// A passive monitor notices file drags and presents a native drag destination.
/// No event is swallowed, and an ordinary drag without Shift is unaffected.
final class FileDragConversionService: ObservableObject {
    static let shared = FileDragConversionService()

    @Published private(set) var formats: [FileDragFormat] = []
    @Published private(set) var selected: FileDragFormat?
    @Published private(set) var status: String?

    private var monitor: Any?
    private var panel: NSPanel?
    private var watchdog: Timer?
    private var dragBaseline = 0
    private var sawMouseDown = false
    private var isProcessing = false

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
        dismiss()
    }

    private func considerDrag() {
        guard !isProcessing, panel?.isVisible != true else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragBaseline else { return }
        let urls = fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return }
        let sourceTypes = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
        let kinds = urls.compactMap { url -> FileDragFormat.Kind? in
            guard let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType else { return nil }
            if sourceTypes.contains(type.identifier) || type.conforms(to: .image) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      CGImageSourceGetCount(source) == 1 else { return nil }
                return .image
            }
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
        let angle = atan2(dy, dx)
        let normalized = angle < 0 ? angle + 2 * CGFloat.pi : angle
        let index = Int((normalized / (2 * CGFloat.pi) * CGFloat(formats.count)).rounded()) % formats.count
        selected = formats[index]
        return .copy
    }

    fileprivate func accept(_ pasteboard: NSPasteboard) -> Bool {
        guard AppFeature.mediaTools.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.mediaDragConvertEnabled),
              let format = selected else { return false }
        let urls = fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return false }
        dismiss()
        isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = urls.map { url -> Result<URL, Error> in
                guard AppFeature.mediaTools.isAvailable,
                      UserDefaults.standard.bool(forKey: DefaultsKey.mediaDragConvertEnabled) else {
                    return .failure(CocoaError(.userCancelled))
                }
                do { return .success(try Self.convert(url, to: format)) }
                catch { return .failure(error) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isProcessing = false
                let outputs = results.compactMap { try? $0.get() }
                let failures = results.count - outputs.count
                self.status = failures == 0 ? "Converted \(outputs.count) file(s)" : "Converted \(outputs.count); \(failures) failed"
                if !outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
                if failures > 0 {
                    let alert = NSAlert()
                    alert.messageText = "Some files could not be converted"
                    alert.informativeText = "\(failures) of \(results.count) files failed. The original files were not changed."
                    alert.runModal()
                }
            }
        }
        return true
    }

    private static func convert(_ input: URL, to format: FileDragFormat) throws -> URL {
        switch format.kind {
        case .image: return try convertImage(input, to: format)
        case .video, .audio: return try convertMedia(input, to: format)
        }
    }

    private static func convertMedia(_ input: URL, to format: FileDragFormat) throws -> URL {
        let output = FileDragFormat.uniqueOutputURL(for: input, format: format)
        let staged = try MediaSupport.temporaryOutputURL(for: output)
        defer { MediaSupport.discardStagedOutput(staged) }
        let process = Process()
        switch format {
        case .mp4, .mov:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/avconvert")
            process.arguments = ["--source", input.path, "--preset", "PresetHighestQuality",
                                 "--output", staged.path]
        case .m4a, .wav, .aiff, .flac:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            let settings: (String, String)
            switch format {
            case .m4a: settings = ("m4af", "aac ")
            case .wav: settings = ("WAVE", "LEI16")
            case .aiff: settings = ("AIFF", "BEI16")
            case .flac: settings = ("flac", "flac")
            default: throw CocoaError(.fileWriteUnknown)
            }
            process.arguments = ["-f", settings.0, "-d", settings.1, input.path, staged.path]
        default: throw CocoaError(.fileWriteUnknown)
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              (try? staged.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0 > 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false)
        return output
    }

    private static func convertImage(_ input: URL, to format: FileDragFormat) throws -> URL {
        guard let type = format.typeIdentifier,
              let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceSize = MediaSupport.imageDisplaySize(properties: properties),
              MediaSupport.imageRenderSizeIsSafe(sourceSize),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 32768,
              ] as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let output = FileDragFormat.uniqueOutputURL(for: input, format: format)
        let staged = try MediaSupport.temporaryOutputURL(for: output)
        defer { MediaSupport.discardStagedOutput(staged) }
        guard let destination = CGImageDestinationCreateWithURL(staged as CFURL, type as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let rendered: CGImage
        if format == .jpeg || format == .bmp {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw CocoaError(.fileWriteUnknown)
            }
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let opaque = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
            rendered = opaque
        } else {
            rendered = image
        }
        CGImageDestinationAddImage(destination, rendered, [
            kCGImageDestinationLossyCompressionQuality: 0.85,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false)
        return output
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

    var body: some View {
        ZStack {
            Circle().fill(.regularMaterial)
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
            ForEach(Array(service.formats.enumerated()), id: \.element.id) { index, format in
                let angle = Double(index) * 2 * Double.pi / Double(max(1, service.formats.count))
                Text(format.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(service.selected == format ? .white : .primary)
                    .frame(width: 64, height: 32)
                    .background(service.selected == format ? Color.accentColor : Color.clear,
                                in: Capsule())
                    .offset(x: cos(angle) * 116, y: -sin(angle) * 116)
            }
            VStack(spacing: 3) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text(service.selected?.title ?? "Convert")
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .frame(width: 332, height: 332)
        .accessibilityLabel("Drop on a format to convert a copy beside the original")
    }
}
