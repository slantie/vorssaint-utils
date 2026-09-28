// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct FileMetadataSection: Equatable, Identifiable {
    enum Kind: Equatable { case file, track(Int), chapter(Int) }
    let kind: Kind
    var tags: [String: String]
    var id: String {
        switch kind { case .file: return "file"; case .track(let index): return "track-\(index)"; case .chapter(let index): return "chapter-\(index)" }
    }
}
struct FileMetadataSnapshot {
    var sections: [FileMetadataSection]
    let inspection: String
    var imageProperties: [String: Any]?
    var generatedChapterTracks: [Int] = []
}
enum FileMetadataTools {
    private static func valid(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard url.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 8_000_000_000 else { throw CocoaError(.fileReadTooLarge) }
    }
    static func read(_ url: URL, engines: MediaEngineBundle?, batch: FileDragBatch) throws -> FileMetadataSnapshot {
        try valid(url); guard !batch.isCancelled else { throw CancellationError() }
        if FileDragFormat.inputKind(for: url) == .image {
            try ImageFileTools.validate([url])
            guard let source = CGImageSourceCreateWithURL(url as CFURL,nil), let props = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
            let fields: [(String,CFString)] = [("title",kCGImagePropertyTIFFDocumentName),("artist",kCGImagePropertyTIFFArtist),("copyright",kCGImagePropertyTIFFCopyright),("description",kCGImagePropertyTIFFImageDescription)]
            let tags = Dictionary(uniqueKeysWithValues: fields.map { ($0.0,tiff[$0.1 as String].map { String(describing:$0) } ?? "") })
            let text = String(data:try PropertyListSerialization.data(fromPropertyList:props,format:.xml,options:0),encoding:.utf8) ?? ""
            return FileMetadataSnapshot(sections:[FileMetadataSection(kind:.file,tags:tags)],inspection:text,imageProperties:props)
        }
        guard let kind = FileDragFormat.inputKind(for:url), kind == .audio || kind == .video, let engines else { throw CocoaError(.fileReadUnsupportedScheme) }
        let data = try engines.run("ffprobe",arguments:["-v","error","-protocol_whitelist","file,pipe","-show_format","-show_streams","-show_chapters","-of","json",url.path],batch:batch,timeout:30,maxOutputBytes:1_048_576)
        guard let json = try JSONSerialization.jsonObject(with:data) as? [String:Any], let format = json["format"] as? [String:Any],
              let streams = json["streams"] as? [[String:Any]], streams.count <= 100 else { throw CocoaError(.fileReadCorruptFile) }
        let chapters = json["chapters"] as? [[String:Any]] ?? []
        guard chapters.count <= 10000 else { throw CocoaError(.fileReadTooLarge) }
        var sections = [FileMetadataSection(kind:.file,tags:format["tags"] as? [String:String] ?? [:])]
        // MOV/MP4 stores chapter titles twice: chapter records plus a generated
        // bin_data/text stream. Mapping that generated stream and chapters together
        // fails in the M4A muxer or duplicates the chapter track. Regenerate only that
        // stream from the retained chapter records; preserve every other stream.
        let generated = streams.enumerated().filter { _,stream in
            !chapters.isEmpty && stream["codec_type"] as? String == "data" && stream["codec_name"] as? String == "bin_data" && stream["codec_tag_string"] as? String == "text"
        }.map(\.offset)
        sections += streams.enumerated().filter { !generated.contains($0.offset) }.enumerated().map {
            FileMetadataSection(kind:.track($0.offset),tags:$0.element.element["tags"] as? [String:String] ?? [:])
        }
        sections += chapters.enumerated().map { FileMetadataSection(kind:.chapter($0.offset),tags:$0.element["tags"] as? [String:String] ?? [:]) }
        return FileMetadataSnapshot(sections:sections,inspection:String(data:data,encoding:.utf8) ?? "",generatedChapterTracks:generated)
    }
    static func save(_ url: URL, snapshot: FileMetadataSnapshot, remove: Bool, engines: MediaEngineBundle?, batch: FileDragBatch) throws -> URL {
        try valid(url); guard !batch.isCancelled else { throw CancellationError() }
        guard snapshot.sections.count <= 10101, snapshot.sections.allSatisfy({ $0.tags.count <= 1000 && $0.tags.allSatisfy { key,value in
            !key.isEmpty && key.utf8.count <= 256 && !key.contains("=") && !key.contains("\0") && value.utf8.count <= 65536 && !value.contains("\0")
        } }) else { throw CocoaError(.validationMissingMandatoryProperty) }
        let output = MediaSupport.uniqueOutputURL(for:url,suffix:remove ? "-metadata-removed" : "-metadata",fileExtension:url.pathExtension)
        let stage = try MediaSupport.temporaryOutputURL(for:output); defer { MediaSupport.discardStagedOutput(stage) }
        if let props = snapshot.imageProperties {
            try ImageFileTools.validate([url])
            guard let source = CGImageSourceCreateWithURL(url as CFURL,nil), let type = CGImageSourceGetType(source),
                  let destination = CGImageDestinationCreateWithURL(stage as CFURL,type,1,nil) else { throw CocoaError(.fileWriteUnsupportedScheme) }
            let image = try ImageFileTools.load(url)
            var properties = remove ? [:] : props
            if !remove {
                var tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String:Any] ?? [:]
                let tags = snapshot.sections.first?.tags ?? [:]
                for (key,property) in [("title",kCGImagePropertyTIFFDocumentName),("artist",kCGImagePropertyTIFFArtist),("copyright",kCGImagePropertyTIFFCopyright),("description",kCGImagePropertyTIFFImageDescription)] {
                    if let value = tags[key], !value.isEmpty { tiff[property as String] = value } else { tiff.removeValue(forKey:property as String) }
                }
                tiff[kCGImagePropertyTIFFOrientation as String] = 1
                properties[kCGImagePropertyTIFFDictionary as String] = tiff; properties[kCGImagePropertyOrientation as String] = 1
                properties[kCGImagePropertyPixelWidth as String] = image.width; properties[kCGImagePropertyPixelHeight as String] = image.height
            }
            CGImageDestinationAddImage(destination,image,properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            if !remove {
                let actual = try read(stage,engines:engines,batch:batch).sections[0].tags
                guard (snapshot.sections.first?.tags ?? [:]).allSatisfy({ $0.value.isEmpty || actual[$0.key] == $0.value }) else { throw CocoaError(.fileWriteUnsupportedScheme) }
            }
        } else {
            guard let engines else { throw CocoaError(.executableNotLoadable) }
            // Re-probe so a stale/forged snapshot cannot select nonexistent streams or chapters.
            let original = try read(url,engines:engines,batch:batch)
            guard snapshot.sections.map(\.id) == original.sections.map(\.id) else { throw CocoaError(.fileReadCorruptFile) }
            var args = ["-nostdin","-v","error","-n","-protocol_whitelist","file,pipe","-i",url.path,"-map","0","-map_chapters","0","-c","copy"]
            for index in original.generatedChapterTracks { args += ["-map","-0:\(index)"] }
            if remove {
                args += ["-map_metadata","-1","-map_metadata:s","-1"]
                for section in original.sections {
                    if case .chapter(let index) = section.kind {
                        args += ["-map_metadata:c:\(index)","-1"]
                        // MOV omits a chapter-text stream whose titles are all zero
                        // bytes, leaving a dangling QT chapter reference. A blank
                        // display title retains valid chapter timing without any
                        // source title or personal tag.
                        if !original.generatedChapterTracks.isEmpty { args += ["-metadata:c:\(index)","title= "] }
                    }
                }
            } else {
                for (section,prior) in zip(snapshot.sections,original.sections) {
                    let specifier: String
                    switch section.kind { case .file: specifier = "-metadata"; case .track(let index): specifier = "-metadata:s:\(index)"; case .chapter(let index): specifier = "-metadata:c:\(index)" }
                    for key in Set(prior.tags.keys).union(section.tags.keys).sorted() {
                        var value = section.tags[key] ?? ""
                        if case .chapter = section.kind, key == "title", value.isEmpty, !original.generatedChapterTracks.isEmpty { value = " " }
                        args += [specifier,key+"="+value]
                    }
                }
            }
            if ["mp4","mov","m4a","m4v"].contains(url.pathExtension.lowercased()) { args += ["-movflags","use_metadata_tags"] }
            args.append(stage.path)
            _ = try engines.run("ffmpeg",arguments:args,batch:batch)
            if !remove {
                let actual = try read(stage,engines:engines,batch:batch)
                for (section,prior) in zip(snapshot.sections,original.sections) {
                    guard let saved = actual.sections.first(where: { $0.id == section.id }) else { throw CocoaError(.fileWriteUnsupportedScheme) }
                    // Only changed fields must round-trip: muxer-generated technical tags may change.
                    for key in Set(prior.tags.keys).union(section.tags.keys) where section.tags[key] != prior.tags[key] {
                        let value = section.tags[key] ?? "", stored = saved.tags.first { $0.key.lowercased() == key.lowercased() }?.value ?? ""
                        let blankChapter: Bool
                        if case .chapter = section.kind { blankChapter = key == "title" && value.isEmpty && stored.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
                        else { blankChapter = false }
                        guard stored == value || blankChapter else { throw CocoaError(.fileWriteUnsupportedScheme) }
                    }
                }
            }
        }
        guard !batch.isCancelled else { throw CancellationError() }
        try MediaSupport.installStagedOutput(stage,at:output,replacingExisting:false); return output
    }
}
