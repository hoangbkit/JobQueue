import Testing
@testable import ConcurrentJobQueue

extension ConcurrentJobQueueTests.ActionsAndProgress {
    @Test("tracks progress for multiple active app jobs")
    @MainActor func tracksConcurrentProgress() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 3)
        let first = DownloadModelJob(
            "english",
            durationMilliseconds: 120,
            reportsProgress: true
        )
        let second = DownloadModelJob(
            "vietnamese",
            durationMilliseconds: 120,
            reportsProgress: true
        )

        try queue.enqueue(first)
        try queue.enqueue(second)
        await waitUntil {
            queue.progress(for: first.id)?.fractionCompleted == 0.25 &&
            queue.progress(for: second.id)?.fractionCompleted == 0.25
        }

        #expect(queue.runningCount == 2)
        #expect(queue.progress(for: first.id)?.message == "Downloading model")
        #expect(queue.progress(for: second.id)?.message == "Downloading model")

        await waitUntil { queue.activeCount == 0 }
        #expect(queue.progress(for: first.id) == .completed)
        #expect(queue.progress(for: second.id) == .completed)
    }

    @Test("failed app job can be retried and does not hide queue actions")
    @MainActor func exposesRetryActions() async throws {
        let (queue, _, _) = try makeQueue(globalLimit: 2)
        let failed = FailingExportJob("retry-export")

        try queue.enqueue(failed)
        await waitUntil { queue.records[failed.id]?.status == .failed }

        let record = try #require(queue.records[failed.id])
        #expect(queue.availableActions.contains(.retryAll))
        #expect(queue.availableActions(for: record) == [.retry, .remove])
    }

    @Test("pending app job can be edited and requeued")
    @MainActor func replacesPendingJob() throws {
        let (queue, _, _) = try makeQueue(globalLimit: 1)
        try queue.pause()

        let original = DownloadModelJob("old-model")
        try queue.enqueue(original)

        let pending = try #require(queue.records[original.id])
        #expect(pending.status == .pending)
        #expect(
            queue.availableActions(for: pending, allowsEditing: true)
                == [.editAndRequeue, .cancel]
        )

        let replacement = DownloadModelJob("new-model")
        let replacementID = try queue.replace(id: original.id, with: replacement)

        #expect(replacementID == replacement.id)
        #expect(queue.records[original.id] == nil)

        let replacementRecord = try #require(queue.records[replacementID])
        #expect(replacementRecord.status == .pending)
        #expect(try replacementRecord.decode(DownloadModelJob.self).payload.modelID == "new-model")
    }

    @Test("cancel all cancels pending and every active job")
    @MainActor func cancelsAllConcurrentWork() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 3)
        let synthesis = SynthesisJob("cancel-all-synthesis", durationMilliseconds: 2_000)
        let download = DownloadModelJob("cancel-all-model", durationMilliseconds: 2_000)
        let export = ExportJob("cancel-all-export", durationMilliseconds: 2_000)
        let pending = ImportTextFileJob("pending.txt")

        try queue.enqueue(synthesis)
        try queue.enqueue(download)
        try queue.enqueue(export)
        try queue.enqueue(pending)
        await waitUntil { queue.runningCount == 3 }

        try queue.cancelAll()
        await waitUntil { queue.runningCount == 0 }

        #expect(queue.records[synthesis.id]?.status == .cancelled)
        #expect(queue.records[download.id]?.status == .cancelled)
        #expect(queue.records[export.id]?.status == .cancelled)
        #expect(queue.records[pending.id]?.status == .cancelled)
    }

    @Test("emits lifecycle events for concurrent jobs")
    @MainActor func emitsConcurrentLifecycleEvents() async throws {
        let (queue, _, _) = try makeQueue(globalLimit: 2)
        let synthesis = SynthesisJob("event-synthesis")
        let export = ExportJob("event-export")
        var events: [JobQueueEvent] = []
        queue.eventHandler = { events.append($0) }

        try queue.enqueue(synthesis)
        try queue.enqueue(export)
        await waitUntil { queue.activeCount == 0 }

        #expect(events.contains(.jobAdded(id: synthesis.id)))
        #expect(events.contains(.jobStarted(id: synthesis.id)))
        #expect(events.contains(.jobCompleted(id: synthesis.id)))
        #expect(events.contains(.jobAdded(id: export.id)))
        #expect(events.contains(.jobStarted(id: export.id)))
        #expect(events.contains(.jobCompleted(id: export.id)))
        #expect(events.last == .queueDrained)
    }
}
