//
//  ContentView.swift
//  JobQueueDemo
//
//  Created by Hoang Nguyen on 2/6/26.
//

import SwiftUI
import JobQueue

struct ContentView: View {
    @State private var queue: JobQueue
    private let queueFileURL: URL
    @State private var jobKind: DemoJobKind = .progress
    @State private var jobTitle: String = ""
    @State private var jobMessage: String = ""
    @State private var useCustomDuration = true
    @State private var duration: Double = 3
    @State private var showQueuePopover = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    init(queue: JobQueue, queueFileURL: URL) {
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
                JobQueueBadge(queue: queue)
            }
            .accessibilityIdentifier("demo-queue-badge-button")
            .popover(isPresented: $showQueuePopover, arrowEdge: .bottom) {
                JobQueueView(queue: queue) { _ in

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

            let brokenQueue = JobQueue(
                fileURL: queueFileURL,
                policy: JobQueuePolicy(maxConcurrentExecutions: 1),
                registry: DemoJobRegistry.make(),
                maxRecords: 100,
                autoCleanupEnabled: true
            )
            do {
                try brokenQueue.start()
            } catch {
                // Keep the queue instance so JobQueueView can show recovery actions.
            }
            queue = brokenQueue
            showQueuePopover = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func seedJobs() {
        let shouldResume = !queue.isPaused

        do {
            if shouldResume {
                try queue.pause()
            }
            defer {
                if shouldResume {
                    try? queue.resume()
                }
            }

            for record in queue.sortedRecords {
                try queue.remove(id: record.id)
            }

            for index in 0..<80 {
                let configuration = DemoJobConfiguration(
                    title: seededTitle(for: index),
                    message: seededDetail(for: index),
                    duration: seededDuration(for: index)
                )

                let id: UUID
                switch index % 3 {
                case 0:
                    id = try queue.enqueue(ProgressDemoJob(configuration))
                case 1:
                    id = try queue.enqueue(SilentDemoJob(configuration))
                default:
                    id = try queue.enqueue(FailingDemoJob(configuration))
                }

                if index % 10 == 0 {
                    try queue.cancel(id: id)
                }
            }

            showQueuePopover = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func seededDuration(for index: Int) -> TimeInterval {
        0.05 + (Double(index % 4) * 0.05)
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
