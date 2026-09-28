// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum AVFileTool: String, CaseIterable, Identifiable {
    case videoTrim, videoCrop, videoSpeed, videoJoin, videoFrames, videoSplit, videoRedact, videoCompress
    case audioTrim, audioNormalize, audioChannels, audioBleep, audioVisualizer
    var id: String { rawValue }
    var isVideo: Bool { rawValue.hasPrefix("video") }
    var icon: String {
        switch self {
        case .videoTrim, .audioTrim: return "scissors"
        case .videoCrop: return "crop"
        case .videoSpeed: return "speedometer"
        case .videoJoin: return "square.stack"
        case .videoFrames: return "photo.stack"
        case .videoSplit: return "rectangle.split.2x1"
        case .videoRedact, .audioBleep: return "rectangle.fill"
        case .videoCompress: return "arrow.down.right.and.arrow.up.left"
        case .audioNormalize: return "waveform.path"
        case .audioChannels: return "speaker.wave.2"
        case .audioVisualizer: return "waveform"
        }
    }
    static func wheelTools(video: Bool, count: Int) -> [Self] {
        video ? (count > 1 ? [.videoCompress, .videoJoin, .videoTrim, .videoSpeed, .videoFrames] : [.videoCompress, .videoCrop, .videoTrim, .videoSpeed, .videoRedact])
            : [.audioNormalize, .audioVisualizer, .audioTrim, .audioChannels, .audioBleep]
    }
}
struct AVTimedArea: Equatable, Identifiable {
    var id = UUID()
    var start = 0.0, end = 1.0
    var rect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    var style = ImageRedactionStyle.solid
}
struct AVFileEdit: Equatable {
    var start = 0.0, end = 0.0 // End zero means the source duration.
    var speed = 1.0
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var areas: [AVTimedArea] = []
    var splitCount = 2
    var splitTimes = "" // Optional comma-separated cut times in seconds.
    var frameTime = 0.0, allFrames = false
    var targetBytes: Int64 = 10_000_000
    var maxDimension = 1920
    var loudness = -16.0, truePeak = -1.0, loudnessRange = 11.0
    var mono = false, leftGain = 1.0, rightGain = 1.0
    var visualWidth = 1280, visualHeight = 720
    var stillImage: URL?
}
struct AVFileInfo {
    let duration: Double
    let width: Int, height: Int, channels: Int
    let fps: Double
    var hasVideo: Bool { width > 0 && height > 0 }
    var hasAudio: Bool { channels > 0 }
}
struct AVLoudness: Equatable {
    let integrated: Double, peak: Double, range: Double, threshold: Double, offset: Double
}
struct AVFileResult {
    let output: URL
    var inputLoudness: AVLoudness?
    var outputLoudness: AVLoudness?
}

enum AVFileTools {
    private static let base = ["-nostdin", "-v", "error", "-n", "-max_alloc", "536870912", "-filter_threads", "2", "-filter_complex_threads", "2", "-threads", "4"]
    private static func input(_ url: URL) -> [String] { ["-protocol_whitelist", "file,pipe", "-i", url.path] }
    private static let videoEncoder = ["-c:v", "h264_videotoolbox", "-b:v", "8M", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
    static func info(_ url: URL, engines: MediaEngineBundle, batch: FileDragBatch) throws -> AVFileInfo {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard url.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 8_000_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let data = try engines.run("ffprobe", arguments: ["-v", "error", "-protocol_whitelist", "file,pipe", "-show_streams", "-show_format", "-of", "json", url.path], batch: batch, timeout: 30, maxOutputBytes: 262144)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let streams = json["streams"] as? [[String: Any]],
              let format = json["format"] as? [String: Any], let duration = Double(format["duration"] as? String ?? ""), duration.isFinite, duration > 0, duration <= 86400 else { throw CocoaError(.fileReadCorruptFile) }
        let video = streams.first { $0["codec_type"] as? String == "video" && (($0["disposition"] as? [String: Int])?["attached_pic"] ?? 0) == 0 }
        let audio = streams.first { $0["codec_type"] as? String == "audio" }
        var width = video?["width"] as? Int ?? 0, height = video?["height"] as? Int ?? 0
        let sideData = video?["side_data_list"] as? [[String: Any]] ?? []
        let rotation = sideData.compactMap { ($0["rotation"] as? NSNumber)?.doubleValue }.first ?? Double((video?["tags"] as? [String: String])?["rotate"] ?? "0") ?? 0
        guard rotation.isFinite, abs(rotation) <= 36000 else { throw CocoaError(.fileReadCorruptFile) }
        if abs(Int((rotation/90).rounded())) % 2 == 1 { swap(&width, &height) }
        let rate = (video?["avg_frame_rate"] as? String ?? "0/1").split(separator: "/").compactMap { Double($0) }
        let fps = rate.count == 2 && rate[1] > 0 ? rate[0]/rate[1] : 0
        guard video == nil || MediaSupport.imageRenderSizeIsSafe(CGSize(width: width, height: height)), fps.isFinite, fps <= 1000 else { throw CocoaError(.fileReadTooLarge) }
        return AVFileInfo(duration: duration, width: width, height: height, channels: audio?["channels"] as? Int ?? 0, fps: fps)
    }
    static func timeRange(_ edit: AVFileEdit, duration: Double) throws -> ClosedRange<Double> {
        let end = edit.end == 0 ? duration : edit.end
        guard edit.start.isFinite, end.isFinite, edit.start >= 0, end > edit.start, end <= duration + 0.001 else { throw CocoaError(.validationMissingMandatoryProperty) }
        return edit.start...min(end, duration)
    }
    static func cuts(_ edit: AVFileEdit, duration: Double) throws -> [Double] {
        if edit.splitTimes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard (2...100).contains(edit.splitCount) else { throw CocoaError(.validationMissingMandatoryProperty) }
            return (0...edit.splitCount).map { duration * Double($0)/Double(edit.splitCount) }
        }
        guard edit.splitTimes.utf8.count <= 4096 else { throw CocoaError(.fileReadTooLarge) }
        let values = edit.splitTimes.split(separator: ",", omittingEmptySubsequences: false).map { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count <= 99, values.allSatisfy({ $0?.isFinite == true }), values.compactMap({ $0 }).allSatisfy({ $0 > 0 && $0 < duration }) else { throw CocoaError(.validationMissingMandatoryProperty) }
        let times = values.compactMap { $0 }
        guard zip(times, times.dropFirst()).allSatisfy({ $0 < $1 }) else { throw CocoaError(.validationMissingMandatoryProperty) }
        return [0] + times + [duration]
    }
    static func tempo(_ speed: Double) throws -> String {
        guard speed.isFinite, (0.125...8).contains(speed) else { throw CocoaError(.validationMissingMandatoryProperty) }
        var remainder = speed, factors: [Double] = []
        while remainder > 2 { factors.append(2); remainder /= 2 }
        while remainder < 0.5 { factors.append(0.5); remainder *= 2 }
        factors.append(remainder)
        return factors.map { "atempo=\($0)" }.joined(separator: ",")
    }
    private static func area(_ rect: CGRect, info: AVFileInfo) throws -> (x: Int, y: Int, w: Int, h: Int) {
        let r = try ImageFileTools.normalized(rect)
        let x = Int(r.minX * Double(info.width))/2*2, y = Int(r.minY * Double(info.height))/2*2
        let w = min(info.width-x, max(2, Int(r.width * Double(info.width))/2*2)), h = min(info.height-y, max(2, Int(r.height * Double(info.height))/2*2))
        guard w >= 2, h >= 2 else { throw CocoaError(.validationMissingMandatoryProperty) }
        return (x,y,w,h)
    }
    private static func validateAreas(_ areas: [AVTimedArea], duration: Double) throws {
        guard !areas.isEmpty, areas.count <= 100, areas.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && $0.end <= duration }) else { throw CocoaError(.validationMissingMandatoryProperty) }
    }
    private static func measure(_ url: URL, edit: AVFileEdit, engines: MediaEngineBundle, batch: FileDragBatch) throws -> AVLoudness {
        let data = try engines.run("ffmpeg", arguments: ["-nostdin", "-nostats", "-v", "info"] + input(url) + ["-map", "0:a:0", "-af", "loudnorm=I=\(edit.loudness):TP=\(edit.truePeak):LRA=\(edit.loudnessRange):print_format=json", "-f", "null", "-"], batch: batch, maxOutputBytes: 65536)
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let start = text.lastIndex(of: "{"), let end = text.lastIndex(of: "}"), end > start,
              let jsonData = String(text[start...end]).data(using: .utf8), let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: String],
              let i = Double(json["input_i"] ?? ""), let p = Double(json["input_tp"] ?? ""), let r = Double(json["input_lra"] ?? ""), let t = Double(json["input_thresh"] ?? ""), let o = Double(json["target_offset"] ?? ""),
              [i,p,r,t,o].allSatisfy(\.isFinite) else { throw CocoaError(.fileReadCorruptFile) }
        return AVLoudness(integrated: i, peak: p, range: r, threshold: t, offset: o)
    }
    static func preview(_ url: URL, info: AVFileInfo, engines: MediaEngineBundle, batch: FileDragBatch, time: Double = 0) throws -> CGImage {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("av-preview-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: destination) }
        let args: [String]
        if info.hasVideo {
            args = base + ["-ss", String(min(max(0,time), max(0,info.duration-0.01)))] + input(url) + ["-map", "0:v:0", "-vf", "scale=1000:700:force_original_aspect_ratio=decrease", "-frames:v", "1", destination.path]
        } else {
            let sampleRate = Int(min(96000,max(100,ceil(1200/info.duration))))
            let width = Int(max(1,min(1000,floor(info.duration*Double(sampleRate)))))
            args = base + input(url) + ["-filter_complex", "[0:a:0]aformat=channel_layouts=mono,aeval=abs(val(0)),aresample=\(sampleRate),showwavespic=s=\(width)x220:colors=0xff5900:draw=full:filter=peak[v]", "-map", "[v]", "-frames:v", "1", destination.path]
        }
        _ = try engines.run("ffmpeg", arguments: args, batch: batch, timeout: 60)
        return try ImageFileTools.load(destination, preview: true)
    }
    static func save(_ urls: [URL], tool: AVFileTool, edit: AVFileEdit, engines: MediaEngineBundle, batch: FileDragBatch, outputDirectory: URL? = nil) throws -> AVFileResult {
        guard !urls.isEmpty, urls.count <= 100, !batch.isCancelled else { throw CancellationError() }
        let infos = try urls.map { try info($0, engines: engines, batch: batch) }, source = infos[0], url = urls[0]
        guard tool.isVideo ? infos.allSatisfy(\.hasVideo) : infos.allSatisfy(\.hasAudio) else { throw CocoaError(.fileReadCorruptFile) }
        if tool == .videoJoin { return try join(urls, infos: infos, engines: engines, batch: batch) }
        let folder = tool == .videoSplit || (tool == .videoFrames && edit.allFrames)
        let ext = folder ? "" : (tool == .videoFrames ? "png" : (tool.isVideo || tool == .audioVisualizer ? "mp4" : "wav"))
        let namingInput = outputDirectory.map { $0.appendingPathComponent(url.lastPathComponent) } ?? url
        let output = MediaSupport.uniqueOutputURL(for: namingInput, suffix: "-" + tool.rawValue, fileExtension: ext)
        let staged = try MediaSupport.temporaryOutputURL(for: output); defer { MediaSupport.discardStagedOutput(staged) }
        var args = base + input(url), result = AVFileResult(output: output)
        if folder { try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: false) }
        switch tool {
        case .videoTrim, .audioTrim:
            let range = try timeRange(edit, duration: source.duration)
            args += ["-ss", String(range.lowerBound), "-t", String(range.upperBound-range.lowerBound)]
        case .videoCrop:
            let r = try area(edit.crop, info: source)
            args += ["-vf", "crop=\(r.w):\(r.h):\(r.x):\(r.y)"]
        case .videoSpeed:
            let audio = try tempo(edit.speed)
            args += ["-vf", "setpts=(PTS-STARTPTS)/\(edit.speed),fps=\(source.fps > 0 ? source.fps : 30)"]
            if source.hasAudio { args += ["-af", audio] }
            args += ["-t", String(source.duration/edit.speed)]
        case .videoCompress:
            guard (100_000...10_000_000_000).contains(edit.targetBytes), (64...8192).contains(edit.maxDimension) else { throw CocoaError(.validationMissingMandatoryProperty) }
            let videoBitrate = Int(Double(edit.targetBytes)*8*0.92/source.duration) - (source.hasAudio ? 128000 : 0)
            guard videoBitrate >= 32000, videoBitrate <= 1_000_000_000 else { throw CocoaError(.validationMissingMandatoryProperty) }
            args += ["-map", "0:v:0", "-map", "0:a:0?", "-vf", "scale=w='min(\(edit.maxDimension),iw)':h='min(\(edit.maxDimension),ih)':force_original_aspect_ratio=decrease:force_divisible_by=2", "-c:v", "h264_videotoolbox", "-b:v", String(videoBitrate), "-maxrate", String(videoBitrate), "-bufsize", String(videoBitrate*2), "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", "-map_metadata", "-1", staged.path]
            _ = try engines.run("ffmpeg", arguments: args, batch: batch)
            guard (try staged.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= edit.targetBytes else { throw CocoaError(.validationMissingMandatoryProperty) }
        case .videoFrames:
            if edit.allFrames {
                guard source.fps > 0, source.duration*source.fps <= 5000 else { throw CocoaError(.fileReadTooLarge) }
                args += ["-map", "0:v:0", "-an", "-fps_mode", "passthrough", "-frames:v", "5001", staged.appendingPathComponent("Frame %06d.png").path]
            } else {
                guard edit.frameTime.isFinite, edit.frameTime >= 0, edit.frameTime < source.duration else { throw CocoaError(.validationMissingMandatoryProperty) }
                args += ["-ss", String(edit.frameTime), "-map", "0:v:0", "-frames:v", "1", staged.path]
            }
            _ = try engines.run("ffmpeg", arguments: args, batch: batch)
        case .videoSplit:
            let boundaries = try cuts(edit, duration: source.duration)
            for index in 0..<boundaries.count-1 {
                guard !batch.isCancelled else { throw CancellationError() }
                _ = try engines.run("ffmpeg", arguments: base + input(url) + ["-ss", String(boundaries[index]), "-t", String(boundaries[index+1]-boundaries[index]), "-map", "0:v:0", "-map", "0:a:0?"] + videoEncoder + ["-map_metadata", "-1", staged.appendingPathComponent(String(format: "Part %04d.mp4", index+1)).path], batch: batch)
            }
        case .videoRedact:
            try validateAreas(edit.areas, duration: source.duration)
            var filters: [String] = [], current = "0:v:0"
            for (index, region) in edit.areas.enumerated() {
                let r = try area(region.rect, info: source), next = "v\(index)", enable = "between(t,\(region.start),\(region.end))"
                if region.style == .solid { filters.append("[\(current)]drawbox=x=\(r.x):y=\(r.y):w=\(r.w):h=\(r.h):color=black:t=fill:enable='\(enable)'[\(next)]") }
                else {
                    let transform = region.style == .blur ? "gblur=sigma=\(min(12,min(r.w,r.h)/2)):steps=2" : "scale=\(max(1,r.w/16)):\(max(1,r.h/16)),scale=\(r.w):\(r.h):flags=neighbor"
                    filters += ["[\(current)]split[b\(index)][p\(index)]", "[p\(index)]crop=\(r.w):\(r.h):\(r.x):\(r.y),\(transform)[q\(index)]", "[b\(index)][q\(index)]overlay=\(r.x):\(r.y):enable='\(enable)'[\(next)]"]
                }
                current = next
            }
            args += ["-filter_complex", filters.joined(separator: ";"), "-map", "[\(current)]", "-map", "0:a:0?"] + videoEncoder + ["-map_metadata", "-1", staged.path]
            _ = try engines.run("ffmpeg", arguments: args, batch: batch)
        case .audioNormalize:
            guard edit.loudness.isFinite, (-70 ... -5).contains(edit.loudness), edit.truePeak.isFinite, (-9...0).contains(edit.truePeak), edit.loudnessRange.isFinite, (1...50).contains(edit.loudnessRange) else { throw CocoaError(.validationMissingMandatoryProperty) }
            let measured = try measure(url, edit: edit, engines: engines, batch: batch); result.inputLoudness = measured
            args += ["-af", "loudnorm=I=\(edit.loudness):TP=\(edit.truePeak):LRA=\(edit.loudnessRange):measured_I=\(measured.integrated):measured_TP=\(measured.peak):measured_LRA=\(measured.range):measured_thresh=\(measured.threshold):offset=\(measured.offset):linear=true", "-map", "0:a:0", "-vn", "-ar", "48000", "-c:a", "pcm_s24le", "-map_metadata", "-1", staged.path]
            _ = try engines.run("ffmpeg", arguments: args, batch: batch)
            result.outputLoudness = try measure(staged, edit: edit, engines: engines, batch: batch)
        case .audioChannels:
            guard source.channels <= 2, [edit.leftGain,edit.rightGain].allSatisfy({ $0.isFinite && (0...2).contains($0) }) else { throw CocoaError(.validationMissingMandatoryProperty) }
            let right = source.channels == 1 ? "c0" : "c1"
            let expression = edit.mono ? "pan=mono|c0=\(edit.leftGain/2)*c0+\(edit.rightGain/2)*\(right)" : "pan=stereo|c0=\(edit.leftGain)*c0|c1=\(edit.rightGain)*\(right)"
            args += ["-af", expression]
        case .audioBleep:
            try validateAreas(edit.areas, duration: source.duration)
            let gate = edit.areas.map { "between(t,\($0.start),\($0.end))" }.joined(separator: "+")
            args += ["-filter_complex", "[0:a:0]aformat=sample_rates=48000:channel_layouts=stereo,volume=0:enable='\(gate)'[clean];sine=frequency=1000:sample_rate=48000:duration=\(source.duration),aformat=channel_layouts=stereo,volume='if(gt(\(gate),0),0.25,0)':eval=frame[tone];[clean][tone]amix=inputs=2:normalize=0:duration=first[a]", "-map", "[a]", "-vn", "-c:a", "pcm_s24le", "-map_metadata", "-1", staged.path]
            _ = try engines.run("ffmpeg", arguments: args, batch: batch)
        case .audioVisualizer:
            guard edit.visualWidth >= 64, edit.visualHeight >= 64, MediaSupport.imageRenderSizeIsSafe(CGSize(width: edit.visualWidth,height: edit.visualHeight)), edit.visualWidth%2 == 0, edit.visualHeight%2 == 0 else { throw CocoaError(.validationMissingMandatoryProperty) }
            let size = "\(edit.visualWidth)x\(edit.visualHeight)"
            if let image = edit.stillImage {
                try ImageFileTools.validate([image])
                args = base + ["-loop", "1"] + input(image) + input(url) + ["-vf", "scale=\(edit.visualWidth):\(edit.visualHeight):force_original_aspect_ratio=decrease,pad=\(edit.visualWidth):\(edit.visualHeight):(ow-iw)/2:(oh-ih)/2:color=black", "-map", "0:v:0", "-map", "1:a:0", "-r", "30", "-t", String(source.duration)]
            } else { args += ["-filter_complex", "[0:a:0]showwaves=s=\(size):mode=cline:colors=0xff5900:rate=30[v]", "-map", "[v]", "-map", "0:a:0"] }
            args += videoEncoder + ["-map_metadata", "-1", staged.path]
            _ = try engines.run("ffmpeg", arguments: args, batch: batch)
        case .videoJoin: break // Handled before staging above.
        }
        if [.videoTrim,.videoCrop,.videoSpeed].contains(tool) {
            args += ["-map", "0:v:0", "-map", "0:a:0?"] + videoEncoder + ["-map_metadata", "-1", staged.path]
            _ = try engines.run("ffmpeg", arguments: args, batch: batch)
        } else if tool == .audioTrim || tool == .audioChannels {
            args += ["-map", "0:a:0", "-vn", "-c:a", "pcm_s24le", "-map_metadata", "-1", staged.path]
            _ = try engines.run("ffmpeg", arguments: args, batch: batch)
        }
        guard !batch.isCancelled else { throw CancellationError() }
        if folder {
            let files = try FileManager.default.contentsOfDirectory(atPath: staged.path)
            guard !files.isEmpty, tool != .videoFrames || files.count <= 5000 else { throw CocoaError(.fileReadTooLarge) }
        }
        else { guard (try staged.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else { throw CocoaError(.fileWriteUnknown) } }
        try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false)
        return result
    }
    private static func join(_ urls: [URL], infos: [AVFileInfo], engines: MediaEngineBundle, batch: FileDragBatch) throws -> AVFileResult {
        guard urls.count > 1, infos.reduce(0,{ $0+$1.duration }) <= 86400 else { throw CocoaError(.validationMissingMandatoryProperty) }
        let output = MediaSupport.uniqueOutputURL(for: urls[0], suffix: "-joined", fileExtension: "mp4"), stage = try MediaSupport.temporaryOutputURL(for: output)
        defer { MediaSupport.discardStagedOutput(stage) }
        let directory = stage.deletingLastPathComponent(), width = infos[0].width/2*2, height = infos[0].height/2*2
        guard width >= 2, height >= 2 else { throw CocoaError(.validationMissingMandatoryProperty) }
        var lines: [String] = []
        for (index,url) in urls.enumerated() {
            let segment = directory.appendingPathComponent("segment\(index).mp4")
            var args = base + input(url)
            if !infos[index].hasAudio { args += ["-filter_complex", "anullsrc=r=48000:cl=stereo[a]"] }
            args += ["-map", "0:v:0", "-map", infos[index].hasAudio ? "0:a:0" : "[a]", "-vf", "scale=\(width):\(height):force_original_aspect_ratio=decrease,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30", "-ar", "48000", "-ac", "2", "-t", String(infos[index].duration)] + videoEncoder + ["-map_metadata", "-1", segment.path]
            _ = try engines.run("ffmpeg", arguments: args, batch: batch)
            lines.append("file 'segment\(index).mp4'") // Only private generated names enter the concat manifest.
        }
        let list = directory.appendingPathComponent("join.txt"); try lines.joined(separator: "\n").write(to: list, atomically: false, encoding: .utf8)
        _ = try engines.run("ffmpeg", arguments: base + ["-protocol_whitelist", "file,pipe", "-f", "concat", "-safe", "1", "-i", list.path, "-c", "copy", "-movflags", "+faststart", "-map_metadata", "-1", stage.path], batch: batch)
        guard !batch.isCancelled else { throw CancellationError() }
        try MediaSupport.installStagedOutput(stage, at: output, replacingExisting: false)
        return AVFileResult(output: output)
    }
}
