import Foundation

final class JobQueueStore: Sendable {
    struct LoadResult {
        let records: [JobRecord]
        let requiresRewrite: Bool
    }

    fileprivate enum Status: String, Codable {
        case pending
        case processing
        case cancelling
        case pausing
        case completed
        case failed
        case cancelled
        case unrecoverable
    }

    fileprivate struct Record: Codable {
        var id: UUID?
        var typeName: String?
        var title: String?
        var detail: String?
        var status: String?
        var priority: JobPriority?
        var error: String?
        var createdAt: Date?
        var updatedAt: Date?
        var startedAt: Date?
        var completedAt: Date?
        var enqueueSequence: UInt64?
        var encodedJob: Data?

        init(
            id: UUID? = nil,
            typeName: String? = nil,
            title: String? = nil,
            detail: String? = nil,
            status: String? = nil,
            priority: JobPriority? = nil,
            error: String? = nil,
            createdAt: Date? = nil,
            updatedAt: Date? = nil,
            startedAt: Date? = nil,
            completedAt: Date? = nil,
            enqueueSequence: UInt64? = nil,
            encodedJob: Data? = nil
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

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.decodeLossy(UUID.self, forKey: .id)
            typeName = container.decodeLossy(String.self, forKey: .typeName)
            title = container.decodeLossy(String.self, forKey: .title)
            detail = container.decodeLossy(String.self, forKey: .detail)
            status = container.decodeLossy(String.self, forKey: .status)
            priority = container.decodeLossy(JobPriority.self, forKey: .priority)
            error = container.decodeLossy(String.self, forKey: .error)
            createdAt = container.decodeLossy(Date.self, forKey: .createdAt)
            updatedAt = container.decodeLossy(Date.self, forKey: .updatedAt)
            startedAt = container.decodeLossy(Date.self, forKey: .startedAt)
            completedAt = container.decodeLossy(Date.self, forKey: .completedAt)
            enqueueSequence = container.decodeLossy(UInt64.self, forKey: .enqueueSequence)
            encodedJob = container.decodeLossy(Data.self, forKey: .encodedJob)
        }
    }

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func save(_ records: [JobRecord]) throws {
        do {
            // The public ConcurrentJobQueue contract requires callers to provision the
            // persistence parent directory before use. Do not silently recreate a missing
            // parent here: package-scoped queues (such as Spokio Projects) must fail locally
            // if their owning storage is moved or disconnected rather than recreating a stale
            // directory tree. Existing global callers already provide their persistence parent.
            let directory = fileURL.deletingLastPathComponent()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: directory.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileNoSuchFileError,
                    userInfo: [NSFilePathErrorKey: directory.path]
                )
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(records.map(Record.init)).write(to: fileURL, options: .atomic)
        } catch {
            throw JobQueueError.persistenceFailed(error)
        }
    }

    func load() throws -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LoadResult(records: [], requiresRewrite: false)
        }

        do {
            let stored = try loadRecords(from: Data(contentsOf: fileURL))
            return LoadResult(
                records: stored.map(JobRecord.init),
                requiresRewrite: stored.contains {
                    $0.priority == nil || $0.enqueueSequence == nil
                }
            )
        } catch {
            throw JobQueueError.persistenceFailed(error)
        }
    }

    private func loadRecords(from data: Data) throws -> [Record] {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let array = root as? [Any] else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Job queue storage must be a record array."
                )
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return array.map { element in
            guard JSONSerialization.isValidJSONObject(element),
                  let data = try? JSONSerialization.data(withJSONObject: element),
                  let record = try? decoder.decode(Record.self, from: data) else {
                return Record()
            }
            return record
        }
    }

    func reset() throws {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try save([])
        } catch let error as JobQueueError {
            throw error
        } catch {
            throw JobQueueError.persistenceFailed(error)
        }
    }
}

private extension JobRecord {
    init(_ record: JobQueueStore.Record) {
        let now = Date()
        let createdAt = record.createdAt ?? now
        let updatedAt = record.updatedAt ?? createdAt
        let decodedStatus = record.status
            .flatMap(JobQueueStore.Status.init(rawValue:))
            .map(JobStatus.init)
        let isMissingRequiredField = record.id == nil ||
            record.typeName == nil ||
            record.status == nil ||
            record.createdAt == nil ||
            record.updatedAt == nil ||
            record.encodedJob == nil
        let status = isMissingRequiredField
            ? JobStatus.unrecoverable
            : decodedStatus ?? .unrecoverable
        let error: String? = {
            if decodedStatus == nil, let status = record.status {
                return "Persisted job status '\(status)' is unrecoverable."
            }
            if isMissingRequiredField {
                return "Persisted job record is missing required fields."
            }
            return record.error
        }()

        self.init(
            id: record.id ?? UUID(),
            typeName: record.typeName ?? "UnknownJob",
            title: record.title,
            detail: record.detail,
            status: status,
            priority: record.priority ?? .default,
            error: error,
            createdAt: createdAt,
            updatedAt: updatedAt,
            startedAt: record.startedAt,
            completedAt: status == .unrecoverable
                ? record.completedAt ?? updatedAt
                : record.completedAt,
            enqueueSequence: record.enqueueSequence ?? 0,
            encodedJob: record.encodedJob ?? Data()
        )
    }
}

private extension JobQueueStore.Record {
    init(_ record: JobRecord) {
        self.init(
            id: record.id,
            typeName: record.typeName,
            title: record.title,
            detail: record.detail,
            status: JobQueueStore.Status(record.status).rawValue,
            priority: record.priority,
            error: record.error,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            startedAt: record.startedAt,
            completedAt: record.completedAt,
            enqueueSequence: record.enqueueSequence,
            encodedJob: record.encodedJob
        )
    }
}

private extension JobStatus {
    init(_ status: JobQueueStore.Status) {
        self = JobStatus(rawValue: status.rawValue) ?? .unrecoverable
    }
}

private extension JobQueueStore.Status {
    init(_ status: JobStatus) {
        self = JobQueueStore.Status(rawValue: status.rawValue) ?? .unrecoverable
    }
}

private extension KeyedDecodingContainer {
    func decodeLossy<Value: Decodable>(
        _ type: Value.Type,
        forKey key: Key
    ) -> Value? {
        try? decodeIfPresent(type, forKey: key)
    }
}
