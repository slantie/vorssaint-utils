// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// RAR5 method 0 (stored files), following https://www.rarlab.com/technote.htm.
/// No compression algorithm, encryption, external executable or UnRAR code is used.
enum StoredRARWriter {
    private static let table: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 { crc = crc & 1 != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
        return crc
    }
    private static func crc(_ data: Data, from value: UInt32 = 0xffffffff) -> UInt32 {
        data.reduce(value) { (value, byte) in table[Int((value ^ UInt32(byte)) & 0xff)] ^ (value >> 8) }
    }
    private static func vint(_ number: UInt64) -> Data {
        var number = number, result = Data()
        repeat { let byte = UInt8(number & 0x7f); number >>= 7; result.append(number == 0 ? byte : byte | 0x80) } while number > 0
        return result
    }
    private static func little(_ number: UInt32) -> Data { var value = number.littleEndian; return withUnsafeBytes(of: &value) { Data($0) } }
    private static func header(_ body: Data) -> Data {
        let content = vint(UInt64(body.count)) + body
        return little(crc(content) ^ 0xffffffff) + content
    }
    static func write(tree: URL, to output: URL, batch: FileDragBatch) throws {
        try Data().write(to: output, options: .withoutOverwriting)
        let outputFile = try FileHandle(forWritingTo: output); defer { try? outputFile.close() }
        try outputFile.write(contentsOf: Data([0x52,0x61,0x72,0x21,0x1a,0x07,0x01,0x00]))
        try outputFile.write(contentsOf: header(Data([1,0,0]))) // Main header; no volume/solid flags.
        guard let enumerator = FileManager.default.enumerator(atPath: tree.path) else { throw CocoaError(.fileReadUnknown) }
        for case let name as String in enumerator {
            let url = tree.appendingPathComponent(name)
            guard !batch.isCancelled else { throw CancellationError() }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
            let directory = values.isDirectory == true, size = directory ? 0 : values.fileSize ?? 0
            let nameData = Data(name.utf8)
            _ = try FileArchiveTools.components(name)
            var checksum: UInt32 = 0xffffffff
            var input: FileHandle?
            if !directory {
                let file = try FileHandle(forReadingFrom: url); input = file
                while true {
                    guard !batch.isCancelled else { try? file.close(); throw CancellationError() }
                    let data = try file.read(upToCount: 65536) ?? Data(); if data.isEmpty { break }; checksum = crc(data, from: checksum)
                }
                try file.seek(toOffset: 0)
            }
            defer { try? input?.close() }
            var body = vint(2) + vint(2) // File headers declare a data area, also for zero-length directories.
            body += vint(UInt64(size))
            body += vint(directory ? 1 : 4) + vint(UInt64(size)) + vint(directory ? 0o40755 : 0o100644)
            if !directory { body += little(checksum ^ 0xffffffff) }
            body += vint(0) + vint(1) + vint(UInt64(nameData.count)) + nameData // Method 0; Unix; UTF-8 name.
            try outputFile.write(contentsOf: header(body))
            if let file = input {
                while true {
                    guard !batch.isCancelled else { throw CancellationError() }
                    let data = try file.read(upToCount: 65536) ?? Data(); if data.isEmpty { break }
                    try outputFile.write(contentsOf: data)
                }
            }
        }
        try outputFile.write(contentsOf: header(Data([5,0,0]))) // End header; not another volume.
    }
}
