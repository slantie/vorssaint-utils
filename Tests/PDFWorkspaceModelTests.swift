// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import PDFKit

enum PDFWorkspaceModelTests {
    private static func finish(_ model: PDFWorkspaceModel) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while model.busy && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return !model.busy
    }

    static func run(_ suite: TestSuite) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-pdf-workspace-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let a = directory.appendingPathComponent("A.pdf"), b = directory.appendingPathComponent("B.pdf")
            try PDFToolTests.fixture(a, labels: ["ALPHA", "BETA", "GAMMA"])
            try PDFToolTests.fixture(b, labels: ["DELTA", "EPSILON"])
            for (url, title, author) in [(a, "First title", "First author"), (b, "Second title", "Second author")] {
                let document = try PDFTools.document(url)
                document.documentAttributes = [PDFDocumentAttribute.titleAttribute: title, PDFDocumentAttribute.authorAttribute: author,
                                               PDFDocumentAttribute.subjectAttribute: title + " subject",
                                               PDFDocumentAttribute.keywordsAttribute: [author + " keyword"]]
                suite.expect(document.write(to: url), "Workspace fixture writes distinct document metadata")
            }
            let originalA = try Data(contentsOf: a), originalB = try Data(contentsOf: b)
            let history = try PDFWorkspaceModel(inputs: [a], tool: .organize, featureAvailable: { true })
            let originalPlan = history.plan
            history.plan.rotate(history.plan.pages[0].id); let rotatedPlan = history.plan
            history.undo()
            suite.expect(history.plan == originalPlan && history.canRedo, "PDF undo restores the page rotation and identity")
            history.redo()
            suite.expect(history.plan == rotatedPlan, "PDF redo restores the exact edited plan")
            try history.append([b]); history.undo()
            suite.expect(history.inputs == [a] && history.plan == rotatedPlan, "Undoing PDF import preserves earlier page edits")
            history.redo()
            suite.expect(history.inputs == [a,b] && history.plan.pages.count == 5, "Redoing PDF import restores document and page order together")
            history.removeDocument(0); history.undo()
            suite.expect(history.inputs == [a,b] && history.plan.pages.count == 5 && history.metadata.title == "First title",
                         "PDF undo restores removed documents together with their own metadata")
            let ranges = try PDFWorkspaceModel(inputs: [a,b], tool: .split, featureAvailable: { true })
            ranges.splitRangeText = "1-2,3-5"
            suite.expect(try PDFTools.splitGroups(ranges.splitRangeText, pageCount: 5) == [[0,1],[2,3,4]], "PDF split ranges parse inclusive one-based page groups")
            suite.expect((try? PDFTools.splitGroups("3-1", pageCount: 5)) == nil && (try? PDFTools.splitGroups("1-6", pageCount: 5)) == nil,
                         "PDF split ranges reject reversed and out-of-document bounds")
            var splitOutputs: [URL] = []
            let splitter = try PDFWorkspaceModel(inputs: [a,b], tool: .split, featureAvailable: { true }, publishOutputs: { splitOutputs = $0 })
            splitter.splitRangeText = "1-2,3-5"; splitter.save()
            suite.expect(finish(splitter) && splitOutputs.count == 1, "PDF range split saves through the asynchronous workspace")
            if let folder = splitOutputs.first {
                let first = try PDFTools.document(folder.appendingPathComponent("Part 0001.pdf")), second = try PDFTools.document(folder.appendingPathComponent("Part 0002.pdf"))
                suite.expect(first.pageCount == 2 && second.pageCount == 3 && first.page(at: 0)?.string?.contains("ALPHA") == true
                             && second.page(at: 0)?.string?.contains("GAMMA") == true && second.page(at: 2)?.string?.contains("EPSILON") == true,
                             "PDF page-range output preserves page contents and group order")
            }
            var outputs: [URL] = []
            let model = try PDFWorkspaceModel(inputs: [a], tool: .organize, featureAvailable: { true }, publishOutputs: { outputs = $0 })
            let alpha = model.plan.pages[0].id, gamma = model.plan.pages[2].id
            model.plan.move(gamma, to: 0); model.plan.rotate(gamma); model.plan.duplicate(gamma); model.plan.remove(alpha)
            model.plan.normalizeWidths = true
            let edited = model.plan.pages
            try model.append([b])
            suite.expect(Array(model.plan.pages.prefix(edited.count)) == edited && model.plan.pages.count == 5,
                         "Adding a PDF preserves edited page identities, order, rotations, duplicates and removals")
            suite.expect(model.plan.pages.suffix(2).map(\.index) == [0, 1]
                         && model.plan.pages.suffix(2).allSatisfy { $0.source == b } && model.plan.normalizeWidths,
                         "Adding a PDF appends only its new pages and retains the export option")
            try model.append([a, b, b])
            suite.expect(model.plan.pages.count == 5 && model.inputs == [a, b],
                         "Adding an already present PDF leaves page edits unchanged")
            let invalid = directory.appendingPathComponent("Invalid.pdf")
            try Data("not a PDF".utf8).write(to: invalid)
            let beforeInvalid = model.plan.pages
            suite.expect((try? model.append([invalid])) == nil && model.plan.pages == beforeInvalid && model.inputs == [a, b],
                         "Invalid additions are rejected without partially changing workspace state")
            model.plan.normalizeWidths = false
            model.save()
            suite.expect((try? model.append([invalid])) == nil && model.busy,
                         "A processing workspace rejects additions before touching the page plan")
            suite.expect(finish(model) && outputs.count == 1, "Edited workspace saves through its asynchronous production path")
            guard let saved = outputs.first else { throw CocoaError(.fileWriteUnknown) }
            let savedDoc = try PDFTools.document(saved)
            let labels = (0..<savedDoc.pageCount).map { savedDoc.page(at: $0)?.string ?? "" }
            suite.expect(labels.count == 5 && labels[0].contains("GAMMA") && labels[1].contains("GAMMA")
                         && labels[2].contains("BETA") && labels[3].contains("DELTA") && labels[4].contains("EPSILON")
                         && !labels.contains(where: { $0.contains("ALPHA") }),
                         "Saved workspace keeps edits made before adding a document; removed pages stay removed")
            suite.expect(savedDoc.page(at: 0)?.rotation == 90 && savedDoc.page(at: 1)?.rotation == 90,
                         "Saved added-document workspace retains page rotations")
            model.moveDocument(b, to: 0)
            suite.expect(model.inputs == [b, a] && model.plan.pages.filter { $0.source == a } == edited,
                         "Document dragging preserves edits within existing page groups")
            model.sortDocuments()
            suite.expect(model.inputs == [a, b] && model.plan.pages.filter { $0.source == a } == edited,
                         "Document name sorting preserves existing page edits")
            model.reset()
            suite.expect(model.plan.pages.count == 5 && Set(model.plan.pages.map(\.id)) == Set(beforeInvalid.map(\.id))
                         && model.plan.pages.filter { $0.source == a }.map(\.index) == [1, 2, 2]
                         && model.plan.pages.filter { $0.source == a && $0.index == 2 }.allSatisfy { $0.quarterTurns == 1 },
                         "Reset order retains rotations, duplicates and removals while restoring page order")

            var metadataOutputs: [URL] = []
            let metadata = try PDFWorkspaceModel(inputs: [a, b], tool: .merge, featureAvailable: { true }, publishOutputs: { metadataOutputs = $0 })
            metadata.metadata.title = "Typed for removed A"
            metadata.metadata.author = "Typed A author"
            metadata.removeDocument(0)
            metadata.tool = .metadata
            suite.expect(metadata.inputs == [b] && metadata.plan.pages.allSatisfy { $0.source == b }
                         && metadata.metadata.title == "Second title" && metadata.metadata.author == "Second author"
                         && metadata.metadata.subject == "Second title subject" && metadata.metadata.keywords == "Second author keyword" && metadata.canSave,
                         "Removing the first document then choosing metadata loads the remaining PDF's own fields")
            metadata.save()
            suite.expect(finish(metadata) && metadataOutputs.count == 1, "Current-document metadata saves through the workspace model")
            guard let metadataCopy = metadataOutputs.first else { throw CocoaError(.fileWriteUnknown) }
            let stored = try PDFTools.metadata(metadataCopy)
            suite.expect(stored.title == "Second title" && stored.author == "Second author"
                         && stored.subject == "Second title subject" && stored.keywords == "Second author keyword",
                         "The saved metadata copy contains no fields from the removed PDF")
            metadata.metadata.title = "User edit for B"
            metadata.tool = .organize; metadata.tool = .metadata
            suite.expect(metadata.metadata.title == "User edit for B", "Switching tools retains unsaved metadata edits for the same document")

            let retained = try PDFWorkspaceModel(inputs: [a], tool: .metadata, featureAvailable: { true })
            retained.metadata.title = "Keep this edit"
            try retained.append([b]); retained.removeDocument(1)
            suite.expect(retained.metadata.title == "Keep this edit" && retained.inputs == [a],
                         "Adding and removing another document does not erase metadata edits for an unchanged source")
            let unreadable = directory.appendingPathComponent("Unreadable.pdf")
            try PDFToolTests.fixture(unreadable, labels: ["TEMPORARY"])
            let failedMetadata = try PDFWorkspaceModel(inputs: [a, unreadable], tool: .merge, featureAvailable: { true })
            try Data("no longer a PDF".utf8).write(to: unreadable)
            failedMetadata.removeDocument(0); failedMetadata.tool = .metadata
            suite.expect(failedMetadata.metadata.title.isEmpty && failedMetadata.metadata.author.isEmpty
                         && !failedMetadata.canSave && failedMetadata.message != nil,
                         "A failed metadata reload clears stale fields and prevents writing them to another source")
            let duplicates = try PDFWorkspaceModel(inputs: [a, a], tool: .merge, featureAvailable: { true })
            duplicates.moveDocument(a, to: 0)
            suite.expect(duplicates.inputs == [a] && duplicates.plan.pages.count == 3,
                         "Repeated input URLs cannot duplicate groups or crash document ordering")

            var cancelledOutputs: [URL] = []
            let cancelled = try PDFWorkspaceModel(inputs: [a], tool: .organize, featureAvailable: { true }, publishOutputs: { cancelledOutputs = $0 })
            cancelled.save(); cancelled.cancel()
            suite.expect(finish(cancelled) && cancelledOutputs.isEmpty && cancelled.message == nil,
                         "Cancelled workspace jobs publish neither outputs nor completion messages")
            var available = true, disabledOutputs: [URL] = []
            let disabled = try PDFWorkspaceModel(inputs: [a], tool: .organize, featureAvailable: { available }, publishOutputs: { disabledOutputs = $0 })
            disabled.save(); available = false
            suite.expect(finish(disabled) && disabledOutputs.isEmpty && !disabled.canSave,
                         "Feature changes suppress workspace publication while a completion is queued")
            suite.expect((try? disabled.append([b])) == nil && disabled.inputs == [a],
                         "Disabled workspaces reject imported files without changing state")
            let afterA = try Data(contentsOf: a), afterB = try Data(contentsOf: b)
            suite.expect(afterA == originalA && afterB == originalB, "Workspace transitions and exports preserve both original PDFs")
        } catch { suite.expect(false, "PDF workspace review fixtures complete: \(error)") }
    }
}
