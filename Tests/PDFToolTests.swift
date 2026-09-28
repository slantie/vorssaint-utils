// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreText
import Foundation
import ImageIO
import PDFKit

enum PDFToolTests {
    static func fixture(_ url: URL, labels: [String]) throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for (index, label) in labels.enumerated() {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
            context.setFillColor(CGColor(red: CGFloat(index + 1) / CGFloat(labels.count + 1), green: 0.4, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 20, y: 30, width: 160, height: 70))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica" as CFString, 18, nil),
                .foregroundColor: NSColor.black,
            ]
            context.textPosition = CGPoint(x: 20, y: 200)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attributes)), context)
            context.endPDFPage()
        }
        context.closePDF()
        try (data as Data).write(to: url, options: .withoutOverwriting)
    }

    static func run(_ suite: TestSuite) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-pdf-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let a = directory.appendingPathComponent("Three pages.pdf"), b = directory.appendingPathComponent("Two pages.pdf")
            try fixture(a, labels: ["ALPHA", "BETA", "GAMMA"])
            try fixture(b, labels: ["DELTA", "EPSILON"])
            let originalDoc = try PDFTools.document(a)
            originalDoc.page(at: 1)?.rotation = 90
            let annotation = PDFAnnotation(bounds: CGRect(x: 20, y: 30, width: 40, height: 30), forType: .square, withProperties: nil)
            annotation.color = .red
            originalDoc.page(at: 2)?.addAnnotation(annotation)
            originalDoc.documentAttributes = [PDFDocumentAttribute.titleAttribute: "Original title"]
            suite.expect(originalDoc.write(to: a), "PDF fixture stores its rotation and metadata")
            let originalA = try Data(contentsOf: a), originalB = try Data(contentsOf: b)
            var plan = try PDFTools.plan([a])
            let gamma = plan.pages[2].id
            plan.move(gamma, to: 0); plan.rotate(gamma); plan.duplicate(gamma)
            plan.remove(plan.pages[2].id)
            suite.expect(plan.pages.map(\.index) == [2, 2, 1] && Set(plan.pages.map(\.id)).count == 3,
                         "Organizing reorders, rotates, duplicates and removes distinct page instances")
            let organized = try PDFTools.save(plan, tool: .organize, batch: FileDragBatch())
            let result = try PDFTools.document(organized)
            suite.expect(result.pageCount == 3 && result.page(at: 0)?.string?.contains("GAMMA") == true
                         && result.page(at: 1)?.string?.contains("GAMMA") == true && result.page(at: 2)?.string?.contains("BETA") == true,
                         "The organized PDF has the chosen contents and order")
            suite.expect(result.page(at: 0)?.rotation == 90 && result.page(at: 2)?.rotation == 90,
                         "Export retains both existing and newly applied rotations")
            suite.expect(result.page(at: 0)?.annotations.count == 1 && result.page(at: 1)?.annotations.count == 1,
                         "Duplicated and reordered PDF pages retain their annotations")
            let previous = try Data(contentsOf: organized)
            let again = try PDFTools.save(plan, tool: .organize, batch: FileDragBatch())
            let preserved = try Data(contentsOf: organized)
            suite.expect(again != organized && preserved == previous,
                         "PDF save-copy never overwrites an existing organized document")
            let merged = try PDFTools.save(PDFTools.plan([b, a]), tool: .merge, batch: FileDragBatch())
            let mergedDoc = try PDFTools.document(merged)
            suite.expect(mergedDoc.pageCount == 5 && mergedDoc.page(at: 0)?.string?.contains("DELTA") == true
                         && mergedDoc.page(at: 2)?.string?.contains("ALPHA") == true,
                         "Merge follows the selected document order and preserves every page")
            let split = try PDFTools.save(PDFTools.plan([a]), tool: .split, batch: FileDragBatch())
            let files = try FileManager.default.contentsOfDirectory(at: split, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
            suite.expect(files.count == 3 && files.allSatisfy { (try? PDFTools.document($0).pageCount) == 1 },
                         "Split creates a new folder of readable single-page PDFs")
            suite.expect(try PDFTools.document(files[1]).page(at: 0)?.rotation == 90,
                         "Split preserves original page rotation")
            let txt = try FileDragConversionEngine.convert(a, to: .txt, batch: FileDragBatch())
            let text = try String(contentsOf: txt, encoding: .utf8)
            suite.expect(["ALPHA", "BETA", "GAMMA"].allSatisfy(text.contains), "PDF text export includes every page")
            let imageFolder = try FileDragConversionEngine.convert(a, to: .png, batch: FileDragBatch())
            let images = try FileManager.default.contentsOfDirectory(at: imageFolder, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
            suite.expect(images.count == 3, "PDF image export includes every page in a new folder")
            let rotatedImage = images.count > 1 ? CGImageSourceCreateWithURL(images[1] as CFURL, nil) : nil
            let properties = rotatedImage.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            suite.expect((properties?[kCGImagePropertyPixelWidth] as? Int) == 1250
                         && (properties?[kCGImagePropertyPixelHeight] as? Int) == 834
                         && (properties?[kCGImagePropertyDPIWidth] as? Double) == 300,
                         "PDF images render at 300 DPI with rotated dimensions")
            let docx = try FileDragConversionEngine.convert(a, to: .docx, batch: FileDragBatch())
            let word = BoundedProcessRunner.run("/usr/bin/unzip", ["-p", docx.path, "word/document.xml"], timeout: 10, maxOutputBytes: 1_000_000)
            let wordText = String(data: word.output, encoding: .utf8) ?? ""
            suite.expect(word.status == 0 && ["ALPHA", "BETA", "GAMMA"].allSatisfy(wordText.contains)
                         && (try? XMLDocument(data: word.output)) != nil,
                         "PDF Word export contains well-formed selectable text from every page")
            let imageOnly = directory.appendingPathComponent("Image only.pdf")
            try fixture(imageOnly, labels: [""])
            let imageWord = try FileDragConversionEngine.convert(imageOnly, to: .docx, batch: FileDragBatch())
            let embedded = BoundedProcessRunner.run("/usr/bin/unzip", ["-p", imageWord.path, "word/media/page1.png"], timeout: 10, maxOutputBytes: 1_000_000)
            suite.expect(embedded.status == 0 && CGImageSourceCreateWithData(embedded.output as CFData, nil) != nil,
                         "PDF Word export embeds a real page image when selectable text is absent")
            let jpeg = try FileDragConversionEngine.convert(imageOnly, to: .jpeg, batch: FileDragBatch())
            suite.expect(jpeg.pathExtension == "jpg" && CGImageSourceCreateWithURL(jpeg as CFURL, nil) != nil,
                         "A single-page PDF exports directly to a readable JPEG beside the source")
            let compressed = try PDFTools.save(PDFTools.plan([a]), tool: .compress, batch: FileDragBatch())
            suite.expect(try PDFTools.document(compressed).pageCount == 3 && PDFTools.document(compressed).string?.contains("ALPHA") == true,
                         "Native PDF compression preserves pages and selectable text")
            let meta = PDFMetadata(title: "Changed title", author: "Fixture author", subject: "Testing", keywords: "one, two")
            let edited = try PDFTools.save(PDFTools.plan([a]), tool: .metadata, metadata: meta, batch: FileDragBatch())
            suite.expect(try PDFTools.metadata(edited).title == "Changed title" && PDFTools.metadata(edited).author == "Fixture author",
                         "PDF metadata changes are saved in a separate document")
            let cleared = try PDFTools.save(PDFTools.plan([a]), tool: .metadata, batch: FileDragBatch())
            suite.expect(try PDFTools.metadata(cleared).title.isEmpty && PDFTools.metadata(a).title == "Original title",
                         "Clearing standard fields leaves original metadata untouched")
            let batch = FileDragBatch(); batch.cancel()
            suite.expect((try? PDFTools.save(plan, tool: .split, batch: batch)) == nil, "Cancelled PDF work creates no output")
            suite.expect((try? PDFTools.save(PDFEditPlan(pages: []), tool: .organize, batch: FileDragBatch())) == nil,
                         "Deleting every page cannot create an invalid empty PDF")
            let link = directory.appendingPathComponent("Link.pdf")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
            suite.expect((try? PDFTools.plan([link])) == nil && (try? FileDragConversionEngine.convert(link, to: .txt, batch: FileDragBatch())) == nil,
                         "PDF tools reject symbolic-link inputs")
            let protected = directory.appendingPathComponent("Protected.pdf")
            suite.expect(originalDoc.write(to: protected, withOptions: [.ownerPasswordOption: "fixture-owner", .userPasswordOption: "fixture-user"]),
                         "The password-protected PDF fixture can be written")
            suite.expect((try? PDFTools.plan([protected])) == nil, "Locked PDFs are rejected without bypassing document protection")
            suite.expect(try Data(contentsOf: a) == originalA && Data(contentsOf: b) == originalB,
                         "Every PDF operation preserves source bytes")
            var drop = FileDragDropSession<FileDragAction>(inputs: [a, b], formats: [.pdfTool(.merge), .pdfTool(.split)])
            drop.select(.pdfTool(.merge)); drop.releaseMouse()
            suite.expect(drop.prepare(formatAtDrop: .pdfTool(.merge)) && drop.takeDrop()?.inputs == [a, b]
                         && drop.takeDrop() == nil, "Shift–Option tool drops retain Finder order across release and are consumed once")
            for language in AppLanguage.allCases {
                let strings = PDFToolStrings.localized(language)
                suite.expect(PDFToolStrings.Key.allCases.allSatisfy { !strings[$0].isEmpty }
                             && strings[.pages].contains("%d"), "PDF tools are localized for \(language)")
            }
        } catch { suite.expect(false, "PDF production fixtures complete: \(error)") }
    }
}
