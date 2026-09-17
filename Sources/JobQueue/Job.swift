import Foundation

public protocol Job: Codable, Sendable {
    associatedtype Payload: Codable & Sendable

    static var maxConcurrentExecutions: Int { get }

    var id: UUID { get }
    var payload: Payload { get }
    var title: String? { get }
    var detail: String? { get }
    var priority: JobPriority { get }

    func execute() async throws
    func execute(progress: JobProgressReporter) async throws
}

public extension Job {
    static var maxConcurrentExecutions: Int { 10 }

    var title: String? { nil }
    var detail: String? { nil }
    var priority: JobPriority { .default }

    func execute() async throws {}

    func execute(progress: JobProgressReporter) async throws {
        try await execute()
    }
}

protocol AnyExecutable: Sendable {
    func execute(progress: JobProgressReporter) async throws
}

extension Job {
    func eraseToAnyExecutable() -> any AnyExecutable {
        AnyExecutableBox(self)
    }
}

private struct AnyExecutableBox<J: Job>: AnyExecutable {
    let job: J

    init(_ job: J) {
        self.job = job
    }

    func execute(progress: JobProgressReporter) async throws {
        try await job.execute(progress: progress)
    }
}

public enum JobPriority: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case userInitiated
    case `default`
    case utility
    case background

    var taskPriority: TaskPriority {
        switch self {
        case .userInitiated:
            .userInitiated
        case .default:
            .medium
        case .utility:
            .low
        case .background:
            .background
        }
    }
}

public enum JobStartPolicy: Equatable, Sendable {
    case scheduled
    case immediate
}

public struct JobProgress: Codable, Equatable, Sendable {
    public let fractionCompleted: Double?
    public let message: String?

    public init(fractionCompleted: Double? = nil, message: String? = nil) {
        self.fractionCompleted = fractionCompleted.map { min(max($0, 0), 1) }
        self.message = message
    }

    public static let completed = JobProgress(fractionCompleted: 1)
}

public struct JobProgressReporter: Sendable {
    private let reportProgress: @Sendable (JobProgress) async -> Void

    init(reportProgress: @escaping @Sendable (JobProgress) async -> Void) {
        self.reportProgress = reportProgress
    }

    public func report(
        fractionCompleted: Double? = nil,
        message: String? = nil
    ) async {
        await reportProgress(
            JobProgress(
                fractionCompleted: fractionCompleted,
                message: message
            )
        )
    }
}

public enum JobStatus: String, Codable, Equatable, Hashable, Comparable, Sendable, CaseIterable {
    case pending
    case processing
    case cancelling
    case pausing
    case completed
    case failed
    case cancelled
    case unrecoverable

    public var isTerminal: Bool {
        self == .completed ||
        self == .failed ||
        self == .cancelled ||
        self == .unrecoverable
    }

    public var isExecuting: Bool {
        self == .processing || self == .cancelling || self == .pausing
    }

    public var isRetryable: Bool {
        self == .failed || self == .cancelled
    }

    public static func < (lhs: JobStatus, rhs: JobStatus) -> Bool {
        guard
            let lhsIndex = allCases.firstIndex(of: lhs),
            let rhsIndex = allCases.firstIndex(of: rhs)
        else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

public struct JobRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let typeName: String
    public var title: String?
    public var detail: String?
    public var status: JobStatus
    public let priority: JobPriority
    public var error: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var enqueueSequence: UInt64

    let encodedJob: Data

    public init(
        id: UUID,
        typeName: String,
        title: String?,
        detail: String?,
        status: JobStatus,
        priority: JobPriority = .default,
        error: String?,
        createdAt: Date,
        updatedAt: Date,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        enqueueSequence: UInt64 = 0,
        encodedJob: Data
    ) {
        self.id = id
        self.typeName = typeName
        self.title = title
        self.detail = detail
        self.status = status
        self.priority = priority
        self.error = error
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.enqueueSequence = enqueueSequence
        self.encodedJob = encodedJob
    }

    public var processingDuration: TimeInterval? {
        guard let startedAt, let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }

    public func decode<J: Job>(_ type: J.Type) throws -> J {
        try JSONDecoder().decode(type, from: encodedJob)
    }

    /// Compares the encoded job without decoding it. Status, progress timestamps,
    /// and other queue metadata do not affect payload identity.
    public func hasSamePayload(as other: JobRecord) -> Bool {
        typeName == other.typeName && encodedJob == other.encodedJob
    }
}

public enum JobQueueError: Error, LocalizedError {
    case unregisteredJobType(String)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case persistenceFailed(Error)
    case queueFull(limit: Int)
    case duplicateJobID(UUID)
    case duplicateRegisteredTypeName(String)
    case invalidStatusTransition(from: JobStatus, to: JobStatus)
    case persistenceRecoveryUnavailableWhileExecuting
    case unsupportedRecordAction(JobRecordAction)

    public var errorDescription: String? {
        switch self {
        case .unregisteredJobType(let name):
            "Job type '\(name)' has not been registered."
        case .encodingFailed(let error):
            "Failed to encode job: \(error.localizedDescription)"
        case .decodingFailed(let error):
            "Failed to decode job: \(error.localizedDescription)"
        case .persistenceFailed(let error):
            "Persistence error: \(error.localizedDescription)"
        case .queueFull(let limit):
            "Job queue is full (limit: \(limit))."
        case .duplicateJobID(let id):
            "A job with ID '\(id)' already exists."
        case .duplicateRegisteredTypeName(let name):
            "A different job type is already registered as '\(name)'."
        case .invalidStatusTransition(let from, let to):
            "Cannot transition job from '\(from.rawValue)' to '\(to.rawValue)'."
        case .persistenceRecoveryUnavailableWhileExecuting:
            "Persistence recovery is unavailable while jobs are still executing."
        case .unsupportedRecordAction(let action):
            "Job record action '\(action)' must be handled by the app."
        }
    }
}

public enum JobQueueEvent: Equatable, Sendable {
    case jobAdded(id: UUID)
    case jobStarted(id: UUID)
    case jobPausing(id: UUID)
    case jobCancelling(id: UUID)
    case jobProgressUpdated(id: UUID, progress: JobProgress)
    case jobCompleted(id: UUID)
    case jobFailed(id: UUID, errorDescription: String)
    case jobCancelled(id: UUID)
    case jobRemoved(id: UUID)
    case queueStatusChanged(JobQueueStatus)
    case queueDrained
    case persistenceFailed(errorDescription: String)
}
