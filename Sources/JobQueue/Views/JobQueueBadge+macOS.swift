#if os(macOS)
import SwiftUI

public struct JobQueueBadge: View {
    private let queue: JobQueue
    private let visibleStatuses: [JobStatus]
    private let showsQueueStatus: Bool

    public init(
        queue: JobQueue,
        visibleStatuses: [JobStatus] = JobStatus.allCases,
        showsQueueStatus: Bool = true
    ) {
        self.queue = queue
        self.visibleStatuses = visibleStatuses
        self.showsQueueStatus = showsQueueStatus
    }

    public var body: some View {
        HStack(spacing: 8) {
            if showsQueueStatus {
                Text("Queue:")
                    .foregroundStyle(.secondary)

                Text(queue.status.label)
                    .foregroundStyle(queue.status.color)
                    .font(.caption.bold())
            }

            if showsQueueStatus && hasVisibleStatusCounts {
                Text("|")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(visibleStatuses, id: \.self) { status in
                statusCount(status)
            }
        }
    }

    private var hasVisibleStatusCounts: Bool {
        visibleStatuses.contains { queue.records(with: $0).count > 0 }
    }

    @ViewBuilder
    private func statusCount(_ status: JobStatus) -> some View {
        let count = queue.records(with: status).count
        if count > 0 {
            HStack(spacing: 4) {
                Circle()
                    .fill(status.color)
                    .frame(width: 7, height: 7)

                Text("\(count)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .help(status.label)
        }
    }
}
#endif
