// JobQueueViews.swift — Ready-made SwiftUI components for displaying a JobQueue.
//
// Drop these directly into your app or use them as a starting point.
// They mirror your existing BatchItemView / BatchQueueView patterns.

import SwiftUI

// MARK: - Status Color

public extension JobStatus {
    var color: Color {
        switch self {
        case .pending:    .orange
        case .processing: .blue
        case .completed:  .green
        case .failed:     .red
        case .cancelled:  .gray
        }
    }

    var icon: String {
        switch self {
        case .pending:    "clock"
        case .processing: "arrow.triangle.2.circlepath"
        case .completed:  "checkmark.circle.fill"
        case .failed:     "exclamationmark.circle.fill"
        case .cancelled:  "xmark.circle.fill"
        }
    }
}

// MARK: - JobRecordView

/// A single row for a `JobRecord`. Provide closures for cancel / resume / remove.
/// Customize `label:` to display job-specific data from the encoded payload if needed.
public struct JobRecordView: View {

    public let record: JobRecord
    public var onCancel: ((UUID) -> Void)?
    public var onResume: ((UUID) -> Void)?
    public var onRemove: ((UUID) -> Void)?
    public var onEdit: ((UUID) -> Void)?
    @State private var isHovering = false

    public init(
        record: JobRecord,
        onCancel: ((UUID) -> Void)? = nil,
        onResume: ((UUID) -> Void)? = nil,
        onRemove: ((UUID) -> Void)? = nil,
        onEdit: ((UUID) -> Void)? = nil
    ) {
        self.record = record
        self.onCancel = onCancel
        self.onResume = onResume
        self.onRemove = onRemove
        self.onEdit = onEdit
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Status icon
            Image(systemName: record.status.icon)
                .foregroundStyle(record.status.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.title ?? record.typeName)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let detail = record.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(record.timelineDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Text(record.status.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(record.status.color)
                
                if let error = record.error, record.status == .failed {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            if record.status == .processing {
                ProgressView()
                    .scaleEffect(0.7)
                    .progressViewStyle(.circular)
            }

            if shouldShowInlineActions {
                inlineActionButtons
            }
        }
        .padding(.vertical, 4)
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
        .animation(.easeInOut(duration: 0.15), value: shouldShowInlineActions)
    }

    @ViewBuilder
    private var inlineActionButtons: some View {
        HStack(spacing: 8) {
            if canEdit {
                inlineButton(systemName: "pencil.circle.fill", tint: .orange) {
                    onEdit?(record.id)
                }
                .help("Edit & Requeue")
            }
            
            if canCancel {
                inlineButton(systemName: "xmark.circle.fill", tint: .red) {
                    onCancel?(record.id)
                }
                .help("Cancel")
            }
            if canRetry {
                inlineButton(systemName: "arrow.clockwise.circle.fill", tint: .blue) {
                    onResume?(record.id)
                }
                .help("Retry")
            }
            if canRemove {
                inlineButton(systemName: "trash.circle.fill", tint: .red) {
                    onRemove?(record.id)
                }
                .help("Remove")
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var canEdit: Bool {
        onEdit != nil && (record.status == .failed || record.status == .cancelled)
    }
    
    private var canCancel: Bool {
        record.status == .pending || record.status == .processing
    }

    private var canRetry: Bool {
        record.status == .cancelled || record.status == .failed
    }

    private var canRemove: Bool {
        record.status == .completed || record.status == .failed || record.status == .cancelled
    }

    private var shouldShowInlineActions: Bool {
        isHovering && (canCancel || canRetry || canRemove)
    }

    private func inlineButton(
        systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - JobQueueView

/// A full list view bound directly to a `JobQueue`.
/// Pass a `label` closure to turn a `JobRecord` into display text.
///
/// ```swift
/// JobQueueView(queue: myQueue) { record in
///     // decode your payload from record.encodedJob if you need richer labels
///     record.typeName
/// }
/// ```
public struct JobQueueView: View {

    @Bindable var queue: JobQueue          // @Observable, @MainActor
    var onEdit: ((JobRecord) -> Void)?

    // Optional selection support
    @State private var selectedID: UUID?

    public init(
        queue: JobQueue,
        onEdit: ((JobRecord) -> Void)? = nil
    ) {
        self.queue = queue
        self.onEdit = onEdit
    }

    private var sorted: [JobRecord] {
        queue.records.values.sorted { $0.createdAt > $1.createdAt }
    }

    private var hasRetryable: Bool {
        queue.records.values.contains(where: { $0.status == .failed || $0.status == .cancelled })
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                if sorted.isEmpty {
                    ContentUnavailableView(
                        "Queue Empty",
                        systemImage: "tray",
                        description: Text("Jobs you add will appear here.")
                    )
                } else {
                    List(sorted) { record in
                        JobRecordView(
                            record: record,
                            onCancel: { queue.cancel(id: $0) },
                            onResume: { queue.resume(id: $0) },
                            onRemove: { queue.remove(id: $0) },
                            onEdit:   {
                                if let record = queue.records[$0] {
                                    onEdit?(record)
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                        .background(selectedID == record.id ? Color.accentColor.opacity(0.15) : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedID = record.id }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            if !sorted.isEmpty {
                footerActions
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footerActions: some View {
        HStack(spacing: 12) {
            JobQueueBadge(queue: queue)
            
            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if hasRetryable {
                    Button("Retry All", systemImage: "arrow.clockwise") {
                        queue.retryAll()
                    }
                }

                Button("Clear All", systemImage: "trash") {
                    queue.clearAll()
                }
                .foregroundStyle(.red)
                .tint(.red)
                .buttonStyle(.borderedProminent)
            }
            .disabled(queue.records.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }
}

// MARK: - Queue Stats Badge

/// A compact summary suitable for a tab badge or toolbar item.
public struct JobQueueBadge: View {
    let queue: JobQueue

    public init(queue: JobQueue) { self.queue = queue }

    private var pendingCount: Int { queue.records(with: .pending).count }
    private var processingCount: Int { queue.records(with: .processing).count }
    private var completedCount: Int { queue.records(with: .completed).count }
    private var failedCount: Int { queue.records(with: .failed).count }
    private var cancelledCount: Int { queue.records(with: .cancelled).count }

    public var body: some View {
        HStack(spacing: 6) {
            if pendingCount > 0 {
                Label("\(pendingCount)", systemImage: "clock")
                    .foregroundStyle(.orange)
                    .font(.caption.bold())
            }
            if processingCount > 0 {
                Label("\(processingCount)", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
                    .font(.caption.bold())
            }
            if completedCount > 0 {
                Label("\(completedCount)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption.bold())
            }
            if failedCount > 0 {
                Label("\(failedCount)", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption.bold())
            }
            if cancelledCount > 0 {
                Label("\(cancelledCount)", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.gray)
                    .font(.caption.bold())
            }
        }
    }
}

// MARK: - Queue Button

/// A queue button that highlights active processing and failed job count.
public struct JobQueueButton: View {
    let queue: JobQueue
    let iconName: String
    let action: () -> Void

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

    private var failedCount: Int { queue.records(with: .failed).count }
    private var runningCount: Int { queue.records(with: .processing).count }
    private var isRunning: Bool { runningCount > 0 }
    private var badgeCount: Int { isRunning ? runningCount : failedCount }

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isRunning ? JobStatus.processing.color : .primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.thinMaterial))
                    .overlay { processingRing }

                if badgeCount > 0 {
                    Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.red)
                        )
                        .offset(x: 3, y: -2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: badgeCount)
        .onAppear { syncProcessingAnimation() }
        .onChange(of: isRunning) { _, _ in syncProcessingAnimation() }
    }

    @ViewBuilder
    private var processingRing: some View {
        if isRunning {
            Circle()
                .stroke(JobStatus.processing.color.opacity(0.22), lineWidth: 2)
                .overlay {
                    Circle()
                        .trim(from: 0.02, to: 0.33)
                        .stroke(JobStatus.processing.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(ringRotation))
                }
                .padding(1)
        } else {
            Circle()
                .strokeBorder(.clear, lineWidth: 0)
        }
    }

    private func syncProcessingAnimation() {
        if isRunning {
            ringRotation = 0
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        } else {
            ringRotation = 0
        }
    }
}

#if DEBUG

@MainActor
private enum JobQueuePreviewData {
    static let now = Date()
    
    static func record(
        status: JobStatus,
        label: String,
        title: String? = nil,
        detail: String? = nil,
        error: String? = nil,
        createdOffset: TimeInterval,
        startedOffset: TimeInterval? = nil,
        completedOffset: TimeInterval? = nil
    ) -> (record: JobRecord, label: String) {
        let id = UUID()
        let createdAt = now.addingTimeInterval(-createdOffset)
        let startedAt = startedOffset.map { now.addingTimeInterval(-$0) }
        let completedAt = completedOffset.map { now.addingTimeInterval(-$0) }
        
        let item = JobRecord(
            id: id,
            typeName: "PreviewJob",
            title: title,
            detail: detail,
            status: status,
            error: error,
            createdAt: createdAt,
            updatedAt: completedAt ?? startedAt ?? createdAt,
            startedAt: startedAt,
            completedAt: completedAt,
            encodedJob: Data()
        )
        return (item, label)
    }
    
    static let samples: [(record: JobRecord, label: String)] = [
        record(
            status: .pending,
            label: "Sync invoices",
            title: "Sync Invoice Attachments",
            detail: "24 pending files.",
            createdOffset: 300
        ),
        record(
            status: .processing,
            label: "Upload photos",
            title: "Upload Product Photos",
            detail: "Uploading 18 of 64.",
            createdOffset: 120,
            startedOffset: 45
        ),
        record(
            status: .completed,
            label: "Generate report",
            title: "Generate Weekly Report",
            detail: "Stored in /Reports/weekly.pdf.",
            createdOffset: 600,
            startedOffset: 580,
            completedOffset: 540
        ),
        record(
            status: .failed,
            label: "Email campaign",
            title: "Dispatch Email Campaign",
            detail: "SMTP timeout.",
            error: "SMTP timeout",
            createdOffset: 900,
            startedOffset: 880,
            completedOffset: 860
        ),
        record(
            status: .cancelled,
            label: "Export archive",
            title: "Export Customer Archive",
            detail: "Cancelled before compression.",
            createdOffset: 1200,
            startedOffset: 1180,
            completedOffset: 1170
        )
    ]
    
    static func queue() -> JobQueue {
        let queue = JobQueue(fileURL: FileManager.default.temporaryDirectory.appending(path: "jobqueue-preview-\(UUID().uuidString).json"))
        queue.records = Dictionary(uniqueKeysWithValues: samples.map { ($0.record.id, $0.record) })
        queue.isProcessing = true
        return queue
    }
    
    static func emptyQueue() -> JobQueue {
        JobQueue(fileURL: FileManager.default.temporaryDirectory.appending(path: "jobqueue-preview-empty-\(UUID().uuidString).json"))
    }
    
    static func singleJobQueue() -> JobQueue {
        let queue = JobQueue(fileURL: FileManager.default.temporaryDirectory.appending(path: "jobqueue-preview-single-\(UUID().uuidString).json"))
        let single = samples[3].record // failed — most interesting for single preview
        queue.records = [single.id: single]
        return queue
    }
    
    static func label(for record: JobRecord) -> String {
        samples.first(where: { $0.record.id == record.id })?.label ?? record.typeName
    }
}

#Preview("JobRecordView (Failed)", traits: .sizeThatFitsLayout) {
    JobRecordView(
        record: JobQueuePreviewData.samples[2].record
    )
    .padding()
}

#Preview("JobQueueView") {
    NavigationStack {
        JobQueueView(queue: JobQueuePreviewData.queue())
        .navigationTitle("Jobs")
    }
}

#Preview("JobQueueView Empty") {
    NavigationStack {
        JobQueueView(queue: JobQueuePreviewData.emptyQueue())
        .navigationTitle("Jobs")
    }
}

#Preview("JobQueueView Single Job") {
    NavigationStack {
        JobQueueView(queue: JobQueuePreviewData.singleJobQueue())
        .navigationTitle("Jobs")
        .frame(height: 320)
    }
}

#Preview("JobQueueBadge", traits: .sizeThatFitsLayout) {
    JobQueueBadge(queue: JobQueuePreviewData.queue())
        .padding()
}

#Preview("JobQueueButton", traits: .sizeThatFitsLayout) {
    JobQueueButton(queue: JobQueuePreviewData.queue()) {}
        .padding()
}

#endif
