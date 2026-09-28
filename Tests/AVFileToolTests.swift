// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation
import ImageIO

// Export fixtures exercise the same bundled engines and staging path as the UI.
enum AVFileToolTests {
    static func run(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = AVFileToolStrings.localized(language)
            suite.expect(AVFileTool.allCases.allSatisfy { !strings.label($0).isEmpty } && AVFileToolStrings.Key.allCases.allSatisfy { !strings[$0].isEmpty }, "AV tool labels and controls cover \(language)")
        }
        suite.expect(AVTimeInputs.parse("00:00:01:05",fps:10) == 1.5 && AVTimeInputs.parse("01:02.250") == 62.25 && AVTimeInputs.parse("1.25") == 1.25,"Time inputs accept frame timecodes, minute/second timestamps and fractional seconds")
        suite.expect(AVTimeInputs.parse("00:00:01:30",fps:30) == nil && AVTimeInputs.parse("00:60:00") == nil && AVTimeInputs.parse("nan") == nil && AVTimeInputs.parse("00:00:01:01") == nil,"Time inputs reject invalid frame indices, minute bounds and nonfinite/missing frame rates")
        suite.expect(AVRangeDrag(range:1...2,anchor:1.5,duration:4,tolerance:0.01).range(at:4) == 3...4,"Moving a waveform interval retains its length and clamps to the end")
        suite.expect(AVRangeDrag(range:1...2,anchor:1,duration:4,tolerance:0.01).range(at:0.5) == 0.5...2,"Waveform edge adjustment changes only the selected start edge")
        suite.expect(AVRangeDrag(range:nil,anchor:3,duration:4,tolerance:0.01).range(at:1) == 1...3,"Dragging backward creates an ordered waveform interval")
        suite.expect(AVTimeInputs.step(0,direction:-1,fps:10,duration:4) == 0 && AVTimeInputs.step(0.5,direction:1,fps:10,duration:4) == 0.6 && AVTimeInputs.step(4,direction:1,fps:10,duration:4) == 3.9,"Frame stepping advances one source frame and retains valid endpoint bounds")
        var edit = AVFileEdit(); edit.splitTimes = "0.5, 1.5"
        suite.expect((try? AVFileTools.cuts(edit, duration: 2)) == [0,0.5,1.5,2], "Video custom cut times retain ordered subsecond boundaries")
        edit.splitTimes = "1.5,0.5"
        suite.expect((try? AVFileTools.cuts(edit, duration: 2)) == nil, "Video split rejects unordered cuts")
        edit.splitTimes = ""; edit.splitCount = 4
        suite.expect((try? AVFileTools.cuts(edit,duration: 2)) == [0,0.5,1,1.5,2], "Equal video split covers the whole duration")
        suite.expect((try? AVFileTools.tempo(8)) == "atempo=2.0,atempo=2.0,atempo=2.0" && (try? AVFileTools.tempo(0.125)) == "atempo=0.5,atempo=0.5,atempo=0.5", "Pitch-preserving speed chains stay inside each atempo filter range")
        suite.expect((try? AVFileTools.tempo(.nan)) == nil && (try? AVFileTools.tempo(0)) == nil, "Speed rejects nonfinite and zero values")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/media-engines/runtime")
        guard let engines = MediaEngineBundle(root: root) else { print("SKIP: AV export fixtures require the staged compatible engine bundle."); return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-av-tools-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let video = directory.appendingPathComponent("video.mp4"), audio = directory.appendingPathComponent("stereo.wav"), silentVideo = directory.appendingPathComponent("portrait.mp4")
            _ = try engines.run("ffmpeg",arguments: ["-nostdin","-v","error","-n","-filter_complex","color=red:s=160x96:r=10:d=4[v];sine=frequency=440:sample_rate=48000:duration=4[a]","-map","[v]","-map","[a]","-c:v","h264_videotoolbox","-b:v","300k","-pix_fmt","yuv420p","-c:a","aac","-shortest",video.path],batch: FileDragBatch())
            _ = try engines.run("ffmpeg",arguments: ["-nostdin","-v","error","-n","-filter_complex","sine=frequency=440:sample_rate=48000:duration=4[l];sine=frequency=880:sample_rate=48000:duration=4[r];[l][r]amerge=inputs=2[a]","-map","[a]","-c:a","pcm_s16le",audio.path],batch: FileDragBatch())
            _ = try engines.run("ffmpeg",arguments: ["-nostdin","-v","error","-n","-filter_complex","color=blue:s=96x160:r=10:d=1[v]","-map","[v]","-c:v","h264_videotoolbox","-b:v","300k","-pix_fmt","yuv420p",silentVideo.path],batch: FileDragBatch())
            let originalVideo = try Data(contentsOf: video), originalAudio = try Data(contentsOf: audio)
            let silenceAudio = directory.appendingPathComponent("silence.wav")
            _ = try engines.run("ffmpeg",arguments:["-nostdin","-v","error","-n","-filter_complex","anullsrc=r=48000:cl=mono:d=0.5[s0];sine=frequency=440:sample_rate=48000:duration=1[tone];anullsrc=r=48000:cl=mono:d=0.5[s1];[s0][tone][s1]concat=n=3:v=0:a=1[a]","-map","[a]","-c:a","pcm_s16le",silenceAudio.path],batch:FileDragBatch())
            let silenceInfo = try AVFileTools.info(silenceAudio,engines:engines,batch:FileDragBatch())
            let endpoints = try AVFileTools.silenceEndpoints(silenceAudio,info:silenceInfo,engines:engines,batch:FileDragBatch())
            suite.expect(abs(endpoints.lowerBound-0.5) < 0.05 && abs(endpoints.upperBound-1.5) < 0.05,"Silent endpoint detection retains the audible middle and trims both quiet ends")
            func pcm(_ url: URL) throws -> [Float] {
                let raw = directory.appendingPathComponent("pcm-\(UUID().uuidString).raw")
                defer { try? FileManager.default.removeItem(at:raw) }
                _ = try engines.run("ffmpeg",arguments:["-nostdin","-v","error","-n","-protocol_whitelist","file,pipe","-i",url.path,"-map","0:a:0","-ac","1","-ar","48000","-f","f32le",raw.path],batch:FileDragBatch())
                let data = try Data(contentsOf:raw)
                return data.withUnsafeBytes { bytes in stride(from:0,to:bytes.count-3,by:4).map { Float(bitPattern:UInt32(littleEndian:bytes.loadUnaligned(fromByteOffset:$0,as:UInt32.self))) } }
            }
            func amplitude(_ samples: [Float],frequency: Double,start: Double) -> Double {
                let first = Int(start*48000), count = 4800
                guard first >= 0, first+count <= samples.count else { return 0 }
                var sine = 0.0, cosine = 0.0
                for i in 0..<count { let phase = 2*Double.pi*frequency*Double(i)/48000, sample = Double(samples[first+i]); sine += sample*sin(phase); cosine += sample*cos(phase) }
                return 2*sqrt(sine*sine+cosine*cosine)/Double(count)
            }

            func export(_ tool: AVFileTool,_ inputs: [URL],_ edit: AVFileEdit = AVFileEdit(),check: (AVFileResult) throws -> Void) {
                do { try check(AVFileTools.save(inputs,tool: tool,edit: edit,engines: engines,batch: FileDragBatch())) }
                catch { suite.expect(false,"\(tool) actual export fixture: \(error)") }
            }
            func info(_ url: URL) throws -> AVFileInfo { try AVFileTools.info(url,engines: engines,batch: FileDragBatch()) }
            var trim = AVFileEdit(); trim.start = 0.5; trim.end = 2
            export(.videoTrim,[video],trim) { result in let data = try info(result.output); suite.expect(abs(data.duration-1.5) < 0.15 && data.hasAudio, "Video trim exports the selected subsecond range with audio") }
            export(.audioTrim,[audio],trim) { result in suite.expect(abs(try info(result.output).duration-1.5) < 0.02, "Audio trim exports the selected duration") }
            var crop = AVFileEdit(); crop.crop = CGRect(x: 0.25,y: 0.25,width: 0.5,height: 0.5)
            export(.videoCrop,[video],crop) { result in let data = try info(result.output); suite.expect(data.width == 80 && data.height == 48 && data.hasAudio,"Video crop retains audio and exports selected pixel dimensions") }
            var speed = AVFileEdit(); speed.speed = 2
            export(.videoSpeed,[video],speed) { result in let data = try info(result.output); suite.expect(abs(data.duration-2) < 0.2 && data.hasAudio,"Double speed shortens video and pitch-preserving audio together: \(data.duration)s"); suite.expect(amplitude(try pcm(result.output),frequency:440,start:0.5) > 0.05,"Speed changes retain the original 440 Hz pitch in decoded audio") }
            export(.videoJoin,[video,silentVideo]) { result in let data = try info(result.output); suite.expect(abs(data.duration-5) < 0.2 && data.width == 160 && data.height == 96 && data.hasAudio,"Join fits mixed dimensions to the first canvas and fills missing audio") }
            var frames = AVFileEdit(); frames.allFrames = true
            export(.videoFrames,[video],frames) { result in
                let files = try FileManager.default.contentsOfDirectory(at: result.output,includingPropertiesForKeys: nil)
                let size = files.first.flatMap { MediaSupport.imageDisplaySize(at: $0) }
                suite.expect(files.count == 40 && size == CGSize(width: 160,height: 96),"All-frame export writes every full-resolution PNG")
            }
            export(.videoFrames,[video]) { result in suite.expect(MediaSupport.imageDisplaySize(at: result.output) == CGSize(width:160,height:96),"Single-frame export preserves resolution") }
            var split = AVFileEdit(); split.splitTimes = "1,2.5"
            export(.videoSplit,[video],split) { result in
                let files = try FileManager.default.contentsOfDirectory(at: result.output,includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
                let durations = try files.map { try info($0).duration }
                suite.expect(files.count == 3 && zip(durations,[1.0,1.5,1.5]).allSatisfy { abs($0-$1) < 0.15 },"Custom video split exports each complete segment")
            }
            for style in ImageRedactionStyle.allCases {
                var redact = AVFileEdit(); redact.areas = [AVTimedArea(start: 1,end: 2,rect: CGRect(x:0.25,y:0.25,width:0.5,height:0.5),style: style)]
                export(.videoRedact,[video],redact) { result in
                    let data = try info(result.output)
                    suite.expect(data.hasAudio && abs(data.duration-4) < 0.1,"Timed \(style) video redaction retains audio and duration")
                    if style == .solid {
                        let frame = try AVFileTools.preview(result.output,info: data,engines: engines,batch: FileDragBatch(),time: 1.5)
                        let context = CGContext(data:nil,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                        context.translateBy(x: -500,y: -300); context.draw(frame,in:CGRect(x:0,y:0,width:1000,height:600))
                        let pixels = context.data!.assumingMemoryBound(to:UInt8.self)
                        suite.expect(pixels[0] < 20 && pixels[1] < 20 && pixels[2] < 20,"Timed solid redaction burns the covered center into exported pixels")
                    }
                }
            }
            var compress = AVFileEdit(); compress.targetBytes = 300000; compress.maxDimension = 128
            export(.videoCompress,[video],compress) { result in suite.expect(try (result.output.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 300000 && info(result.output).width <= 128,"Video target-size compression enforces its requested size and dimension ceiling") }
            var channels = AVFileEdit(); channels.mono = true; channels.leftGain = 0; channels.rightGain = 1
            export(.audioChannels,[audio],channels) { result in suite.expect(try info(result.output).channels == 1,"Channel mixing creates mono output with independent source gains"); let samples = try pcm(result.output); suite.expect(amplitude(samples,frequency:880,start:0.5) > 0.04 && amplitude(samples,frequency:440,start:0.5) < 0.002,"Independent channel gains retain the right tone and remove the muted left tone") }
            var bleep = AVFileEdit(); bleep.areas = [AVTimedArea(start:1,end:2)]
            export(.audioBleep,[audio],bleep) { result in suite.expect(try abs(info(result.output).duration-4) < 0.02 && info(result.output).channels == 2,"Bleep exports timed censor tone without changing duration"); let samples = try pcm(result.output); suite.expect(amplitude(samples,frequency:440,start:0.25) > 0.04 && amplitude(samples,frequency:440,start:1.25) < 0.002 && amplitude(samples,frequency:1000,start:1.25) > 0.01,"Bleep retains original audio outside the interval and replaces covered speech with a 1 kHz tone") }
            export(.audioNormalize,[audio]) { result in suite.expect(result.inputLoudness != nil && abs((result.outputLoudness?.integrated ?? 0)+16) < 1 && (result.outputLoudness?.peak ?? 1) <= -0.8,"Two-pass normalization reports measured input/output and meets loudness/peak targets") }
            var visual = AVFileEdit(); visual.visualWidth = 160; visual.visualHeight = 96
            export(.audioVisualizer,[audio],visual) { result in let data = try info(result.output); suite.expect(data.width == 160 && data.height == 96 && data.hasAudio && abs(data.duration-4) < 0.1,"Waveform visualizer exports a complete video with source audio") }
            var previewPublished = 0
            let previewModel = try AVWorkspaceModel(inputs:[audio],tool:.audioBleep,engines:engines,available:{ true },publish:{ previewPublished += $0.count })
            let prepareDeadline = Date().addingTimeInterval(10)
            while previewModel.info == nil && previewModel.message == nil && Date() < prepareDeadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
            previewModel.change { $0.areas = [AVTimedArea(start:1,end:2)] }
            let countBefore = try FileManager.default.contentsOfDirectory(atPath:directory.path).count
            previewModel.previewProcessed(); let previewDeadline = Date().addingTimeInterval(10)
            while previewModel.busy && Date() < previewDeadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
            let previewOutput = previewModel.processedPreview
            suite.expect(try previewOutput != nil && previewModel.previewStart == 1 && previewPublished == 0 && FileManager.default.contentsOfDirectory(atPath:directory.path).count == countBefore,"Processed audio preview renders the selected interval privately without creating user-folder output or revealing files: \(previewModel.message ?? "no error"), info=\(previewModel.info != nil)")
            if let previewOutput { suite.expect(abs(try info(previewOutput).duration-3) < 0.02,"Processed preview is clipped to the remaining selected interval"); previewModel.cancel(); suite.expect(!FileManager.default.fileExists(atPath:previewOutput.path),"Closing the editor removes its private preview files") }
            let cancelled = FileDragBatch(); cancelled.cancel()
            suite.expect((try? AVFileTools.save([video],tool:.videoTrim,edit:AVFileEdit(),engines:engines,batch:cancelled)) == nil,"Cancelled AV operation cannot publish an output")
            suite.expect(try Data(contentsOf:video) == originalVideo && Data(contentsOf:audio) == originalAudio,"Every video/audio tool preserves the original bytes")
            let first = try AVFileTools.save([video],tool:.videoTrim,edit:trim,engines:engines,batch:FileDragBatch())
            let second = try AVFileTools.save([video],tool:.videoTrim,edit:trim,engines:engines,batch:FileDragBatch())
            suite.expect(first.output != second.output && FileManager.default.fileExists(atPath:first.output.path),"Repeated AV export preserves earlier outputs")
        } catch { suite.expect(false,"AV fixtures setup: \(error)") }
    }
}
