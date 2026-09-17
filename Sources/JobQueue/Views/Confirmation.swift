import SwiftUI

enum Confirmation: Identifiable {
    case queue(JobQueueAction)
    case record(action: JobRecordAction, record: JobRecord)

    var id: String {
        switch self {
        case .queue(let action):
            "queue-\(action)"
        case .record(let action, let record):
            "record-\(record.id)-\(action)"
        }
    }

    var title: String {
        switch self {
        case .queue(.cancelAll):
            "Cancel all jobs?"
        case .queue(.resetPersistence):
            "Reset queue storage?"
        case .queue:
            "Confirm action?"
        case .record(.cancel, let record):
            "Cancel \(record.title ?? record.typeName)?"
        case .record(.remove, let record):
            "Remove \(record.title ?? record.typeName)?"
        case .record:
            "Confirm action?"
        }
    }

    var message: String? {
        switch self {
        case .queue(.cancelAll):
            "Pending jobs will be cancelled and active jobs will be asked to stop."
        case .queue(.resetPersistence):
            "Saved queue data will be discarded. This cannot be undone."
        case .record(action: .cancel, record: _):
            "This job will be cancelled."
        case .record(action: .remove, record: _):
            "This job will be removed from the queue."
        case .queue, .record:
            nil
        }
    }

    var confirmLabel: String {
        switch self {
        case .queue(let action):
            action.label
        case .record(.cancel, _):
            "Cancel Job"
        case .record(let action, _):
            action.label
        }
    }
}
