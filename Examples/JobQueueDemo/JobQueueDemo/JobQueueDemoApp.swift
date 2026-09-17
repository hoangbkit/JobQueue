//
//  JobQueueDemoApp.swift
//  JobQueueDemo
//
//  Created by Hoang Nguyen on 2/6/26.
//

import SwiftUI
import JobQueue

@main
struct JobQueueDemoApp: App {
    @State private var serialQueue: JobQueue
    @State private var concurrentQueue: JobQueue
    private let serialQueueFileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JobQueueDemo", isDirectory: true)
        try! FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let serialQueueFileURL = appSupport.appendingPathComponent("jobqueue.json")
        let concurrentQueueFileURL = appSupport.appendingPathComponent("concurrent-jobqueue.json")
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            try? FileManager.default.removeItem(at: serialQueueFileURL)
            try? FileManager.default.removeItem(at: concurrentQueueFileURL)
        }

        let serialQueue = JobQueue(
            fileURL: serialQueueFileURL,
            policy: JobQueuePolicy(maxConcurrentExecutions: 1),
            registry: DemoJobRegistry.make(),
            maxRecords: 100,
            autoCleanupEnabled: true
        )
        let concurrentQueue = JobQueue(
            fileURL: concurrentQueueFileURL,
            policy: JobQueuePolicy(maxConcurrentExecutions: 8),
            registry: ConcurrentDemoJobRegistry.make(),
            maxRecords: 500,
            autoCleanupEnabled: true
        )

        try? serialQueue.start()
        try? concurrentQueue.start()
        self.serialQueueFileURL = serialQueueFileURL
        self._serialQueue = State(initialValue: serialQueue)
        self._concurrentQueue = State(initialValue: concurrentQueue)
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Serial Queue", systemImage: "list.number") {
                    ContentView(
                        queue: serialQueue,
                        queueFileURL: serialQueueFileURL
                    )
                }

                Tab("Concurrent Queue", systemImage: "square.stack.3d.up.fill") {
                    ConcurrentDemoView(queue: concurrentQueue)
                }
            }
                .preferredColorScheme(.dark)
        }
    }
}
