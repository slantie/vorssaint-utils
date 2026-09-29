// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

enum FileJobWorkspaceTests {
    private static func finish(_ model: FileJobWorkspaceModel) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while model.busy && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
        return !model.busy
    }
    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-file-jobs-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            defer { try? FileManager.default.removeItem(at:folder) }
            let good = folder.appendingPathComponent("good.png"), bad = folder.appendingPathComponent("bad.png")
            try ImageFileToolTests.fixture(good,red:true); try Data("not an image".utf8).write(to:bad)
            var published: [URL] = [], successfulFinishes = 0
            let model = try FileJobWorkspaceModel(inputs:[good,bad],action:.convert(.pdf),engines:nil,available:{ true },publish:{ published += $0 },didFinishSuccessfully:{ successfulFinishes += 1 })
            model.run()
            suite.expect(finish(model) && model.completed == 2 && model.total == 2 && published.count == 1 && model.hasFailures,"Conversion workspace reports per-file partial success and errors through actual exports")
            suite.expect(successfulFinishes == 0,"Partial conversion failures retain the workspace for retry")
            guard let firstOutput = published.first else { return }
            try ImageFileToolTests.fixture(bad,red:false); model.run(retryFailures:true)
            suite.expect(finish(model) && model.total == 1 && published.count == 2 && !model.hasFailures && published[0] == firstOutput && FileManager.default.fileExists(atPath:firstOutput.path),"Retry converts only failed inputs and retains the earlier successful output")
            suite.expect(successfulFinishes == 1,"A successful retry dismisses the workspace once all rows are saved")
            let text = folder.appendingPathComponent("notes.txt")
            try Data("First line\nSecond line".utf8).write(to:text)
            var textOutputs: [URL] = [], textFinishes = 0
            let textModel = try FileJobWorkspaceModel(inputs:[text],action:.convert(.pdf),engines:nil,available:{ true },publish:{ textOutputs = $0 },didFinishSuccessfully:{ textFinishes += 1 })
            textModel.run()
            suite.expect(finish(textModel) && textFinishes == 1 && textOutputs.count == 1
                         && FileManager.default.fileExists(atPath:textOutputs[0].path),"TXT to PDF dismisses only after its output is saved")
            let lateInput = folder.appendingPathComponent("late.png"); try ImageFileToolTests.fixture(lateInput,red:true)
            let expected = FileDragFormat.uniqueOutputURL(for:lateInput,format:.pdf)
            var latePublished = 0, lateFinishes = 0
            let late = try FileJobWorkspaceModel(inputs:[lateInput],action:.convert(.pdf),engines:nil,available:{ true },publish:{ latePublished += $0.count },didFinishSuccessfully:{ lateFinishes += 1 })
            late.run()
            let deadline = Date().addingTimeInterval(5)
            // Hold the main queue until encoding finishes, reproducing the owner's
            // cancellation-after-encoding/before-presentation review case.
            while !FileManager.default.fileExists(atPath:expected.path) && Date() < deadline { Thread.sleep(forTimeInterval:0.005) }
            let encoded = FileManager.default.fileExists(atPath:expected.path)
            late.cancel()
            suite.expect(encoded && finish(late) && latePublished == 0 && late.rows[0].state == .cancelled,"Cancellation after file publication suppresses queued success/reveal callbacks")
            suite.expect(lateFinishes == 0,"Cancellation suppresses automatic workspace dismissal")
            var available = true, suppressed = 0, disabledFinishes = 0
            let disabledInput = folder.appendingPathComponent("disabled.png"); try ImageFileToolTests.fixture(disabledInput,red:true)
            let disabledOutput = FileDragFormat.uniqueOutputURL(for:disabledInput,format:.pdf)
            let disabled = try FileJobWorkspaceModel(inputs:[disabledInput],action:.convert(.pdf),engines:nil,available:{ available },publish:{ suppressed += $0.count },didFinishSuccessfully:{ disabledFinishes += 1 })
            disabled.run(); let disableDeadline = Date().addingTimeInterval(5)
            while !FileManager.default.fileExists(atPath:disabledOutput.path) && Date() < disableDeadline { Thread.sleep(forTimeInterval:0.005) }
            available = false
            suite.expect(finish(disabled) && suppressed == 0,"Feature disablement after encoding suppresses queued conversion presentation")
            suite.expect(disabledFinishes == 0,"Feature disablement suppresses automatic workspace dismissal")
        } catch { suite.expect(false,"Conversion workspace fixtures: \(error)") }
    }
}
