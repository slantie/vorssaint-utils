// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import PDFKit
import Darwin
import SystemArchive

enum FileDocumentConversionTests {
    private static func archive(_ url: URL, names: [String], link: Bool = false) throws {
        guard let writer = archive_write_new() else { throw CocoaError(.fileWriteUnknown) }; defer { archive_write_free(writer) }
        guard archive_write_set_format_pax_restricted(writer) == ARCHIVE_OK, archive_write_open_filename(writer, url.path) == ARCHIVE_OK else { throw CocoaError(.fileWriteUnknown) }
        for name in names {
            let entry = archive_entry_new()!; defer { archive_entry_free(entry) }
            let bytes = Data(("Payload: " + name).utf8)
            archive_entry_set_pathname(entry, name); archive_entry_set_perm(entry, 0o644)
            archive_entry_set_filetype(entry, UInt32(link ? S_IFLNK : S_IFREG))
            if link { archive_entry_set_symlink(entry, "../outside") }
            archive_entry_set_size(entry, link ? 0 : Int64(bytes.count))
            guard archive_write_header(writer, entry) == ARCHIVE_OK else { throw CocoaError(.fileWriteUnknown) }
            if !link { guard bytes.withUnsafeBytes({ archive_write_data(writer, $0.baseAddress, $0.count) }) == bytes.count else { throw CocoaError(.fileWriteUnknown) } }
        }
        guard archive_write_close(writer) == ARCHIVE_OK else { throw CocoaError(.fileWriteUnknown) }
    }
    static func run(_ suite: TestSuite) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-file-conversions-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let input = directory.appendingPathComponent("notes.txt")
            let text = (0..<120).map { "Line \($0): Native local conversion, café 日本語." }.joined(separator: "\n")
            try text.write(to: input, atomically: false, encoding: .utf8)
            let original = try Data(contentsOf: input)
            let pdf = try FileDragConversionEngine.convert(input, to: .pdf, batch: FileDragBatch())
            let document = try PDFTools.document(pdf)
            suite.expect(document.pageCount > 1 && document.page(at: 0)?.string?.contains("Line 0") == true
                         && document.page(at: document.pageCount-1)?.string?.contains("Line 119") == true,
                         "UTF-8 text converts to a paginated PDF with selectable first and final content")
            let images = try FileDragConversionEngine.convert(input, to: .png, batch: FileDragBatch())
            suite.expect(try FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil).count == document.pageCount,
                         "Text-to-images saves every page in a new folder beside the input")
            let subtitles = directory.appendingPathComponent("captions.srt")
            let source = "1\r\n00:00:01,250 --> 00:00:02,750\r\nHello café\r\nSecond line\r\n\r\n2\r\n00:00:05,000 --> 00:00:06,000\r\nWorld\r\n"
            try source.write(to: subtitles, atomically: false, encoding: .utf8)
            let vtt = try FileDragConversionEngine.convert(subtitles, to: .vtt, batch: FileDragBatch())
            let srtCues = try TextFileTools.cues(TextFileTools.read(subtitles)), vttCues = try TextFileTools.cues(TextFileTools.read(vtt))
            suite.expect(srtCues == vttCues && vttCues[0].start == 1250 && vttCues[0].end == 2750 && vttCues[0].text.contains("Second line"),
                         "SRT-to-VTT retains millisecond timings, Unicode and multiline cue content")
            let back = try FileDragConversionEngine.convert(vtt, to: .srt, batch: FileDragBatch())
            suite.expect(try TextFileTools.cues(TextFileTools.read(back)) == srtCues, "VTT-to-SRT round trips cue content and timings")
            let txt = try FileDragConversionEngine.convert(subtitles, to: .txt, batch: FileDragBatch())
            suite.expect(try TextFileTools.read(txt).contains("Hello café\nSecond line") && !TextFileTools.read(txt).contains("-->"),
                         "Subtitle-to-text exports cue content without timestamp lines")
            let generated = try FileDragConversionEngine.convert(input, to: .srt, batch: FileDragBatch())
            let generatedCues = try TextFileTools.cues(TextFileTools.read(generated))
            suite.expect(generatedCues.count == 120 && generatedCues[0].start == 0 && generatedCues[0].end == 3000,
                         "Plain text subtitle generation uses the documented three-second duration per nonempty line")
            let timed = try TextFileTools.convert(input,to:"vtt",batch:FileDragBatch(),timing:SubtitleTiming(duration:1.5,offset:2,gap:0.25))
            let timedCues = try TextFileTools.cues(TextFileTools.read(timed))
            suite.expect(timedCues[0].start == 2000 && timedCues[0].end == 3500 && timedCues[1].start == 3750,"Plain-text timing controls preserve offset, duration and gaps in exported cue timestamps")
            suite.expect((try? TextFileTools.convert(input,to:"srt",batch:FileDragBatch(),timing:SubtitleTiming(duration:.nan))) == nil,"Malformed plain-text duration cannot publish a subtitle file")
            for language in AppLanguage.allCases { suite.expect(FileToolExtraStrings.Key.allCases.allSatisfy { !FileToolExtraStrings.localized(language)[$0].isEmpty },"Additional file-tool controls cover \(language)") }
            suite.expect((try? TextFileTools.cues("1\n00:60:00,000 --> 00:60:01,000\nBad")) == nil
                         && (try? TextFileTools.cues("1\n00:00:05,000 --> 00:00:04,000\nBad")) == nil,
                         "Malformed and reversed subtitle timings are rejected")
            let malformed = directory.appendingPathComponent("bad.txt"); try Data([0xff,0xfe,0x00]).write(to: malformed)
            suite.expect((try? FileDragConversionEngine.convert(malformed, to: .pdf, batch: FileDragBatch())) == nil, "Text conversion rejects non-UTF-8 input")
            suite.expect(try Data(contentsOf: input) == original, "Text conversion preserves original bytes")

            let image = directory.appendingPathComponent("source.png"); try ImageFileToolTests.fixture(image,red:true)
            let imageBytes = try Data(contentsOf:image)
            let word = try FileDragConversionEngine.convert(image,to:.docx,batch:FileDragBatch())
            let wordTree = directory.appendingPathComponent("word-content")
            let wordUnzip = BoundedProcessRunner.run("/usr/bin/ditto",["-x","-k",word.path,wordTree.path],timeout:10,maxOutputBytes:4096)
            let imageXML = try String(contentsOf:wordTree.appendingPathComponent("word/document.xml"),encoding:.utf8)
            suite.expect(wordUnzip.status == 0 && imageXML.contains("r:embed=\"image1\"") && MediaSupport.imageDisplaySize(at:wordTree.appendingPathComponent("word/media/image.png")) == CGSize(width:100,height:80),"Image-to-Word embeds full-resolution normalized pixels with a valid relationship")
            let imageActions = FileToolCatalog.actions(for:[image],enginesAvailable:true)
            suite.expect(ImageFileTool.allCases.allSatisfy { imageActions.contains(.imageTool($0)) } && imageActions.contains(.metadata) && imageActions.contains(.readImageQR),"Finder’s additional image tools catalog includes every editor, metadata and QR reading")
            let videoActions = FileToolCatalog.actions(for:[directory.appendingPathComponent("test.mp4")],enginesAvailable:true)
            suite.expect(AVFileTool.allCases.filter { $0.isVideo && $0 != .videoJoin }.allSatisfy { videoActions.contains(.avTool($0)) },"Single-video catalog exposes split and frame export alongside the primary wheel tools")
            let svg = try FileDragConversionEngine.convert(image,to:.svg,batch:FileDragBatch())
            let svgText = try String(contentsOf:svg,encoding:.utf8)
            suite.expect(svgText.contains("data:image/png;base64,") && svgText.contains("viewBox=\"0 0 100 80\""),"Raster-to-SVG embeds pixels in a correctly sized portable SVG rather than claiming tracing")
            let engines = MediaEngineBundle(root:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/media-engines/runtime"))
            if let engines {
                let vector = directory.appendingPathComponent("vector.svg")
                let vectorXML = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"120\" height=\"60\"><rect width=\"120\" height=\"60\" fill=\"#ff0000\"/></svg>"
                try vectorXML.write(to:vector,atomically:false,encoding:.utf8)
                let privateImage = try ImageDocumentTools.renderSVG(vector,batch:FileDragBatch(),engines:engines)
                suite.expect(privateImage.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath() == directory.resolvingSymlinksInPath(),"SVG private staging shares the source volume so final exclusive publication works on external disks")
                try FileManager.default.removeItem(at:privateImage.deletingLastPathComponent())
                let rendered = try FileDragConversionEngine.convert(vector,to:.png,batch:FileDragBatch(),engines:engines)
                suite.expect(rendered.deletingLastPathComponent().resolvingSymlinksInPath() == directory.resolvingSymlinksInPath() && MediaSupport.imageDisplaySize(at:rendered) == CGSize(width:120,height:60),"Bundled static SVG conversion publishes beside the vector source at its original dimensions")
                let wrapped = try FileDragConversionEngine.convert(svg,to:.png,batch:FileDragBatch(),engines:engines)
                suite.expect(MediaSupport.imageDisplaySize(at:wrapped) == CGSize(width:100,height:80),"Raster-embedded SVG round trips through the independent bundled renderer")
                let preserved = try FileDragConversionEngine.convert(vector,to:.svg,batch:FileDragBatch(),engines:engines)
                suite.expect(try String(contentsOf:preserved,encoding:.utf8) == vectorXML,"SVG-to-SVG preserves static vector geometry and source bytes")
                for (index,payload) in ["<!DOCTYPE svg [<!ENTITY leak SYSTEM 'file:///etc/passwd'>]><svg>&leak;</svg>","<svg width='10' height='10'><image href='file:///etc/passwd'/></svg>","<svg width='10' height='10'><style>@import url(https://example.com/x);</style></svg>","<svg width='10' height='10'><script>foo()</script></svg>","<svg width='30000' height='30000'/>","<svg width='10' height='10'><animate attributeName='x'/></svg>"].enumerated() {
                    let invalid = directory.appendingPathComponent("bad-\(index).svg"); try payload.write(to:invalid,atomically:false,encoding:.utf8)
                    suite.expect((try? FileDragConversionEngine.convert(invalid,to:.png,batch:FileDragBatch(),engines:engines)) == nil,"Static SVG rejects external, active or over-budget content \(index)")
                }
            }
            suite.expect(try Data(contentsOf:image) == imageBytes,"SVG and Word conversion preserve source image bytes")

            let tar = directory.appendingPathComponent("test.tar"), names = ["nested/café.txt", "space and '$' file.txt"]
            try archive(tar, names: names)
            let tarBytes = try Data(contentsOf: tar)
            let extracted = try FileArchiveTools.extract(tar, batch: FileDragBatch())
            suite.expect(try names.allSatisfy { try Data(contentsOf: extracted.appendingPathComponent($0)) == Data(("Payload: "+$0).utf8) },
                         "Archive extraction preserves nested Unicode filenames and file contents")
            for format in FileArchiveFormat.allCases {
                let converted = try FileArchiveTools.convert(tar, to: format, batch: FileDragBatch())
                let tree = try FileArchiveTools.extract(converted, batch: FileDragBatch())
                let actual = FileManager.default.enumerator(atPath: tree.path)?.allObjects as? [String] ?? []
                suite.expect(names.allSatisfy { actual.contains($0) }, "\(format) preserves filenames: \(actual)")
                suite.expect(try names.allSatisfy { try Data(contentsOf: tree.appendingPathComponent($0)) == Data(("Payload: "+$0).utf8) },
                             "\(format) archive output round trips through the independent system reader")
            }
            let repeated = try FileArchiveTools.extract(tar, batch: FileDragBatch())
            suite.expect(repeated != extracted && FileManager.default.fileExists(atPath: extracted.path), "Extraction preserves earlier output folders")
            for (index, name) in ["../outside.txt", "/outside.txt", "nested/../../outside.txt"].enumerated() {
                let attack = directory.appendingPathComponent("attack\(index).tar"); try archive(attack, names: [name])
                suite.expect((try? FileArchiveTools.extract(attack, batch: FileDragBatch())) == nil,
                             "Archive extraction rejects path traversal or absolute entry \(index)")
            }
            let link = directory.appendingPathComponent("links.tar"); try archive(link, names: ["link"], link: true)
            suite.expect((try? FileArchiveTools.extract(link, batch: FileDragBatch())) == nil, "Archive extraction rejects symbolic-link entries")
            let duplicate = directory.appendingPathComponent("duplicate.tar"); try archive(duplicate, names: ["same", "same"])
            suite.expect((try? FileArchiveTools.extract(duplicate, batch: FileDragBatch())) == nil, "Archive extraction rejects duplicate file entries")
            suite.expect((try? FileArchiveTools.extract(tar, batch: FileDragBatch(), byteLimit: 1)) == nil,
                         "Archive expansion budget rejects an oversized payload before publication")
            let cancelled = FileDragBatch(); cancelled.cancel()
            suite.expect((try? FileArchiveTools.extract(tar, batch: cancelled)) == nil, "Cancelled archive extraction does not publish output")
            suite.expect(try Data(contentsOf: tar) == tarBytes, "Archive extraction and conversion preserve the original archive")
            suite.expect((try? FileArchiveTools.extract(tar,batch:FileDragBatch(),byteLimit:-1)) == nil,"Negative archive budgets fail before extraction")
            let deep = directory.appendingPathComponent("deep.tar"); try archive(deep,names:[Array(repeating:"d",count:129).joined(separator:"/")+"/file.txt"])
            suite.expect((try? FileArchiveTools.extract(deep,batch:FileDragBatch())) == nil,"Deep archive paths cannot create unbounded implicit parent directories")
            let empty = directory.appendingPathComponent("empty.tar"); try archive(empty,names:[])
            for format in FileArchiveFormat.allCases {
                let container = try FileArchiveTools.convert(empty,to:format,batch:FileDragBatch())
                let tree = try FileArchiveTools.extract(container,batch:FileDragBatch())
                suite.expect(try FileManager.default.contentsOfDirectory(atPath:tree.path).isEmpty,"Empty \(format) containers round trip without inventing files")
            }
            let crcZip = try FileArchiveTools.convert(tar,to:.zip,batch:FileDragBatch())
            var damaged = try Data(contentsOf:crcZip)
            // Corrupt the expected CRC in both local and central headers, leaving compressed payload intact.
            for signature in [Data([0x50,0x4b,0x03,0x04]),Data([0x50,0x4b,0x01,0x02])] {
                if let range = damaged.range(of:signature) { let crcOffset = range.lowerBound + (signature[2] == 3 ? 14 : 16); damaged[crcOffset] ^= 0xff }
            }
            let damagedZip = directory.appendingPathComponent("damaged.zip"); try damaged.write(to:damagedZip)
            suite.expect((try? FileArchiveTools.extract(damagedZip,batch:FileDragBatch())) == nil,"CRC corruption aborts archive extraction without publishing partial contents")
            let invalid = directory.appendingPathComponent("invalid.zip"); try Data("not a zip".utf8).write(to: invalid)
            suite.expect((try? FileArchiveTools.extract(invalid, batch: FileDragBatch())) == nil, "Invalid containers cannot fall back to a raw file extraction")
        } catch { suite.expect(false, "Document/archive conversion fixtures: \(error)") }
    }
}
