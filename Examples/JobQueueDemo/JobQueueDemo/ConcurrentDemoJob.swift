import Foundation
import JobQueue

enum ConcurrentDemoJobRegistry {
    static func make() -> JobRegistry {
        let registry = JobRegistry()
        try! registry.register(DemoSynthesisJob.self)
        try! registry.register(DemoModelDownloadJob.self)
        try! registry.register(DemoTextImportJob.self)
        try! registry.register(DemoAudioExportJob.self)
        return registry
    }
}

struct DemoSynthesisJob: Job {
    struct Payload: Codable, Sendable {
        let name: String
        let duration: TimeInterval
        let priority: JobPriority
    }

    static let maxConcurrentExecutions = 3

    let id: UUID
    let payload: Payload

    var title: String? { payload.name }
    var detail: String? { "Neural speech synthesis" }
    var priority: JobPriority { payload.priority }

    init(
        name: String,
        duration: TimeInterval,
        priority: JobPriority
    ) {
        id = UUID()
        payload = Payload(
            name: name,
            duration: duration,
            priority: priority
        )
    }

    func execute(progress: JobProgressReporter) async throws {
        let steps = 12
        for step in 1...steps {
            try Task.checkCancellation()
            await progress.report(
                fractionCompleted: Double(step) / Double(steps),
                message: step < steps ? "Synthesizing chunk \(step)" : "Finalizing audio"
            )
            try await Task.sleep(for: .seconds(payload.duration / Double(steps)))
        }
    }
}

struct DemoModelDownloadJob: Job {
    struct Payload: Codable, Sendable {
        let modelName: String
        let duration: TimeInterval
    }

    static let maxConcurrentExecutions = 2

    let id: UUID
    let payload: Payload

    var title: String? { "Download \(payload.modelName)" }
    var detail: String? { "Voice model" }
    var priority: JobPriority { .utility }

    init(modelName: String, duration: TimeInterval = 5) {
        id = UUID()
        payload = Payload(modelName: modelName, duration: duration)
    }

    func execute(progress: JobProgressReporter) async throws {
        let steps = 10
        for step in 1...steps {
            try Task.checkCancellation()
            await progress.report(
                fractionCompleted: Double(step) / Double(steps),
                message: step < 9 ? "Downloading model" : "Verifying model"
            )
            try await Task.sleep(for: .seconds(payload.duration / Double(steps)))
        }
    }
}

struct DemoTextImportJob: Job {
    struct Payload: Codable, Sendable {
        let filename: String
        let duration: TimeInterval
    }

    static let maxConcurrentExecutions = 4

    let id: UUID
    let payload: Payload

    var title: String? { "Import \(payload.filename)" }
    var detail: String? { "Normalize and split text" }
    var priority: JobPriority { .utility }

    init(filename: String, duration: TimeInterval = 2) {
        id = UUID()
        payload = Payload(filename: filename, duration: duration)
    }

    func execute() async throws {
        try await Task.sleep(for: .seconds(payload.duration))
    }
}

struct DemoAudioExportJob: Job {
    struct Payload: Codable, Sendable {
        let filename: String
        let duration: TimeInterval
    }

    static let maxConcurrentExecutions = 2

    let id: UUID
    let payload: Payload

    var title: String? { "Export \(payload.filename)" }
    var detail: String? { "Encode final audio" }

    init(filename: String, duration: TimeInterval = 3) {
        id = UUID()
        payload = Payload(filename: filename, duration: duration)
    }

    func execute(progress: JobProgressReporter) async throws {
        let steps = 6
        for step in 1...steps {
            try Task.checkCancellation()
            await progress.report(
                fractionCompleted: Double(step) / Double(steps),
                message: "Encoding audio"
            )
            try await Task.sleep(for: .seconds(payload.duration / Double(steps)))
        }
    }
}
