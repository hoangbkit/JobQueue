import Foundation
import JobQueue

enum DemoJobRegistry {
    static func make() -> JobRegistry {
        let registry = JobRegistry()
        try! registry.register(ProgressDemoJob.self)
        try! registry.register(SilentDemoJob.self)
        try! registry.register(FailingDemoJob.self)
        return registry
    }
}

enum DemoJobKind: String, CaseIterable, Identifiable {
    case progress = "Progress"
    case silent = "Silent"
    case failing = "Failing"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .progress:
            "waveform"
        case .silent:
            "clock"
        case .failing:
            "exclamationmark.triangle"
        }
    }
}

struct DemoJobConfiguration {
    let title: String?
    let message: String
    let duration: TimeInterval
}

struct ProgressDemoJob: Job {
    struct Payload: Codable, Sendable {
        let title: String?
        let message: String
        let duration: TimeInterval
    }

    let id: UUID
    let payload: Payload

    var title: String? { payload.title ?? "Progress Job" }
    var detail: String? { payload.message }

    init(_ configuration: DemoJobConfiguration) {
        id = UUID()
        payload = Payload(
            title: configuration.title,
            message: configuration.message,
            duration: configuration.duration
        )
    }

    func execute(progress: JobProgressReporter) async throws {
        let steps = 10
        for step in 1...steps {
            try Task.checkCancellation()
            await progress.report(
                fractionCompleted: Double(step) / Double(steps),
                message: "Step \(step) of \(steps)"
            )
            try await Task.sleep(for: .seconds(payload.duration / Double(steps)))
        }
    }
}

struct SilentDemoJob: Job {
    struct Payload: Codable, Sendable {
        let title: String?
        let message: String
        let duration: TimeInterval
    }

    let id: UUID
    let payload: Payload

    var title: String? { payload.title ?? "Silent Job" }
    var detail: String? { payload.message }

    init(_ configuration: DemoJobConfiguration) {
        id = UUID()
        payload = Payload(
            title: configuration.title,
            message: configuration.message,
            duration: configuration.duration
        )
    }

    func execute() async throws {
        try await Task.sleep(for: .seconds(payload.duration))
    }
}

struct FailingDemoJob: Job {
    struct Payload: Codable, Sendable {
        let title: String?
        let message: String
        let duration: TimeInterval
    }

    let id: UUID
    let payload: Payload

    var title: String? { payload.title ?? "Failing Job" }
    var detail: String? { payload.message }

    init(_ configuration: DemoJobConfiguration) {
        id = UUID()
        payload = Payload(
            title: configuration.title,
            message: configuration.message,
            duration: configuration.duration
        )
    }

    func execute(progress: JobProgressReporter) async throws {
        await progress.report(fractionCompleted: 0.2, message: "Starting")
        try await Task.sleep(for: .seconds(payload.duration))
        await progress.report(fractionCompleted: 0.9, message: "About to fail")
        throw DemoJobError.simulatedFailure
    }
}

enum DemoJobError: LocalizedError {
    case simulatedFailure

    var errorDescription: String? {
        "Demo job failed intentionally."
    }
}
