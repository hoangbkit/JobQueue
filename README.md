# JobQueue

> [!WARNING]
> This package is public, but it is not actively maintained. Use it as-is; issues, pull requests, and support requests may not be addressed.

A persistent Swift job queue for iOS and macOS with concurrency control, priorities, progress reporting, cancellation, pause/resume support, and SwiftUI queue views.

## Requirements

- Swift 6+
- iOS 17+
- macOS 15+

## Installation

Add `JobQueue` with Swift Package Manager:

```swift
.package(url: "https://github.com/hoangbkit/JobQueue.git", branch: "master")
```

Then add the `JobQueue` product to your target and import it:

```swift
import JobQueue
```

## Quick Start

Define a job. Jobs are `Codable` so pending work can be persisted and restored across launches.

```swift
import Foundation
import JobQueue

struct DownloadJob: Job {
    struct Payload: Codable, Sendable {
        let url: URL
    }

    static let maxConcurrentExecutions = 2

    let id = UUID()
    let payload: Payload

    var title: String? { payload.url.lastPathComponent }
    var detail: String? { payload.url.absoluteString }
    var priority: JobPriority { .utility }

    func execute(progress: JobProgressReporter) async throws {
        for step in 1...10 {
            try Task.checkCancellation()

            await progress.report(
                fractionCompleted: Double(step) / 10,
                message: "Downloading"
            )

            try await Task.sleep(for: .milliseconds(200))
        }
    }
}
```

Register the job types that the queue needs to restore, create a persistent queue, and start it:

```swift
let registry = JobRegistry()
try registry.register(DownloadJob.self)

let queueURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("jobs.json")

let queue = JobQueue(
    fileURL: queueURL,
    policy: JobQueuePolicy(maxConcurrentExecutions: 4),
    registry: registry
)

try queue.start()
```

Enqueue work normally:

```swift
try queue.enqueue(
    DownloadJob(
        payload: .init(url: URL(string: "https://example.com/file.zip")!)
    )
)
```

Or request an immediate start for user-initiated work:

```swift
try queue.enqueue(
    DownloadJob(
        payload: .init(url: URL(string: "https://example.com/preview.zip")!)
    ),
    startPolicy: .immediate
)
```

## Queue Control

`JobQueue` supports queue-wide and job-type-specific control, including:

- pause and resume
- cancellation
- retrying failed or cancelled work
- removing records
- priority-aware scheduling
- per-job-type concurrency limits
- queue-wide concurrency limits
- persistent job records
- live progress and queue status
- recovery of interrupted work after relaunch

You can observe queue state directly through properties such as `records`, `runningCount`, `activeCount`, `status`, and `liveProgress`.

## SwiftUI

The package includes native SwiftUI queue UI for both supported platforms.

```swift
import SwiftUI
import JobQueue

struct JobsView: View {
    let queue: JobQueue

    var body: some View {
        JobQueueView(queue: queue)
    }
}
```

`JobQueueBadge` is available when you only need a compact queue status control.

## Demo App

The demo lives in [`Examples/JobQueueDemo`](Examples/JobQueueDemo) and uses XcodeGen. The generated Xcode project is intentionally not committed.

Generate it with:

```bash
cd Examples/JobQueueDemo
xcodegen generate
```

The project defines explicit application target and scheme names for each platform:

| Platform | Minimum | Target / Scheme |
| --- | --- | --- |
| iOS | 17.0 | `JobQueueDemo-iOS` |
| macOS | 15.0 | `JobQueueDemo-macOS` |

Both demo targets use bundle identifier `com.hoangbkit.jobqueue.demo`.

### mycli

Because each platform has exactly one application target, `mycli` can resolve the target directly from `project.yml`.

From the repository root or the demo directory:

```bash
mycli xcodegen build ios
mycli xcodegen build mac
```

You can also select the schemes explicitly:

```bash
mycli xcodegen build ios --scheme JobQueueDemo-iOS
mycli xcodegen build mac --scheme JobQueueDemo-macOS
```

For deployment, use the same project configuration with `mycli xcodegen deploy` and your device name.

## License

JobQueue is available under the MIT License. See [LICENSE](LICENSE) for details.
