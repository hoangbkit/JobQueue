import Foundation

public final class JobRegistry: @unchecked Sendable {
    public static let shared = JobRegistry()

    private let lock = NSLock()
    private var factories: [String: (Data) throws -> any AnyExecutable] = [:]
    private var concreteTypeNames: [String: String] = [:]
    private var concurrencyLimits: [String: Int] = [:]

    public init() {}

    public func register<J: Job>(_ type: J.Type) throws {
        let limit = type.maxConcurrentExecutions
        precondition(
            (1...10).contains(limit),
            "\(String(describing: type)).maxConcurrentExecutions must be in 1...10."
        )

        let key = typeName(for: type)
        let concreteTypeName = String(reflecting: type)
        try lock.withLock {
            if let registeredConcreteTypeName = concreteTypeNames[key] {
                guard registeredConcreteTypeName == concreteTypeName else {
                    throw JobQueueError.duplicateRegisteredTypeName(key)
                }
                return
            }

            factories[key] = { data in
                do {
                    return try JSONDecoder()
                        .decode(type, from: data)
                        .eraseToAnyExecutable()
                } catch {
                    throw JobQueueError.decodingFailed(error)
                }
            }
            concreteTypeNames[key] = concreteTypeName
            concurrencyLimits[key] = limit
        }
    }

    func encode<J: Job>(_ job: J, enqueueSequence: UInt64) throws -> JobRecord {
        precondition(
            (1...10).contains(J.maxConcurrentExecutions),
            "\(String(describing: J.self)).maxConcurrentExecutions must be in 1...10."
        )

        guard canRestoreType(named: typeName(for: J.self)) else {
            throw JobQueueError.unregisteredJobType(typeName(for: J.self))
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(job)
        } catch {
            throw JobQueueError.encodingFailed(error)
        }

        let now = Date()
        return JobRecord(
            id: job.id,
            typeName: typeName(for: J.self),
            title: job.title,
            detail: job.detail,
            status: .pending,
            priority: job.priority,
            error: nil,
            createdAt: now,
            updatedAt: now,
            enqueueSequence: enqueueSequence,
            encodedJob: data
        )
    }

    func restore(from record: JobRecord) throws -> any AnyExecutable {
        let factory = lock.withLock { factories[record.typeName] }
        guard let factory else {
            throw JobQueueError.unregisteredJobType(record.typeName)
        }
        return try factory(record.encodedJob)
    }

    func canRestoreType(named typeName: String) -> Bool {
        lock.withLock { factories[typeName] != nil }
    }

    func concurrencyLimit(for typeName: String) -> Int? {
        lock.withLock { concurrencyLimits[typeName] }
    }

    private func typeName<J: Job>(for type: J.Type) -> String {
        String(describing: type)
    }
}
