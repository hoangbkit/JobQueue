#if os(macOS)
import SwiftUI

#if DEBUG

@MainActor
private enum JobQueuePreviewData {
    static let now = Date()

    static func record(
        status: JobStatus,
        title: String,
        detail: String? = nil,
        error: String? = nil,
        createdOffset: TimeInterval,
        startedOffset: TimeInterval? = nil,
        completedOffset: TimeInterval? = nil
    ) -> JobRecord {
        let createdAt = now.addingTimeInterval(-createdOffset)
        let startedAt = startedOffset.map { now.addingTimeInterval(-$0) }
        let completedAt = completedOffset.map { now.addingTimeInterval(-$0) }

        return JobRecord(
            id: UUID(),
            typeName: "PreviewJob",
            title: title,
            detail: detail,
            status: status,
            error: error,
            createdAt: createdAt,
            updatedAt: completedAt ?? startedAt ?? createdAt,
            startedAt: startedAt,
            completedAt: completedAt,
            encodedJob: Data()
        )
    }

    static let samples: [JobRecord] = [
        record(
            status: .pending,
            title: "Generate a Very Long Welcome Audio Track for the New Multi-Step Onboarding Experience",
            detail: "Queued for synthesis with a long description that should wrap to two lines and then truncate cleanly inside the compact task column.",
            createdOffset: 90
        ),
        record(
            status: .processing,
            title: "Render Chapter 4",
            detail: "Neural voice rendering.",
            createdOffset: 240,
            startedOffset: 35
        ),
        record(
            status: .completed,
            title: "Export Daily Briefing",
            detail: "Saved to Audio Library.",
            createdOffset: 900,
            startedOffset: 840,
            completedOffset: 780
        ),
        record(
            status: .completed,
            title: "Synthesize Product Intro",
            detail: "Finished 38 second narration.",
            createdOffset: 23 * 60 * 60,
            startedOffset: 23 * 60 * 60 - 40,
            completedOffset: 23 * 60 * 60 - 80
        ),
        record(
            status: .completed,
            title: "Generate Lesson Summary",
            detail: "Saved MP3 and captions.",
            createdOffset: 25 * 60 * 60,
            startedOffset: 25 * 60 * 60 - 40,
            completedOffset: 25 * 60 * 60 - 80
        ),
        record(
            status: .completed,
            title: "Render Podcast Segment",
            detail: "Voiceover exported.",
            createdOffset: 30 * 60 * 60,
            startedOffset: 30 * 60 * 60 - 40,
            completedOffset: 30 * 60 * 60 - 90
        ),
        record(
            status: .completed,
            title: "Create Onboarding Clip",
            detail: "Added to onboarding pack.",
            createdOffset: 2 * 24 * 60 * 60,
            startedOffset: 2 * 24 * 60 * 60 - 40,
            completedOffset: 2 * 24 * 60 * 60 - 90
        ),
        record(
            status: .completed,
            title: "Narrate Release Notes",
            detail: "Generated final audio.",
            createdOffset: 3 * 24 * 60 * 60,
            startedOffset: 3 * 24 * 60 * 60 - 40,
            completedOffset: 3 * 24 * 60 * 60 - 80
        ),
        record(
            status: .completed,
            title: "Export Meditation Prompt",
            detail: "Calm voice preset.",
            createdOffset: 4 * 24 * 60 * 60,
            startedOffset: 4 * 24 * 60 * 60 - 40,
            completedOffset: 4 * 24 * 60 * 60 - 80
        ),
        record(
            status: .completed,
            title: "Generate Support Reply",
            detail: "Short-form answer audio.",
            createdOffset: 5 * 24 * 60 * 60,
            startedOffset: 5 * 24 * 60 * 60 - 40,
            completedOffset: 5 * 24 * 60 * 60 - 80
        ),
        record(
            status: .completed,
            title: "Render Story Draft",
            detail: "Chapter preview completed.",
            createdOffset: 6 * 24 * 60 * 60,
            startedOffset: 6 * 24 * 60 * 60 - 40,
            completedOffset: 6 * 24 * 60 * 60 - 80
        ),
        record(
            status: .completed,
            title: "Create Training Prompt",
            detail: "Voice sample generated.",
            createdOffset: 7 * 24 * 60 * 60,
            startedOffset: 7 * 24 * 60 * 60 - 40,
            completedOffset: 7 * 24 * 60 * 60 - 80
        ),
        record(
            status: .completed,
            title: "Synthesize Closing Message",
            detail: "Final greeting exported.",
            createdOffset: 8 * 24 * 60 * 60,
            startedOffset: 8 * 24 * 60 * 60 - 40,
            completedOffset: 8 * 24 * 60 * 60 - 80
        ),
        record(
            status: .failed,
            title: "Sync Narration Draft",
            detail: "Remote service unavailable.",
            error: "Remote service unavailable.",
            createdOffset: 1_800,
            startedOffset: 1_740,
            completedOffset: 1_700
        ),
        record(
            status: .cancelled,
            title: "Batch Voice Cleanup",
            detail: "Cancelled before export.",
            createdOffset: 3_600,
            startedOffset: 3_540,
            completedOffset: 3_500
        ),
        record(
            status: .unrecoverable,
            title: "Unsupported Legacy Job",
            detail: "Stored job type no longer exists.",
            error: "Job type 'LegacyPreviewJob' is no longer supported.",
            createdOffset: 7_200,
            completedOffset: 7_100
        )
    ]

    static func queue() -> JobQueue {
        let queue = JobQueue(
            fileURL: previewURL("queue"),
            policy: JobQueuePolicy(maxConcurrentExecutions: 4)
        )
        queue.configurePreview(
            records: samples,
            progress: [
                samples[1].id: JobProgress(
                    fractionCompleted: 0.42,
                    message: "Rendering"
                )
            ]
        )
        return queue
    }

    static func emptyQueue() -> JobQueue {
        JobQueue(
            fileURL: previewURL("empty"),
            policy: JobQueuePolicy(maxConcurrentExecutions: 4)
        )
    }

    private static func previewURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("concurrent-jobqueue-preview-\(name)-\(UUID().uuidString).json")
    }
}

@MainActor
private struct JobQueuePopoverPreview: View {
    let queue = JobQueuePreviewData.queue()
    let emptyQueue = JobQueuePreviewData.emptyQueue()

    @State private var presentedQueue: PresentedQueue?

    private enum PresentedQueue: Identifiable {
        case populated
        case empty
        case filtered

        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 16) {
            Button {
                presentedQueue = .populated
            } label: {
                JobQueueBadge(queue: queue)
            }

            Button {
                presentedQueue = .empty
            } label: {
                HStack(spacing: 6) {
                    JobQueueBadge(queue: emptyQueue)
                }
            }

            Button {
                presentedQueue = .filtered
            } label: {
                JobQueueBadge(
                    queue: queue,
                    visibleStatuses: [.processing, .failed],
                    showsQueueStatus: false
                )
            }
        }
        .padding()
        .popover(item: $presentedQueue) { presentedQueue in
            NavigationStack {
                JobQueueView(
                    queue: queue(for: presentedQueue),
                    onEdit: presentedQueue == .empty ? nil : { _ in }
                )
            }
            .frame(width: 520, height: 420)
        }
    }

    private func queue(for presentedQueue: PresentedQueue) -> JobQueue {
        switch presentedQueue {
        case .populated:
            queue
        case .empty:
            emptyQueue
        case .filtered:
            queue
        }
    }
}

#Preview("JobQueue Popover") {
    JobQueuePopoverPreview()
        .frame(width: 500, height: 180)
}

#endif
#endif
