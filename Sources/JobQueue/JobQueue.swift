// JobQueue.swift — Serial, persistent, observable job queue.
//
// Design goals (mirroring your BatchManager patterns):
//  • @MainActor + @Observable  → drop-in for SwiftUI bindings
//  • actor-isolated processing  → no data races, no manual locking
//  • type-erased Job storage   → heterogeneous payloads in one JSON file
//  • cooperative cancellation  → Swift structured-concurrency native
//  • automatic cleanup         → keep the queue under a configurable cap

import Foundation
import Observation
import Logging

let logger = Logger(label: "JobQueue")

// MARK: - JobQueue

/// A serial, observable, persistent job queue.
///
/// **Setup**
/// ```swift
/// // 1. Register every Job type you use (once, at app start)
/// JobRegistry.shared.register(EmailJob.self)
/// JobRegistry.shared.register(ImageResizeJob.self)
///
/// // 2. Create the queue pointing at a JSON file
/// let queue = JobQueue(
///     fileURL: URL.documentsDirectory.appending(path: "jobqueue.json")
/// )
///
/// // 3. Restore persisted jobs from last run
/// queue.loadPersistedState()
/// ```
///
/// **Enqueue & observe**
/// ```swift
/// try queue.enqueue(EmailJob(to: "a@b.com", subject: "Hi", body: "…"))
///
/// // In SwiftUI
/// ForEach(queue.records.values.sorted { … }) { record in … }
/// ```
@MainActor
@Observable
public final class JobQueue {

    // MARK: - Public State (Observable)

    /// All known records keyed by job ID — bind your UI directly to this.
    public var records: [UUID: JobRecord] = [:]

    /// `true` while a job is actively executing.
    public var isProcessing: Bool = false

    // MARK: - Configuration

    /// Maximum number of records kept in the queue before automatic cleanup.
    public var maxRecords: Int

    /// When `autoCleanupEnabled` is true, completed/failed/cancelled records
    /// are removed once the queue exceeds `maxRecords`.
    public var autoCleanupEnabled: Bool

    /// Called after every significant queue event. Runs on `@MainActor`.
    public var eventHandler: ((JobQueueEvent) -> Void)?

    // MARK: - Private

    private let store: JobQueueStore
    private let registry: JobRegistry
    private var currentTask: Task<Void, Never>?
    private var isPaused = false

    // MARK: - Init

    /// - Parameters:
    ///   - fileURL:            JSON file where the queue is persisted.
    ///   - registry:           Type registry (defaults to `JobRegistry.shared`).
    ///   - maxRecords:         Cap on total records before auto-cleanup (default 100).
    ///   - autoCleanupEnabled: Whether to prune old terminal records automatically (default true).
    public init(
        fileURL: URL,
        registry: JobRegistry = .shared,
        maxRecords: Int = 100,
        autoCleanupEnabled: Bool = true
    ) {
        self.store = JobQueueStore(fileURL: fileURL)
        self.registry = registry
        self.maxRecords = maxRecords
        self.autoCleanupEnabled = autoCleanupEnabled
    }

    // MARK: - Public API

    // ─── Enqueue ─────────────────────────────────────────────────────────────

    /// Add a new job to the queue and start processing if idle.
    /// Throws `JobQueueError.queueFull` if the queue is at capacity and
    /// no terminal records can be pruned.
    @discardableResult
    public func enqueue<J: Job>(_ job: J) throws -> UUID {
        if autoCleanupEnabled { pruneIfNeeded() }

        let activeCount = records.values.filter {
            $0.status == .pending || $0.status == .processing
        }.count
        if activeCount >= maxRecords {
            throw JobQueueError.queueFull(limit: maxRecords)
        }

        let record = try registry.encode(job)
        records[record.id] = record
        persistSilently()
        emit(.jobAdded(id: record.id))
        advanceQueue()
        return record.id
    }

    // ─── Cancel ──────────────────────────────────────────────────────────────

    /// Cancel a job. If it's currently executing, the running `Task` receives
    /// cooperative cancellation. If pending, it's marked cancelled immediately.
    public func cancel(id: UUID) {
        guard var record = records[id] else { return }
        guard record.status == .pending || record.status == .processing else { return }

        if record.status == .processing {
            currentTask?.cancel()
        }

        record.status = .cancelled
        record.error = "Cancelled by caller."
        record.updatedAt = Date()
        records[id] = record
        persistSilently()
        emit(.jobCancelled(id: id))
    }

    // ─── Resume ──────────────────────────────────────────────────────────────

    /// Reset a failed or cancelled job back to `.pending` so it will be retried.
    public func resume(id: UUID) {
        guard var record = records[id] else { return }
        guard record.status == .failed || record.status == .cancelled else { return }

        record.status = .pending
        record.error = nil
        record.updatedAt = Date()
        records[id] = record
        persistSilently()
        advanceQueue()
    }

    // ─── Remove ──────────────────────────────────────────────────────────────

    /// Permanently remove a record from the queue.
    /// If the job is currently processing, it is cancelled first.
    public func remove(id: UUID) {
        guard let record = records[id] else { return }
        if record.status == .processing {
            currentTask?.cancel()
            currentTask = nil
            isProcessing = false
        }
        records.removeValue(forKey: id)
        persistSilently()
        emit(.jobRemoved(id: id))
        advanceQueue()
    }
    
    @discardableResult
    public func replace<J: Job>(id: UUID, with job: J) throws -> UUID {
        guard let existing = records[id] else { return try enqueue(job) }
        guard existing.status == .failed || existing.status == .cancelled else {
            throw JobQueueError.invalidStatusTransition(from: existing.status, to: .pending)
        }
        records.removeValue(forKey: id)
        emit(.jobRemoved(id: id))
        return try enqueue(job)
    }

    // MARK: - Bulk ops
    public func start() {
        loadPersistedState()
        advanceQueue()
        logger.info("queue started")
    }
    
    public func pause() {
        isPaused = true
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        for id in records.keys where records[id]?.status == .processing {
            records[id]?.status = .pending
            records[id]?.updatedAt = Date()
        }
        persistSilently()
        logger.info("queue paused")
    }
    
    public func resume() {
        isPaused = false
        advanceQueue()
        logger.info("queue resumed")
    }
    
    /// Cancel all pending and processing jobs.
    public func cancelAll() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        for id in records.keys where records[id]?.status == .pending || records[id]?.status == .processing {
            records[id]?.status = .cancelled
            records[id]?.error = "Cancelled by cancelAll()."
            records[id]?.updatedAt = Date()
        }
        persistSilently()
        logger.info("queue cancelld all pending and processing jobs")
    }

    /// Remove every record from the queue and cancel any in-flight work.
    public func clearAll() {
        let ids = records.keys.filter {
            records[$0]?.status == .completed ||
            records[$0]?.status == .failed ||
            records[$0]?.status == .cancelled
        }
        guard !ids.isEmpty else { return }
        for id in ids {
            records.removeValue(forKey: id)
        }
        persistSilently()
        logger.info("queue cleared all completed, failed, cancelled")
    }

    // ─── Retry all failed/cancelled ──────────────────────────────────────────

    /// Resume every failed or cancelled job at once.
    public func retryAll() {
        var changed = false
        for id in records.keys where records[id]?.status == .failed || records[id]?.status == .cancelled {
            records[id]?.status = .pending
            records[id]?.error = nil
            records[id]?.updatedAt = Date()
            changed = true
        }
        if changed {
            persistSilently()
            advanceQueue()
        }
        logger.info("queue retry all failed and cancelled jobs")
    }

    // ─── Persistence ─────────────────────────────────────────────────────────

    /// Call once at app launch (e.g. in `AppDelegate` / `.task`) to restore
    /// persisted jobs. Jobs that were mid-flight are reset to `.pending`.
    private func loadPersistedState() {
        do {
            var loaded = try store.load()

            // Reset any jobs that were "processing" when the app was killed.
            for i in loaded.indices where loaded[i].status == .processing {
                loaded[i].status = .pending
                loaded[i].updatedAt = Date()
            }

            records.removeAll()
            for record in loaded {
                records[record.id] = record
            }

            if autoCleanupEnabled { pruneIfNeeded() }
        } catch {
            // Corrupted file — start with empty queue.
            logger.error("Failed to load persisted state: \(error.localizedDescription)")
        }
    }

    // MARK: - Computed helpers

    /// Pending + processing count only.
    public var activeCount: Int {
        records.values.filter { $0.status == .pending || $0.status == .processing }.count
    }

    /// All records sorted by creation date, newest first.
    public var sortedRecords: [JobRecord] {
        records.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func records(with status: JobStatus) -> [JobRecord] {
        records.values.filter { $0.status == status }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Internal Processing

    private func advanceQueue() {
        guard !isProcessing else { return }

        guard let next = records.values
            .filter({ $0.status == .pending })
            .min(by: { $0.createdAt < $1.createdAt })   // FIFO
        else {
            if records.values.allSatisfy({ $0.status != .processing }) {
                emit(.queueDrained)
            }
            return
        }

        isProcessing = true
        records[next.id]?.status = .processing
        records[next.id]?.updatedAt = Date()
        records[next.id]?.startedAt = Date()
        emit(.jobStarted(id: next.id))

        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.execute(recordID: next.id)
        }
    }

    private func execute(recordID: UUID) async {
        guard let record = records[recordID] else {
            finishExecution(id: recordID)
            return
        }

        do {
            let executable = try registry.restore(from: record)
            try await executable.execute()

            records[recordID]?.status = .completed
            records[recordID]?.error = nil
            records[recordID]?.updatedAt = Date()
            records[recordID]?.completedAt = Date()
            emit(.jobCompleted(id: recordID))

        } catch is CancellationError {
            // Only update to .cancelled if the caller already marked it; otherwise
            // leave whatever the cancelRequest set (to avoid clobbering the reason).
            if records[recordID]?.status == .processing {
                records[recordID]?.status = .cancelled
                records[recordID]?.error = "Cancelled."
                records[recordID]?.updatedAt = Date()
            }
            emit(.jobCancelled(id: recordID))

        } catch {
            records[recordID]?.status = .failed
            records[recordID]?.error = error.localizedDescription
            records[recordID]?.updatedAt = Date()
            emit(.jobFailed(id: recordID, error: error))
        }

        finishExecution(id: recordID)
    }

    private func finishExecution(id: UUID) {
        currentTask = nil
        isProcessing = false
        guard records[id] != nil else { return }  // ← cleared while executing
        persistSilently()
        
        if isPaused { return }
        advanceQueue()
    }

    // MARK: - Auto-Cleanup

    /// Removes terminal (completed / failed / cancelled) records when the queue
    /// exceeds `maxRecords`, oldest first.
    private func pruneIfNeeded() {
        guard records.count > maxRecords else { return }

        let terminal = records.values
            .filter { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
            .sorted { $0.createdAt < $1.createdAt }  // oldest first

        let excess = records.count - maxRecords
        for record in terminal.prefix(excess) {
            records.removeValue(forKey: record.id)
        }
    }

    // MARK: - Persistence helpers

    private func persistSilently() {
        do {
            try store.save(Array(records.values))
        } catch {
            print("[JobQueue] Persistence error: \(error.localizedDescription)")
        }
    }

    private func emit(_ event: JobQueueEvent) {
        eventHandler?(event)
    }
}
