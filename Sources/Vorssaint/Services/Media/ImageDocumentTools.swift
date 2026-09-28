// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import Foundation
import ImageIO

/// Static SVG inputs are parsed before entering a renderer built without file
/// IO. Interactive content and external resources are never silently fetched.
private final class StaticSVGValidator: NSObject, XMLParserDelegate {
    var valid = true
    private var count = 0
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String]) {
        count += 1
        let name = elementName.lowercased().split(separator: ":").last.map(String.init) ?? ""
        if count > 50_000 || ["script", "foreignobject", "animate", "animatetransform", "animatemotion", "set", "include"].contains(name) { valid = false }
        if count == 1 && name != "svg" { valid = false }
        for (key,value) in attributes {
            let key = key.lowercased(), value = value.trimmingCharacters(in:.whitespacesAndNewlines)
            if key.hasPrefix("on") { valid = false }
            if key == "href" || key.hasSuffix(":href") {
                if !value.hasPrefix("#") && !value.hasPrefix("data:image/png;base64,") && !value.hasPrefix("data:image/jpeg;base64,") { valid = false }
            }
            checkStyles(value)
        }
        if !valid { parser.abortParsing() }
    }
    private func checkStyles(_ text: String) {
        let text = text.lowercased()
        if text.contains("@import") || text.contains("\\") { valid = false }
        let pattern = #"url\s*\(\s*["']?\s*([^\s\)"']+)"#
        if let expression = try? NSRegularExpression(pattern:pattern) {
            let ns = text as NSString
            for match in expression.matches(in:text,range:NSRange(location:0,length:ns.length)) {
                if !ns.substring(with:match.range(at:1)).hasPrefix("#") { valid = false }
            }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { checkStyles(string); if !valid { parser.abortParsing() } }
}

enum ImageDocumentTools {
    static func renderSVG(_ input: URL, batch: FileDragBatch, engines: MediaEngineBundle) throws -> URL {
        let values = try input.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard input.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= TextFileTools.maxBytes else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf:input)
        guard data.count <= TextFileTools.maxBytes, let xml = String(data:data,encoding:.utf8),
              !xml.uppercased().contains("<!DOCTYPE"), !xml.uppercased().contains("<!ENTITY") else { throw CocoaError(.fileReadCorruptFile) }
        let validator = StaticSVGValidator(), parser = XMLParser(data:data)
        parser.shouldResolveExternalEntities = false; parser.delegate = validator
        guard parser.parse(), validator.valid else { throw CocoaError(.fileReadUnsupportedScheme) }
        let folder = input.deletingLastPathComponent().appendingPathComponent(".vorssaint-svg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        do {
            let snapshot = folder.appendingPathComponent("Input.svg"), output = folder.appendingPathComponent("Rendered.png")
            try data.write(to:snapshot,options:.withoutOverwriting)
            _ = try engines.run("svg-renderer",arguments:[snapshot.path,output.path],batch:batch,timeout:60)
            try ImageFileTools.validate([output]); return output
        } catch { try? FileManager.default.removeItem(at:folder); throw error }
    }

    /// Raster-to-SVG embeds the original rendered pixels; it is not tracing.
    static func convert(_ input: URL, to format: FileDragFormat, batch: FileDragBatch) throws -> URL {
        guard format == .svg || format == .docx else { throw CocoaError(.fileWriteUnsupportedScheme) }
        let image = try ImageFileTools.load(input)
        let output = FileDragFormat.uniqueOutputURL(for:input,format:format), staged = try MediaSupport.temporaryOutputURL(for:output)
        defer { MediaSupport.discardStagedOutput(staged) }
        let png = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(png,"public.png" as CFString,1,nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(writer,image,nil)
        guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
        guard !batch.isCancelled else { throw CancellationError() }
        if format == .svg {
            let xml = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(image.width)\" height=\"\(image.height)\" viewBox=\"0 0 \(image.width) \(image.height)\"><image width=\"\(image.width)\" height=\"\(image.height)\" href=\"data:image/png;base64,\((png as Data).base64EncodedString())\"/></svg>"
            try xml.write(to:staged,atomically:false,encoding:.utf8)
        } else {
            let package = staged.deletingLastPathComponent().appendingPathComponent("WordPackage"), word = package.appendingPathComponent("word")
            for folder in [word.appendingPathComponent("media"),word.appendingPathComponent("_rels"),package.appendingPathComponent("_rels")] { try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true) }
            try (png as Data).write(to:word.appendingPathComponent("media/image.png"))
            let scale = min(5_486_400.0/Double(image.width),8_229_600.0/Double(image.height))
            let w = Int(Double(image.width)*scale), h = Int(Double(image.height)*scale)
            let header = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            let document = header + "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><w:body><w:p><w:r><w:drawing><wp:inline><wp:extent cx=\"\(w)\" cy=\"\(h)\"/><wp:docPr id=\"1\" name=\"Image\"/><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic><pic:nvPicPr><pic:cNvPr id=\"1\" name=\"image.png\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"image1\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(w)\" cy=\"\(h)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p><w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"720\" w:right=\"720\" w:bottom=\"720\" w:left=\"720\"/></w:sectPr></w:body></w:document>"
            try document.write(to:word.appendingPathComponent("document.xml"),atomically:false,encoding:.utf8)
            let rel = header + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            try (rel+"<Relationship Id=\"image1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/image.png\"/></Relationships>").write(to:word.appendingPathComponent("_rels/document.xml.rels"),atomically:false,encoding:.utf8)
            try (rel+"<Relationship Id=\"document\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>").write(to:package.appendingPathComponent("_rels/.rels"),atomically:false,encoding:.utf8)
            try (header+"<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>").write(to:package.appendingPathComponent("[Content_Types].xml"),atomically:false,encoding:.utf8)
            let child = try batch.beginProcess(); defer { batch.endProcess(child) }
            let result = BoundedProcessRunner.run("/usr/bin/ditto",["-c","-k","--norsrc","--noextattr",package.path,staged.path],timeout:120,maxOutputBytes:16384,cancellation:child)
            guard result.status == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
        guard !batch.isCancelled else { throw CancellationError() }
        try MediaSupport.installStagedOutput(staged,at:output,replacingExisting:false); return output
    }
}
