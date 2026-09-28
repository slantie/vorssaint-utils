// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreImage
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ImageFileTool: String, CaseIterable, Identifiable {
    case crop, redact, edit, background, compress, collage, pdf
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .crop: return "crop"
        case .redact: return "rectangle.fill"
        case .edit: return "slider.horizontal.3"
        case .background: return "photo.on.rectangle"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .collage: return "square.grid.2x2"
        case .pdf: return "doc.richtext"
        }
    }
    static func wheelTools(inputCount: Int) -> [Self] {
        inputCount > 1 ? [.compress, .crop, .collage, .pdf, .redact] : [.compress, .edit, .background, .crop, .redact]
    }
}

enum ImageRedactionStyle: String, CaseIterable { case solid, blur, pixelate }
struct ImageRedaction: Equatable, Identifiable {
    let id: UUID
    var rect: CGRect // Normalized top-left coordinates, independent of preview resolution.
    var style: ImageRedactionStyle
    init(rect: CGRect, style: ImageRedactionStyle, id: UUID = UUID()) { self.rect = rect; self.style = style; self.id = id }
}
struct ImageFileEdit: Equatable {
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var width = 0, height = 0 // Zero retains the cropped source dimensions.
    var lockAspect = true
    var redactions: [ImageRedaction] = []
    var exposure = 0.0, brightness = 0.0, contrast = 1.0, saturation = 1.0, sharpness = 0.0, noiseReduction = 0.0
    var dehaze = 0.0, clarity = 0.0, grain = 0.0
    var featured = false
    var margin = 40, corner = 12, shadow = true
    var background = MediaImageBackground.white
    var backgroundURL: URL?
    var backgroundBlur = 0.0
    var columns = 2, spacing = 16
    var format = MediaImageFormat.png
    var quality = 0.85
    var targetBytes: Int64 = 0
}

enum ImageFileTools {
    static let maxInputs = 200
    private static let ci = CIContext(options: [.cacheIntermediates: false])
    static func validate(_ urls: [URL]) throws {
        guard !urls.isEmpty, urls.count <= maxInputs else { throw CocoaError(.fileReadTooLarge) }
        for url in urls {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard url.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) == 1,
                  let size = MediaSupport.imageDisplaySize(at: url), MediaSupport.imageRenderSizeIsSafe(size) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }
    static func load(_ url: URL, preview: Bool = false) throws -> CGImage {
        try validate([url])
        guard let size = MediaSupport.imageDisplaySize(at: url),
              let image = MediaSupport.imageThumbnail(at: url, maxPixel: preview ? 1200 : Int(max(size.width, size.height))) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }
    static func normalized(_ rect: CGRect) throws -> CGRect {
        guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite), rect.width > 0, rect.height > 0 else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        let bounded = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !bounded.isNull, bounded.width > 0, bounded.height > 0 else { throw CocoaError(.validationMissingMandatoryProperty) }
        return bounded
    }
    private static func context(_ size: CGSize) throws -> CGContext {
        guard MediaSupport.imageRenderSizeIsSafe(size), let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileReadTooLarge)
        }
        context.interpolationQuality = .high
        return context
    }
    /// Atmospheric-scattering correction with a bounded thumbnail estimate of
    /// airlight. Work is linear in the pixel count; alpha is retained.
    private static func dehaze(_ image: CGImage, strength: Double, batch: FileDragBatch?) throws -> CGImage {
        let estimate = try context(CGSize(width:64,height:64))
        estimate.draw(image,in:CGRect(x:0,y:0,width:64,height:64))
        let samples = estimate.data!.assumingMemoryBound(to:UInt8.self)
        var air = [Double](repeating:0.8,count:3), brightest = -1.0
        for index in 0..<4096 {
            let p = index/64*estimate.bytesPerRow + index%64*4, alpha = Double(samples[p+3])/255
            guard alpha > 0.5 else { continue }
            let rgb = (0..<3).map { Double(samples[p+$0])/255/alpha }
            let dark = rgb.min()!
            if dark > brightest { brightest = dark; air = rgb.map { max(0.3,$0) } }
        }
        let canvas = try context(CGSize(width:image.width,height:image.height))
        canvas.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        let pixels = canvas.data!.assumingMemoryBound(to:UInt8.self)
        for y in 0..<image.height {
            if y % 64 == 0, batch?.isCancelled == true { throw CancellationError() }
            for x in 0..<image.width {
            let p = y*canvas.bytesPerRow+x*4, alpha = Double(pixels[p+3])/255
            if alpha <= 0 { continue }
            let r = Double(pixels[p])/255/alpha, g = Double(pixels[p+1])/255/alpha, b = Double(pixels[p+2])/255/alpha
            let transmission = max(0.15,1-0.95*strength*min(r/air[0],g/air[1],b/air[2]))
            pixels[p] = UInt8((min(1,max(0,(r-air[0])/transmission+air[0]))*alpha*255).rounded())
            pixels[p+1] = UInt8((min(1,max(0,(g-air[1])/transmission+air[1]))*alpha*255).rounded())
            pixels[p+2] = UInt8((min(1,max(0,(b-air[2])/transmission+air[2]))*alpha*255).rounded())
        } }
        guard let result = canvas.makeImage() else { throw CocoaError(.fileWriteUnknown) }; return result
    }
    private static func filtered(_ image: CGImage, _ name: String, _ parameters: [String: Any]) throws -> CGImage {
        let input = CIImage(cgImage: image)
        var parameters = parameters; parameters[kCIInputImageKey] = input.clampedToExtent()
        guard let filter = CIFilter(name: name, parameters: parameters), let output = filter.outputImage,
              let result = ci.createCGImage(output.cropped(to: input.extent), from: input.extent) else { throw CocoaError(.fileReadUnknown) }
        return result
    }
    static func render(_ source: CGImage, edit: ImageFileEdit, tool: ImageFileTool, preview: Bool = false, batch: FileDragBatch? = nil) throws -> CGImage {
        var image = source
        if tool == .edit {
            guard [edit.exposure, edit.brightness, edit.contrast, edit.saturation, edit.sharpness, edit.noiseReduction, edit.dehaze, edit.clarity, edit.grain].allSatisfy(\.isFinite),
                  (-3...3).contains(edit.exposure), (-1...1).contains(edit.brightness), (0...3).contains(edit.contrast),
                  (0...3).contains(edit.saturation), (0...2).contains(edit.sharpness), (0...0.1).contains(edit.noiseReduction), (0...1).contains(edit.dehaze), (0...1).contains(edit.clarity), (0...1).contains(edit.grain) else { throw CocoaError(.validationMissingMandatoryProperty) }
            if edit.dehaze > 0 { image = try dehaze(image, strength: edit.dehaze, batch: batch) }
            image = try filtered(image, "CIExposureAdjust", [kCIInputEVKey: edit.exposure])
            image = try filtered(image, "CIColorControls", [kCIInputBrightnessKey: edit.brightness, kCIInputContrastKey: edit.contrast, kCIInputSaturationKey: edit.saturation])
            if edit.noiseReduction > 0 { image = try filtered(image, "CINoiseReduction", ["inputNoiseLevel": edit.noiseReduction, "inputSharpness": 0]) }
            if edit.sharpness > 0 { image = try filtered(image, "CISharpenLuminance", [kCIInputSharpnessKey: edit.sharpness]) }
            if edit.clarity > 0 { image = try filtered(image, "CIUnsharpMask", [kCIInputRadiusKey: 12, kCIInputIntensityKey: edit.clarity]) }
            if edit.grain > 0 {
                let input = CIImage(cgImage:image)
                guard let noise = CIFilter(name:"CIRandomGenerator")?.outputImage,
                      let gray = CIFilter(name:"CIColorControls",parameters:[kCIInputImageKey:noise,kCIInputSaturationKey:0,kCIInputContrastKey:edit.grain*0.4])?.outputImage,
                      let mixed = CIFilter(name:"CIOverlayBlendMode",parameters:[kCIInputImageKey:gray,kCIInputBackgroundImageKey:input])?.outputImage,
                      let result = ci.createCGImage(mixed.cropped(to:input.extent),from:input.extent) else { throw CocoaError(.fileWriteUnknown) }
                image = result
            }
        }
        if tool == .redact {
            guard edit.redactions.count <= 200 else { throw CocoaError(.fileReadTooLarge) }
            let canvas = try context(CGSize(width: image.width, height: image.height))
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            canvas.draw(image, in: bounds)
            for redaction in edit.redactions {
                let r = try normalized(redaction.rect)
                let area = CGRect(x: floor(r.minX * bounds.width), y: floor((1 - r.maxY) * bounds.height),
                    width: ceil(r.width * bounds.width), height: ceil(r.height * bounds.height)).intersection(bounds)
                canvas.saveGState(); canvas.clip(to: area)
                switch redaction.style {
                case .solid: canvas.setFillColor(CGColor(gray: 0, alpha: 1)); canvas.fill(area)
                case .blur: canvas.draw(try filtered(image, "CIGaussianBlur", [kCIInputRadiusKey: max(8, bounds.width / 50)]), in: bounds)
                case .pixelate: canvas.draw(try filtered(image, "CIPixellate", [kCIInputScaleKey: max(10, bounds.width / 40)]), in: bounds)
                }
                canvas.restoreGState()
            }
            guard let result = canvas.makeImage() else { throw CocoaError(.fileWriteUnknown) }; image = result
        }
        if tool == .crop {
            let r = try normalized(edit.crop)
            let rect = CGRect(x: floor(r.minX * CGFloat(image.width)), y: floor(r.minY * CGFloat(image.height)),
                width: max(1, floor(r.width * CGFloat(image.width))), height: max(1, floor(r.height * CGFloat(image.height))))
            guard let result = image.cropping(to: rect) else { throw CocoaError(.fileReadUnknown) }; image = result
        }
        if tool == .crop || tool == .compress {
            guard edit.width >= 0, edit.height >= 0, edit.width <= 20000, edit.height <= 20000 else { throw CocoaError(.fileReadTooLarge) }
            let sourceSize = CGSize(width: image.width, height: image.height)
            var size = sourceSize
            if edit.width > 0 { size.width = CGFloat(edit.width); size.height = edit.lockAspect ? round(sourceSize.height * size.width / sourceSize.width) : CGFloat(edit.height > 0 ? edit.height : image.height) }
            else if edit.height > 0 { size.height = CGFloat(edit.height); size.width = round(sourceSize.width * size.height / sourceSize.height) }
            guard MediaSupport.imageRenderSizeIsSafe(size) else { throw CocoaError(.fileReadTooLarge) }
            if preview { let scale = min(1, 1200 / max(size.width, size.height)); size = CGSize(width: max(1, round(size.width * scale)), height: max(1, round(size.height * scale))) }
            let canvas = try context(size); canvas.draw(image, in: CGRect(origin: .zero, size: size))
            guard let result = canvas.makeImage() else { throw CocoaError(.fileWriteUnknown) }; image = result
        }
        if tool == .background {
            guard (0...2000).contains(edit.margin), (0...1000).contains(edit.corner), edit.backgroundBlur.isFinite, (0...100).contains(edit.backgroundBlur) else { throw CocoaError(.validationMissingMandatoryProperty) }
            let ratio = preview && edit.width > 0 ? min(1, CGFloat(source.width) / CGFloat(edit.width)) : 1
            let margin = CGFloat(edit.margin) * ratio
            let size = CGSize(width: CGFloat(image.width) + 2 * margin, height: CGFloat(image.height) + 2 * margin)
            let canvas = try context(CGSize(width: ceil(size.width), height: ceil(size.height)))
            try drawBackground(edit, in: canvas, bounds: CGRect(origin: .zero, size: size), preview: preview)
            let rect = CGRect(x: margin, y: margin, width: CGFloat(image.width), height: CGFloat(image.height))
            let rounded = CGPath(roundedRect: rect, cornerWidth: CGFloat(edit.corner) * ratio, cornerHeight: CGFloat(edit.corner) * ratio, transform: nil)
            if edit.shadow { canvas.saveGState(); canvas.setShadow(offset: CGSize(width: 0, height: -4 * ratio), blur: 12 * ratio, color: CGColor(gray: 0, alpha: 0.35)); canvas.addPath(rounded); canvas.setFillColor(CGColor(gray: 0, alpha: 1)); canvas.fillPath(); canvas.restoreGState() }
            canvas.addPath(rounded); canvas.clip(); canvas.draw(image, in: rect)
            guard let result = canvas.makeImage() else { throw CocoaError(.fileWriteUnknown) }; image = result
        }
        return image
    }
    private static func drawBackground(_ edit: ImageFileEdit, in canvas: CGContext, bounds: CGRect, preview: Bool) throws {
        if edit.background != .transparent { canvas.setFillColor(CGColor(gray: edit.background == .white ? 1 : 0, alpha: 1)); canvas.fill(bounds) }
        if let url = edit.backgroundURL {
            var image = try load(url, preview: preview)
            if edit.backgroundBlur > 0 { image = try filtered(image, "CIGaussianBlur", [kCIInputRadiusKey: edit.backgroundBlur]) }
            let scale = max(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            canvas.saveGState(); canvas.clip(to: bounds); canvas.draw(image, in: CGRect(x: bounds.midX-size.width/2, y: bounds.midY-size.height/2, width: size.width, height: size.height)); canvas.restoreGState()
        }
    }
    static func collage(_ inputs: [URL], edit: ImageFileEdit, preview: Bool, batch: FileDragBatch) throws -> CGImage {
        try validate(inputs)
        guard inputs.count > 1, (1...20).contains(edit.columns), (0...500).contains(edit.spacing), (0...1000).contains(edit.corner) else { throw CocoaError(.validationMissingMandatoryProperty) }
        var size = CGSize(width: edit.width > 0 ? edit.width : 1600, height: edit.height > 0 ? edit.height : 1200)
        guard MediaSupport.imageRenderSizeIsSafe(size) else { throw CocoaError(.fileReadTooLarge) }
        let ratio = preview ? min(1, 1200 / max(size.width, size.height)) : 1
        size = CGSize(width: round(size.width * ratio), height: round(size.height * ratio))
        let canvas = try context(size); try drawBackground(edit, in: canvas, bounds: CGRect(origin: .zero, size: size), preview: preview)
        let columns = min(inputs.count, edit.columns), rows = Int(ceil(Double(inputs.count) / Double(columns)))
        let gap = CGFloat(edit.spacing) * ratio
        let cell = CGSize(width: (size.width - gap * CGFloat(columns + 1)) / CGFloat(columns), height: (size.height - gap * CGFloat(rows + 1)) / CGFloat(rows))
        guard cell.width >= 1, cell.height >= 1 else { throw CocoaError(.validationMissingMandatoryProperty) }
        for (index, url) in inputs.enumerated() {
            guard !batch.isCancelled else { throw CancellationError() }
            let image = try load(url, preview: preview)
            var rect = CGRect(x: gap + CGFloat(index % columns) * (cell.width + gap), y: size.height - gap - CGFloat(index / columns + 1) * (cell.height + gap) + gap, width: cell.width, height: cell.height)
            if edit.featured {
                let leadWidth = (size.width-gap*3)*0.6
                if index == 0 { rect = CGRect(x:gap,y:gap,width:leadWidth,height:size.height-gap*2) }
                else {
                    let sideColumns = min(inputs.count-1,max(1,columns-1)), sideRows = Int(ceil(Double(inputs.count-1)/Double(sideColumns)))
                    let sideWidth = (size.width-leadWidth-gap*CGFloat(sideColumns+2))/CGFloat(sideColumns)
                    let sideHeight = (size.height-gap*CGFloat(sideRows+1))/CGFloat(sideRows)
                    rect = CGRect(x:leadWidth+gap*2+CGFloat((index-1)%sideColumns)*(sideWidth+gap),y:size.height-gap-CGFloat((index-1)/sideColumns+1)*(sideHeight+gap)+gap,width:sideWidth,height:sideHeight)
                }
                guard rect.width >= 1, rect.height >= 1 else { throw CocoaError(.validationMissingMandatoryProperty) }
            }
            canvas.saveGState(); canvas.addPath(CGPath(roundedRect: rect, cornerWidth: CGFloat(edit.corner) * ratio, cornerHeight: CGFloat(edit.corner) * ratio, transform: nil)); canvas.clip()
            let scale = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
            let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            canvas.draw(image, in: CGRect(x: rect.midX-drawn.width/2, y: rect.midY-drawn.height/2, width: drawn.width, height: drawn.height)); canvas.restoreGState()
        }
        guard let image = canvas.makeImage() else { throw CocoaError(.fileWriteUnknown) }; return image
    }
    private static func encode(_ image: CGImage, format: MediaImageFormat, quality: Double) throws -> Data {
        let data = NSMutableData()
        if format == .pdf {
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
            context.beginPDFPage(nil); context.draw(image, in: box); context.endPDFPage(); context.closePDF()
        } else {
            guard let writer = CGImageDestinationCreateWithData(data, (UTType(filenameExtension: format.fileExtension)?.identifier ?? "public.png") as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
            // Rendered pixels only: never carry source metadata or covered pixels into an export.
            var encodedImage = image
            if format == .jpeg {
                let canvas = try context(CGSize(width:image.width,height:image.height))
                let bounds = CGRect(x:0,y:0,width:image.width,height:image.height)
                canvas.setFillColor(CGColor(gray:1,alpha:1)); canvas.fill(bounds); canvas.draw(image,in:bounds)
                guard let flattened = canvas.makeImage() else { throw CocoaError(.fileWriteUnknown) }; encodedImage = flattened
            }
            CGImageDestinationAddImage(writer, encodedImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
        }
        return data as Data
    }
    static func save(_ inputs: [URL], tool: ImageFileTool, edit: ImageFileEdit, batch: FileDragBatch,
                     progress: (Int, Int) -> Void = { _, _ in }) throws -> [URL] {
        try validate(inputs)
        guard edit.quality.isFinite, (0...1).contains(edit.quality), edit.targetBytes >= 0 else { throw CocoaError(.validationMissingMandatoryProperty) }
        if tool == .pdf {
            let output = MediaSupport.uniqueOutputURL(for: inputs[0], suffix: "-images", fileExtension: "pdf")
            let staged = try MediaSupport.temporaryOutputURL(for: output); defer { MediaSupport.discardStagedOutput(staged) }
            guard let consumer = CGDataConsumer(url: staged as CFURL), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw CocoaError(.fileWriteUnknown) }
            for (index, url) in inputs.enumerated() {
                guard !batch.isCancelled else { context.closePDF(); throw CancellationError() }
                let image = try load(url)
                let box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                context.beginPDFPage([kCGPDFContextMediaBox as String: withUnsafeBytes(of: box) { Data($0) }] as CFDictionary)
                context.draw(image, in: box); context.endPDFPage(); progress(index + 1, inputs.count)
            }
            context.closePDF(); guard !batch.isCancelled else { throw CancellationError() }
            try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false); return [output]
        }
        let jobs = tool == .collage ? [inputs[0]] : inputs
        var outputs: [URL] = []
        for (index, input) in jobs.enumerated() {
            guard !batch.isCancelled else { throw CancellationError() }
            let image = tool == .collage ? try collage(inputs, edit: edit, preview: false, batch: batch) : try render(load(input), edit: edit, tool: tool, batch: batch)
            var data = try encode(image, format: edit.format, quality: edit.quality)
            if tool == .compress && edit.targetBytes > 0 && data.count > edit.targetBytes {
                guard edit.format == .jpeg || edit.format == .heic else { throw NSError(domain:"ImageFileTools",code:1,userInfo:[NSLocalizedDescriptionKey:ImageFileToolStrings.localized(L10n.shared.language)[.targetSmall]]) }
                var low = 0.0, high = edit.quality, candidate: Data?
                for _ in 0..<8 {
                    guard !batch.isCancelled else { throw CancellationError() }
                    let quality = (low + high) / 2, encoded = try encode(image, format: edit.format, quality: quality)
                    if encoded.count <= edit.targetBytes { candidate = encoded; low = quality } else { high = quality }
                }
                guard let candidate else { throw NSError(domain:"ImageFileTools",code:1,userInfo:[NSLocalizedDescriptionKey:ImageFileToolStrings.localized(L10n.shared.language)[.targetSmall]]) }; data = candidate
            }
            let output = MediaSupport.uniqueOutputURL(for: input, suffix: "-" + tool.rawValue, fileExtension: edit.format.fileExtension)
            let staged = try MediaSupport.temporaryOutputURL(for: output); defer { MediaSupport.discardStagedOutput(staged) }
            try data.write(to: staged, options: .withoutOverwriting)
            guard !batch.isCancelled else { throw CancellationError() }
            try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false)
            outputs.append(output); progress(index + 1, jobs.count)
        }
        return outputs
    }
}
