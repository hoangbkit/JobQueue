# JobQueue

A serial, persistent job queue for macOS apps, built with Swift concurrency and
Observation. Define `Codable` jobs, enqueue them from your application, restore
unfinished work on launch, and optionally display queue state with the included
SwiftUI views.

> [!WARNING]
> JobQueue is under active development. Version `0.1.0` is an initial release,
> and public APIs, persistence format, and behavior may change before `1.0.0`.
> Evaluate upgrades carefully before using it for production-critical queues.

## Features

- FIFO processing with one active job per queue
- JSON persistence with atomic writes
- Restore pending work across application launches
- Cooperative cancellation, retry, pause, resume, replace, and cleanup APIs
- Observable queue state for SwiftUI applications
- Built-in `JobQueueView`, `JobRecordView`, `JobQueueBadge`, and
  `JobQueueButton` components
- Lifecycle events through `eventHandler`
- No external package dependencies

## Requirements

- Swift 6.0 or later
- macOS 14 or later

## Installation

Add JobQueue to your package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/hoangbkit/JobQueue.git", from: "0.1.0")
]
```

Then add `JobQueue` to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "JobQueue", package: "JobQueue")
    ]
)
```

In Xcode, use **File > Add Package Dependencies...** and enter the same
repository URL.

## Quick Start

### 1. Define A Job

Every job is `Codable` and `Sendable` so its data can be stored and restored.
Put everything needed to repeat the work in the payload.

```swift
import Foundation
import JobQueue

struct DownloadPayload: Codable, Sendable {
    let sourceURL: URL
    let destinationURL: URL
}

struct DownloadJob: Job {
    let id: UUID
    let payload: DownloadPayload

    var title: String? { "Download File" }
    var detail: String? { payload.sourceURL.lastPathComponent }

    init(sourceURL: URL, destinationURL: URL) {
        self.id = UUID()
        self.payload = DownloadPayload(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        )
    }

    func execute() async throws {
        try Task.checkCancellation()

        let (data, _) = try await URLSession.shared.data(from: payload.sourceURL)

        try Task.checkCancellation()
        try data.write(to: payload.destinationURL, options: .atomic)
    }
}
```

### 2. Create And Start The Queue

Register each concrete job type before calling `start()`. The parent directory
for the persistence file must already exist.

```swift
import Foundation
import JobQueue

@MainActor
func makeJobQueue() throws -> JobQueue {
    JobRegistry.shared.register(DownloadJob.self)

    let directory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("YourApp", isDirectory: true)

    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )

    let queue = JobQueue(
        fileURL: directory.appendingPathComponent("jobqueue.json"),
        maxRecords: 100,
        autoCleanupEnabled: true
    )

    queue.start()
    return queue
}
```

`start()` restores persisted records and resumes pending work. A job that was
processing when the application exited is restored as pending.

### 3. Enqueue Work

```swift
let job = DownloadJob(
    sourceURL: URL(string: "https://example.com/report.pdf")!,
    destinationURL: URL.documentsDirectory.appendingPathComponent("report.pdf")
)

try queue.enqueue(job)
```

## Observing Events

Set `eventHandler` to respond to queue lifecycle changes:

```swift
queue.eventHandler = { event in
    switch event {
    case .jobCompleted(let id):
        print("Completed: \(id)")
    case .jobFailed(let id, let error):
        print("Failed \(id): \(error.localizedDescription)")
    case .queueDrained:
        print("Queue drained")
    default:
        break
    }
}
```

Available events are `jobAdded`, `jobStarted`, `jobCompleted`, `jobFailed`,
`jobCancelled`, `jobRemoved`, and `queueDrained`.

## SwiftUI Views

`JobQueue` is observable and can be passed directly to the supplied views:

```swift
import SwiftUI
import JobQueue

struct QueueScreen: View {
    let queue: JobQueue

    var body: some View {
        VStack {
            JobQueueView(queue: queue)

            HStack {
                JobQueueBadge(queue: queue)

                JobQueueButton(queue: queue) {
                    // Present the full queue UI.
                }
            }
        }
    }
}
```

The package includes:

| View | Purpose |
| --- | --- |
| `JobQueueView` | Queue list with retry and clear actions |
| `JobRecordView` | One record row with status and row actions |
| `JobQueueBadge` | Compact counts by status |
| `JobQueueButton` | Queue button with processing/failure badge |

## Queue Operations

```swift
queue.cancel(id: id)                  // Cancel pending or processing work
queue.resume(id: id)                  // Retry one failed or cancelled record
try queue.replace(id: id, with: job)  // Replace failed or cancelled work
queue.retryAll()                      // Retry all failed/cancelled records
queue.pause()                         // Pause queue advancement
queue.resume()                        // Resume queue advancement
queue.cancelAll()                     // Cancel active/pending records
queue.clearAll()                      // Remove terminal records
queue.remove(id: id)                  // Remove a record
```

Read state through `records`, `sortedRecords`, `activeCount`,
`isProcessing`, or `records(with:)`.

## Execution Model

Queue state is managed on `MainActor`, and the queue starts jobs serially in
FIFO order. `Job.execute()` is asynchronous, but JobQueue does not guarantee a
dedicated background thread for synchronous work.

Network and other naturally asynchronous operations can be performed directly
inside `execute()`. A job that performs expensive synchronous work should
choose its own offloading strategy and honor cancellation where possible.

```swift
func execute() async throws {
    let result = try await Task.detached(priority: .utility) {
        try performExpensiveSynchronousWork()
    }.value

    try await save(result)
}
```

If multiple features share an exclusive resource, such as an on-device model,
coordinate access outside the queue and give interactive work appropriate
priority.

## Persistence

The queue writes `[JobRecord]` values as JSON to the `fileURL` supplied during
initialization. Jobs retain their encoded payload so queued work can be
restored and executed after relaunch.

Register all restored job types before `start()`:

```swift
JobRegistry.shared.register(DownloadJob.self)
queue.start()
```

If persisted JSON cannot be decoded, the corrupted file is removed and the
queue starts empty.

## Testing

Run the test suite with:

```bash
swift test
```

Tests cover FIFO execution, JSON save and restore, retry behavior, and emitted
lifecycle events. SwiftUI code is compiled by the package tests; interaction
testing of packaged views requires a small host application with UI tests.

## License

JobQueue is available under the MIT License. See [LICENSE](LICENSE).
