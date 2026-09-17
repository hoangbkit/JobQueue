#if os(macOS)
import SwiftUI

public struct JobRecordView: View {
    public let record: JobRecord
    public var onCancel: ((UUID) -> Void)?
    public var onRetry: ((UUID) -> Void)?
    public var onRemove: ((UUID) -> Void)?
    public var onEdit: ((UUID) -> Void)?
    public var progress: JobProgress?

    public init(
        record: JobRecord,
        onCancel: ((UUID) -> Void)? = nil,
        onRetry: ((UUID) -> Void)? = nil,
        onRemove: ((UUID) -> Void)? = nil,
        onEdit: ((UUID) -> Void)? = nil,
        progress: JobProgress? = nil
    ) {
        self.record = record
        self.onCancel = onCancel
        self.onRetry = onRetry
        self.onRemove = onRemove
        self.onEdit = onEdit
        self.progress = progress
    }

    public var body: some View {
        HStack(spacing: 12) {
            JobStatusIndicator(status: record.status)
                .frame(width: 18, height: 18)

            Text(record.title ?? record.typeName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            statusSummary
                .frame(minWidth: 120, idealWidth: 180, maxWidth: 220, alignment: .leading)

            createdTime
                .frame(width: 52, alignment: .trailing)

            Menu {
                actionMenuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 2)
        .contextMenu {
            actionMenuItems
        }
    }

    @ViewBuilder
    private var statusSummary: some View {
        Text(progressText ?? statusText)
            .font(.caption)
            .foregroundStyle(progressText == nil ? statusTextColor : .secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var statusText: String {
        if let error = record.error,
           record.status == .failed || record.status == .unrecoverable {
            return error
        }
        return record.status.label
    }

    private var statusTextColor: Color {
        if record.status == .failed || record.status == .unrecoverable {
            return .red
        }
        return record.status.color
    }

    private var progressText: String? {
        guard let progress else { return nil }
        if let fractionCompleted = progress.fractionCompleted {
            let percentage = Int((fractionCompleted * 100).rounded())
            if let message = progress.message, !message.isEmpty {
                return "\(percentage)% · \(message)"
            }
            return "\(percentage)%"
        }
        guard let message = progress.message, !message.isEmpty else { return nil }
        return message
    }

    private var createdTime: some View {
        Text(JobRelativeCreatedTime.display(from: record.createdAt).primary)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(JobRelativeCreatedTime.exactString(from: record.createdAt))
    }

    @ViewBuilder
    private var actionMenuItems: some View {
        let actions = JobQueue
            .availableActions(for: record, allowsEditing: onEdit != nil)
            .filter(isSupported)

        ForEach(actions, id: \.self) { action in
            Button(role: action.role) {
                perform(action)
            } label: {
                Label(action.label, systemImage: action.systemImage)
            }
        }

        if actions.isEmpty {
            Label("No Actions", systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func isSupported(_ action: JobRecordAction) -> Bool {
        switch action {
        case .editAndRequeue:
            onEdit != nil
        case .cancel:
            onCancel != nil
        case .retry:
            onRetry != nil
        case .remove:
            onRemove != nil
        }
    }

    private func perform(_ action: JobRecordAction) {
        switch action {
        case .editAndRequeue:
            onEdit?(record.id)
        case .cancel:
            onCancel?(record.id)
        case .retry:
            onRetry?(record.id)
        case .remove:
            onRemove?(record.id)
        }
    }
}
#endif
