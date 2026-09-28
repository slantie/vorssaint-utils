// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation
import ImageIO
import AppKit

enum FileMetadataToolTests {
    static func run(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = FileMetadataStrings.localized(language)
            suite.expect(FileMetadataStrings.Key.allCases.allSatisfy { !strings[$0].isEmpty },"File/track/chapter metadata controls cover \(language)")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-metadata-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            defer { try? FileManager.default.removeItem(at:folder) }
            let image = folder.appendingPathComponent("photo.jpg")
            let context = CGContext(data:nil,width:32,height:24,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray:0.5,alpha:1)); context.fill(CGRect(x:0,y:0,width:32,height:24))
            let writer = CGImageDestinationCreateWithURL(image as CFURL,"public.jpeg" as CFString,1,nil)!
            CGImageDestinationAddImage(writer,context.makeImage()!,[kCGImagePropertyTIFFDictionary:[kCGImagePropertyTIFFArtist:"Original Artist",kCGImagePropertyTIFFDocumentName:"Original Title"],kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:12.3,kCGImagePropertyGPSLatitudeRef:"N",kCGImagePropertyGPSLongitude:45.6,kCGImagePropertyGPSLongitudeRef:"E"]] as CFDictionary)
            guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
            let original = try Data(contentsOf:image)
            var snapshot = try FileMetadataTools.read(image,engines:nil,batch:FileDragBatch())
            suite.expect(snapshot.sections[0].tags["artist"] == "Original Artist" && snapshot.inspection.contains("GPS"),"Image metadata inspection includes descriptive fields and location dictionaries")
            snapshot.sections[0].tags["title"] = "Changed Title"; snapshot.sections[0].tags["artist"] = "New Artist"
            let edited = try FileMetadataTools.save(image,snapshot:snapshot,remove:false,engines:nil,batch:FileDragBatch())
            let reopened = try FileMetadataTools.read(edited,engines:nil,batch:FileDragBatch())
            suite.expect(reopened.sections[0].tags["title"] == "Changed Title" && reopened.sections[0].tags["artist"] == "New Artist","Image metadata edits round trip through ImageIO")
            let stripped = try FileMetadataTools.save(image,snapshot:snapshot,remove:true,engines:nil,batch:FileDragBatch())
            let clean = try FileMetadataTools.read(stripped,engines:nil,batch:FileDragBatch())
            suite.expect(clean.sections[0].tags.values.allSatisfy(\.isEmpty) && clean.imageProperties?[kCGImagePropertyGPSDictionary as String] == nil,"Image metadata removal drops descriptive tags and GPS without exporting source dictionaries")
            suite.expect(try Data(contentsOf:image) == original,"Image metadata editing/removal preserves original bytes")
            let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/media-engines/runtime")
            guard let engines = MediaEngineBundle(root:root) else { print("SKIP: AV metadata fixtures need staged engines."); return }
            let audio = folder.appendingPathComponent("audio.m4a"), chapterData = folder.appendingPathComponent("chapters.txt")
            try ";FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=1000\ntitle=First Chapter\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=1000\nEND=2000\ntitle=Second Chapter\n".write(to:chapterData,atomically:false,encoding:.utf8)
            _ = try engines.run("ffmpeg",arguments:["-nostdin","-v","error","-n","-f","ffmetadata","-i",chapterData.path,"-filter_complex","sine=frequency=440:duration=2[a]","-map","[a]","-map_chapters","0","-c:a","aac","-metadata","title=File Title","-metadata","artist=File Artist","-metadata:s:a:0","language=eng",audio.path],batch:FileDragBatch())
            let originalAudio = try Data(contentsOf:audio)
            var av = try FileMetadataTools.read(audio,engines:engines,batch:FileDragBatch())
            suite.expect(av.sections.contains { if case .chapter = $0.kind { return true }; return false },"Metadata inspector exposes chapter tags alongside file and track tags")
            av.sections[0].tags["title"] = "Revised File"
            for index in av.sections.indices {
                if case .track(0) = av.sections[index].kind { av.sections[index].tags["language"] = "fra" }
                if case .chapter(0) = av.sections[index].kind { av.sections[index].tags["title"] = "Revised Chapter" }
            }
            let saved = try FileMetadataTools.save(audio,snapshot:av,remove:false,engines:engines,batch:FileDragBatch())
            let actual = try FileMetadataTools.read(saved,engines:engines,batch:FileDragBatch())
            suite.expect(actual.sections.first?.tags["title"] == "Revised File" && actual.sections.first { $0.kind == .track(0) }?.tags["language"] == "fra" && actual.sections.first { $0.kind == .chapter(0) }?.tags["title"] == "Revised Chapter","File/track/chapter edits survive an actual container remux")
            let removed = try FileMetadataTools.save(audio,snapshot:av,remove:true,engines:engines,batch:FileDragBatch())
            let rawProbe = BoundedProcessRunner.run(engines.root.appendingPathComponent("bin/ffprobe").path,["-v","error","-show_chapters","-of","json",removed.path],timeout:30,maxOutputBytes:16384)
            suite.expect((try? JSONSerialization.jsonObject(with:rawProbe.output)) != nil,"Removed metadata file has a valid chapter table without reader errors: \(String(data:rawProbe.output,encoding:.utf8) ?? "")")
            let removedInfo = try FileMetadataTools.read(removed,engines:engines,batch:FileDragBatch())
            suite.expect(!removedInfo.sections.contains { $0.tags["artist"] == "File Artist" || $0.tags["title"] == "File Title" || $0.tags["title"] == "First Chapter" },"AV removal drops personal file and chapter tags")
            suite.expect(try abs(AVFileTools.info(removed,engines:engines,batch:FileDragBatch()).duration-2) < 0.1 && Data(contentsOf:audio) == originalAudio,"Metadata remux preserves duration and original bytes")
            let cancel = FileDragBatch(); cancel.cancel()
            suite.expect((try? FileMetadataTools.save(audio,snapshot:av,remove:false,engines:engines,batch:cancel)) == nil,"Cancelled metadata edit cannot publish")
        } catch { suite.expect(false,"Metadata fixtures: \(error)") }
    }
}
