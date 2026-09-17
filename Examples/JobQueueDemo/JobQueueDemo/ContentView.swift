//
//  ContentView.swift
//  JobQueueDemo
//
//  Created by Hoang Nguyen on 2/6/26.
//

import SwiftUI
import SerialJobQueue

struct ContentView: View {
    @State private var queue: SerialJobQueue
    private let queueFileURL: URL
    @State private var jobKind: DemoJobKind = .progress
    @State private var jobTitle: String = ""
    @State private var jobMessage: String = ""
    @State private var useCustomDuration = true
    @State private var duration: Double = 3
    @State private var showQueuePopover = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    init(queue: SerialJobQueue, queueFileURL: URL) {
        self._queue = State(initialValue: queue)
        self.queueFileURL = queueFileURL
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Job Queue Demo")
                .font(.title)

            VStack(alignment: .leading, spacing: 12) {
                Picker("Job Type", selection: $jobKind) {
                    ForEach(DemoJobKind.allCases) { kind in
                        Label(kind.rawValue, systemImage: kind.icon)
                            .tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Optional title", text: $jobTitle)
                    .textFieldStyle(.roundedBorder)

                TextField("Message", text: $jobMessage)
                    .textFieldStyle(.roundedBorder)

                Toggle("Custom Duration", isOn: $useCustomDuration)

                if useCustomDuration {
                    HStack {
                        Slider(value: $duration, in: 0.5...12, step: 0.5)

                        Text("\(duration, specifier: "%.1f")s")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                Button("Enqueue \(jobKind.rawValue) Job", systemImage: "plus.circle.fill") {
                    enqueueJob()
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedMessage.isEmpty)
                .accessibilityIdentifier("demo-enqueue-job-button")

                Divider()

                HStack {
                    Button("Seed Jobs", systemImage: "square.stack.3d.up.fill") {
                        seedJobs()
                    }
                    .accessibilityIdentifier("demo-seed-jobs-button")

                    Button("Break JSON", systemImage: "doc.badge.gearshape") {
                        breakStorage(with: "[")
                    }
                    .accessibilityIdentifier("demo-break-json-button")

                    Button("Wrong Root", systemImage: "exclamationmark.brakesignal") {
                        breakStorage(with: #"{"records":[]}"#)
                    }
                    .accessibilityIdentifier("demo-wrong-root-button")
                }
            }
            .frame(maxWidth: 400)

            Button {
                showQueuePopover = true
            } label: {
                SerialJobQueueBadge(queue: queue)
            }
            .accessibilityIdentifier("demo-queue-badge-button")
            .popover(isPresented: $showQueuePopover, arrowEdge: .bottom) {
                SerialJobQueueView(queue: queue) { _ in
                    
                } onError: { _ in
                    
                }
                    .frame(minWidth: 620, minHeight: 420)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .alert("Error", isPresented: $showError) {
            Button("OK") { showError = false }
        } message: {
            Text(errorMessage)
        }
    }

    private var trimmedTitle: String? {
        let title = jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private var trimmedMessage: String {
        jobMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var configuredDuration: TimeInterval {
        useCustomDuration ? duration : 3
    }

    private func enqueueJob() {
        let message = trimmedMessage
        guard !message.isEmpty else { return }

        do {
            let configuration = DemoJobConfiguration(
                title: trimmedTitle,
                message: message,
                duration: configuredDuration
            )

            switch jobKind {
            case .progress:
                try queue.enqueue(ProgressDemoJob(configuration))
            case .silent:
                try queue.enqueue(SilentDemoJob(configuration))
            case .failing:
                try queue.enqueue(FailingDemoJob(configuration))
            }

            jobTitle = ""
            jobMessage = ""
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func breakStorage(with contents: String) {
        do {
            try FileManager.default.createDirectory(
                at: queueFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: queueFileURL, options: .atomic)

            let brokenQueue = SerialJobQueue(
                fileURL: queueFileURL,
                registry: DemoJobRegistry.make(),
                maxRecords: 100,
                autoCleanupEnabled: true
            )
            do {
                try brokenQueue.start()
            } catch {
                // Keep the queue instance so SerialJobQueueView can show recovery actions.
            }
            queue = brokenQueue
            showQueuePopover = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func seedJobs() {
        do {
            try FileManager.default.createDirectory(
                at: queueFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let records = try makeSeededRecords(count: 80)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(records).write(to: queueFileURL, options: .atomic)

            let seededQueue = SerialJobQueue(
                fileURL: queueFileURL,
                registry: DemoJobRegistry.make(),
                maxRecords: 100,
                autoCleanupEnabled: true
            )
            try seededQueue.start()
            queue = seededQueue
            showQueuePopover = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func makeSeededRecords(count: Int) throws -> [SeededSerialJobRecord] {
        try (0..<count).map { index in
            let createdAt = seededDate(for: index)
            let status = seededStatus(for: index)
            let duration = TimeInterval(1 + (index % 8))
            let title = seededTitle(for: index)
            let detail = seededDetail(for: index)
            let encodedJob = try encodedSeededJob(
                index: index,
                title: title,
                detail: detail,
                duration: duration
            )
            let startedAt = status == "pending" ? nil : createdAt.addingTimeInterval(15)
            let completedAt = status == "pending" ? nil : createdAt.addingTimeInterval(15 + duration)

            return SeededSerialJobRecord(
                id: UUID(),
                typeName: seededTypeName(for: index),
                title: title,
                detail: detail,
                status: status,
                error: status == "failed" ? "Seeded synthesis failed after a simulated service timeout." : nil,
                createdAt: createdAt,
                updatedAt: completedAt ?? createdAt,
                startedAt: startedAt,
                completedAt: completedAt,
                encodedJob: encodedJob
            )
        }
    }

    private func encodedSeededJob(
        index: Int,
        title: String,
        detail: String,
        duration: TimeInterval
    ) throws -> Data {
        let configuration = DemoJobConfiguration(
            title: title,
            message: detail,
            duration: duration
        )

        switch index % 3 {
        case 0:
            return try JSONEncoder().encode(ProgressDemoJob(configuration))
        case 1:
            return try JSONEncoder().encode(SilentDemoJob(configuration))
        default:
            return try JSONEncoder().encode(FailingDemoJob(configuration))
        }
    }

    private func seededTypeName(for index: Int) -> String {
        switch index % 3 {
        case 0:
            String(describing: ProgressDemoJob.self)
        case 1:
            String(describing: SilentDemoJob.self)
        default:
            String(describing: FailingDemoJob.self)
        }
    }

    private func seededStatus(for index: Int) -> String {
        switch index % 10 {
        case 0:
            "pending"
        case 1:
            "failed"
        case 2:
            "cancelled"
        default:
            "completed"
        }
    }

    private func seededDate(for index: Int) -> Date {
        let minutesBack = ((index * 137) % (14 * 24 * 60)) + (index % 9) * 11
        return Date().addingTimeInterval(-TimeInterval(minutesBack * 60))
    }

    private func seededTitle(for index: Int) -> String {
        let titles = [
            "Generate product launch narration",
            "Synthesize onboarding lesson",
            "Render weekly briefing",
            "Create meditation voice prompt",
            "Export support reply audio",
            "Narrate release notes",
            "Generate podcast intro",
            "Render customer story draft"
        ]
        return "\(titles[index % titles.count]) #\(index + 1)"
    }

    private func seededDetail(for index: Int) -> String {
        let details = [
            "Natural voice preset with normalized loudness and final MP3 export.",
            "Fast draft synthesis for review before publishing to the library.",
            "Long-form text chunk split into sections and merged after rendering.",
            "Short response generated from customer support macro content.",
            "Background task created by the demo seeding tool for queue layout testing."
        ]
        return details[index % details.count]
    }
}

private struct SeededSerialJobRecord: Codable {
    let id: UUID
    let typeName: String
    let title: String
    let detail: String
    let status: String
    let error: String?
    let createdAt: Date
    let updatedAt: Date
    let startedAt: Date?
    let completedAt: Date?
    let encodedJob: Data
}
