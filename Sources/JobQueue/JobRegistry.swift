// JobRegistry.swift — Maps type names → decode factories for persistence restore.

import Foundation

// MARK: - JobRegistry

/// A process-wide registry that maps Swift type names to their decode factories.
///
/// Register every `Job` type **before** loading queue state so that persisted
/// records can be reconstructed after an app relaunch.
///
/// ```swift
/// JobRegistry.shared.register(EmailJob.self)
/// JobRegistry.shared.register(ImageResizeJob.self)
/// ```
public final class JobRegistry: @unchecked Sendable {

    public static let shared = JobRegistry()

    // You can also create a dedicated instance if you prefer DI over singletons.
    public init() {}

    // typeName → (Data) throws -> AnyExecutable
    private var lock = NSLock()
    private var factories: [String: (Data) throws -> any AnyExecutable] = [:]
    private var registeredNames: Set<String> = []

    // MARK: - Register

    /// Register a `Job` type. Call this once at app start for every job type you use.
    public func register<J: Job>(_ type: J.Type) {
        let key = typeName(for: type)
        lock.withLock {
            factories[key] = { data in
                do {
                    return try JSONDecoder().decode(J.self, from: data).asAnyExecutable()
                } catch {
                    throw JobQueueError.decodingFailed(error)
                }
            }
            registeredNames.insert(key)
        }
    }

    // MARK: - Restore

    func restore(from record: JobRecord) throws -> any AnyExecutable {
        let factory = lock.withLock { factories[record.typeName] }
        guard let factory else {
            throw JobQueueError.unregisteredJobType(record.typeName)
        }
        return try factory(record.encodedJob)
    }

    // MARK: - Encode

    func encode<J: Job>(_ job: J) throws -> JobRecord {
        let data: Data
        do {
            data = try JSONEncoder().encode(job)
        } catch {
            throw JobQueueError.encodingFailed(error)
        }
        return JobRecord(
            id: job.id,
            typeName: typeName(for: J.self),
            title: job.title,
            detail: job.detail,
            status: .pending,
            error: nil,
            createdAt: Date(),
            updatedAt: Date(),
            encodedJob: data
        )
    }

    // MARK: - Helpers

    func isRegistered(_ name: String) -> Bool {
        lock.withLock { registeredNames.contains(name) }
    }

    private func typeName<J: Job>(for type: J.Type) -> String {
        String(describing: type)
    }
}
