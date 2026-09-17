#if os(iOS)
import SwiftUI

public struct JobQueueButton: View {
    private let queue: JobQueue
    private let iconName: String
    private let action: () -> Void

    public init(
        queue: JobQueue,
        iconName: String = "tray.full.fill",
        action: @escaping () -> Void = {}
    ) {
        self.queue = queue
        self.iconName = iconName
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: iconName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(queue.status.isExecuting ? queue.status.color : .primary)
                    .frame(width: 32, height: 32)

                if badgeCount > 0 {
                    Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(badgeColor))
                        .offset(x: 8, y: -6)
                }
            }
        }
        .accessibilityLabel("Queue")
        .accessibilityValue(badgeCount > 0 ? "\(badgeCount) active or failed jobs" : queue.status.label)
    }

    private var badgeCount: Int {
        queue.activeCount > 0 ? queue.activeCount : queue.records(with: .failed).count
    }

    private var badgeColor: Color {
        queue.records(with: .failed).isEmpty ? queue.status.color : .red
    }
}
#endif
