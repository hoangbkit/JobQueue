// Job.swift — Core protocols and types for JobQueue
// Defines the Job protocol, status, errors, and the type-erased envelope used for persistence.

import Foundation

// MARK: - Job Protocol

/// Conform your job types to this protocol. `Payload` must be `Codable` so the
/// queue can persist and restore the full job across app launches.
///
/// Example:
/// ```swift
/// struct EmailJob: Job {
///     let id: UUID
///     let payload: EmailPayload
///     func execute() async throws { … }
/// }
/// ```
public protocol Job: Codable, Sendable {
    associatedtype Payload: Codable & Sendable

    /// Stable, unique identity for this job instance.
    var id: UUID { get }

    /// All data needed to carry out the job.
    var payload: Payload { get }

    /// The asynchronous unit of work executed serially by `JobQueue`.
    /// Implementations should offload blocking synchronous work as needed and
    /// throw `CancellationError` (or check `Task.isCancelled`) for cooperative cancellation.
    func execute() async throws

    /// Optional UI-friendly title for queue displays.
    var title: String? { get }

    /// Optional UI-friendly detail for queue displays.
    var detail: String? { get }
}

// MARK: - Type-Erased Executable (avoids PAT constraints at call sites)

protocol AnyExecutable: Sendable {
    var id: UUID { get }
    func execute() async throws
}

extension Job {
    func asAnyExecutable() -> any AnyExecutable { AnyExecutableBox(self) }

    public var title: String? { nil }
    public var detail: String? { nil }
}

private struct AnyExecutableBox<J: Job>: AnyExecutable {
    let wrapped: J
    var id: UUID { wrapped.id }
    func execute() async throws { try await wrapped.execute() }
    init(_ job: J) { self.wrapped = job }
}

// MARK: - Job Status

/// The lifecycle state of a job inside the queue.
public enum JobStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case pending
    case processing
    case completed
    case failed
    case cancelled
}

// MARK: - Queue Record

/// Everything the queue knows about one job — status, timestamps, last error.
/// This is what you bind your UI to.
public struct JobRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    /// Swift type name used to look up the registered decoder at restore time.
    public let typeName: String
    public var title: String?
    public var detail: String?
    public var status: JobStatus
    public var error: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var completedAt: Date?

    // Raw encoded payload kept so the queue can re-execute after a restore.
    var encodedJob: Data

    public static func == (lhs: JobRecord, rhs: JobRecord) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.detail == rhs.detail &&
        lhs.status == rhs.status &&
        lhs.error == rhs.error &&
        lhs.updatedAt == rhs.updatedAt &&
        lhs.startedAt == rhs.startedAt &&
        lhs.completedAt == rhs.completedAt
    }
    
    public var processingDuration: TimeInterval? {
        guard let start = startedAt, let end = completedAt else { return nil }
        return end.timeIntervalSince(start)
    }
    
    public func decode<J: Job>(_ type: J.Type) throws -> J {
        try JSONDecoder().decode(J.self, from: encodedJob)
    }
    
    public var timelineDescription: String {
        let created: String = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MMM-dd HH:mm"
            return formatter.string(from: createdAt)
        }()
        
        let fmt: (Date) -> String = { date in
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        
        switch status {
            case .pending:
                return "\(created)"
                
            case .processing:
                guard let start = startedAt else { return "\(created)" }
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(start))
                return "\(created) · started \(fmt(start)) · \(elapsed)s elapsed"
                
            case .completed:
                guard let start = startedAt, let end = completedAt else { return "\(created)" }
                let took = String(format: "%.1f", end.timeIntervalSince(start))
                return "\(created) · finished \(fmt(end)) · took \(took)s"
                
            case .failed:
                guard let end = completedAt else { return "\(created)" }
                return "\(created) · failed at \(fmt(end))"
                
            case .cancelled:
                guard let end = completedAt else { return "\(created)" }
                return "\(created) · cancelled at \(fmt(end))"
        }
    }
}

// MARK: - Queue Errors

public enum JobQueueError: Error, LocalizedError {
    case unregisteredJobType(String)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case persistenceFailed(Error)
    case queueFull(limit: Int)
    case invalidStatusTransition(from: JobStatus, to: JobStatus)

    public var errorDescription: String? {
        switch self {
        case .unregisteredJobType(let name):
            return "Job type '\(name)' has not been registered with the JobRegistry."
        case .encodingFailed(let e):
            return "Failed to encode job: \(e.localizedDescription)"
        case .decodingFailed(let e):
            return "Failed to decode job: \(e.localizedDescription)"
        case .persistenceFailed(let e):
            return "Persistence error: \(e.localizedDescription)"
        case .queueFull(let limit):
            return "Queue is full (limit: \(limit)). Remove completed jobs before adding new ones."
        case .invalidStatusTransition(let from, let to):
            return "Cannot transition job from '\(from.rawValue)' to '\(to.rawValue)'."
        }
    }
}

// MARK: - Queue Events (optional delegate / callback)

/// Called on the actor's context after each significant event.
public enum JobQueueEvent: Sendable {
    case jobAdded(id: UUID)
    case jobStarted(id: UUID)
    case jobCompleted(id: UUID)
    case jobFailed(id: UUID, error: Error)
    case jobCancelled(id: UUID)
    case jobRemoved(id: UUID)
    case queueDrained
}
