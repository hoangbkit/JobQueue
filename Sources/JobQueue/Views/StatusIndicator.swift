#if os(macOS)
import SwiftUI

struct JobStatusIndicator: View {
    let status: JobStatus

    @State private var ringRotation: Double = 0

    var body: some View {
        ZStack {
            if status.isExecuting {
                Circle()
                    .stroke(Color.blue.opacity(0.18), lineWidth: 1.5)

                Circle()
                    .trim(from: 0.08, to: 0.68)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(ringRotation))

                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityLabel(status.label)
        .onAppear { syncAnimation() }
        .onChange(of: status) { _, _ in syncAnimation() }
    }

    private func syncAnimation() {
        if status.isExecuting {
            ringRotation = 0
            withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        } else {
            ringRotation = 0
        }
    }
}
#endif
