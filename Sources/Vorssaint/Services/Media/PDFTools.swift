// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import PDFKit

enum PDFTool: String, CaseIterable, Identifiable {
    case split, merge, organize, compress, metadata, readQR
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .split: return "rectangle.split.2x1"
        case .merge: return "doc.on.doc"
        case .organize: return "square.grid.2x2"
        case .metadata: return "tag"
        case .readQR: return "qrcode.viewfinder"
        }
    }
    static func wheelTools(inputCount: Int) -> [Self] {
        inputCount > 1 ? [.compress, .split, .merge, .readQR] : [.compress, .metadata, .split, .organize, .readQR]
    }
}

enum FileDragAction: Equatable, Identifiable {
    case convert(FileDragFormat)
    case pdfTool(PDFTool)
    case imageTool(ImageFileTool)
    case avTool(AVFileTool)
    case moreTools, readImageQR
    case metadata
    case extractArchive
    var id: String {
        switch self {
        case .convert(let format): return format.id
        case .pdfTool(let tool): return "pdf-" + tool.rawValue
        case .imageTool(let tool): return "image-" + tool.rawValue
        case .avTool(let tool): return "av-" + tool.rawValue
        case .moreTools: return "more-tools"
        case .readImageQR: return "image-qr"
        case .metadata: return "file-metadata"
        case .extractArchive: return "archive-extract"
        }
    }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .convert(let format): return format.title
        case .pdfTool(let tool): return PDFToolStrings.localized(language).label(tool)
        case .imageTool(let tool): return ImageFileToolStrings.localized(language).label(tool)
        case .avTool(let tool): return AVFileToolStrings.localized(language).label(tool)
        case .moreTools: return FileToolExtraStrings.localized(language)[.more]
        case .readImageQR: return PDFToolStrings.localized(language).label(.readQR)
        case .metadata: return FileMetadataStrings.localized(language)[.title]
        case .extractArchive: return ArchiveToolStrings.extract(language)
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

struct PDFEditPlan: Equatable {
    var pages: [PDFPageEdit]
    var normalizeWidths = false
    var splitGroups: [[Int]]?

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

struct PDFMetadata: Equatable {
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

    static func splitGroups(_ raw: String, pageCount: Int) throws -> [[Int]]? {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard raw.utf8.count <= 10000, pageCount > 0, pageCount <= maxPages else { throw CocoaError(.fileReadTooLarge) }
        var groups: [[Int]] = []
        for part in raw.split(separator: ",", omittingEmptySubsequences: false) {
            let range = part.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
            guard range.count == 1 || range.count == 2, let first = Int(range[0]), first > 0, first <= pageCount,
                  let last = range.count == 2 ? Int(range[1]) : first, last >= first, last <= pageCount else { throw CocoaError(.validationMissingMandatoryProperty) }
            groups.append(Array((first-1)..<last))
        }
        guard groups.count <= maxPages else { throw CocoaError(.fileReadTooLarge) }; return groups
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
        guard tool != .readQR else { throw CocoaError(.fileWriteUnsupportedScheme) }
        guard !plan.pages.isEmpty, plan.pages.count <= maxPages else { throw CocoaError(.fileReadCorruptFile) }
        let input = plan.pages[0].source
        let output = MediaSupport.uniqueOutputURL(for: input, suffix: "-" + tool.rawValue,
                                                 fileExtension: tool == .split ? "" : "pdf")
        let staged = try MediaSupport.temporaryOutputURL(for: output)
        defer { MediaSupport.discardStagedOutput(staged) }
        if tool == .split { try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: false) }
        var sources: [URL: PDFDocument] = [:]
        let combined = PDFDocument()
        var targetWidth: CGFloat?
        if plan.normalizeWidths {
            for edit in plan.pages {
                guard !batch.isCancelled else { throw CancellationError() }
                if sources[edit.source] == nil { sources[edit.source] = try document(edit.source) }
                guard let page = sources[edit.source]?.page(at: edit.index) else { throw CocoaError(.fileReadCorruptFile) }
                let bounds = page.bounds(for: .mediaBox)
                let rotation = page.rotation + edit.quarterTurns * 90
                let width = abs(rotation) % 180 == 0 ? bounds.width : bounds.height
                guard width.isFinite, width > 0 else { throw CocoaError(.fileReadCorruptFile) }
                targetWidth = min(targetWidth ?? width, width)
            }
        }
        for edit in plan.pages {
            try autoreleasepool {
                guard !batch.isCancelled else { throw CancellationError() }
                if sources[edit.source] == nil { sources[edit.source] = try document(edit.source) }
                guard let source = sources[edit.source], source.allowsDocumentAssembly,
                      let original = source.page(at: edit.index), var page = original.copy() as? PDFPage,
                      (0...3).contains(edit.quarterTurns) else { throw CocoaError(.fileReadNoPermission) }
                page.rotation = (page.rotation + edit.quarterTurns * 90) % 360
                if let targetWidth { page = try normalizedPage(page, width: targetWidth) }
                combined.insert(page, at: combined.pageCount)
            }
        }
        if tool == .split {
            let groups = plan.splitGroups ?? plan.pages.indices.map { [$0] }
            guard !groups.isEmpty, groups.count <= maxPages, groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ plan.pages.indices.contains($0) }) }) else { throw CocoaError(.fileReadCorruptFile) }
            for (offset, group) in groups.enumerated() {
                guard !batch.isCancelled else { throw CancellationError() }
                let result = PDFDocument()
                for index in group { guard let page = combined.page(at: index)?.copy() as? PDFPage else { throw CocoaError(.fileReadCorruptFile) }; result.insert(page, at: result.pageCount) }
                let name = String(format: "%@ %04d.pdf", locale: Locale(identifier: "en_US_POSIX"), plan.splitGroups == nil ? "Page" : "Part", offset + 1)
                guard result.write(to: staged.appendingPathComponent(name)) else { throw CocoaError(.fileWriteUnknown) }
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

    private static func normalizedPage(_ page: PDFPage, width: CGFloat) throws -> PDFPage {
        let bounds = page.bounds(for: .mediaBox)
        let rotated = abs(page.rotation) % 180 != 0
        let originalWidth = rotated ? bounds.height : bounds.width
        let originalHeight = rotated ? bounds.width : bounds.height
        var box = CGRect(x: 0, y: 0, width: width, height: originalHeight * width / originalWidth)
        let data = NSMutableData()
        guard box.height.isFinite, box.height > 0, let reference = page.pageRef,
              let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        context.beginPDFPage(nil)
        context.concatenate(reference.getDrawingTransform(.mediaBox, rect: box,
                            rotate: Int32(page.rotation) - reference.rotationAngle, preserveAspectRatio: true))
        context.drawPDFPage(reference)
        // Normalization flattens annotation appearances into the transformed
        // vector page; ordinary organization retains editable annotations.
        for annotation in page.annotations where annotation.shouldDisplay { annotation.draw(with: .mediaBox, in: context) }
        context.endPDFPage(); context.closePDF()
        guard let normalized = PDFDocument(data: data as Data)?.page(at: 0)?.copy() as? PDFPage else {
            throw CocoaError(.fileWriteUnknown)
        }
        return normalized
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

    static func readQR(_ inputs: [URL], batch: FileDragBatch) throws -> [String] {
        var results: [String] = []
        var pageCount = 0
        for input in inputs {
            let source = try document(input)
            guard source.allowsCopying else { throw CocoaError(.fileReadNoPermission) }
            pageCount += source.pageCount
            guard pageCount <= maxPages else { throw CocoaError(.fileReadTooLarge) }
            for index in 0..<source.pageCount {
                try autoreleasepool {
                    guard !batch.isCancelled else { throw CancellationError() }
                    guard let page = source.page(at: index) else { throw CocoaError(.fileReadCorruptFile) }
                    let codes = BarcodeDetector.decode(try renderImage(page))
                    for code in codes where !results.contains(code.payload) { results.append(code.payload) }
                }
            }
        }
        guard !batch.isCancelled else { throw CancellationError() }
        return results
    }

    static func writeImage(_ page: PDFPage, to url: URL, format: FileDragFormat) throws {
        let image = try renderImage(page)
        guard let writer = CGImageDestinationCreateWithURL(url as CFURL, (format.typeIdentifier ?? "public.png") as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.9,
                                                kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func renderImage(_ page: PDFPage) throws -> CGImage {
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
        guard let image = context.makeImage() else { throw CocoaError(.fileReadCorruptFile) }
        return image
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
