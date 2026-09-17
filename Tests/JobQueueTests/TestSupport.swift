import Foundation
import Testing
@testable import JobQueue

@Suite("JobQueue", .serialized)
struct JobQueueTests {
    @Suite("Execution")
    struct Execution {}

    @Suite("Scheduling")
    struct Scheduling {}

    @Suite("Persistence")
    struct Persistence {}

    @Suite("Spokio Workflows")
    struct SpokioWorkflows {}

    @Suite("Actions and Progress")
    struct ActionsAndProgress {}

    @Suite("Registry")
    struct Registry {}

    @Suite("Durability")
    struct Durability {}
}

actor ExecutionProbe {
    private var activeCount = 0
    private var maximumActiveCount = 0
    private var activeByKind: [String: Int] = [:]
    private var maximumByKind: [String: Int] = [:]
    private var starts: [String] = []
    private var finishes: [String] = []
    private var cancellations: [String] = []
    private var cancellationDelays: [String: Duration] = [:]

    func reset() {
        activeCount = 0
        maximumActiveCount = 0
        activeByKind = [:]
        maximumByKind = [:]
        starts = []
        finishes = []
        cancellations = []
        cancellationDelays = [:]
    }

    func setCancellationDelay(_ delay: Duration, for label: String) {
        cancellationDelays[label] = delay
    }

    func run(
        label: String,
        kind: String,
        duration: Duration
    ) async throws {
        activeCount += 1
        activeByKind[kind, default: 0] += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        maximumByKind[kind] = max(
            maximumByKind[kind, default: 0],
            activeByKind[kind, default: 0]
        )
        starts.append(label)

        defer {
            activeCount -= 1
            activeByKind[kind, default: 0] -= 1
        }

        do {
            try await Task.sleep(for: duration)
        } catch is CancellationError {
            cancellations.append(label)
            if let delay = cancellationDelays[label] {
                await Task.detached {
                    try? await Task.sleep(for: delay)
                }.value
            }
            throw CancellationError()
        }
        finishes.append(label)
    }

    func runIgnoringCancellation(
        label: String,
        kind: String,
        duration: Duration
    ) async {
        activeCount += 1
        activeByKind[kind, default: 0] += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        maximumByKind[kind] = max(
            maximumByKind[kind, default: 0],
            activeByKind[kind, default: 0]
        )
        starts.append(label)

        await Task.detached {
            try? await Task.sleep(for: duration)
        }.value

        finishes.append(label)
        activeCount -= 1
        activeByKind[kind, default: 0] -= 1
    }

    func snapshot() -> (
        maximumActiveCount: Int,
        maximumByKind: [String: Int],
        starts: [String],
        finishes: [String],
        cancellations: [String]
    ) {
        (
            maximumActiveCount,
            maximumByKind,
            starts,
            finishes,
            cancellations
        )
    }
}

struct SynthesisJob: Job {
    struct Payload: Codable, Sendable {
        let label: String
        let durationMilliseconds: Int
        let priority: JobPriority
        let ignoresCancellation: Bool
    }

    static let probe = ExecutionProbe()
    static let maxConcurrentExecutions = 1

    let id: UUID
    let payload: Payload
    var priority: JobPriority { payload.priority }

    init(
        _ label: String,
        durationMilliseconds: Int = 20,
        priority: JobPriority = .default,
        ignoresCancellation: Bool = false
    ) {
        id = UUID()
        payload = Payload(
            label: label,
            durationMilliseconds: durationMilliseconds,
            priority: priority,
            ignoresCancellation: ignoresCancellation
        )
    }

    func execute() async throws {
        if payload.ignoresCancellation {
            await Self.probe.runIgnoringCancellation(
                label: payload.label,
                kind: "synthesis",
                duration: .milliseconds(payload.durationMilliseconds)
            )
        } else {
            try await Self.probe.run(
                label: payload.label,
                kind: "synthesis",
                duration: .milliseconds(payload.durationMilliseconds)
            )
        }
    }
}

struct ExportJob: Job {
    struct Payload: Codable, Sendable {
        let label: String
        let durationMilliseconds: Int
        let priority: JobPriority
    }

    static let probe = SynthesisJob.probe
    static let maxConcurrentExecutions = 2

    let id: UUID
    let payload: Payload
    var priority: JobPriority { payload.priority }

    init(
        _ label: String,
        durationMilliseconds: Int = 20,
        priority: JobPriority = .default
    ) {
        id = UUID()
        payload = Payload(
            label: label,
            durationMilliseconds: durationMilliseconds,
            priority: priority
        )
    }

    func execute() async throws {
        try await Self.probe.run(
            label: payload.label,
            kind: "export",
            duration: .milliseconds(payload.durationMilliseconds)
        )
    }
}

struct DownloadModelJob: Job {
    struct Payload: Codable, Sendable {
        let modelID: String
        let durationMilliseconds: Int
        let priority: JobPriority
        let reportsProgress: Bool
    }

    static let probe = SynthesisJob.probe
    static let maxConcurrentExecutions = 2

    let id: UUID
    let payload: Payload
    var title: String? { "Download \(payload.modelID)" }
    var priority: JobPriority { payload.priority }

    init(
        _ modelID: String,
        durationMilliseconds: Int = 20,
        priority: JobPriority = .utility,
        reportsProgress: Bool = false
    ) {
        id = UUID()
        payload = Payload(
            modelID: modelID,
            durationMilliseconds: durationMilliseconds,
            priority: priority,
            reportsProgress: reportsProgress
        )
    }

    func execute(progress: JobProgressReporter) async throws {
        if payload.reportsProgress {
            await progress.report(
                fractionCompleted: 0.25,
                message: "Downloading model"
            )
        }
        try await Self.probe.run(
            label: "download-\(payload.modelID)",
            kind: "download",
            duration: .milliseconds(payload.durationMilliseconds)
        )
        if payload.reportsProgress {
            await progress.report(
                fractionCompleted: 0.9,
                message: "Verifying model"
            )
        }
    }
}

struct ImportTextFileJob: Job {
    struct Payload: Codable, Sendable {
        let filename: String
        let durationMilliseconds: Int
    }

    static let probe = SynthesisJob.probe
    static let maxConcurrentExecutions = 4

    let id: UUID
    let payload: Payload
    var title: String? { "Import \(payload.filename)" }
    var priority: JobPriority { .utility }

    init(_ filename: String, durationMilliseconds: Int = 20) {
        id = UUID()
        payload = Payload(
            filename: filename,
            durationMilliseconds: durationMilliseconds
        )
    }

    func execute() async throws {
        try await Self.probe.run(
            label: "import-\(payload.filename)",
            kind: "import",
            duration: .milliseconds(payload.durationMilliseconds)
        )
    }
}

struct FailingExportJob: Job {
    struct Payload: Codable, Sendable {
        let label: String
    }

    let id: UUID
    let payload: Payload

    init(_ label: String) {
        id = UUID()
        payload = Payload(label: label)
    }

    func execute() async throws {
        throw TestJobError.exportFailed
    }
}

enum TestJobError: Error {
    case exportFailed
}

@MainActor
func makeQueue(
    fileURL: URL? = nil,
    globalLimit: Int = 3
) throws -> (JobQueue, URL, JobRegistry) {
    let registry = JobRegistry()
    try registry.register(SynthesisJob.self)
    try registry.register(ExportJob.self)
    try registry.register(DownloadModelJob.self)
    try registry.register(ImportTextFileJob.self)
    try registry.register(FailingExportJob.self)
    let url = fileURL ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).json")
    let queue = JobQueue(
        fileURL: url,
        policy: JobQueuePolicy(maxConcurrentExecutions: globalLimit),
        registry: registry,
        maxRecords: 1_000,
        autoCleanupEnabled: false
    )
    return (queue, url, registry)
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(3),
    _ condition: @MainActor () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}
