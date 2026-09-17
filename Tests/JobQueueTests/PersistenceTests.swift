import Foundation
import Testing
@testable import JobQueue

extension JobQueueTests.Persistence {
    @Test("migrates serial records with sensible defaults")
    @MainActor func migratesSerialRecords() async throws {
        await SynthesisJob.probe.reset()
        let (queue, url, _) = try makeQueue(globalLimit: 1)
        let job = SynthesisJob("legacy")
        let now = Date()
        let legacy = LegacyRecord(
            id: job.id,
            typeName: "SynthesisJob",
            title: nil,
            detail: nil,
            status: "processing",
            error: nil,
            createdAt: now,
            updatedAt: now,
            startedAt: now,
            completedAt: nil,
            encodedJob: try JSONEncoder().encode(job)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([legacy]).write(to: url, options: .atomic)

        try queue.start()
        await waitUntil { queue.records[job.id]?.status == .completed }

        let record = try #require(queue.records[job.id])
        #expect(record.priority == .default)
        #expect(record.enqueueSequence > 0)
        let migratedJSON = try String(contentsOf: url, encoding: .utf8)
        #expect(migratedJSON.contains("\"priority\""))
        #expect(migratedJSON.contains("\"enqueueSequence\""))
    }

    @Test("does not persist runtime immediate policy")
    @MainActor func immediatePolicyIsRuntimeOnly() async throws {
        await SynthesisJob.probe.reset()
        let (queue, url, _) = try makeQueue(globalLimit: 1)
        try queue.pause()
        try queue.enqueue(
            SynthesisJob("runtime-policy"),
            startPolicy: .immediate
        )

        let json = try String(contentsOf: url, encoding: .utf8)
        #expect(!json.contains("immediate"))
        #expect(!json.contains("startPolicy"))
    }

    @Test("restores every serial transient status safely")
    @MainActor func restoresSerialTransientStatuses() async throws {
        await SynthesisJob.probe.reset()
        let (queue, url, _) = try makeQueue(globalLimit: 2)
        let processing = SynthesisJob("legacy-processing")
        let pausing = SynthesisJob("legacy-pausing")
        let cancelling = SynthesisJob("legacy-cancelling")
        let now = Date()

        try writeLegacyRecords([
            legacyRecord(processing, status: "processing", at: now),
            legacyRecord(pausing, status: "pausing", at: now.addingTimeInterval(1)),
            legacyRecord(cancelling, status: "cancelling", at: now.addingTimeInterval(2))
        ], to: url)

        try queue.start()
        await waitUntil { queue.activeCount == 0 && queue.runningCount == 0 }

        #expect(queue.records[processing.id]?.status == .completed)
        #expect(queue.records[pausing.id]?.status == .completed)
        #expect(queue.records[cancelling.id]?.status == .cancelled)
        let snapshot = await SynthesisJob.probe.snapshot()
        let starts = snapshot.starts
        #expect(starts == ["legacy-processing", "legacy-pausing"])
    }

    @Test("pause gates clear after application restart")
    @MainActor func pauseStateIsRuntimeOnly() async throws {
        await SynthesisJob.probe.reset()
        let (queue1, url, registry) = try makeQueue(globalLimit: 1)
        let job = SynthesisJob("resume-after-relaunch")

        try queue1.pause(SynthesisJob.self)
        try queue1.enqueue(job)
        #expect(queue1.records[job.id]?.status == .pending)

        let queue2 = JobQueue(
            fileURL: url,
            policy: JobQueuePolicy(maxConcurrentExecutions: 1),
            registry: registry,
            maxRecords: 1_000,
            autoCleanupEnabled: false
        )
        try queue2.start()
        await waitUntil { queue2.records[job.id]?.status == .completed }

        #expect(queue2.pausedJobTypeNames.isEmpty)
        #expect(!queue2.isPaused)
    }

    @Test("immediate ordering advantage clears after restart")
    @MainActor func immediateOrderingClearsAfterRestart() async throws {
        await SynthesisJob.probe.reset()
        let (queue1, url, registry) = try makeQueue(globalLimit: 1)
        let scheduled = SynthesisJob("scheduled-first")
        let immediate = SynthesisJob("runtime-immediate")

        try queue1.pause()
        try queue1.enqueue(scheduled)
        try queue1.enqueue(immediate, startPolicy: .immediate)

        let queue2 = JobQueue(
            fileURL: url,
            policy: JobQueuePolicy(maxConcurrentExecutions: 1),
            registry: registry,
            maxRecords: 1_000,
            autoCleanupEnabled: false
        )
        try queue2.start()
        await waitUntil { queue2.activeCount == 0 }

        let snapshot = await SynthesisJob.probe.snapshot()
        let starts = snapshot.starts
        #expect(starts == [
            "scheduled-first",
            "runtime-immediate"
        ])
    }

    @Test("preserves job priority and encoded app payload across relaunch")
    @MainActor func preservesPriorityAndPayload() async throws {
        let (queue1, url, registry) = try makeQueue(globalLimit: 1)
        let job = DownloadModelJob(
            "creator-voice",
            priority: .userInitiated
        )

        try queue1.pause()
        try queue1.enqueue(job)

        let queue2 = JobQueue(
            fileURL: url,
            policy: JobQueuePolicy(maxConcurrentExecutions: 1),
            registry: registry,
            maxRecords: 1_000,
            autoCleanupEnabled: false
        )
        try queue2.start()
        let restored = try #require(queue2.records[job.id])
        let decoded = try restored.decode(DownloadModelJob.self)

        #expect(restored.priority == .userInitiated)
        #expect(decoded.payload.modelID == "creator-voice")
        await waitUntil { queue2.records[job.id]?.status == .completed }
    }

    @Test("unregistered legacy app job becomes unrecoverable")
    @MainActor func unregisteredTypeBecomesUnrecoverable() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        let job = SynthesisJob("removed-app-job")
        let now = Date()
        var record = try legacyRecord(job, status: "pending", at: now)
        record = LegacyRecord(
            id: record.id,
            typeName: "RemovedSynthesisJob",
            title: record.title,
            detail: record.detail,
            status: record.status,
            error: record.error,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            startedAt: record.startedAt,
            completedAt: record.completedAt,
            encodedJob: record.encodedJob
        )
        try writeLegacyRecords([record], to: url)

        let queue = JobQueue(
            fileURL: url,
            policy: JobQueuePolicy(maxConcurrentExecutions: 1),
            registry: JobRegistry()
        )
        try queue.start()

        #expect(queue.records[job.id]?.status == .unrecoverable)
        #expect(queue.records[job.id]?.error?.contains("RemovedSynthesisJob") == true)
    }
}

private struct LegacyRecord: Codable {
    let id: UUID
    let typeName: String
    let title: String?
    let detail: String?
    let status: String
    let error: String?
    let createdAt: Date
    let updatedAt: Date
    let startedAt: Date?
    let completedAt: Date?
    let encodedJob: Data
}

private func legacyRecord<J: Job>(
    _ job: J,
    status: String,
    at date: Date
) throws -> LegacyRecord {
    LegacyRecord(
        id: job.id,
        typeName: String(describing: J.self),
        title: job.title,
        detail: job.detail,
        status: status,
        error: nil,
        createdAt: date,
        updatedAt: date,
        startedAt: status == "processing" ||
            status == "pausing" ||
            status == "cancelling" ? date : nil,
        completedAt: nil,
        encodedJob: try JSONEncoder().encode(job)
    )
}

private func writeLegacyRecords(
    _ records: [LegacyRecord],
    to url: URL
) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(records).write(to: url, options: .atomic)
}
