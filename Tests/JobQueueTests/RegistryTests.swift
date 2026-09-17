import Foundation
import Testing
@testable import JobQueue

extension ConcurrentJobQueueTests.Registry {
    @Test("registers realistic app job types idempotently")
    func registersAppTypesIdempotently() throws {
        let registry = JobRegistry()

        try registry.register(SynthesisJob.self)
        try registry.register(SynthesisJob.self)
        try registry.register(DownloadModelJob.self)
        try registry.register(ExportJob.self)

        #expect(registry.concurrencyLimit(for: "SynthesisJob") == 1)
        #expect(registry.concurrencyLimit(for: "DownloadModelJob") == 2)
        #expect(registry.concurrencyLimit(for: "ExportJob") == 2)
    }

    @Test("rejects enqueueing an app job type that was not registered")
    @MainActor func rejectsUnregisteredJob() throws {
        let queue = JobQueue(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).json"),
            policy: JobQueuePolicy(maxConcurrentExecutions: 2),
            registry: JobRegistry()
        )

        #expect(throws: JobQueueError.self) {
            try queue.enqueue(SynthesisJob("unregistered"))
        }
    }
}
