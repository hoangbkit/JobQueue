import Testing
@testable import ConcurrentJobQueue

extension ConcurrentJobQueueTests.Execution {
    @Test("enforces global and per-type concurrency limits")
    @MainActor func enforcesConcurrencyLimits() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 3)

        try queue.enqueue(SynthesisJob("synthesis-1", durationMilliseconds: 80))
        try queue.enqueue(SynthesisJob("synthesis-2", durationMilliseconds: 80))
        try queue.enqueue(ExportJob("export-1", durationMilliseconds: 80))
        try queue.enqueue(ExportJob("export-2", durationMilliseconds: 80))
        try queue.enqueue(ExportJob("export-3", durationMilliseconds: 80))

        await waitUntil { queue.activeCount == 0 && queue.runningCount == 0 }

        let snapshot = await SynthesisJob.probe.snapshot()
        #expect(snapshot.maximumActiveCount == 3)
        #expect(snapshot.maximumByKind["synthesis"] == 1)
        #expect(snapshot.maximumByKind["export"] == 2)
    }

    @Test("immediate work displaces the most recently started same-type job")
    @MainActor func immediateDisplacesSameTypeWork() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 3)
        let background = SynthesisJob(
            "background",
            durationMilliseconds: 2_000,
            priority: .background
        )
        let urgent = SynthesisJob(
            "urgent",
            durationMilliseconds: 20,
            priority: .userInitiated
        )
        await SynthesisJob.probe.setCancellationDelay(
            .milliseconds(80),
            for: "background"
        )

        try queue.enqueue(background)
        await waitUntil { queue.records[background.id]?.status == .processing }
        try queue.enqueue(urgent, startPolicy: .immediate)

        #expect(queue.records[background.id]?.status == .pausing)
        #expect(queue.records[urgent.id]?.status == .pending)
        #expect(queue.runningCount == 1)

        await waitUntil { queue.records[urgent.id]?.status == .completed }
        await waitUntil { queue.records[background.id]?.status == .processing }
        try queue.cancel(id: background.id)
        await waitUntil { queue.runningCount == 0 }

        let snapshot = await SynthesisJob.probe.snapshot()
        #expect(snapshot.maximumByKind["synthesis"] == 1)
        #expect(snapshot.starts.prefix(3) == ["background", "urgent", "background"])
    }

    @Test("pausing one type allows other types to continue")
    @MainActor func pausesOneType() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 3)
        let synthesis = SynthesisJob("paused-synthesis", durationMilliseconds: 2_000)
        let export = ExportJob("continuing-export", durationMilliseconds: 20)

        try queue.enqueue(synthesis)
        await waitUntil { queue.records[synthesis.id]?.status == .processing }
        try queue.pause(SynthesisJob.self)
        try queue.enqueue(export)

        await waitUntil { queue.records[export.id]?.status == .completed }
        await waitUntil { queue.records[synthesis.id]?.status == .pending }
        #expect(queue.pausedJobTypeNames.contains("SynthesisJob"))

        try queue.resume(SynthesisJob.self)
        await waitUntil { queue.records[synthesis.id]?.status == .processing }
        try queue.cancel(id: synthesis.id)
        await waitUntil { queue.runningCount == 0 }
    }

    @Test("slow pausing synthesis retains its type slot until execution exits")
    @MainActor func slowPauseRetainsSlot() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 3)
        let background = SynthesisJob(
            "slow-cancel",
            durationMilliseconds: 2_000
        )
        let preview = SynthesisJob("next-preview", durationMilliseconds: 20)
        await SynthesisJob.probe.setCancellationDelay(
            .milliseconds(120),
            for: "slow-cancel"
        )

        try queue.enqueue(background)
        await waitUntil { queue.records[background.id]?.status == .processing }
        try queue.enqueue(preview, startPolicy: .immediate)

        try? await Task.sleep(for: .milliseconds(40))
        #expect(queue.records[preview.id]?.status == .pending)
        #expect(queue.runningCount == 1)

        await waitUntil { queue.records[preview.id]?.status == .completed }
        try queue.cancel(id: background.id)
        await waitUntil { queue.runningCount == 0 }

        let snapshot = await SynthesisJob.probe.snapshot()
        #expect(snapshot.maximumByKind["synthesis"] == 1)
    }

    @Test("queue pause stops dispatch and resume restarts all recoverable work")
    @MainActor func pausesAndResumesWholeQueue() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 4)
        let synthesis = SynthesisJob("queue-pause-synthesis", durationMilliseconds: 2_000)
        let download = DownloadModelJob("queue-pause-model", durationMilliseconds: 2_000)
        let pendingExport = ExportJob("after-resume")

        try queue.enqueue(synthesis)
        try queue.enqueue(download)
        await waitUntil { queue.runningCount == 2 }
        try queue.pause()
        try queue.enqueue(pendingExport)

        await waitUntil {
            queue.runningCount == 0 &&
            queue.records[synthesis.id]?.status == .pending &&
            queue.records[download.id]?.status == .pending
        }
        #expect(queue.isPaused)
        #expect(queue.records[pendingExport.id]?.status == .pending)

        try queue.resume()
        await waitUntil { queue.records[pendingExport.id]?.status == .completed }
        try queue.cancelAll()
        await waitUntil { queue.runningCount == 0 }
    }

    @Test("job completing while pause unwinds remains completed")
    @MainActor func completionDuringPauseRemainsCompleted() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 2)
        let job = SynthesisJob(
            "ignores-pause",
            durationMilliseconds: 80,
            ignoresCancellation: true
        )

        try queue.enqueue(job)
        await waitUntil { queue.records[job.id]?.status == .processing }
        try queue.pause(SynthesisJob.self)
        await waitUntil { queue.runningCount == 0 }

        #expect(queue.records[job.id]?.status == .completed)
        #expect(queue.pausedJobTypeNames.contains("SynthesisJob"))
    }

    @Test("immediate pauses the most recently started execution at a type limit")
    @MainActor func immediatePausesMostRecentExecution() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 4)
        let first = ExportJob("older-export", durationMilliseconds: 2_000)
        let second = ExportJob("newer-export", durationMilliseconds: 2_000)
        let immediate = ExportJob("urgent-export", durationMilliseconds: 20)

        try queue.enqueue(first)
        await waitUntil { queue.records[first.id]?.status == .processing }
        try queue.enqueue(second)
        await waitUntil { queue.records[second.id]?.status == .processing }
        try queue.enqueue(immediate, startPolicy: .immediate)

        #expect(queue.records[first.id]?.status == .processing)
        #expect(queue.records[second.id]?.status == .pausing)
        #expect(queue.records[immediate.id]?.status == .pending)

        await waitUntil { queue.records[immediate.id]?.status == .completed }
        try queue.cancelAll()
        await waitUntil { queue.runningCount == 0 }
    }
}
