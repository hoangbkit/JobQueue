import Testing
@testable import ConcurrentJobQueue

extension ConcurrentJobQueueTests.Scheduling {
    @Test("preserves FIFO within a type and priority")
    @MainActor func preservesLaneFIFO() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 1)
        let first = ExportJob("first")
        let second = ExportJob("second")
        let third = ExportJob("third")

        try queue.pause()
        try queue.enqueue(first)
        try queue.enqueue(second)
        try queue.enqueue(third)
        try queue.resume()
        await waitUntil { queue.activeCount == 0 }

        let snapshot = await SynthesisJob.probe.snapshot()
        let starts = snapshot.starts
        #expect(starts == [
            "first",
            "second",
            "third"
        ])
    }

    @Test("higher priority receives earlier dispatch without starving other types")
    @MainActor func schedulesByPriorityAndType() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 1)
        let backgroundExport = ExportJob("background-export", priority: .background)
        let urgentSynthesis = SynthesisJob(
            "urgent-synthesis",
            priority: .userInitiated
        )

        try queue.pause()
        try queue.enqueue(backgroundExport)
        try queue.enqueue(urgentSynthesis)
        try queue.resume()
        await waitUntil { queue.activeCount == 0 }

        let snapshot = await SynthesisJob.probe.snapshot()
        let starts = snapshot.starts
        #expect(starts == [
            "urgent-synthesis",
            "background-export"
        ])
    }

    @Test("multiple immediate jobs preserve enqueue order")
    @MainActor func immediateJobsPreserveFIFO() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 1)
        let blocker = SynthesisJob("blocker", durationMilliseconds: 2_000)
        let first = SynthesisJob("immediate-first")
        let second = SynthesisJob("immediate-second")

        try queue.enqueue(blocker)
        await waitUntil { queue.records[blocker.id]?.status == .processing }
        try queue.enqueue(first, startPolicy: .immediate)
        try queue.enqueue(second, startPolicy: .immediate)

        await waitUntil { queue.records[second.id]?.status == .completed }
        try queue.cancel(id: blocker.id)
        await waitUntil { queue.runningCount == 0 }

        let snapshot = await SynthesisJob.probe.snapshot()
        let starts = snapshot.starts
        #expect(starts.prefix(3) == ["blocker", "immediate-first", "immediate-second"])
    }

    @Test("weighted priority cycle gives every priority dispatch opportunities")
    @MainActor func followsWeightedPriorityCycle() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 1)

        try queue.pause()
        for index in 1...10 {
            try queue.enqueue(
                ExportJob(
                    "user-\(index)",
                    durationMilliseconds: 1,
                    priority: .userInitiated
                )
            )
            try queue.enqueue(
                ExportJob(
                    "default-\(index)",
                    durationMilliseconds: 1,
                    priority: .default
                )
            )
            try queue.enqueue(
                ExportJob(
                    "utility-\(index)",
                    durationMilliseconds: 1,
                    priority: .utility
                )
            )
            try queue.enqueue(
                ExportJob(
                    "background-\(index)",
                    durationMilliseconds: 1,
                    priority: .background
                )
            )
        }
        try queue.resume()

        await waitUntil(timeout: .seconds(15)) { queue.activeCount == 0 }
        #expect(queue.activeCount == 0)
        #expect(queue.runningCount == 0)
        let snapshot = await SynthesisJob.probe.snapshot()
        let starts = snapshot.starts
        let firstCycle = Array(starts.prefix(15))

        #expect(firstCycle.filter { $0.hasPrefix("user-") }.count == 8)
        #expect(firstCycle.filter { $0.hasPrefix("default-") }.count == 4)
        #expect(firstCycle.filter { $0.hasPrefix("utility-") }.count == 2)
        #expect(firstCycle.filter { $0.hasPrefix("background-") }.count == 1)
    }

    @Test("rotates across eligible job types at the same priority")
    @MainActor func rotatesAcrossTypes() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 1)

        try queue.pause()
        try queue.enqueue(DownloadModelJob("rotation", priority: .default))
        try queue.enqueue(ExportJob("export-rotation", priority: .default))
        try queue.enqueue(SynthesisJob("synthesis-rotation", priority: .default))
        try queue.enqueue(DownloadModelJob("rotation-2", priority: .default))
        try queue.enqueue(ExportJob("export-rotation-2", priority: .default))
        try queue.enqueue(SynthesisJob("synthesis-rotation-2", priority: .default))
        try queue.resume()

        await waitUntil { queue.activeCount == 0 }
        let snapshot = await SynthesisJob.probe.snapshot()
        let starts = snapshot.starts

        #expect(Set(starts.prefix(3)) == [
            "download-rotation",
            "export-rotation",
            "synthesis-rotation"
        ])
        #expect(Set(starts.suffix(3)) == [
            "download-rotation-2",
            "export-rotation-2",
            "synthesis-rotation-2"
        ])
    }

    @Test("blocked synthesis lane does not stall an eligible export")
    @MainActor func skipsBlockedType() async throws {
        await SynthesisJob.probe.reset()
        let (queue, _, _) = try makeQueue(globalLimit: 2)
        let running = SynthesisJob("running", durationMilliseconds: 120)
        let blocked = SynthesisJob("blocked", durationMilliseconds: 20)
        let export = ExportJob("eligible-export", durationMilliseconds: 20)

        try queue.enqueue(running)
        try queue.enqueue(blocked)
        try queue.enqueue(export)

        await waitUntil { queue.records[export.id]?.status == .completed }
        #expect(queue.records[blocked.id]?.status == .pending)
        await waitUntil { queue.activeCount == 0 }
    }
}
