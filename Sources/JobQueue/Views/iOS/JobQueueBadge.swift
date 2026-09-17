#if os(iOS)
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
                Label(queue.status.label, systemImage: queue.status.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(queue.status.color)
            }

            ForEach(visibleStatuses, id: \.self) { status in
                let count = queue.records(with: status).count
                if count > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 7, height: 7)
                        Text("\(count)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("\(status.label): \(count)")
                }
            }
        }
    }
}
#endif
