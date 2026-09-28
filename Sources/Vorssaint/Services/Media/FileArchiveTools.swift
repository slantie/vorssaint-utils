// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Darwin
import SystemArchive

enum FileArchiveFormat: String, CaseIterable { case zip, tar, gzip, rar }
/// Reads data with macOS's libarchive; no shell extraction and no external tool install.
/// Only regular files and directories are accepted. Every result is staged privately.
enum FileArchiveTools {
    static let maxBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let maxEntries = 100_000
    static func components(_ path: String) throws -> [String] {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), path.utf8.count <= 4096 else { throw CocoaError(.fileReadInvalidFileName) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init).filter { $0 != "." }
        guard !parts.isEmpty, !parts.contains(".."), parts.allSatisfy({ $0.utf8.count <= 255 }) else { throw CocoaError(.fileReadInvalidFileName) }
        return parts
    }
    private static func error(_ archive: OpaquePointer) -> Error {
        let detail = archive_error_string(archive).map { String(cString: $0) } ?? CocoaError(.fileReadCorruptFile).localizedDescription
        return NSError(domain: "FileArchive", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }
    private static func validate(_ input: URL) throws {
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard input.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= 512*1024*1024 else { throw CocoaError(.fileReadTooLarge) }
    }
    private static func unpack(_ input: URL, into directory: URL, batch: FileDragBatch, byteLimit: Int64) throws {
        try validate(input)
        guard byteLimit >= 0, byteLimit <= maxBytes else { throw CocoaError(.fileReadTooLarge) }
        guard !batch.isCancelled, let archive = archive_read_new() else { throw CancellationError() }
        defer { archive_read_free(archive) }
        guard archive_read_support_filter_none(archive) == ARCHIVE_OK, archive_read_support_filter_gzip(archive) == ARCHIVE_OK, archive_read_support_format_all(archive) == ARCHIVE_OK,
              archive_read_support_format_raw(archive) == ARCHIVE_OK,
              archive_read_open_filename(archive, input.path, 65536) == ARCHIVE_OK else { throw error(archive) }
        var entry: OpaquePointer?, total: Int64 = 0, count = 0, paths = Set<String>(), createdPaths = Set<String>()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            guard !batch.isCancelled else { throw CancellationError() }
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF { break }
            guard status == ARCHIVE_OK, let entry else { throw error(archive) }
            count += 1; guard count <= maxEntries else { throw CocoaError(.fileReadTooLarge) }
            guard archive_entry_symlink(entry) == nil, archive_entry_hardlink(entry) == nil,
                  archive_entry_filetype(entry) == S_IFREG || archive_entry_filetype(entry) == S_IFDIR else { throw CocoaError(.fileReadUnsupportedScheme) }
            let raw = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry)
            guard let raw, let name = String(validatingCString: raw) else { throw CocoaError(.fileReadInvalidFileName) }
            // Raw GZIP has one data entry rather than a file tree.
            let rawFormat = archive_format(archive) == ARCHIVE_FORMAT_RAW
            guard !rawFormat || (["gz", "gzip"].contains(input.pathExtension.lowercased()) && archive_filter_code(archive, 0) == ARCHIVE_FILTER_GZIP) else { throw CocoaError(.fileReadCorruptFile) }
            let path = rawFormat ? input.deletingPathExtension().lastPathComponent : name
            if path == "." || path == "./" { guard archive_entry_filetype(entry) == S_IFDIR else { throw CocoaError(.fileReadInvalidFileName) }; continue }
            let parts = try components(path), canonical = parts.joined(separator: "/")
            guard paths.insert(canonical).inserted, parts.count <= 128 else { throw CocoaError(.fileReadInvalidFileName) }
            // Bound implicit parent directories too, not just archive headers.
            // Otherwise many deep tiny files can exhaust the inode budget.
            var prefix = ""
            for part in parts {
                prefix = prefix.isEmpty ? part : prefix+"/"+part
                createdPaths.insert(prefix)
                guard createdPaths.count <= maxEntries else { throw CocoaError(.fileReadTooLarge) }
            }
            let target = parts.reduce(directory) { $0.appendingPathComponent($1) }
            if archive_entry_filetype(entry) == S_IFDIR {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true); continue
            }
            let expected = archive_entry_size(entry)
            guard rawFormat || (expected >= 0 && expected <= byteLimit-total) else { throw CocoaError(.fileReadTooLarge) }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Exclusive creation rejects duplicate/case-colliding names on the destination filesystem.
            let descriptor = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
            guard descriptor >= 0 else { throw CocoaError(.fileWriteInvalidFileName) }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            var written: Int64 = 0
            do {
                while true {
                    guard !batch.isCancelled else { throw CancellationError() }
                    let read = buffer.withUnsafeMutableBytes { archive_read_data(archive, $0.baseAddress, $0.count) }
                    guard read >= 0 else { throw error(archive) }
                    if read == 0 { break }
                    total += Int64(read); written += Int64(read)
                    guard total <= byteLimit else { throw CocoaError(.fileReadTooLarge) }
                    try file.write(contentsOf: Data(buffer.prefix(read)))
                }
                try file.close()
                let mode = archive_entry_perm(entry) & 0o777
                try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode == 0 ? 0o644 : mode)], ofItemAtPath: target.path)
            } catch { try? file.close(); throw error }
            // Raw streams may not declare a length; container files must match their declared size.
            guard rawFormat || written == expected else { throw CocoaError(.fileReadCorruptFile) }
        }
        guard count > 0 || (archive_format(archive) != 0 && archive_format(archive) != ARCHIVE_FORMAT_RAW) else { throw CocoaError(.fileReadCorruptFile) }
    }
    static func extract(_ input: URL, batch: FileDragBatch, byteLimit: Int64 = maxBytes) throws -> URL {
        let output = MediaSupport.uniqueOutputURL(for: input, suffix: "-extracted", fileExtension: "")
        let staged = try MediaSupport.temporaryOutputURL(for: output); defer { MediaSupport.discardStagedOutput(staged) }
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try unpack(input, into: staged, batch: batch, byteLimit: byteLimit)
        guard !batch.isCancelled else { throw CancellationError() }
        try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false); return output
    }
    static func convert(_ input: URL, to format: FileArchiveFormat, batch: FileDragBatch) throws -> URL {
        let output = MediaSupport.uniqueOutputURL(for: input, suffix: "-converted", fileExtension: format == .gzip ? "tar.gz" : format.rawValue)
        let staged = try MediaSupport.temporaryOutputURL(for: output); defer { MediaSupport.discardStagedOutput(staged) }
        let tree = staged.deletingLastPathComponent().appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        try unpack(input, into: tree, batch: batch, byteLimit: maxBytes)
        if format == .rar {
            try StoredRARWriter.write(tree: tree, to: staged, batch: batch)
            guard !batch.isCancelled else { throw CancellationError() }
            try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false); return output
        }
        guard let writer = archive_write_new() else { throw CocoaError(.fileWriteUnknown) }; defer { archive_write_free(writer) }
        let formatStatus = format == .zip ? archive_write_set_format_zip(writer) : archive_write_set_format_pax_restricted(writer)
        guard formatStatus == ARCHIVE_OK, format != .gzip || archive_write_add_filter_gzip(writer) == ARCHIVE_OK else { throw error(writer) }
        if format == .zip { guard archive_write_set_format_option(writer, "zip", "hdrcharset", "UTF-8") == ARCHIVE_OK else { throw error(writer) } }
        guard archive_write_open_filename(writer, staged.path) == ARCHIVE_OK else { throw error(writer) }
        guard let contents = FileManager.default.enumerator(atPath: tree.path) else { throw CocoaError(.fileReadUnknown) }
        let chunkSize = 65536
        for case let relative as String in contents {
            guard !batch.isCancelled else { throw CancellationError() }
            let url = tree.appendingPathComponent(relative)
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            guard let entry = archive_entry_new() else { throw CocoaError(.fileWriteUnknown) }
            defer { archive_entry_free(entry) }
            archive_entry_set_pathname_utf8(entry, relative); archive_entry_set_filetype(entry, values.isDirectory == true ? UInt32(S_IFDIR) : UInt32(S_IFREG))
            archive_entry_set_perm(entry, values.isDirectory == true ? 0o755 : 0o644)
            archive_entry_set_size(entry, values.isDirectory == true ? 0 : Int64(values.fileSize ?? 0))
            guard archive_write_header(writer, entry) == ARCHIVE_OK else { throw error(writer) }
            if values.isDirectory != true {
                let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                while true {
                    guard !batch.isCancelled else { throw CancellationError() }
                    let data = try file.read(upToCount: chunkSize) ?? Data(); if data.isEmpty { break }
                    let written = data.withUnsafeBytes { archive_write_data(writer, $0.baseAddress, $0.count) }
                    guard written == data.count else { throw error(writer) }
                }
            }
        }
        guard archive_write_close(writer) == ARCHIVE_OK else { throw error(writer) }
        guard !batch.isCancelled else { throw CancellationError() }
        try MediaSupport.installStagedOutput(staged, at: output, replacingExisting: false); return output
    }
}
