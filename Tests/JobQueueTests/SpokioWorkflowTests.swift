import Testing
@testable import JobQueue

extension ConcurrentJobQueueTests.SpokioWorkflows {
    @Test("runs a creator workflow without letting synthesis monopolize the queue")
    @MainActor func runsMixedCreatorWorkflow() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 5)

        for chapter in 1...6 {
            try queue.enqueue(
                SynthesisJob(
                    "chapter-\(chapter)",
                    durationMilliseconds: 80,
                    priority: .background
                )
            )
        }
        try queue.enqueue(DownloadModelJob("narrator", durationMilliseconds: 80))
        try queue.enqueue(DownloadModelJob("guest", durationMilliseconds: 80))
        try queue.enqueue(ImportTextFileJob("chapter-1.txt", durationMilliseconds: 80))
        try queue.enqueue(ExportJob("chapter-preview", durationMilliseconds: 80))

        await waitUntil { queue.activeCount == 0 && queue.runningCount == 0 }

        let snapshot = await SynthesisJob.probe.snapshot()
        #expect(snapshot.maximumByKind["synthesis"] == 1)
        #expect(snapshot.maximumByKind["download"] == 2)
        #expect(snapshot.maximumActiveCount >= 4)
        #expect(snapshot.finishes.contains("chapter-preview"))
        #expect(snapshot.finishes.contains("download-narrator"))
        #expect(snapshot.finishes.contains("import-chapter-1.txt"))
    }

    @Test("editor preview displaces synthesis but leaves download and export running")
    @MainActor func editorPreviewOnlyDisplacesSynthesis() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 4)
        let audiobook = SynthesisJob(
            "audiobook-background",
            durationMilliseconds: 2_000,
            priority: .background
        )
        let download = DownloadModelJob(
            "voice-model",
            durationMilliseconds: 250
        )
        let export = ExportJob(
            "existing-export",
            durationMilliseconds: 250
        )
        let preview = SynthesisJob(
            "editor-preview",
            durationMilliseconds: 20,
            priority: .userInitiated
        )
        await SynthesisJob.probe.setCancellationDelay(
            .milliseconds(80),
            for: "audiobook-background"
        )

        try queue.enqueue(audiobook)
        try queue.enqueue(download)
        try queue.enqueue(export)
        await waitUntil {
            queue.records[audiobook.id]?.status == .processing &&
            queue.records[download.id]?.status == .processing &&
            queue.records[export.id]?.status == .processing
        }

        try queue.enqueue(preview, startPolicy: .immediate)

        #expect(queue.records[audiobook.id]?.status == .pausing)
        #expect(queue.records[download.id]?.status == .processing)
        #expect(queue.records[export.id]?.status == .processing)

        await waitUntil { queue.records[preview.id]?.status == .completed }
        try queue.cancel(id: audiobook.id)
        await waitUntil { queue.runningCount == 0 }

        let snapshot = await SynthesisJob.probe.snapshot()
        #expect(snapshot.cancellations.contains("audiobook-background"))
        #expect(!snapshot.cancellations.contains("download-voice-model"))
        #expect(!snapshot.cancellations.contains("existing-export"))
    }

    @Test("folder synthesis imports files concurrently and synthesizes serially")
    @MainActor func synthesizesFolderOfTextFiles() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 6)

        for index in 1...8 {
            try queue.enqueue(
                ImportTextFileJob(
                    "chapter-\(index).txt",
                    durationMilliseconds: 40
                )
            )
            try queue.enqueue(
                SynthesisJob(
                    "folder-chapter-\(index)",
                    durationMilliseconds: 25,
                    priority: .background
                )
            )
        }

        await waitUntil { queue.activeCount == 0 && queue.runningCount == 0 }

        let snapshot = await SynthesisJob.probe.snapshot()
        #expect(snapshot.maximumByKind["import"] == 4)
        #expect(snapshot.maximumByKind["synthesis"] == 1)
        #expect(snapshot.starts.filter { $0.hasPrefix("folder-chapter-") }.count == 8)
        #expect(snapshot.starts.filter { $0.hasPrefix("import-chapter-") }.count == 8)
    }

    @Test("failed export does not stop unrelated workflow jobs")
    @MainActor func isolatesWorkflowFailure() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 3)
        let failed = FailingExportJob("mp3")
        let synthesis = SynthesisJob("voiceover")
        let download = DownloadModelJob("fallback")

        try queue.enqueue(failed)
        try queue.enqueue(synthesis)
        try queue.enqueue(download)

        await waitUntil { queue.activeCount == 0 && queue.runningCount == 0 }

        #expect(queue.records[failed.id]?.status == .failed)
        #expect(queue.records[synthesis.id]?.status == .completed)
        #expect(queue.records[download.id]?.status == .completed)
    }
}
