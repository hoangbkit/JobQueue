#if os(iOS)
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.status.icon)
                .foregroundStyle(record.status.color)
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.title ?? record.typeName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)

                if let detail = record.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(progressText ?? record.status.label)
                    .font(.caption)
                    .foregroundStyle(progressText == nil ? record.status.color : .secondary)

                if let fraction = progress?.fractionCompleted,
                   record.status.isExecuting {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                }

                if let error = record.error,
                   record.status == .failed || record.status == .unrecoverable {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 4)

            Menu {
                actionMenuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
            }
        }
        .padding(.vertical, 5)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if onCancel != nil && (record.status == .pending || record.status.isExecuting) {
                Button("Cancel", systemImage: "xmark.circle", role: .destructive) {
                    onCancel?(record.id)
                }
            } else if onRemove != nil && record.status.isTerminal {
                Button("Remove", systemImage: "trash", role: .destructive) {
                    onRemove?(record.id)
                }
            }
        }
    }

    private var progressText: String? {
        guard let progress else { return nil }
        if let fraction = progress.fractionCompleted {
            let percentage = Int((fraction * 100).rounded())
            if let message = progress.message, !message.isEmpty {
                return "\(percentage)% · \(message)"
            }
            return "\(percentage)%"
        }
        guard let message = progress.message, !message.isEmpty else { return nil }
        return message
    }

    @ViewBuilder
    private var actionMenuItems: some View {
        let actions = JobQueue
            .availableActions(for: record, allowsEditing: onEdit != nil)
            .filter(isSupported)

        ForEach(actions, id: \.self) { action in
            Button(action.label, systemImage: action.systemImage, role: action.role) {
                perform(action)
            }
        }
    }

    private func isSupported(_ action: JobRecordAction) -> Bool {
        switch action {
        case .editAndRequeue: onEdit != nil
        case .cancel: onCancel != nil
        case .retry: onRetry != nil
        case .remove: onRemove != nil
        }
    }

    private func perform(_ action: JobRecordAction) {
        switch action {
        case .editAndRequeue: onEdit?(record.id)
        case .cancel: onCancel?(record.id)
        case .retry: onRetry?(record.id)
        case .remove: onRemove?(record.id)
        }
    }
}
#endif
