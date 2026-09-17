#if os(macOS)
import SwiftUI

public struct JobQueueView: View {
    @Bindable private var queue: JobQueue
    private var customTaskContent: ((JobRecord) -> AnyView?)?
    private var onInfo: ((JobRecord) -> Void)?
    private var onEdit: ((JobRecord) -> Void)?
    private var onError: ((Error) -> Void)?

    @State private var selectedID: UUID?
    @State private var alertMessage: String?
    @State private var confirmation: Confirmation?
    @State private var sortOrder: [KeyPathComparator<JobRecord>] = [
        .init(\.createdAt, order: .reverse)
    ]

    private var sortedRecords: [JobRecord] {
        queue.records.values.sorted(using: sortOrder)
    }

    public init(
        queue: JobQueue,
        onInfo: ((JobRecord) -> Void)? = nil,
        onEdit: ((JobRecord) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.queue = queue
        self.customTaskContent = nil
        self.onInfo = onInfo
        self.onEdit = onEdit
        self.onError = onError
    }

    public init<J: Job, TaskContent: View>(
        queue: JobQueue,
        onInfo: ((JobRecord) -> Void)? = nil,
        onEdit: ((JobRecord) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil,
        taskContentFor jobType: J.Type,
        @ViewBuilder taskContent: @escaping (J, JobRecord) -> TaskContent
    ) {
        self.queue = queue
        self.customTaskContent = { record in
            guard
                record.typeName == String(describing: jobType),
                let job = try? record.decode(jobType)
            else {
                return nil
            }
            return AnyView(taskContent(job, record))
        }
        self.onInfo = onInfo
        self.onEdit = onEdit
        self.onError = onError
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                if sortedRecords.isEmpty {
                    emptyState
                } else {
                    recordsTable
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let issue = queue.persistenceIssue {
                persistenceErrorBanner(issue)
            }

            footerActions
        }
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("concurrent-job-queue-view")
        .alert("Error", isPresented: isShowingAlert) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: isShowingConfirmation,
            titleVisibility: .visible
        ) {
            if let confirmation {
                Button(confirmation.confirmLabel, role: .destructive) {
                    performConfirmed(confirmation)
                }

                Button("Cancel", role: .cancel) {
                    self.confirmation = nil
                }
            }
        } message: {
            if let message = confirmation?.message {
                Text(message)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Queue Empty",
            systemImage: "tray",
            description: Text("Synthesis jobs you add will appear here.")
        )
        .accessibilityIdentifier("concurrent-job-queue-empty-state")
    }

    private var recordsTable: some View {
        Table(sortedRecords, selection: $selectedID, sortOrder: $sortOrder) {
            TableColumn("#") { record in
                statusIndicator(for: record)
            }
            .width(18)

            TableColumn("Task", sortUsing: KeyPathComparator(\.title)) { record in
                taskSummary(for: record)
            }
            .width(min: 120, ideal: 190)

            TableColumn("Status", sortUsing: KeyPathComparator(\.status)) { record in
                statusSummary(for: record)
            }
            .width(min: 80, ideal: 80, max: 80)

            TableColumn("Added", sortUsing: KeyPathComparator(\.createdAt)) { record in
                addedTime(for: record)
            }
            .width(min: 70, ideal: 70, max: 80)

            TableColumn("Actions") { record in
                actionButtons(for: record)
            }
            .width(min: 88, ideal: 100, max: 112)
        }
        .accessibilityIdentifier("concurrent-job-queue-table")
    }

    @ViewBuilder
    private func statusIndicator(for record: JobRecord) -> some View {
        JobStatusIndicator(status: record.status)
    }

    private func addedTime(for record: JobRecord) -> some View {
        let display = JobRelativeCreatedTime.display(from: record.createdAt)
        return VStack(alignment: .leading, spacing: 1) {
            Text(display.primary)
                .font(.caption.monospacedDigit())
                .lineLimit(1)

            if let secondary = display.secondary {
                Text(secondary)
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.secondary)
        .help(JobRelativeCreatedTime.exactString(from: record.createdAt))
    }

    @ViewBuilder
    private func taskSummary(for record: JobRecord) -> some View {
        if let customContent = customTaskContent?(record) {
            customContent
        } else {
            defaultTaskSummary(for: record)
        }
    }

    private func defaultTaskSummary(for record: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(record.title ?? record.typeName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)

            if let detail = record.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if record.status == .processing,
               let progress = queue.progress(for: record.id) {
                progressBar(progress)
            }

            if (record.status == .failed || record.status == .unrecoverable),
               let error = record.error,
               !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(error)
            }

        }
    }

    @ViewBuilder
    private func statusSummary(for record: JobRecord) -> some View {
        Text(record.status.label)
            .font(.caption)
            .foregroundStyle(record.status.color)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func progressBar(_ progress: JobProgress) -> some View {
        if let fractionCompleted = progress.fractionCompleted {
            ProgressView(value: fractionCompleted)
                .controlSize(.small)
                .tint(.blue)
                .frame(maxWidth: 60)
        } else {
            Text(progress.message?.isEmpty == false ? progress.message! : "Processing")
                .font(.caption)
                .foregroundStyle(.blue)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func actionButtons(for record: JobRecord) -> some View {
        let actions = queue.availableActions(for: record, allowsEditing: onEdit != nil)
        return HStack(spacing: 4) {
            Spacer(minLength: 0)

            if let onInfo {
                Button {
                    onInfo(record)
                } label: {
                    JobActionIcon(
                        systemImage: "info.circle",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)
                .help("Show Details")
                .accessibilityLabel("Show Details")
            }

            ForEach(actions, id: \.self) { action in
                Button(role: action.role) {
                    request(recordAction: action, record: record)
                } label: {
                    JobRecordActionIcon(action: action)
                }
                .buttonStyle(.plain)
                .help(action.label)
            }
        }
    }

    private func request(recordAction action: JobRecordAction, record: JobRecord) {
        switch action {
        case .editAndRequeue:
            onEdit?(record)
        case .retry:
            perform { try queue.perform(action, for: record.id) }
        case .remove where record.status == .completed:
            perform { try queue.perform(action, for: record.id) }
        case .cancel, .remove:
            confirmation = .record(action: action, record: record)
        }
    }

    private func persistenceErrorBanner(
        _ issue: JobQueuePersistenceIssue
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(persistenceErrorTitle(issue))
                    .font(.caption.bold())

                Text(issue.errorDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            ForEach(queue.availableActions.filter(\.isPersistenceRecovery), id: \.self) { action in
                Button(action.label, role: action.role) {
                    request(queueAction: action)
                }
                .accessibilityIdentifier("concurrent-job-queue-persistence-\(action)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
        .accessibilityIdentifier("concurrent-job-queue-persistence-banner")
    }

    private func persistenceErrorTitle(
        _ issue: JobQueuePersistenceIssue
    ) -> String {
        switch issue {
        case .loadFailed:
            "Saved queue data could not be loaded."
        case .saveFailed:
            "Queue changes could not be saved."
        }
    }

    private var footerActions: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            HStack(spacing: 8) {
                ForEach(footerQueueActions, id: \.self) { action in
                    Button(action.label, systemImage: action.systemImage, role: action.role) {
                        request(queueAction: action)
                    }
                    .buttonStyle(AdaptiveButtonStyle(prominence: .subtle))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var footerQueueActions: [JobQueueAction] {
        let pauseAction: JobQueueAction = queue.isPaused ? .resume : .pause
        let otherActions = queue.availableActions.filter {
            $0.isQueueControl && $0 != .pause && $0 != .resume
        }
        return [pauseAction] + otherActions
    }

    private var isShowingAlert: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )
    }

    private var isShowingConfirmation: Binding<Bool> {
        Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        )
    }

    private func request(queueAction action: JobQueueAction) {
        if action.requiresConfirmation {
            confirmation = .queue(action)
        } else {
            perform { try queue.perform(action) }
        }
    }

    private func performConfirmed(_ confirmation: Confirmation) {
        self.confirmation = nil
        switch confirmation {
        case .queue(let action):
            perform { try queue.perform(action) }
        case .record(let action, let record):
            perform { try queue.perform(action, for: record.id) }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            alertMessage = error.localizedDescription
            onError?(error)
        }
    }
}
#endif
