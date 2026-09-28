// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import PDFKit

enum ImageFileToolTests {
    static func fixture(_ url: URL, red: Bool) throws {
        let context = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red ? CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1) : CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        let writer = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, context.makeImage()!, [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "Private source author"]] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
    }
    private static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width*4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = (y*image.width+x)*4
        return (0..<4).map { bytes[offset+$0] }
    }
    private static func finish(_ model: ImageWorkspaceModel) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while model.busy && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        return !model.busy
    }
    static func run(_ suite: TestSuite) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-image-tools-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let a = directory.appendingPathComponent("red.png"), b = directory.appendingPathComponent("blue.png")
            try fixture(a, red: true); try fixture(b, red: false)
            let bytesA = try Data(contentsOf: a), bytesB = try Data(contentsOf: b), source = try ImageFileTools.load(a)
            var edit = ImageFileEdit()
            edit.crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5); edit.width = 200
            let cropped = try ImageFileTools.render(source, edit: edit, tool: .crop)
            suite.expect(cropped.width == 200 && cropped.height == 160 && pixel(cropped, x: 100, y: 80)[0] > 240,
                         "Crop uses normalized source pixels and proportional exact resize")
            edit.lockAspect = false; edit.height = 100
            let stretched = try ImageFileTools.render(source, edit: edit, tool: .crop)
            suite.expect(stretched.width == 200 && stretched.height == 100, "Unlocked resize uses both exact dimensions")
            edit.width = 20000; edit.height = 20000
            suite.expect((try? ImageFileTools.render(source, edit: edit, tool: .crop)) == nil, "Image tools reject unsafe canvas allocations")
            edit = ImageFileEdit(); edit.crop.size.width = .nan
            suite.expect((try? ImageFileTools.render(source, edit: edit, tool: .crop)) == nil, "Malformed crop geometry is rejected before allocation")
            edit = ImageFileEdit(); edit.redactions = [ImageRedaction(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), style: .solid)]
            let redacted = try ImageFileTools.render(source, edit: edit, tool: .redact)
            suite.expect(pixel(redacted, x: 10, y: 10).prefix(3).allSatisfy { $0 == 0 }
                         && pixel(redacted, x: 90, y: 70)[0] > 240,
                         "Solid redaction flattens only the selected top-left area into exported pixels")
            let outputs = try ImageFileTools.save([a], tool: .redact, edit: edit, batch: FileDragBatch())
            let reopened = try ImageFileTools.load(outputs[0])
            let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(outputs[0] as CFURL, nil)!, 0, nil) as? [CFString: Any]
            suite.expect(pixel(reopened, x: 10, y: 10).prefix(3).allSatisfy { $0 == 0 }
                         && props?[kCGImagePropertyTIFFDictionary] == nil, "Redacted output contains flattened coverage and no copied source metadata")
            let second = try ImageFileTools.save([a], tool: .redact, edit: edit, batch: FileDragBatch())
            suite.expect(outputs != second && FileManager.default.fileExists(atPath: outputs[0].path), "Image tool output collisions preserve earlier copies")
            for style in [ImageRedactionStyle.blur, .pixelate] {
                edit.redactions[0].style = style
                suite.expect((try? ImageFileTools.render(source, edit: edit, tool: .redact)) != nil, "Redaction renders the selected \(style) coverage")
            }
            edit = ImageFileEdit(); edit.margin = 8; edit.corner = 0; edit.shadow = false
            let framed = try ImageFileTools.render(source, edit: edit, tool: .background)
            suite.expect(framed.width == 116 && framed.height == 96 && pixel(framed, x: 2, y: 2).prefix(3).allSatisfy { $0 > 240 },
                         "Background export keeps the original image inside the requested canvas margin")
            edit.width = 200; edit.height = 100; edit.columns = 2; edit.spacing = 0
            let collage = try ImageFileTools.collage([a,b], edit: edit, preview: false, batch: FileDragBatch())
            suite.expect(collage.width == 200 && collage.height == 100 && pixel(collage, x: 50, y: 50)[0] > 240
                         && pixel(collage, x: 150, y: 50)[2] > 240, "Collage places source images in input order without a full decoded-image array")
            edit.featured = true
            let featured = try ImageFileTools.collage([a,b], edit: edit, preview: false, batch: FileDragBatch())
            suite.expect(pixel(featured,x:110,y:50)[0] > 240 && pixel(featured,x:150,y:50)[2] > 240,"Featured collage gives the first image a larger region while retaining input order")
            var photo = ImageFileEdit(); photo.dehaze = 0.5; photo.clarity = 0.5; photo.grain = 0.3
            let adjusted = try ImageFileTools.render(source,edit:photo,tool:.edit)
            suite.expect(adjusted.width == source.width && adjusted.height == source.height && pixel(adjusted,x:50,y:40)[3] == 255,"Dehaze, clarity and grain render together without changing dimensions or opaque alpha")
            let cancelledPhoto = FileDragBatch(); cancelledPhoto.cancel()
            suite.expect((try? ImageFileTools.render(source,edit:photo,tool:.edit,batch:cancelledPhoto)) == nil,"CPU photo adjustment observes cancellation before processing rows")
            let pdf = try ImageFileTools.save([b,a], tool: .pdf, edit: edit, batch: FileDragBatch())[0]
            let document = try PDFTools.document(pdf)
            let p1 = directory.appendingPathComponent("pdf-first.png"), p2 = directory.appendingPathComponent("pdf-last.png")
            try PDFTools.writeImage(document.page(at: 0)!, to: p1, format: .png)
            try PDFTools.writeImage(document.page(at: 1)!, to: p2, format: .png)
            let first = try ImageFileTools.load(p1), last = try ImageFileTools.load(p2)
            suite.expect(document.pageCount == 2 && pixel(first, x: first.width/2, y: first.height/2)[2] > 240
                         && pixel(last, x: last.width/2, y: last.height/2)[0] > 240,
                         "Images-to-PDF saves one page per image in the user-selected order")
            let cancelled = FileDragBatch(); cancelled.cancel()
            suite.expect((try? ImageFileTools.save([a,b], tool: .pdf, edit: edit, batch: cancelled)) == nil,
                         "Cancelled image jobs do not publish a new output")
            edit = ImageFileEdit(); edit.format = .jpeg; edit.targetBytes = 1
            suite.expect((try? ImageFileTools.save([a], tool: .compress, edit: edit, batch: FileDragBatch())) == nil,
                         "An impossible target size fails rather than returning an oversized file")
            var published: [URL] = []
            let model = try ImageWorkspaceModel(inputs: [a], tool: .crop, available: { true }, publish: { published = $0 })
            model.change { $0.width = 50 }; model.undo()
            suite.expect(model.edit.width == 0 && model.canRedo, "Image workspace undo restores the prior export options")
            model.redo(); model.save()
            suite.expect(finish(model) && published.count == 1 && (try? ImageFileTools.load(published[0]))?.width == 50,
                         "Image workspace redo survives the actual asynchronous save and reopen path")
            model.undo()
            suite.expect(model.edit.width == 0, "Undo after redo returns to the original export configuration")
            model.cancel()
            let ordered = try ImageWorkspaceModel(inputs: [a,b], tool: .pdf, available: { true })
            ordered.moveInput(1, offset: -1); ordered.undo()
            suite.expect(ordered.inputs == [a,b] && ordered.canRedo, "Undo restores image document order")
            ordered.redo()
            suite.expect(ordered.inputs == [b,a], "Redo restores the user-selected image document order")
            ordered.cancel()
            var partial: [URL] = []
            let batchModel = try ImageWorkspaceModel(inputs: [a,b], tool: .crop, available: { true }, publish: { partial = $0 })
            try FileManager.default.removeItem(at: b)
            batchModel.save()
            suite.expect(finish(batchModel) && partial.count == 1 && batchModel.failures[b] != nil && batchModel.completed == 2,
                         "Batch exports publish successful copies and retain errors for each failed file")
            try bytesB.write(to: b)
            batchModel.save(retryFailures: true)
            suite.expect(finish(batchModel) && partial.count == 1 && batchModel.failures.isEmpty && partial[0].lastPathComponent.hasPrefix("blue"),
                         "Retry exports only the failed file after its input is restored")
            batchModel.cancel()
            var cancelledPublish = false
            let cancelledModel = try ImageWorkspaceModel(inputs: [a], tool: .crop, available: { true }, publish: { _ in cancelledPublish = true })
            cancelledModel.save(); cancelledModel.cancel()
            suite.expect(finish(cancelledModel) && !cancelledPublish && cancelledModel.message == nil,
                         "Cancelled asynchronous jobs cannot report successful completion")
            let link = directory.appendingPathComponent("link.png")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
            suite.expect((try? ImageFileTools.validate([link])) == nil, "Image tools reject symbolic-link inputs")
            let animated = directory.appendingPathComponent("animated.gif")
            let writer = CGImageDestinationCreateWithURL(animated as CFURL, "com.compuserve.gif" as CFString, 2, nil)!
            CGImageDestinationAddImage(writer, source, nil); CGImageDestinationAddImage(writer, source, nil)
            suite.expect(CGImageDestinationFinalize(writer) && (try? ImageFileTools.validate([animated])) == nil,
                         "Image tools reject animated inputs rather than silently flattening them")
            let disabled = try ImageWorkspaceModel(inputs: [a], tool: .crop, available: { false })
            disabled.change { $0.width = 10 }; disabled.save()
            suite.expect(disabled.edit.width == 0 && !disabled.busy, "Disabled image workspaces reject edits and exports")
            disabled.cancel()
            suite.expect(try Data(contentsOf: a) == bytesA && Data(contentsOf: b) == bytesB, "Image tools preserve both source files byte for byte")
            for language in AppLanguage.allCases {
                let strings = ImageFileToolStrings.localized(language)
                suite.expect(ImageFileToolStrings.Key.allCases.allSatisfy { !strings[$0].isEmpty }, "Image tool controls are localized for \(language)")
            }
        } catch { suite.expect(false, "Image file-tool fixtures: \(error)") }
    }
}
