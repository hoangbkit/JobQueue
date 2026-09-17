import Foundation
import Testing
@testable import JobQueue

extension JobQueueTests.Durability {
    @Test("enqueue save failure preserves the previous durable queue")
    @MainActor func enqueueSaveFailureRollsBack() async throws {
        await SynthesisJob.probe.reset()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("queue.json")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let (queue, _, _) = try makeQueue(fileURL: url, globalLimit: 1)
        let persisted = ExportJob("persisted")
        let rejected = ExportJob("rejected")

        try queue.pause()
        try queue.enqueue(persisted)
        try FileManager.default.removeItem(at: directory)
        try Data("blocks-directory".utf8).write(to: directory)

        #expect(throws: JobQueueError.self) {
            try queue.enqueue(rejected)
        }
        #expect(queue.records[persisted.id] != nil)
        #expect(queue.records[rejected.id] == nil)
        if case .saveFailed = queue.persistenceIssue {
            // Expected.
        } else {
            Issue.record("Expected save failure.")
        }
    }

    @Test("completion save failure blocks later app work until retry")
    @MainActor func completionFailureBlocksAdvancement() async throws {
        await SynthesisJob.probe.reset()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("queue.json")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let (queue, _, _) = try makeQueue(fileURL: url, globalLimit: 1)
        let first = ExportJob("finishes-before-save-failure", durationMilliseconds: 100)
        let second = ExportJob("blocked-after-save-failure")

        try queue.enqueue(first)
        try queue.enqueue(second)
        await waitUntil { queue.records[first.id]?.status == .processing }
        try FileManager.default.removeItem(at: directory)
        try Data("blocks-directory".utf8).write(to: directory)

        await waitUntil {
            queue.records[first.id]?.status == .completed &&
            queue.runningCount == 0
        }

        #expect(queue.records[second.id]?.status == .pending)
        let snapshot = await SynthesisJob.probe.snapshot()
        let starts = snapshot.starts
        #expect(!starts.contains("blocked-after-save-failure"))

        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try queue.perform(.retryPersistence)
        await waitUntil { queue.records[second.id]?.status == .completed }
    }

    @Test("corrupted storage exposes reset recovery and remains usable")
    @MainActor func resetsCorruptedStorage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("queue.json")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: url)
        let (queue, _, _) = try makeQueue(fileURL: url)

        #expect(throws: JobQueueError.self) {
            try queue.start()
        }
        #expect(queue.availableActions == [
            .retryPersistence,
            .resetPersistence
        ])

        try queue.perform(.resetPersistence)
        let job = ExportJob("after-reset")
        try queue.enqueue(job)
        await waitUntil { queue.records[job.id]?.status == .completed }
    }

    @Test("auto cleanup removes old terminal records but preserves active work")
    @MainActor func autoCleanupPreservesActiveWork() async throws {
        await SynthesisJob.probe.reset()
        let registry = JobRegistry()
        try registry.register(SynthesisJob.self)
        try registry.register(ExportJob.self)
        let queue = JobQueue(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).json"),
            policy: JobQueuePolicy(maxConcurrentExecutions: 2),
            registry: registry,
            maxRecords: 2,
            autoCleanupEnabled: true
        )
        let completed = ExportJob("old-completed")
        let active = SynthesisJob("active", durationMilliseconds: 2_000)
        let trigger = ExportJob("cleanup-trigger")

        try queue.enqueue(completed)
        await waitUntil { queue.records[completed.id]?.status == .completed }
        try queue.enqueue(active)
        await waitUntil { queue.records[active.id]?.status == .processing }
        try queue.enqueue(trigger)

        #expect(queue.records[completed.id] == nil)
        #expect(queue.records[active.id]?.status == .processing)
        #expect(queue.records[trigger.id] != nil)

        try queue.cancelAll()
        await waitUntil { queue.runningCount == 0 }
    }
}
