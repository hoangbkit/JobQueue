import SwiftUI

extension JobRecordAction {
    var label: String {
        switch self {
        case .editAndRequeue:
            "Edit & Requeue"
        case .cancel:
            "Cancel"
        case .retry:
            "Retry"
        case .remove:
            "Remove"
        }
    }

    var systemImage: String {
        switch self {
        case .editAndRequeue:
            "pencil"
        case .cancel:
            "xmark.circle"
        case .retry:
            "arrow.clockwise"
        case .remove:
            "trash"
        }
    }

    var role: ButtonRole? {
        switch self {
        case .cancel, .remove:
            .destructive
        case .editAndRequeue, .retry:
            nil
        }
    }

    var tint: Color {
        switch self {
        case .editAndRequeue:
            .orange
        case .cancel:
            .gray
        case .remove:
            .red
        case .retry:
            .blue
        }
    }
}
