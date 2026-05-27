# swift-job-queue

```swift
// Usage.swift — How to plug JobQueue into TinyTTS (replaces BatchManager)
//
// This file is NOT part of the library — paste the relevant parts into your app.

import Foundation
import SwiftUI
import JobQueue   // ← your new SPM package

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 1. Define your concrete Job type
// ─────────────────────────────────────────────────────────────────────────────

struct SpeechPayload: Codable, Sendable {
    var audioId: String?          // Audio.ID serialized as String
    var text: String
    var voice: String
    var speed: Double
    // add every field from your Audio.Options that needs to round-trip
}

struct SpeechJob: Job {
    let id: UUID
    let payload: SpeechPayload
    var title: String? { "Synthesize Speech" }
    var detail: String? { payload.text }

    init(audioId: String? = nil, text: String, voice: String, speed: Double = 1.0) {
        self.id      = UUID()
        self.payload = SpeechPayload(audioId: audioId, text: text, voice: voice, speed: speed)
    }

    func execute() async throws {
        // 1. Run KokoroServer / ModelManager synthesis — same logic as your
        //    former synthesizeAndSave(options:) method.
        // 2. On success, save the resulting URL to your database.
        //    (Use Container.shared.dataManager() / appService() here)
        //
        // Throwing CancellationError (or calling try Task.checkCancellation())
        // tells the queue the job was cancelled.
        print("▶️  synthesising: \(payload.text)")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 2. Bootstrap (once at app start)
// ─────────────────────────────────────────────────────────────────────────────

// In your App struct or AppDelegate:

@main
struct TinyTTSApp: App {

    // Shared queue — wire through Container / @Environment as you prefer
    @State private var jobQueue: JobQueue = {
        // Register types BEFORE loading state
        JobRegistry.shared.register(SpeechJob.self)

        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tts_queue.json")

        let queue = JobQueue(
            fileURL: url,
            maxRecords: 50,          // same as your old maxRequests
            autoCleanupEnabled: true
        )

        // Optional: listen to events for analytics / notifications
        queue.eventHandler = { event in
            switch event {
            case .jobCompleted(let id):  print("✅ \(id)")
            case .jobFailed(let id, let err): print("❌ \(id): \(err)")
            case .queueDrained:          print("🏁 queue drained")
            default: break
            }
        }

        // Restore from last run (crashed jobs reset to .pending automatically)
        queue.loadPersistedState()
        return queue
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(jobQueue)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 3. Enqueue from anywhere
// ─────────────────────────────────────────────────────────────────────────────

struct AddJobExample: View {
    @Environment(JobQueue.self) private var queue

    var body: some View {
        Button("Add TTS Job") {
            let job = SpeechJob(text: "Hello from JobQueue", voice: "default")
            try? queue.enqueue(job)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 4. Display the queue  (replaces your BatchQueueView)
// ─────────────────────────────────────────────────────────────────────────────

struct TTSQueueView: View {
    @Environment(JobQueue.self) private var queue

    var body: some View {
        // JobQueueView has built-in docked footer actions (Retry All / Clear All).
        // JobRecordView shows `record.title` and `record.detail` when available.
        JobQueueView(queue: queue) { record in
            // Fallback label if title is not provided by your Job type.
            return record.typeName
        }
        .navigationTitle("TTS Queue")
    }
}

// Optional compact indicators and trigger button
struct QueueIndicators: View {
    @Environment(JobQueue.self) private var queue

    var body: some View {
        HStack(spacing: 12) {
            JobQueueBadge(queue: queue) // shows counts for all statuses
            JobQueueButton(queue: queue, iconName: "waveform") {
                // open queue screen
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 5. Mapping from your old SpeechRequest / BatchManager API
// ─────────────────────────────────────────────────────────────────────────────
//
//  Old API                             New API
//  ──────────────────────────────────  ──────────────────────────────────────
//  batchManager.addRequest(_:)         queue.enqueue(SpeechJob(…))
//  batchManager.cancelRequest(id:)     queue.cancel(id:)
//  batchManager.resumeRequest(id:)     queue.resume(id:)
//  batchManager.removeRequest(id:)     queue.remove(id:)
//  batchManager.clearQueue()           queue.clearAll()
//  batchManager.getCurrentRequests()   queue.sortedRecords
//  batchManager.isProcessing           queue.isProcessing
//  batchManager.requests[id]           queue.records[id]   (JobRecord)
//  SpeechRequest.status                JobRecord.status    (JobStatus)
//  batchManager.loadQueueState()       queue.loadPersistedState()
```
