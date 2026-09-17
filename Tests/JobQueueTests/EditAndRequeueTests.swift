import Testing
@testable import ConcurrentJobQueue

extension ConcurrentJobQueueTests.ActionsAndProgress {
    @Test("failed app job can be edited and requeued")
    @MainActor func replacesFailedJob() async throws {
        let (queue, _, _) = try makeQueue(globalLimit: 1)
        let original = FailingExportJob("failed-edit")

        try queue.enqueue(original)
        await waitUntil { queue.records[original.id]?.status == .failed }
        try queue.pause()

        let failed = try #require(queue.records[original.id])
        #expect(
            queue.availableActions(for: failed, allowsEditing: true)
                == [.editAndRequeue, .retry, .remove]
        )

        let replacement = DownloadModelJob("fixed-model")
        let replacementID = try queue.replace(id: original.id, with: replacement)

        #expect(replacementID == replacement.id)
        #expect(queue.records[original.id] == nil)

        let replacementRecord = try #require(queue.records[replacementID])
        #expect(replacementRecord.status == .pending)
        #expect(
            try replacementRecord.decode(DownloadModelJob.self).payload.modelID
                == "fixed-model"
        )
    }

    @Test("cancelled app job can be edited and requeued")
    @MainActor func replacesCancelledJob() throws {
        let (queue, _, _) = try makeQueue(globalLimit: 1)
        try queue.pause()

        let original = DownloadModelJob("cancelled-edit")
        try queue.enqueue(original)
        try queue.cancel(id: original.id)

        let cancelled = try #require(queue.records[original.id])
        #expect(cancelled.status == .cancelled)
        #expect(
            queue.availableActions(for: cancelled, allowsEditing: true)
                == [.editAndRequeue, .retry, .remove]
        )

        let replacement = DownloadModelJob("replacement-model")
        let replacementID = try queue.replace(id: original.id, with: replacement)

        #expect(replacementID == replacement.id)
        #expect(queue.records[original.id] == nil)

        let replacementRecord = try #require(queue.records[replacementID])
        #expect(replacementRecord.status == .pending)
        #expect(
            try replacementRecord.decode(DownloadModelJob.self).payload.modelID
                == "replacement-model"
        )
    }
}
