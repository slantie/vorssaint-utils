// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers

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
        MediaSupport.uniqueOutputURL(for: input, suffix: "-converted",
                                     fileExtension: format.rawValue, fileManager: fileManager)
    }
}

/// One drag may launch several encoders. Cancelling the batch also terminates
/// its current child, while a queued next file observes the same cancellation.
final class FileDragBatch: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var current: BoundedProcessCancellation?

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func cancel() {
        lock.lock()
        cancelled = true
        let child = current
        lock.unlock()
        child?.cancel()
    }

    func beginProcess() throws -> BoundedProcessCancellation {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        let child = BoundedProcessCancellation()
        current = child
        return child
    }

    func endProcess(_ child: BoundedProcessCancellation) {
        lock.lock()
        defer { lock.unlock() }
        if current === child { current = nil }
    }
}

enum FileDragConversionEngine {
    static func convert(_ input: URL, to format: FileDragFormat,
                        batch: FileDragBatch) throws -> URL {
        guard !batch.isCancelled else { throw CancellationError() }
        guard let type = (try? input.resourceValues(forKeys: [.contentTypeKey]))?.contentType,
              (format.kind == .image && type.conforms(to: .image)
               || format.kind == .video && (type.conforms(to: .movie) || type.conforms(to: .video))
               || format.kind == .audio && type.conforms(to: .audio)) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        switch format.kind {
        case .image: return try convertImage(input, to: format, batch: batch)
        case .video, .audio: return try convertMedia(input, to: format, batch: batch)
        }
    }

    private static func convertMedia(_ input: URL, to format: FileDragFormat,
                                     batch: FileDragBatch) throws -> URL {
        let output = FileDragFormat.uniqueOutputURL(for: input, format: format)
        let staged = try MediaSupport.temporaryOutputURL(for: output)
        defer { MediaSupport.discardStagedOutput(staged) }
        let path: String
        let arguments: [String]
        switch format {
        case .mp4, .mov:
            path = "/usr/bin/avconvert"
            arguments = ["--source", input.path, "--preset", "PresetHighestQuality",
                         "--output", staged.path]
        case .m4a, .wav, .aiff, .flac:
            path = "/usr/bin/afconvert"
            let settings: (String, String)
            switch format {
            case .m4a: settings = ("m4af", "aac ")
            case .wav: settings = ("WAVE", "LEI16")
            case .aiff: settings = ("AIFF", "BEI16")
            case .flac: settings = ("flac", "flac")
            default: throw CocoaError(.fileWriteUnknown)
            }
            arguments = ["-f", settings.0, "-d", settings.1, input.path, staged.path]
        default: throw CocoaError(.fileWriteUnknown)
        }
        let cancellation = try batch.beginProcess()
        defer { batch.endProcess(cancellation) }
        let result = BoundedProcessRunner.run(path, arguments, timeout: 30 * 60,
                                              maxOutputBytes: 16_384,
                                              cancellation: cancellation)
        guard !batch.isCancelled else { throw CancellationError() }
        guard result.status == 0,
              (try? staged.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0 > 0 else {
            let detail = String(data: result.output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "FileDragConversion", code: result.timedOut ? 2 : 1,
                          userInfo: [NSLocalizedDescriptionKey:
                                        detail?.isEmpty == false ? detail! : "The media encoder failed."])
        }
        guard !batch.isCancelled else { throw CancellationError() }
        try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false)
        return output
    }

    private static func convertImage(_ input: URL, to format: FileDragFormat,
                                     batch: FileDragBatch) throws -> URL {
        guard let type = format.typeIdentifier,
              let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
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
        guard !batch.isCancelled else { throw CancellationError() }
        try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false)
        return output
    }
}
