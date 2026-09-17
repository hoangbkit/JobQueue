import Foundation
import Observation

public enum JobQueueStatus: String, Equatable, Sendable {
    case idle
    case processing
    case cancelling
    case pausing
    case paused

    public var isExecuting: Bool {
        self == .processing || self == .cancelling || self == .pausing
    }

    public var isPaused: Bool {
        self == .paused || self == .pausing
    }
}

public enum JobQueuePersistenceIssue: Equatable, Sendable {
    case loadFailed(errorDescription: String)
    case saveFailed(errorDescription: String)

    public var errorDescription: String {
        switch self {
        case .loadFailed(let errorDescription), .saveFailed(let errorDescription):
            errorDescription
        }
    }
}

public enum JobQueueAction: Hashable, Sendable {
    case pause
    case resume
    case retryAll
    case cancelAll
    case clearCompleted
    case retryPersistence
    case resetPersistence
}

public enum JobRecordAction: Hashable, Sendable {
    case editAndRequeue
    case cancel
    case retry
    case remove
}

enum JobQueuePersistenceRecoveryAction {
    case retry
    case reset
}

@MainActor
@Observable
public final class JobQueue {
    public private(set) var records: [UUID: JobRecord] = [:]
    public private(set) var liveProgress: [UUID: JobProgress] = [:]
    public private(set) var status: JobQueueStatus = .idle
    public private(set) var persistenceIssue: JobQueuePersistenceIssue?
    public private(set) var isPaused = false
    public private(set) var pausedJobTypeNames: Set<String> = []

    public let policy: JobQueuePolicy
    public let maxRecords: Int
    public let autoCleanupEnabled: Bool
    public var eventHandler: ((JobQueueEvent) -> Void)?

    public var isProcessing: Bool { !executions.isEmpty }
    public var executingJobIDs: Set<UUID> { Set(executions.keys) }
    public var runningCount: Int { executions.count }
    public var lastPersistenceError: String? { persistenceIssue?.errorDescription }

    public var activeCount: Int {
        records.values.filter { $0.status == .pending || $0.status.isExecuting }.count
    }

    public var sortedRecords: [JobRecord] {
        records.values.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.enqueueSequence > $1.enqueueSequence
        }
    }

    public var availableActions: [JobQueueAction] {
        if let persistenceIssue {
            switch persistenceIssue {
            case .loadFailed:
                return [.retryPersistence, .resetPersistence]
            case .saveFailed:
                return executions.isEmpty
                    ? [.retryPersistence, .resetPersistence]
                    : [.retryPersistence]
            }
        }

        var actions: [JobQueueAction] = []
        if isPaused {
            if records.values.contains(where: { $0.status == .pending }) {
                actions.append(.resume)
            }
        } else if activeCount > 0 {
            actions.append(.pause)
        }
        if records.values.contains(where: \.status.isRetryable) {
            actions.append(.retryAll)
        }
        if activeCount > 0 {
            actions.append(.cancelAll)
        }
        if records.values.contains(where: { $0.status == .completed }) {
            actions.append(.clearCompleted)
        }
        return actions
    }

    private enum StopReason: Equatable {
        case queuePause
        case typePause
        case immediateDisplacement
        case cancellation
        case removal
    }

    private struct CurrentExecution {
        let id: UUID
        let typeName: String
        let token: UUID
        let startedAt: Date
        let task: Task<Void, Never>
        var stopReason: StopReason?
    }

    private enum ExecutionOutcome {
        case succeeded
        case failed(Error)
        case cancelled
    }

    private let store: JobQueueStore
    private let registry: JobRegistry
    private var executions: [UUID: CurrentExecution] = [:]
    private var immediateJobIDs: [UUID] = []
    private var scheduler = JobScheduler()
    private var nextEnqueueSequence: UInt64 = 1
    private var hasStarted = false
    private var hasEmittedDrained = false

    public init(
        fileURL: URL,
        policy: JobQueuePolicy,
        registry: JobRegistry = .shared,
        maxRecords: Int = 100,
        autoCleanupEnabled: Bool = true
    ) {
        precondition(maxRecords > 0, "maxRecords must be greater than zero.")
        self.store = JobQueueStore(fileURL: fileURL)
        self.policy = policy
        self.registry = registry
        self.maxRecords = maxRecords
        self.autoCleanupEnabled = autoCleanupEnabled
    }

    public func start() throws {
        guard !hasStarted else { return }

        let loadResult: JobQueueStore.LoadResult
        do {
            loadResult = try store.load()
        } catch {
            capturePersistenceFailure(error, operation: .load)
            throw error
        }

        var restored = loadResult.records
        let now = Date()
        var changed = loadResult.requiresRewrite

        let orderedIndices = restored.indices.sorted {
            let lhs = restored[$0]
            let rhs = restored[$1]
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var sequence = restored
            .map(\.enqueueSequence)
            .max()
            .map { $0 &+ 1 } ?? 1
        for index in orderedIndices {
            if restored[index].enqueueSequence == 0 {
                restored[index].enqueueSequence = sequence
                sequence &+= 1
                changed = true
            }
        }
        nextEnqueueSequence = sequence

        for index in restored.indices {
            let canRestore = registry.canRestoreType(named: restored[index].typeName)
            switch restored[index].status {
            case .pending, .failed, .cancelled:
                if !canRestore {
                    markUnsupported(&restored[index], now: now)
                    changed = true
                }
            case .processing, .pausing:
                if canRestore {
                    restored[index].status = .pending
                    restored[index].error = nil
                    restored[index].startedAt = nil
                    restored[index].completedAt = nil
                } else {
                    markUnsupported(&restored[index], now: now)
                }
                restored[index].updatedAt = now
                changed = true
            case .cancelling:
                if canRestore {
                    restored[index].status = .cancelled
                    restored[index].completedAt = now
                    restored[index].updatedAt = now
                } else {
                    markUnsupported(&restored[index], now: now)
                }
                changed = true
            case .completed, .unrecoverable:
                break
            }
        }

        var loadedRecords: [UUID: JobRecord] = [:]
        for index in restored.indices {
            if loadedRecords[restored[index].id] != nil {
                restored[index] = duplicateIDRecord(restored[index], now: now)
                changed = true
            }
            let record = restored[index]
            guard loadedRecords[record.id] == nil else {
                let error = JobQueueError.duplicateJobID(record.id)
                capturePersistenceFailure(error, operation: .load)
                throw error
            }
            loadedRecords[record.id] = record
        }

        if changed {
            do {
                try store.save(restored)
            } catch {
                capturePersistenceFailure(error, operation: .save)
                throw error
            }
        }

        records = loadedRecords
        persistenceIssue = nil
        isPaused = false
        pausedJobTypeNames = []
        hasStarted = true
        refreshStatus()
        advanceIfPossible()
    }

    @discardableResult
    public func enqueue<J: Job>(
        _ job: J,
        startPolicy: JobStartPolicy = .scheduled
    ) throws -> UUID {
        try ensureStarted()
        let record = try registry.encode(job, enqueueSequence: nextEnqueueSequence)
        nextEnqueueSequence &+= 1
        guard records[record.id] == nil else {
            throw JobQueueError.duplicateJobID(record.id)
        }

        var updated = records
        updated[record.id] = record
        try pruneIfNeeded(&updated)

        var displacedID: UUID?
        if startPolicy == .immediate {
            immediateJobIDs.append(record.id)
            displacedID = mostRecentlyStartedExecutionID(
                typeName: record.typeName,
                requiringDisplacementFor: updated
            )
            if let displacedID {
                updated[displacedID]?.status = .pausing
                updated[displacedID]?.updatedAt = Date()
            }
        }

        do {
            try commit(updated)
        } catch {
            immediateJobIDs.removeAll { $0 == record.id }
            throw error
        }

        hasEmittedDrained = false
        emit(.jobAdded(id: record.id))
        if let displacedID {
            executions[displacedID]?.stopReason = .immediateDisplacement
            emit(.jobPausing(id: displacedID))
            executions[displacedID]?.task.cancel()
        }
        refreshStatus()
        advanceIfPossible()
        return record.id
    }

    public func cancel(id: UUID) throws {
        try ensureStarted()
        guard let record = records[id] else { return }

        switch record.status {
        case .pending:
            try updateRecord(id) {
                $0.status = .cancelled
                $0.error = "Cancelled by caller."
                $0.updatedAt = Date()
                $0.completedAt = Date()
            }
            immediateJobIDs.removeAll { $0 == id }
            emit(.jobCancelled(id: id))
        case .processing, .pausing:
            try updateRecord(id) {
                $0.status = .cancelling
                $0.error = "Cancellation requested."
                $0.updatedAt = Date()
            }
            executions[id]?.stopReason = .cancellation
            emit(.jobCancelling(id: id))
            executions[id]?.task.cancel()
        case .cancelling, .completed, .failed, .cancelled, .unrecoverable:
            return
        }
        refreshStatus()
        advanceIfPossible()
    }

    public func pause() throws {
        try ensureStarted()
        guard !isPaused else { return }

        let ids = executions.keys.filter { records[$0]?.status == .processing }
        var updated = records
        let now = Date()
        for id in ids {
            updated[id]?.status = .pausing
            updated[id]?.updatedAt = now
        }
        try commit(updated)
        isPaused = true
        for id in ids {
            executions[id]?.stopReason = .queuePause
            emit(.jobPausing(id: id))
            executions[id]?.task.cancel()
        }
        refreshStatus()
    }

    public func resume() throws {
        try ensureStarted()
        guard isPaused else { return }
        isPaused = false
        refreshStatus()
        advanceIfPossible()
    }

    public func pause<J: Job>(_ type: J.Type) throws {
        try ensureStarted()
        let typeName = String(describing: type)
        guard !pausedJobTypeNames.contains(typeName) else { return }

        let ids = executions.values
            .filter { $0.typeName == typeName && records[$0.id]?.status == .processing }
            .map(\.id)
        var updated = records
        let now = Date()
        for id in ids {
            updated[id]?.status = .pausing
            updated[id]?.updatedAt = now
        }
        try commit(updated)
        pausedJobTypeNames.insert(typeName)
        for id in ids {
            executions[id]?.stopReason = .typePause
            emit(.jobPausing(id: id))
            executions[id]?.task.cancel()
        }
        refreshStatus()
        advanceIfPossible()
    }

    public func resume<J: Job>(_ type: J.Type) throws {
        try ensureStarted()
        pausedJobTypeNames.remove(String(describing: type))
        refreshStatus()
        advanceIfPossible()
    }

    public func remove(id: UUID) throws {
        try ensureStarted()
        guard records[id] != nil else { return }

        var updated = records
        updated.removeValue(forKey: id)
        try commit(updated)
        liveProgress.removeValue(forKey: id)
        immediateJobIDs.removeAll { $0 == id }
        emit(.jobRemoved(id: id))

        if executions[id] != nil {
            executions[id]?.stopReason = .removal
            executions[id]?.task.cancel()
        }
        refreshStatus()
        advanceIfPossible()
    }

    @discardableResult
    public func replace<J: Job>(id: UUID, with job: J) throws -> UUID {
        try ensureStarted()
        guard let existing = records[id] else {
            return try enqueue(job)
        }
        guard existing.status == .pending || existing.status.isRetryable else {
            throw JobQueueError.invalidStatusTransition(
                from: existing.status,
                to: .pending
            )
        }

        let replacement = try registry.encode(
            job,
            enqueueSequence: nextEnqueueSequence
        )
        nextEnqueueSequence &+= 1
        var updated = records
        updated.removeValue(forKey: id)
        guard updated[replacement.id] == nil else {
            throw JobQueueError.duplicateJobID(replacement.id)
        }
        updated[replacement.id] = replacement
        try pruneIfNeeded(&updated)
        try commit(updated)
        liveProgress.removeValue(forKey: id)
        immediateJobIDs.removeAll { $0 == id }
        emit(.jobRemoved(id: id))
        emit(.jobAdded(id: replacement.id))
        hasEmittedDrained = false
        advanceIfPossible()
        return replacement.id
    }

    public func cancelAll() throws {
        try ensureStarted()
        let now = Date()
        var updated = records
        var cancelledIDs: [UUID] = []
        var cancellingIDs: [UUID] = []
        for id in updated.keys {
            switch updated[id]?.status {
            case .pending:
                updated[id]?.status = .cancelled
                updated[id]?.error = "Cancelled by cancelAll()."
                updated[id]?.completedAt = now
                updated[id]?.updatedAt = now
                cancelledIDs.append(id)
            case .processing, .pausing:
                updated[id]?.status = .cancelling
                updated[id]?.error = "Cancellation requested by cancelAll()."
                updated[id]?.updatedAt = now
                cancellingIDs.append(id)
            default:
                break
            }
        }
        try commit(updated)
        immediateJobIDs = []
        for id in cancelledIDs {
            emit(.jobCancelled(id: id))
        }
        for id in cancellingIDs {
            executions[id]?.stopReason = .cancellation
            emit(.jobCancelling(id: id))
            executions[id]?.task.cancel()
        }
        refreshStatus()
        emitDrainedIfNeeded()
    }

    public func clearCompleted() throws {
        try ensureStarted()
        let completedIDs = records.values
            .filter { $0.status == .completed }
            .map(\.id)
        guard !completedIDs.isEmpty else { return }

        var updated = records
        for id in completedIDs {
            updated.removeValue(forKey: id)
        }
        try commit(updated)
        for id in completedIDs {
            liveProgress.removeValue(forKey: id)
            emit(.jobRemoved(id: id))
        }
        advanceIfPossible()
    }

    public func retry(id: UUID) throws {
        try ensureStarted()
        guard let record = records[id], record.status.isRetryable else { return }
        try updateRecord(id) {
            $0.status = .pending
            $0.error = nil
            $0.startedAt = nil
            $0.completedAt = nil
            $0.updatedAt = Date()
        }
        liveProgress.removeValue(forKey: id)
        hasEmittedDrained = false
        advanceIfPossible()
    }

    public func retryAll() throws {
        try ensureStarted()
        let now = Date()
        var updated = records
        var changed = false
        for id in updated.keys where updated[id]?.status.isRetryable == true {
            updated[id]?.status = .pending
            updated[id]?.error = nil
            updated[id]?.startedAt = nil
            updated[id]?.completedAt = nil
            updated[id]?.updatedAt = now
            liveProgress.removeValue(forKey: id)
            changed = true
        }
        guard changed else { return }
        try commit(updated)
        hasEmittedDrained = false
        advanceIfPossible()
    }

    public func perform(_ action: JobQueueAction) throws {
        switch action {
        case .pause:
            try pause()
        case .resume:
            try resume()
        case .retryAll:
            try retryAll()
        case .cancelAll:
            try cancelAll()
        case .clearCompleted:
            try clearCompleted()
        case .retryPersistence:
            try handlePersistenceRecovery(.retry)
        case .resetPersistence:
            try handlePersistenceRecovery(.reset)
        }
    }

    public func perform(_ action: JobRecordAction, for id: UUID) throws {
        switch action {
        case .editAndRequeue:
            throw JobQueueError.unsupportedRecordAction(action)
        case .cancel:
            try cancel(id: id)
        case .retry:
            try retry(id: id)
        case .remove:
            try remove(id: id)
        }
    }

    public func availableActions(
        for record: JobRecord,
        allowsEditing: Bool = false
    ) -> [JobRecordAction] {
        Self.availableActions(for: record, allowsEditing: allowsEditing)
    }

    public static func availableActions(
        for record: JobRecord,
        allowsEditing: Bool = false
    ) -> [JobRecordAction] {
        var actions: [JobRecordAction] = []
        // Pending jobs are still mutable — editing rewrites the payload before
        // the job runs. Executing jobs are not: their inputs are captured.
        if allowsEditing && (record.status == .pending || record.status.isRetryable) {
            actions.append(.editAndRequeue)
        }
        if record.status == .pending || record.status.isExecuting {
            actions.append(.cancel)
        }
        if record.status.isRetryable {
            actions.append(.retry)
        }
        if record.status.isTerminal {
            actions.append(.remove)
        }
        return actions
    }

    public func records(with status: JobStatus) -> [JobRecord] {
        records.values
            .filter { $0.status == status }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func progress(for id: UUID) -> JobProgress? {
        liveProgress[id]
    }

    func handlePersistenceRecovery(
        _ action: JobQueuePersistenceRecoveryAction
    ) throws {
        switch action {
        case .retry:
            try retryPersistenceAndAdvance()
        case .reset:
            try discardPersistedState()
        }
    }

    private func retryPersistenceAndAdvance() throws {
        switch persistenceIssue {
        case .loadFailed:
            try start()
        case .saveFailed:
            do {
                try store.save(Array(records.values))
                persistenceIssue = nil
                advanceIfPossible()
            } catch {
                capturePersistenceFailure(error, operation: .save)
                throw error
            }
        case nil:
            advanceIfPossible()
        }
    }

    private func discardPersistedState() throws {
        guard executions.isEmpty else {
            throw JobQueueError.persistenceRecoveryUnavailableWhileExecuting
        }
        do {
            try store.reset()
        } catch {
            capturePersistenceFailure(error, operation: .save)
            throw error
        }
        records = [:]
        liveProgress = [:]
        immediateJobIDs = []
        isPaused = false
        pausedJobTypeNames = []
        persistenceIssue = nil
        hasStarted = true
        hasEmittedDrained = false
        refreshStatus()
    }

    private func advanceIfPossible() {
        guard persistenceIssue == nil, !isPaused else {
            refreshStatus()
            return
        }

        while executions.count < policy.maxConcurrentExecutions {
            let runningByType = Dictionary(
                grouping: executions.values,
                by: \.typeName
            ).mapValues(\.count)
            guard let id = scheduler.nextJobID(
                records: records,
                immediateJobIDs: immediateJobIDs,
                pausedTypeNames: pausedJobTypeNames,
                runningCountByType: runningByType,
                concurrencyLimit: registry.concurrencyLimit(for:)
            ) else {
                break
            }
            guard startExecution(id: id) else { break }
        }

        refreshStatus()
        emitDrainedIfNeeded()
    }

    private func startExecution(id: UUID) -> Bool {
        guard var record = records[id], record.status == .pending else {
            immediateJobIDs.removeAll { $0 == id }
            return true
        }

        let now = Date()
        record.status = .processing
        record.error = nil
        record.startedAt = now
        record.completedAt = nil
        record.updatedAt = now
        var updated = records
        updated[id] = record
        do {
            try commit(updated)
        } catch {
            return false
        }

        immediateJobIDs.removeAll { $0 == id }
        liveProgress.removeValue(forKey: id)
        let token = UUID()
        let priority = record.priority.taskPriority
        let task = Task(priority: priority) { [weak self] in
            guard let self else { return }
            var outcome: ExecutionOutcome = .cancelled
            do {
                guard let currentRecord = self.records[id] else {
                    self.executionFinished(id: id, token: token, outcome: outcome)
                    return
                }
                let executable = try self.registry.restore(from: currentRecord)
                let progress = JobProgressReporter { [weak self] progress in
                    await self?.reportProgress(id: id, token: token, progress: progress)
                }
                try await executable.execute(progress: progress)
                outcome = .succeeded
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = .failed(error)
            }
            self.executionFinished(id: id, token: token, outcome: outcome)
        }

        executions[id] = CurrentExecution(
            id: id,
            typeName: record.typeName,
            token: token,
            startedAt: now,
            task: task,
            stopReason: nil
        )
        hasEmittedDrained = false
        emit(.jobStarted(id: id))
        return true
    }

    private func executionFinished(
        id: UUID,
        token: UUID,
        outcome: ExecutionOutcome
    ) {
        guard let execution = executions[id], execution.token == token else {
            return
        }
        executions.removeValue(forKey: id)

        guard records[id] != nil else {
            refreshStatus()
            advanceIfPossible()
            return
        }

        let now = Date()
        var updated = records
        guard var record = updated[id] else { return }
        let shouldRequeue = execution.stopReason == .queuePause ||
            execution.stopReason == .typePause ||
            execution.stopReason == .immediateDisplacement

        switch outcome {
        case .succeeded:
            record.status = .completed
            record.error = nil
            record.completedAt = now
            liveProgress[id] = .completed
        case .failed(let error):
            record.status = .failed
            record.error = error.localizedDescription
            record.completedAt = now
        case .cancelled where shouldRequeue:
            record.status = .pending
            record.error = nil
            record.startedAt = nil
            record.completedAt = nil
            liveProgress.removeValue(forKey: id)
        case .cancelled:
            record.status = .cancelled
            record.error = "Cancelled."
            record.completedAt = now
        }
        record.updatedAt = now
        updated[id] = record

        do {
            try commit(updated)
        } catch {
            records[id] = record
        }

        switch record.status {
        case .completed:
            emit(.jobCompleted(id: id))
        case .failed:
            emit(.jobFailed(
                id: id,
                errorDescription: record.error ?? "Unknown error"
            ))
        case .cancelled:
            emit(.jobCancelled(id: id))
        case .pending, .processing, .cancelling, .pausing, .unrecoverable:
            break
        }

        refreshStatus()
        advanceIfPossible()
    }

    private func reportProgress(
        id: UUID,
        token: UUID,
        progress: JobProgress
    ) {
        guard executions[id]?.token == token else { return }
        guard records[id]?.status.isExecuting == true else { return }
        liveProgress[id] = progress
        records[id]?.updatedAt = Date()
        emit(.jobProgressUpdated(id: id, progress: progress))
    }

    private func mostRecentlyStartedExecutionID(
        typeName: String,
        requiringDisplacementFor updatedRecords: [UUID: JobRecord]
    ) -> UUID? {
        guard let limit = registry.concurrencyLimit(for: typeName) else {
            return nil
        }
        let running = executions.values.filter { $0.typeName == typeName }
        guard running.count >= limit else { return nil }
        guard updatedRecords.values.contains(where: {
            $0.typeName == typeName && $0.status == .pending
        }) else {
            return nil
        }
        return running
            .filter {
                $0.stopReason == nil &&
                records[$0.id]?.status == .processing
            }
            .max(by: { $0.startedAt < $1.startedAt })?
            .id
    }

    private func duplicateIDRecord(
        _ record: JobRecord,
        now: Date
    ) -> JobRecord {
        JobRecord(
            id: UUID(),
            typeName: record.typeName,
            title: record.title,
            detail: record.detail,
            status: .unrecoverable,
            priority: record.priority,
            error: "Persisted job duplicated ID '\(record.id)'.",
            createdAt: record.createdAt,
            updatedAt: now,
            startedAt: record.startedAt,
            completedAt: now,
            enqueueSequence: record.enqueueSequence,
            encodedJob: record.encodedJob
        )
    }

    private func markUnsupported(
        _ record: inout JobRecord,
        now: Date
    ) {
        record.status = .unrecoverable
        record.error = "Job type '\(record.typeName)' is no longer supported."
        record.startedAt = nil
        record.completedAt = now
        record.updatedAt = now
    }

    private func ensureStarted() throws {
        if !hasStarted {
            try start()
        }
    }

    private func updateRecord(
        _ id: UUID,
        mutate: (inout JobRecord) -> Void
    ) throws {
        var updated = records
        guard var record = updated[id] else { return }
        mutate(&record)
        updated[id] = record
        try commit(updated)
    }

    private func commit(_ updated: [UUID: JobRecord]) throws {
        do {
            try store.save(Array(updated.values))
            records = updated
            liveProgress = liveProgress.filter { updated[$0.key] != nil }
            persistenceIssue = nil
        } catch {
            capturePersistenceFailure(error, operation: .save)
            throw error
        }
    }

    private func pruneIfNeeded(_ updated: inout [UUID: JobRecord]) throws {
        guard updated.count > maxRecords else { return }
        guard autoCleanupEnabled else {
            throw JobQueueError.queueFull(limit: maxRecords)
        }
        let terminalRecords = updated.values
            .filter(\.status.isTerminal)
            .sorted {
                if $0.enqueueSequence != $1.enqueueSequence {
                    return $0.enqueueSequence < $1.enqueueSequence
                }
                return $0.createdAt < $1.createdAt
            }
        for record in terminalRecords {
            guard updated.count > maxRecords else { break }
            updated.removeValue(forKey: record.id)
        }
        guard updated.count <= maxRecords else {
            throw JobQueueError.queueFull(limit: maxRecords)
        }
    }

    private func refreshStatus() {
        let newStatus: JobQueueStatus
        if records.values.contains(where: { $0.status == .cancelling }) {
            newStatus = .cancelling
        } else if records.values.contains(where: { $0.status == .pausing }) {
            newStatus = .pausing
        } else if isPaused {
            newStatus = .paused
        } else if !executions.isEmpty {
            newStatus = .processing
        } else {
            newStatus = .idle
        }
        guard status != newStatus else { return }
        status = newStatus
        emit(.queueStatusChanged(newStatus))
    }

    private func emitDrainedIfNeeded() {
        let isDrained = records.values.allSatisfy {
            $0.status != .pending && !$0.status.isExecuting
        } && executions.isEmpty
        guard isDrained, !hasEmittedDrained else { return }
        hasEmittedDrained = true
        emit(.queueDrained)
    }

    private enum PersistenceOperation {
        case load
        case save
    }

    private func capturePersistenceFailure(
        _ error: Error,
        operation: PersistenceOperation
    ) {
        let description = error.localizedDescription
        switch operation {
        case .load:
            persistenceIssue = .loadFailed(errorDescription: description)
        case .save:
            persistenceIssue = .saveFailed(errorDescription: description)
        }
        emit(.persistenceFailed(errorDescription: description))
    }

    private func emit(_ event: JobQueueEvent) {
        eventHandler?(event)
    }
}

#if DEBUG

@MainActor
extension JobQueue {
    func configurePreview(
        records previewRecords: [JobRecord],
        isPaused previewIsPaused: Bool = false,
        progress previewProgress: [UUID: JobProgress] = [:]
    ) {
        records = Dictionary(uniqueKeysWithValues: previewRecords.map { ($0.id, $0) })
        liveProgress = previewProgress
        isPaused = previewIsPaused
        refreshStatus()
    }
}

#endif
