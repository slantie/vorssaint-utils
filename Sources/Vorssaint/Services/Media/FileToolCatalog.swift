// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

enum FileToolCatalog {
    static func actions(for inputs: [URL], enginesAvailable: Bool) -> [FileDragAction] {
        guard let first = inputs.first, let kind = FileDragFormat.inputKind(for:first), inputs.allSatisfy({ FileDragFormat.inputKind(for:$0) == kind }) else { return [] }
        var result: [FileDragAction]
        switch kind {
        case .image:
            guard !inputs.contains(where:{ $0.pathExtension.lowercased() == "svg" }) else { return [] }
            result = ImageFileTool.allCases.map { .imageTool($0) }; result.append(.readImageQR)
        case .video,.audio:
            guard enginesAvailable else { return [] }
            result = AVFileTool.allCases.filter { $0.isVideo == (kind == .video) }.filter { $0 != .videoJoin || inputs.count > 1 }.map { .avTool($0) }
        case .document: return PDFTool.allCases.filter { $0 != .merge || inputs.count > 1 }.map { .pdfTool($0) }
        case .archive: return [.extractArchive]
        case .text,.subtitle: return []
        }
        if inputs.count == 1 { result.append(.metadata) }
        return result
    }
}
