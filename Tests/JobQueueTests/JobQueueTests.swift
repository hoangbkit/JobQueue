import Foundation
import Testing
@testable import JobQueue

actor ExecutionRecorder {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }
}

actor ProbeStore {
    private var handlers: [String: @Sendable () async throws -> Void] = [:]

    func set(_ handler: @escaping @Sendable () async throws -> Void, for label: String) {
        handlers[label] = handler
    }

    func run(_ label: String) async throws {
        try await handlers[label]?()
    }
}

enum ProbeError: Error {
    case failed
}

enum RecordedEvent: Equatable {
    case added(UUID)
    case started(UUID)
    case completed(UUID)
    case failed(UUID)
    case cancelled(UUID)
    case removed(UUID)
    case drained
}

func record(_ event: JobQueueEvent) -> RecordedEvent {
    switch event {
    case .jobAdded(let id):
        return .added(id)
    case .jobStarted(let id):
        return .started(id)
    case .jobCompleted(let id):
        return .completed(id)
    case .jobFailed(let id, _):
        return .failed(id)
    case .jobCancelled(let id):
        return .cancelled(id)
    case .jobRemoved(let id):
        return .removed(id)
    case .queueDrained:
        return .drained
    }
}

struct InstantJob: Job {
    let id: UUID
    let payload: String
    var title: String? { "Instant Job" }
    var detail: String? { payload }

    init(_ label: String = "instant") {
        id = UUID()
        payload = label
    }

    func execute() async throws {
        try await Task.sleep(for: .milliseconds(5))
    }
}

struct ProbeJob: Job {
    struct Payload: Codable, Sendable {
        let label: String
    }

    static let store = ProbeStore()

    let id: UUID
    let payload: Payload

    init(_ label: String, handler: @escaping @Sendable () async throws -> Void) async {
        id = UUID()
        payload = Payload(label: label)
        await Self.store.set(handler, for: label)
    }

    func execute() async throws {
        try await Self.store.run(payload.label)
    }
}

@MainActor
func makeQueue(fileURL: URL? = nil) -> (queue: JobQueue, url: URL, registry: JobRegistry) {
    let registry = JobRegistry()
    registry.register(InstantJob.self)
    registry.register(ProbeJob.self)

    let url = fileURL ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).json")

    let queue = JobQueue(
        fileURL: url,
        registry: registry,
        maxRecords: 100,
        autoCleanupEnabled: false
    )

    return (queue, url, registry)
}

func projectTmpJobQueueURL() throws -> URL {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let tmpDirectory = projectRoot.appendingPathComponent("tmp", isDirectory: true)

    try FileManager.default.createDirectory(
        at: tmpDirectory,
        withIntermediateDirectories: true
    )

    return tmpDirectory.appendingPathComponent("jobqueue.json")
}

@MainActor
func waitUntilIdle(_ queue: JobQueue, timeout: Duration = .seconds(2)) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if !queue.isProcessing && queue.activeCount == 0 { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@Suite("JobQueue", .serialized)
struct JobQueueTests {

    @Test("executes jobs one at a time in FIFO order")
    @MainActor func executesSeriallyInFIFOOrder() async throws {
        let (queue, _, _) = makeQueue()
        let recorder = ExecutionRecorder()

        let first = await ProbeJob("first") {
            await recorder.append("first")
            try await Task.sleep(for: .milliseconds(20))
        }
        let second = await ProbeJob("second") {
            await recorder.append("second")
            try await Task.sleep(for: .milliseconds(20))
        }
        let third = await ProbeJob("third") {
            await recorder.append("third")
            try await Task.sleep(for: .milliseconds(20))
        }

        try queue.enqueue(first)
        try queue.enqueue(second)
        try queue.enqueue(third)

        await waitUntilIdle(queue)

        #expect(await recorder.snapshot() == ["first", "second", "third"])
        #expect(queue.records[first.id]?.status == .completed)
        #expect(queue.records[second.id]?.status == .completed)
        #expect(queue.records[third.id]?.status == .completed)
    }

    @Test("saves completed jobs to tmp and restores them on start")
    @MainActor func savesAndRestoresCompletedJobs() async throws {
        let url = try projectTmpJobQueueURL()
        try? FileManager.default.removeItem(at: url)

        let (queue1, _, registry) = makeQueue(fileURL: url)
        let job = InstantJob("persisted")

        try queue1.enqueue(job)
        await waitUntilIdle(queue1)

        #expect(FileManager.default.fileExists(atPath: url.path))

        let queue2 = JobQueue(
            fileURL: url,
            registry: registry,
            maxRecords: 100,
            autoCleanupEnabled: false
        )
        queue2.start()

        let restored = try #require(queue2.records[job.id])
        #expect(restored.typeName == "InstantJob")
        #expect(restored.title == "Instant Job")
        #expect(restored.detail == "persisted")
        #expect(restored.status == .completed)
    }

    @Test("retryAll requeues failed jobs")
    @MainActor func retryAllRequeuesFailedJobs() async throws {
        let (queue, _, _) = makeQueue()

        let job = await ProbeJob("retry-me") {
            throw ProbeError.failed
        }

        try queue.enqueue(job)
        await waitUntilIdle(queue)
        #expect(queue.records[job.id]?.status == .failed)

        await ProbeJob.store.set({
            try await Task.sleep(for: .milliseconds(5))
        }, for: "retry-me")

        queue.retryAll()
        await waitUntilIdle(queue)

        #expect(queue.records[job.id]?.status == .completed)
        #expect(queue.records[job.id]?.error == nil)
    }

    @Test("emits lifecycle events for a completed job")
    @MainActor func emitsEventsForCompletedJob() async throws {
        let (queue, _, _) = makeQueue()
        let job = InstantJob("events")
        var events: [RecordedEvent] = []
        queue.eventHandler = { events.append(record($0)) }

        try queue.enqueue(job)
        await waitUntilIdle(queue)

        #expect(events == [
            .added(job.id),
            .started(job.id),
            .completed(job.id),
            .drained
        ])
    }

    @Test("emits failure event for a failed job")
    @MainActor func emitsEventsForFailedJob() async throws {
        let (queue, _, _) = makeQueue()
        let job = await ProbeJob("event-failure") {
            throw ProbeError.failed
        }
        var events: [RecordedEvent] = []
        queue.eventHandler = { events.append(record($0)) }

        try queue.enqueue(job)
        await waitUntilIdle(queue)

        #expect(events == [
            .added(job.id),
            .started(job.id),
            .failed(job.id),
            .drained
        ])
    }

    @Test("emits cancellation and removal events for a pending job")
    @MainActor func emitsEventsForCancelledAndRemovedJob() async throws {
        let (queue, _, _) = makeQueue()
        let blocker = await ProbeJob("event-blocker") {
            try await Task.sleep(for: .milliseconds(30))
        }
        let pending = InstantJob("cancel-before-execution")
        var events: [RecordedEvent] = []
        queue.eventHandler = { events.append(record($0)) }

        try queue.enqueue(blocker)
        try queue.enqueue(pending)
        queue.cancel(id: pending.id)
        await waitUntilIdle(queue)
        queue.remove(id: pending.id)

        #expect(events == [
            .added(blocker.id),
            .started(blocker.id),
            .added(pending.id),
            .cancelled(pending.id),
            .completed(blocker.id),
            .drained,
            .removed(pending.id),
            .drained
        ])
    }
}
