// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreText
import PDFKit

struct SubtitleCue: Equatable {
    var start: Int64, end: Int64 // Milliseconds.
    var text: String
}
struct SubtitleTiming: Equatable {
    var duration = 3.0, offset = 0.0, gap = 0.0
    var isValid: Bool { duration.isFinite && offset.isFinite && gap.isFinite && (0.001...3600).contains(duration) && (0...86400).contains(offset) && (0...3600).contains(gap) }
}
enum TextFileTools {
    static let maxBytes = 10 * 1024 * 1024
    static func read(_ input: URL) throws -> String {
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard input.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= maxBytes else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf: input)
        guard data.count <= maxBytes, let text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
    }
    static func time(_ raw: Substring) throws -> Int64 {
        let pieces = raw.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard pieces.count == 2 || pieces.count == 3,
              let seconds = pieces.last.flatMap({ Double($0) }), seconds.isFinite, seconds >= 0, seconds < 60,
              let minutes = Int64(pieces[pieces.count - 2]), (0..<60).contains(minutes),
              let hours = pieces.count == 3 ? Int64(pieces[0]) : 0, (0..<10000).contains(hours) else { throw CocoaError(.fileReadCorruptFile) }
        return (hours*3600 + minutes*60)*1000 + Int64((seconds*1000).rounded())
    }
    static func cues(_ text: String) throws -> [SubtitleCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []
        for block in blocks {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }
            if lines[0].hasPrefix("WEBVTT") || lines[0].hasPrefix("NOTE") || lines[0] == "STYLE" || lines[0] == "REGION" { continue }
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }), timing <= 1 else { throw CocoaError(.fileReadCorruptFile) }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let left = parts[0].split(whereSeparator: \.isWhitespace).first,
                  let right = parts[1].split(whereSeparator: \.isWhitespace).first else { throw CocoaError(.fileReadCorruptFile) }
            let start = try time(left), end = try time(right)
            guard end > start, lines.count > timing+1 else { throw CocoaError(.fileReadCorruptFile) }
            cues.append(SubtitleCue(start: start, end: end, text: lines.dropFirst(timing+1).joined(separator: "\n")))
            guard cues.count <= 100000 else { throw CocoaError(.fileReadTooLarge) }
        }
        guard !cues.isEmpty else { throw CocoaError(.fileReadCorruptFile) }; return cues
    }
    private static func stamp(_ value: Int64, vtt: Bool) -> String {
        String(format: "%02lld:%02lld:%02lld%@%03lld", locale: Locale(identifier: "en_US_POSIX"), value/3600000, (value/60000)%60, (value/1000)%60, vtt ? "." : ",", value%1000)
    }
    static func serialize(_ cues: [SubtitleCue], format: String) -> String {
        if format == "txt" { return cues.map(\.text).joined(separator: "\n\n") + "\n" }
        let vtt = format == "vtt"
        return (vtt ? "WEBVTT\n\n" : "") + cues.enumerated().map { index, cue in
            (vtt ? "" : "\(index+1)\n") + stamp(cue.start, vtt: vtt) + " --> " + stamp(cue.end, vtt: vtt) + "\n" + cue.text
        }.joined(separator: "\n\n") + "\n"
    }
    static func pdf(_ text: String, to url: URL, batch: FileDragBatch) throws {
        guard text.utf8.count <= maxBytes else { throw CocoaError(.fileReadTooLarge) }
        let attributed = NSAttributedString(string: text.isEmpty ? " " : text, attributes: [
            .font: CTFontCreateWithName("Helvetica" as CFString, 12, nil), .foregroundColor: CGColor(gray: 0, alpha: 1)])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        var offset = 0, pages = 0
        repeat {
            guard !batch.isCancelled else { context.closePDF(); throw CancellationError() }
            pages += 1; guard pages <= PDFTools.maxPages else { context.closePDF(); throw CocoaError(.fileReadTooLarge) }
            context.beginPDFPage(nil)
            let path = CGPath(rect: box.insetBy(dx: 36, dy: 36), transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), path, nil)
            let range = CTFrameGetVisibleStringRange(frame)
            guard range.length > 0 else { context.closePDF(); throw CocoaError(.fileWriteUnknown) }
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box); CTFrameDraw(frame, context)
            context.endPDFPage(); offset += range.length
        } while offset < attributed.length
        context.closePDF()
    }
    static func convert(_ input: URL, to format: String, batch: FileDragBatch, timing: SubtitleTiming = SubtitleTiming()) throws -> URL {
        let text = try read(input), subtitle = ["srt", "vtt"].contains(input.pathExtension.lowercased())
        let folder = format == "png" || format == "jpg"
        let output = MediaSupport.uniqueOutputURL(for: input, suffix: folder ? "-converted-"+format : "-converted", fileExtension: folder ? "" : format)
        let staged = try MediaSupport.temporaryOutputURL(for: output); defer { MediaSupport.discardStagedOutput(staged) }
        guard !batch.isCancelled else { throw CancellationError() }
        if ["srt", "vtt", "txt"].contains(format) {
            let cues: [SubtitleCue]
            if subtitle || text.contains("-->") { cues = try self.cues(text) }
            else {
                let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                guard !lines.isEmpty, lines.count <= 100000 else { throw CocoaError(.fileReadCorruptFile) }
                guard timing.isValid else { throw CocoaError(.validationMissingMandatoryProperty) }
                let duration = Int64((timing.duration*1000).rounded()), offset = Int64((timing.offset*1000).rounded()), gap = Int64((timing.gap*1000).rounded())
                guard offset+Int64(lines.count)*(duration+gap) < 36_000_000_000 else { throw CocoaError(.fileReadTooLarge) }
                cues = lines.enumerated().map { i,line in let start = offset+Int64(i)*(duration+gap); return SubtitleCue(start:start,end:start+duration,text:line) }
            }
            try serialize(cues, format: format).write(to: staged, atomically: false, encoding: .utf8)
        } else if format == "pdf" || folder {
            let pdfURL = folder ? staged.deletingLastPathComponent().appendingPathComponent("Text.pdf") : staged
            try pdf(text, to: pdfURL, batch: batch)
            if folder {
                try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
                let document = try PDFTools.document(pdfURL)
                for i in 0..<document.pageCount {
                    guard !batch.isCancelled else { throw CancellationError() }
                    let output = staged.appendingPathComponent(String(format: "Page %04d.%@", locale: Locale(identifier: "en_US_POSIX"), i+1, format))
                    try PDFTools.writeImage(document.page(at: i)!, to: output, format: format == "png" ? .png : .jpeg)
                }
            }
        } else { throw CocoaError(.fileWriteUnsupportedScheme) }
        guard !batch.isCancelled else { throw CancellationError() }
        try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false); return output
    }
}
