// JobQueueStore.swift — Atomic JSON persistence for JobRecord arrays.

import Foundation

// MARK: - JobQueueStore

/// Handles reading and writing the queue's `[JobRecord]` to a single JSON file.
/// Writes are always atomic to prevent corruption on crash.
final class JobQueueStore: Sendable {

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - Save

    func save(_ records: [JobRecord]) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: [.atomicWrite])
        } catch {
            throw JobQueueError.persistenceFailed(error)
        }
    }

    // MARK: - Load

    func load() throws -> [JobRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([JobRecord].self, from: data)
        } catch {
            // Corrupted file — remove it so the queue starts fresh next time.
            try? FileManager.default.removeItem(at: fileURL)
            throw JobQueueError.persistenceFailed(error)
        }
    }

    // MARK: - Clear

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw JobQueueError.persistenceFailed(error)
        }
    }
}
