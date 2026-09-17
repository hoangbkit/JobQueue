#if os(macOS)
import SwiftUI

struct JobRecordActionIcon: View {
    let action: JobRecordAction

    var body: some View {
        JobActionIcon(
            systemImage: action.systemImage,
            tint: action.tint
        )
    }
}

struct JobActionIcon: View {
    let systemImage: String
    let tint: Color

    @State private var isHovering = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .background {
                Circle()
                    .fill(isHovering ? tint.opacity(0.14) : Color.clear)
            }
            #if os(macOS)
            .onHover { isHovering = $0 }
            #endif
            .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}
#endif
