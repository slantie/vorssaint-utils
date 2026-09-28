// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import PDFKit

enum PDFTool: String, CaseIterable, Identifiable {
    case split, merge, organize, compress, metadata
    var id: String { rawValue }
}

enum FileDragAction: Equatable, Identifiable {
    case convert(FileDragFormat)
    case pdfTool(PDFTool)
    var id: String {
        switch self {
        case .convert(let format): return format.id
        case .pdfTool(let tool): return "pdf-" + tool.rawValue
        }
    }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .convert(let format): return format.title
        case .pdfTool(let tool): return PDFToolStrings.localized(language).label(tool)
        }
    }
}

struct PDFPageEdit: Identifiable, Equatable {
    let id: UUID
    let source: URL
    let index: Int
    var quarterTurns: Int

    init(source: URL, index: Int, quarterTurns: Int = 0, id: UUID = UUID()) {
        self.id = id; self.source = source; self.index = index; self.quarterTurns = quarterTurns
    }
}

struct PDFEditPlan {
    var pages: [PDFPageEdit]

    mutating func move(_ id: UUID, to destination: Int) {
        guard let index = pages.firstIndex(where: { $0.id == id }),
              pages.indices.contains(destination) else { return }
        let page = pages.remove(at: index)
        pages.insert(page, at: destination)
    }
    mutating func rotate(_ id: UUID) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].quarterTurns = (pages[index].quarterTurns + 1) % 4
    }
    mutating func duplicate(_ id: UUID) {
        guard pages.count < PDFTools.maxPages, let index = pages.firstIndex(where: { $0.id == id }) else { return }
        let page = pages[index]
        pages.insert(PDFPageEdit(source: page.source, index: page.index, quarterTurns: page.quarterTurns), at: index + 1)
    }
    mutating func remove(_ id: UUID) { pages.removeAll { $0.id == id } }
}

struct PDFMetadata {
    var title = ""
    var author = ""
    var subject = ""
    var keywords = ""
    var attributes: [PDFDocumentAttribute: Any] {
        [.titleAttribute: title, .authorAttribute: author, .subjectAttribute: subject,
         .keywordsAttribute: keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }]
    }
}

enum PDFTools {
    static let maxPages = 2_000

    static func document(_ url: URL) throws -> PDFDocument {
        guard url.isFileURL, let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
        guard (values.fileSize ?? 0) <= 512 * 1_024 * 1_024 else { throw CocoaError(.fileReadTooLarge) }
        guard let document = PDFDocument(url: url), document.pageCount > 0,
              document.pageCount <= maxPages else { throw CocoaError(.fileReadCorruptFile) }
        guard !document.isLocked else { throw CocoaError(.fileReadNoPermission) }
        return document
    }

    static func plan(_ inputs: [URL]) throws -> PDFEditPlan {
        var pages: [PDFPageEdit] = []
        for input in inputs {
            let doc = try document(input)
            guard doc.allowsDocumentAssembly else { throw CocoaError(.fileReadNoPermission) }
            pages += (0..<doc.pageCount).map { PDFPageEdit(source: input, index: $0) }
            guard pages.count <= maxPages else { throw CocoaError(.fileReadTooLarge) }
        }
        guard !pages.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return PDFEditPlan(pages: pages)
    }

    static func metadata(_ input: URL) throws -> PDFMetadata {
        let attributes = try document(input).documentAttributes ?? [:]
        return PDFMetadata(title: attributes[PDFDocumentAttribute.titleAttribute] as? String ?? "",
                           author: attributes[PDFDocumentAttribute.authorAttribute] as? String ?? "",
                           subject: attributes[PDFDocumentAttribute.subjectAttribute] as? String ?? "",
                           keywords: (attributes[PDFDocumentAttribute.keywordsAttribute] as? [String] ?? []).joined(separator: ", "))
    }

    static func save(_ plan: PDFEditPlan, tool: PDFTool, metadata: PDFMetadata = PDFMetadata(),
                     batch: FileDragBatch) throws -> URL {
        guard !batch.isCancelled else { throw CancellationError() }
        guard !plan.pages.isEmpty, plan.pages.count <= maxPages else { throw CocoaError(.fileReadCorruptFile) }
        let input = plan.pages[0].source
        let output = MediaSupport.uniqueOutputURL(for: input, suffix: "-" + tool.rawValue,
                                                 fileExtension: tool == .split ? "" : "pdf")
        let staged = try MediaSupport.temporaryOutputURL(for: output)
        defer { MediaSupport.discardStagedOutput(staged) }
        if tool == .split { try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: false) }
        var sources: [URL: PDFDocument] = [:]
        let combined = PDFDocument()
        for (offset, edit) in plan.pages.enumerated() {
            try autoreleasepool {
                guard !batch.isCancelled else { throw CancellationError() }
                if sources[edit.source] == nil { sources[edit.source] = try document(edit.source) }
                guard let source = sources[edit.source], source.allowsDocumentAssembly,
                      let original = source.page(at: edit.index), let page = original.copy() as? PDFPage,
                      (0...3).contains(edit.quarterTurns) else { throw CocoaError(.fileReadNoPermission) }
                page.rotation = (page.rotation + edit.quarterTurns * 90) % 360
                if tool == .split {
                    let single = PDFDocument(); single.insert(page, at: 0)
                    guard single.write(to: staged.appendingPathComponent(String(format: "Page %04d.pdf", locale: Locale(identifier: "en_US_POSIX"), offset + 1))) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                } else { combined.insert(page, at: combined.pageCount) }
            }
        }
        if tool != .split {
            if tool == .metadata {
                guard sources.values.allSatisfy({ $0.allowsDocumentChanges }) else { throw CocoaError(.fileReadNoPermission) }
                combined.documentAttributes = metadata.attributes
            } else { combined.documentAttributes = sources[input]?.documentAttributes }
            let options: [PDFDocumentWriteOption: Any] = tool == .compress
                ? [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true] : [:]
            guard combined.write(to: staged, withOptions: options) else { throw CocoaError(.fileWriteUnknown) }
        }
        guard !batch.isCancelled else { throw CancellationError() }
        try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false)
        return output
    }

    static func convert(_ input: URL, to format: FileDragFormat, batch: FileDragBatch) throws -> URL {
        let source = try document(input)
        guard source.allowsCopying else { throw CocoaError(.fileReadNoPermission) }
        let output = FileDragFormat.uniqueOutputURL(for: input, format: format)
        let folder = (format == .jpeg || format == .png) && source.pageCount > 1
        let destination = folder ? MediaSupport.uniqueOutputURL(for: input, suffix: "-converted-" + format.rawValue, fileExtension: "") : output
        let staged = try MediaSupport.temporaryOutputURL(for: destination)
        defer { MediaSupport.discardStagedOutput(staged) }
        if folder { try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: false) }
        if format == .txt {
            var parts: [String] = []
            for index in 0..<source.pageCount {
                guard !batch.isCancelled else { throw CancellationError() }
                parts.append(source.page(at: index)?.string ?? "")
            }
            try parts.joined(separator: "\n\n").write(to: staged, atomically: false, encoding: .utf8)
        } else if format == .jpeg || format == .png {
            for index in 0..<source.pageCount {
                try autoreleasepool {
                    guard !batch.isCancelled, let page = source.page(at: index) else { throw CancellationError() }
                    let target = folder ? staged.appendingPathComponent(String(format: "Page %04d.%@", index + 1, format.rawValue)) : staged
                    try writeImage(page, to: target, format: format)
                }
            }
        } else if format == .docx {
            try writeWord(source, staged: staged, batch: batch)
        } else { throw CocoaError(.fileReadUnsupportedScheme) }
        guard !batch.isCancelled else { throw CancellationError() }
        try MediaSupport.installStagedOutput(staged, at: destination, replacingExisting: false)
        return destination
    }

    static func writeImage(_ page: PDFPage, to url: URL, format: FileDragFormat) throws {
        let bounds = page.bounds(for: .mediaBox)
        let swapped = abs(page.rotation) % 180 != 0
        let size = CGSize(width: (swapped ? bounds.height : bounds.width) * 300 / 72,
                          height: (swapped ? bounds.width : bounds.height) * 300 / 72)
        guard MediaSupport.imageRenderSizeIsSafe(size),
              let context = CGContext(data: nil, width: Int(ceil(size.width)), height: Int(ceil(size.height)),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let reference = page.pageRef else { throw CocoaError(.fileReadTooLarge) }
        let canvas = CGRect(x: 0, y: 0, width: context.width, height: context.height)
        context.setFillColor(NSColor.white.cgColor); context.fill(canvas)
        context.concatenate(reference.getDrawingTransform(.mediaBox, rect: canvas, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(reference)
        for annotation in page.annotations where annotation.shouldDisplay {
            annotation.draw(with: .mediaBox, in: context)
        }
        guard let image = context.makeImage(),
              let writer = CGImageDestinationCreateWithURL(url as CFURL, (format.typeIdentifier ?? "public.png") as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.9,
                                                kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func writeWord(_ source: PDFDocument, staged: URL, batch: FileDragBatch) throws {
        let package = staged.deletingLastPathComponent().appendingPathComponent("WordPackage")
        let word = package.appendingPathComponent("word")
        try FileManager.default.createDirectory(at: word.appendingPathComponent("media"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: word.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").filter { $0 == "\n" || $0 == "\t" || $0.unicodeScalars.allSatisfy { $0.value >= 32 } }
        }
        var body = ""; var relationships = ""
        for index in 0..<source.pageCount {
            guard !batch.isCancelled, let page = source.page(at: index) else { throw CancellationError() }
            let text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let name = "page\(index + 1).png"
                try writeImage(page, to: word.appendingPathComponent("media/" + name), format: .png)
                let box = page.bounds(for: .mediaBox)
                let aspect = abs(page.rotation) % 180 == 0 ? box.height / max(1, box.width) : box.width / max(1, box.height)
                let width = 5_486_400, height = Int(Double(width) * aspect)
                relationships += "<Relationship Id=\"image\(index)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(name)\"/>"
                body += "<w:p><w:r><w:drawing><wp:inline><wp:extent cx=\"\(width)\" cy=\"\(height)\"/><wp:docPr id=\"\(index + 1)\" name=\"Page \(index + 1)\"/><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic><pic:nvPicPr><pic:cNvPr id=\"\(index + 1)\" name=\"\(name)\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"image\(index)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(width)\" cy=\"\(height)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>"
            } else {
                for line in text.components(separatedBy: .newlines) {
                    body += "<w:p><w:r><w:t xml:space=\"preserve\">\(escape(line))</w:t></w:r></w:p>"
                }
            }
            if index + 1 < source.pageCount { body += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>" }
        }
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        try (xml + "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><w:body>" + body + "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"720\" w:right=\"720\" w:bottom=\"720\" w:left=\"720\"/></w:sectPr></w:body></w:document>")
            .write(to: word.appendingPathComponent("document.xml"), atomically: false, encoding: .utf8)
        let rel = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        try (xml + rel + relationships + "</Relationships>").write(to: word.appendingPathComponent("_rels/document.xml.rels"), atomically: false, encoding: .utf8)
        try (xml + rel + "<Relationship Id=\"document\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>")
            .write(to: package.appendingPathComponent("_rels/.rels"), atomically: false, encoding: .utf8)
        try (xml + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>")
            .write(to: package.appendingPathComponent("[Content_Types].xml"), atomically: false, encoding: .utf8)
        let child = try batch.beginProcess(); defer { batch.endProcess(child) }
        let result = BoundedProcessRunner.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", package.path, staged.path],
                                              timeout: 120, maxOutputBytes: 16_384, cancellation: child)
        guard !batch.isCancelled else { throw CancellationError() }
        guard result.status == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
