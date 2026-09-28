// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

enum AVTimeInputs {
    /// Seconds, mm:ss, hh:mm:ss.mmm, or hh:mm:ss:frame at the source frame rate.
    static func parse(_ text: String, fps: Double? = nil) -> Double? {
        guard text.utf8.count <= 64 else { return nil }
        let parts = text.trimmingCharacters(in:.whitespacesAndNewlines).split(separator:":",omittingEmptySubsequences:false)
        guard (1...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count, numbers.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        if numbers.count == 1 { return numbers[0] <= 86400 ? numbers[0] : nil }
        guard numbers.dropLast().allSatisfy({ $0.rounded(.towardZero) == $0 }) else { return nil }
        let value: Double
        if numbers.count == 4 {
            guard let fps, fps.isFinite, fps > 0, numbers[1] < 60, numbers[2] < 60,
                  numbers[3].rounded(.towardZero) == numbers[3], numbers[3] < ceil(fps) else { return nil }
            value = numbers[0]*3600+numbers[1]*60+numbers[2]+numbers[3]/fps
        } else {
            guard numbers.last! < 60, numbers.count != 3 || numbers[1] < 60 else { return nil }
            value = numbers.count == 2 ? numbers[0]*60+numbers[1] : numbers[0]*3600+numbers[1]*60+numbers[2]
        }
        return value <= 86400 ? value : nil
    }
}
extension AVFileTools {
    static func silenceEndpoints(_ url: URL, info: AVFileInfo, engines: MediaEngineBundle, batch: FileDragBatch) throws -> ClosedRange<Double> {
        guard info.hasAudio else { throw CocoaError(.fileReadCorruptFile) }
        let data = try engines.run("ffmpeg",arguments:["-nostdin","-nostats","-v","info","-protocol_whitelist","file,pipe","-i",url.path,"-map","0:a:0","-af","silencedetect=noise=-45dB:d=0.2","-f","null","-"],batch:batch,timeout:120,maxOutputBytes:2_000_000)
        guard data.count < 2_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let lines = (String(data:data,encoding:.utf8) ?? "").components(separatedBy:"\n")
        var pending: Double?, silence: [(Double,Double)] = []
        for line in lines {
            if let range = line.range(of:"silence_start: "), let value = Double(line[range.upperBound...].trimmingCharacters(in:.whitespaces)) { pending = max(0,value) }
            if let range = line.range(of:"silence_end: "), let first = line[range.upperBound...].split(separator:"|").first,
               let value = Double(first.trimmingCharacters(in:.whitespaces)), let start = pending {
                silence.append((start,min(info.duration,value))); pending = nil
            }
        }
        if let pending { silence.append((pending,info.duration)) }
        let start = silence.first.flatMap { $0.0 <= 0.005 ? $0.1 : nil } ?? 0
        let end = silence.last.flatMap { $0.1 >= info.duration-0.005 ? $0.0 : nil } ?? info.duration
        guard end > start else { throw CocoaError(.validationMissingMandatoryProperty) }
        return start...end
    }
}
