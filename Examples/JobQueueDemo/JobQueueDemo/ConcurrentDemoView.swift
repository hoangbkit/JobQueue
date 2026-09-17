import SwiftUI
import ConcurrentJobQueue

struct ConcurrentDemoView: View {
    @State private var queue: JobQueue
    @State private var showQueuePopover = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedRecord: JobRecord?
    @State private var previewNumber = 1
    @State private var projectNumber = 1

    init(queue: JobQueue) {
        self._queue = State(initialValue: queue)
    }

    var body: some View {
        VStack(spacing: 18) {
            header
            metrics

            HStack(alignment: .top, spacing: 16) {
                interactiveCard
                workflowCard
            }
            .frame(maxWidth: 760)

            controls

            Button {
                showQueuePopover = true
            } label: {
                JobQueueBadge(queue: queue)
            }
            .accessibilityIdentifier("concurrent-demo-queue-badge-button")
            .popover(isPresented: $showQueuePopover, arrowEdge: .bottom) {
                JobQueueView(
                    queue: queue,
                    onInfo: { selectedRecord = $0 },
                    taskContentFor: DemoModelDownloadJob.self
                ) { job, _ in
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.badge.plus")
                            .foregroundStyle(.purple)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.payload.modelName)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)

                            Text("Voice model download")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minWidth: 680, minHeight: 440)
                .sheet(item: $selectedRecord) { record in
                    ConcurrentJobDetailView(record: record)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 560)
        .alert("Error", isPresented: $showError) {
            Button("OK") { showError = false }
        } message: {
            Text(errorMessage)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(.tint)

            Text("Concurrent Spokio Workloads")
                .font(.title)

            Text("Synthesis limit 3 · downloads 2 · imports 4 · exports 2")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            metric("Running", value: queue.runningCount, color: .blue)
            metric("Active", value: queue.activeCount, color: .orange)
            metric("Completed", value: queue.records(with: .completed).count, color: .green)
            metric("Failed", value: queue.records(with: .failed).count, color: .red)
        }
    }

    private func metric(_ title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 90)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var interactiveCard: some View {
        GroupBox("Interactive Editor") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Start a user-facing preview. It requests the next synthesis slot and pauses background synthesis when necessary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Generate Editor Preview", systemImage: "play.circle.fill") {
                    enqueueEditorPreview()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("concurrent-demo-preview-button")

                Button("Queue Normal Synthesis", systemImage: "text.bubble") {
                    enqueue {
                        try queue.enqueue(
                            DemoSynthesisJob(
                                name: "Quick synthesis \(previewNumber)",
                                duration: 4,
                                priority: .default
                            )
                        )
                        previewNumber += 1
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var workflowCard: some View {
        GroupBox("Creator Workflows") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Seed realistic concurrent work while synthesis remains constrained to three executions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Audiobook Project", systemImage: "books.vertical.fill") {
                    seedAudiobook()
                }
                .accessibilityIdentifier("concurrent-demo-audiobook-button")

                Button("Folder of Text Files", systemImage: "folder.fill") {
                    seedFolder()
                }
                .accessibilityIdentifier("concurrent-demo-folder-button")

                Button("Download Voice Models", systemImage: "arrow.down.circle.fill") {
                    seedDownloads()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(
                queue.pausedJobTypeNames.contains("DemoSynthesisJob")
                    ? "Resume Synthesis"
                    : "Pause Synthesis",
                systemImage: queue.pausedJobTypeNames.contains("DemoSynthesisJob")
                    ? "play.fill"
                    : "pause.fill"
            ) {
                enqueue {
                    if queue.pausedJobTypeNames.contains("DemoSynthesisJob") {
                        try queue.resume(DemoSynthesisJob.self)
                    } else {
                        try queue.pause(DemoSynthesisJob.self)
                    }
                }
            }
            .accessibilityIdentifier("concurrent-demo-toggle-synthesis-button")

            Button("Export Audio", systemImage: "square.and.arrow.up") {
                enqueue {
                    try queue.enqueue(
                        DemoAudioExportJob(filename: "voiceover-\(projectNumber).m4a")
                    )
                }
            }

            Button("Cancel All", systemImage: "xmark.circle", role: .destructive) {
                enqueue { try queue.cancelAll() }
            }
        }
    }

    private func enqueueEditorPreview() {
        enqueue {
            try queue.enqueue(
                DemoSynthesisJob(
                    name: "Editor preview \(previewNumber)",
                    duration: 3,
                    priority: .userInitiated
                ),
                startPolicy: .immediate
            )
            previewNumber += 1
        }
    }

    private func seedAudiobook() {
        enqueue {
            let project = projectNumber
            try queue.enqueue(DemoModelDownloadJob(modelName: "Narrator \(project)"))
            for chapter in 1...6 {
                try queue.enqueue(
                    DemoSynthesisJob(
                        name: "Book \(project) · Chapter \(chapter)",
                        duration: 7,
                        priority: .background
                    )
                )
            }
            try queue.enqueue(
                DemoAudioExportJob(filename: "audiobook-\(project).m4a")
            )
            projectNumber += 1
        }
    }

    private func seedFolder() {
        enqueue {
            let project = projectNumber
            for file in 1...8 {
                try queue.enqueue(
                    DemoTextImportJob(filename: "draft-\(project)-\(file).txt")
                )
                try queue.enqueue(
                    DemoSynthesisJob(
                        name: "Folder \(project) · File \(file)",
                        duration: 5,
                        priority: .background
                    )
                )
            }
            projectNumber += 1
        }
    }

    private func seedDownloads() {
        enqueue {
            try queue.enqueue(DemoModelDownloadJob(modelName: "English Natural"))
            try queue.enqueue(DemoModelDownloadJob(modelName: "Vietnamese Studio"))
            try queue.enqueue(DemoModelDownloadJob(modelName: "Narrator XL"))
        }
    }

    private func enqueue(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

private struct ConcurrentJobDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let record: JobRecord

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label(record.title ?? record.typeName, systemImage: "info.circle.fill")
                    .font(.title2)

                LabeledContent("Type", value: record.typeName)
                LabeledContent("Status", value: record.status.rawValue.capitalized)
                LabeledContent("Priority", value: record.priority.rawValue)

                if record.typeName == String(describing: DemoModelDownloadJob.self),
                   let job = try? record.decode(DemoModelDownloadJob.self) {
                    Divider()
                    LabeledContent("Voice Model", value: job.payload.modelName)
                    LabeledContent(
                        "Expected Duration",
                        value: job.payload.duration.formatted() + " seconds"
                    )
                }

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 360, minHeight: 240)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
