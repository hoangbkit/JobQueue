#if os(iOS)
import SwiftUI

public struct JobQueueView: View {
    @Bindable private var queue: JobQueue
    private var customTaskContent: ((JobRecord) -> AnyView?)?
    private var summaryContent: (() -> AnyView)?
    private var showsQueueSummary: Bool
    private var onInfo: ((JobRecord) -> Void)?
    private var onEdit: ((JobRecord) -> Void)?
    private var onQueueAction: ((JobQueueAction) -> Void)?
    private var onRecordAction: ((JobRecordAction, JobRecord) -> Void)?
    private var onError: ((Error) -> Void)?

    @State private var alertMessage: String?
    @State private var confirmation: Confirmation?

    public init(
        queue: JobQueue,
        showsQueueSummary: Bool = true,
        onInfo: ((JobRecord) -> Void)? = nil,
        onEdit: ((JobRecord) -> Void)? = nil,
        onQueueAction: ((JobQueueAction) -> Void)? = nil,
        onRecordAction: ((JobRecordAction, JobRecord) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.queue = queue
        self.customTaskContent = nil
        self.summaryContent = nil
        self.showsQueueSummary = showsQueueSummary
        self.onInfo = onInfo
        self.onEdit = onEdit
        self.onQueueAction = onQueueAction
        self.onRecordAction = onRecordAction
        self.onError = onError
    }

    public init<SummaryContent: View>(
        queue: JobQueue,
        showsQueueSummary: Bool = true,
        onInfo: ((JobRecord) -> Void)? = nil,
        onEdit: ((JobRecord) -> Void)? = nil,
        onQueueAction: ((JobQueueAction) -> Void)? = nil,
        onRecordAction: ((JobRecordAction, JobRecord) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil,
        @ViewBuilder summaryContent: @escaping () -> SummaryContent
    ) {
        self.queue = queue
        self.customTaskContent = nil
        self.summaryContent = { AnyView(summaryContent()) }
        self.showsQueueSummary = showsQueueSummary
        self.onInfo = onInfo
        self.onEdit = onEdit
        self.onQueueAction = onQueueAction
        self.onRecordAction = onRecordAction
        self.onError = onError
    }

    public init<J: Job, TaskContent: View>(
        queue: JobQueue,
        showsQueueSummary: Bool = true,
        onInfo: ((JobRecord) -> Void)? = nil,
        onEdit: ((JobRecord) -> Void)? = nil,
        onQueueAction: ((JobQueueAction) -> Void)? = nil,
        onRecordAction: ((JobRecordAction, JobRecord) -> Void)? = nil,
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
        self.summaryContent = nil
        self.showsQueueSummary = showsQueueSummary
        self.onInfo = onInfo
        self.onEdit = onEdit
        self.onQueueAction = onQueueAction
        self.onRecordAction = onRecordAction
        self.onError = onError
    }

    public var body: some View {
        List {
            if showsQueueSummary {
                Section {
                    queueSummary
                }
            } else if let summaryContent {
                Section {
                    summaryContent()
                }
            }

            if let issue = queue.persistenceIssue {
                Section {
                    persistenceIssueView(issue)
                }
            }

            Section("Jobs") {
                if queue.sortedRecords.isEmpty {
                    ContentUnavailableView(
                        "Queue Empty",
                        systemImage: "tray",
                        description: Text("Jobs you add will appear here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(queue.sortedRecords) { record in
                        recordRow(record)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            if !toolbarQueueActions.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(toolbarQueueActions, id: \.self) { action in
                            Button(action.label, systemImage: action.systemImage, role: action.role) {
                                request(queueAction: action)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Queue Actions")
                }
            }
        }
        .accessibilityIdentifier("concurrent-job-queue-view-ios")
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

    private var queueSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label(queue.status.label, systemImage: queue.status.icon)
                    .font(.headline)
                    .foregroundStyle(queue.status.color)

                Spacer()

                if queue.activeCount > 0 {
                    Text("\(queue.runningCount) running · \(queue.activeCount) active")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let summaryContent {
                summaryContent()
            }
        }
        .padding(.vertical, 4)
    }

    private var toolbarQueueActions: [JobQueueAction] {
        queue.availableActions.filter { !$0.isPersistenceRecovery }
    }

    private func persistenceIssueView(_ issue: JobQueuePersistenceIssue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Queue Storage Problem", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text(issue.errorDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                ForEach(queue.availableActions.filter(\.isPersistenceRecovery), id: \.self) { action in
                    Button(action.label, systemImage: action.systemImage, role: action.role) {
                        request(queueAction: action)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func recordRow(_ record: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: record.status.icon)
                    .foregroundStyle(record.status.color)
                    .font(.body.weight(.semibold))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 5) {
                    taskSummary(for: record)

                    HStack(spacing: 6) {
                        Text(record.status.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(record.status.color)

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(JobRelativeCreatedTime.display(from: record.createdAt).primary)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        if let message = queue.progress(for: record.id)?.message,
                           record.status.isExecuting,
                           !message.isEmpty {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 4)

                Menu {
                    recordMenu(record)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                }
            }

            if record.status.isExecuting,
               let fraction = queue.progress(for: record.id)?.fractionCompleted {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            }

            if let error = record.error,
               record.status == .failed || record.status == .unrecoverable {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            onInfo?(record)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            trailingSwipeActions(record)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            leadingSwipeActions(record)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func taskSummary(for record: JobRecord) -> some View {
        if let customContent = customTaskContent?(record) {
            customContent
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title ?? record.typeName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)

                if let detail = record.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private func recordMenu(_ record: JobRecord) -> some View {
        if let onInfo {
            Button("Details", systemImage: "info.circle") {
                onInfo(record)
            }
        }

        ForEach(queue.availableActions(for: record, allowsEditing: onEdit != nil), id: \.self) { action in
            Button(action.label, systemImage: action.systemImage, role: action.role) {
                request(recordAction: action, record: record)
            }
        }
    }

    @ViewBuilder
    private func trailingSwipeActions(_ record: JobRecord) -> some View {
        let actions = queue.availableActions(for: record, allowsEditing: onEdit != nil)
        if actions.contains(.cancel) {
            Button("Cancel", systemImage: "xmark.circle", role: .destructive) {
                request(recordAction: .cancel, record: record)
            }
        } else if actions.contains(.remove) {
            Button("Remove", systemImage: "trash", role: .destructive) {
                request(recordAction: .remove, record: record)
            }
        }
    }

    @ViewBuilder
    private func leadingSwipeActions(_ record: JobRecord) -> some View {
        let actions = queue.availableActions(for: record, allowsEditing: onEdit != nil)
        if actions.contains(.retry) {
            Button("Retry", systemImage: "arrow.clockwise") {
                request(recordAction: .retry, record: record)
            }
            .tint(.blue)
        }
        if actions.contains(.editAndRequeue) {
            Button("Edit", systemImage: "pencil") {
                request(recordAction: .editAndRequeue, record: record)
            }
            .tint(.orange)
        }
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
            perform(queueAction: action)
        }
    }

    private func request(recordAction action: JobRecordAction, record: JobRecord) {
        if action == .editAndRequeue {
            onEdit?(record)
            return
        }

        switch action {
        case .cancel, .remove where record.status != .completed:
            confirmation = .record(action: action, record: record)
        case .retry, .remove:
            perform(recordAction: action, record: record)
        case .editAndRequeue:
            break
        }
    }

    private func performConfirmed(_ confirmation: Confirmation) {
        self.confirmation = nil
        switch confirmation {
        case .queue(let action):
            perform(queueAction: action)
        case .record(let action, let record):
            perform(recordAction: action, record: record)
        }
    }

    private func perform(queueAction action: JobQueueAction) {
        if let onQueueAction {
            onQueueAction(action)
            return
        }
        perform { try queue.perform(action) }
    }

    private func perform(recordAction action: JobRecordAction, record: JobRecord) {
        if let onRecordAction {
            onRecordAction(action, record)
            return
        }
        perform { try queue.perform(action, for: record.id) }
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