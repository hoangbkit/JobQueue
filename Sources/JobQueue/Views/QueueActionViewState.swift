import SwiftUI

extension JobQueueAction {
    var isQueueControl: Bool {
        switch self {
        case .pause, .resume, .retryAll, .cancelAll, .clearCompleted:
            true
        case .retryPersistence, .resetPersistence:
            false
        }
    }

    var isPersistenceRecovery: Bool {
        !isQueueControl
    }

    var label: String {
        switch self {
        case .pause:
            "Pause"
        case .resume:
            "Resume"
        case .retryAll:
            "Retry All"
        case .cancelAll:
            "Cancel All"
        case .clearCompleted:
            "Clear Completed"
        case .retryPersistence:
            "Retry"
        case .resetPersistence:
            "Reset Queue"
        }
    }

    var systemImage: String {
        switch self {
        case .pause:
            "pause.fill"
        case .resume:
            "play.fill"
        case .retryAll, .retryPersistence:
            "arrow.clockwise"
        case .cancelAll:
            "xmark.circle"
        case .clearCompleted:
            "checkmark.circle"
        case .resetPersistence:
            "trash"
        }
    }

    var role: ButtonRole? {
        switch self {
        case .cancelAll, .resetPersistence:
            .destructive
        case .pause, .resume, .retryAll, .clearCompleted, .retryPersistence:
            nil
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .cancelAll, .resetPersistence:
            true
        case .pause, .resume, .retryAll, .clearCompleted, .retryPersistence:
            false
        }
    }
}
