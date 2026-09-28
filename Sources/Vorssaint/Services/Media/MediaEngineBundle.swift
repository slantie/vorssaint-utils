// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ImageIO

/// Engines are private app resources. The app never searches PATH, launches
/// Homebrew, or downloads executable code. Tests can inject a staged bundle.
struct MediaEngineBundle {
    let root: URL

    static let bundled: Self? = {
        guard let root = Bundle.main.url(forResource: "MediaEngines", withExtension: nil) else { return nil }
        return Self(root: root)
    }()

    init?(root: URL) {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              manifest["target"] as? String == "arm64-apple-macos14",
              FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("bin/ffmpeg").path),
              FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("bin/ffprobe").path) else { return nil }
        self.root = root
    }

    func run(_ name: String, arguments: [String], batch: FileDragBatch,
             timeout: TimeInterval = 30 * 60, maxOutputBytes: Int = 16_384) throws -> Data {
        guard name == "ffmpeg" || name == "ffprobe" else { throw CocoaError(.executableNotLoadable) }
        let child = try batch.beginProcess()
        defer { batch.endProcess(child) }
        let result = BoundedProcessRunner.run(root.appendingPathComponent("bin/" + name).path,
                                              arguments, timeout: timeout, maxOutputBytes: maxOutputBytes,
                                              cancellation: child)
        guard !batch.isCancelled else { throw CancellationError() }
        guard result.status == 0 else {
            let detail = String(data: result.output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "MediaEngine", code: result.timedOut ? 2 : 1,
                          userInfo: [NSLocalizedDescriptionKey: detail?.isEmpty == false ? detail! :
                                        CocoaError(.fileWriteUnknown).localizedDescription])
        }
        return result.output
    }

    func convert(_ input: URL, to format: FileDragFormat, batch: FileDragBatch) throws -> URL {
        let output = FileDragFormat.uniqueOutputURL(for: input, format: format)
        let staged = try MediaSupport.temporaryOutputURL(for: output)
        defer { MediaSupport.discardStagedOutput(staged) }
        var encoderInput = input
        var imageHasAlpha = false
        if format == .webp || format == .avif {
            guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 32768,
                  ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
            // Normalize orientation before handing pixels to the external
            // encoder. This intermediate is private and removed with the job.
            encoderInput = staged.deletingLastPathComponent().appendingPathComponent("Oriented.png")
            guard let writer = CGImageDestinationCreateWithURL(encoderInput as CFURL, "public.png" as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImage(writer, image, nil)
            guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
            imageHasAlpha = [.first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly].contains(image.alphaInfo)
        }
        var arguments = ["-nostdin", "-v", "error", "-n", "-max_alloc", "536870912",
                         "-filter_threads", "2", "-filter_complex_threads", "2",
                         "-threads", "4", "-protocol_whitelist", "file,pipe", "-i", encoderInput.path]
        switch format {
        case .mp4, .mov, .mkv:
            arguments += ["-map", "0:v:0", "-map", "0:a:0?", "-c:v", "h264_videotoolbox",
                          "-b:v", "8M", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k"]
            if format != .mkv { arguments += ["-movflags", "+faststart"] }
        case .webm:
            arguments += ["-map", "0:v:0", "-map", "0:a:0?", "-c:v", "libvpx-vp9", "-crf", "32",
                          "-b:v", "0", "-row-mt", "1", "-threads", "4", "-c:a", "libopus"]
        case .avi:
            arguments += ["-map", "0:v:0", "-map", "0:a:0?", "-c:v", "mpeg4", "-q:v", "3",
                          "-c:a", "libmp3lame", "-b:a", "192k"]
        case .wmv:
            arguments += ["-map", "0:v:0", "-map", "0:a:0?", "-c:v", "wmv2", "-b:v", "6M",
                          "-c:a", "wmav2", "-b:a", "192k", "-ar", "48000", "-ac", "2"]
        case .gif:
            arguments += ["-an", "-filter_complex",
                          "fps=12,split[video][colors];[colors]palettegen[palette];[video][palette]paletteuse"]
        case .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma:
            arguments += ["-map", "0:a:0", "-vn"]
            switch format {
            case .mp3: arguments += ["-c:a", "libmp3lame", "-q:a", "2"]
            case .m4a: arguments += ["-c:a", "aac", "-b:a", "192k"]
            case .wav: arguments += ["-c:a", "pcm_s16le"]
            case .aiff: arguments += ["-c:a", "pcm_s16be"]
            case .flac: arguments += ["-c:a", "flac"]
            case .ogg: arguments += ["-c:a", "libopus", "-f", "ogg"]
            case .opus: arguments += ["-c:a", "libopus"]
            case .wma: arguments += ["-c:a", "wmav2", "-b:a", "192k", "-ar", "48000", "-ac", "2"]
            default: break
            }
        case .webp:
            arguments += ["-frames:v", "1", "-c:v", "libwebp", "-quality", "85"]
        case .avif:
            if imageHasAlpha {
                arguments += ["-filter_complex", "[0:v]alphaextract,setparams=colorspace=bt709[alpha]",
                              "-map", "0:v:0", "-map", "[alpha]"]
            }
            arguments += ["-frames:v", "1", "-c:v", "libaom-av1", "-still-picture", "1",
                          "-cpu-used", "6", "-crf", "28", "-b:v", "0", "-pix_fmt:v:0", "yuv420p",
                          "-colorspace:v", "bt709", "-color_range:v", "pc"]
            if imageHasAlpha { arguments += ["-pix_fmt:v:1", "gray", "-crf:v:1", "0"] }
        default: throw CocoaError(.fileWriteUnknown)
        }
        arguments += ["-threads", "4", staged.path]
        _ = try run("ffmpeg", arguments: arguments, batch: batch)
        guard !batch.isCancelled else { throw CancellationError() }
        guard (try? staged.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0 > 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false)
        return output
    }
}
