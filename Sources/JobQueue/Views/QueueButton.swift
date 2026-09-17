#if os(macOS)
import SwiftUI

public struct JobQueueButton: View {
    private let queue: JobQueue
    private let iconName: String
    private let action: () -> Void

    @State private var ringRotation: Double = 0

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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(queue.status.isExecuting ? queue.status.color : .primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.thinMaterial))
                    .overlay { processingRing }

                if badgeCount > 0 {
                    Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(badgeColor))
                        .offset(x: 3, y: -2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: badgeCount)
        .onAppear { syncProcessingAnimation() }
        .onChange(of: queue.status) { _, _ in syncProcessingAnimation() }
    }

    private var badgeCount: Int {
        if queue.activeCount > 0 {
            return queue.activeCount
        }
        return queue.records(with: .failed).count
    }

    private var badgeColor: Color {
        queue.records(with: .failed).isEmpty ? queue.status.color : .red
    }

    @ViewBuilder
    private var processingRing: some View {
        if queue.status.isExecuting {
            Circle()
                .stroke(queue.status.color.opacity(0.22), lineWidth: 2)
                .overlay {
                    Circle()
                        .trim(from: 0.02, to: 0.33)
                        .stroke(queue.status.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(ringRotation))
                }
                .padding(1)
        } else {
            Circle()
                .strokeBorder(.clear, lineWidth: 0)
        }
    }

    private func syncProcessingAnimation() {
        if queue.status.isExecuting {
            ringRotation = 0
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        } else {
            ringRotation = 0
        }
    }
}
#endif
