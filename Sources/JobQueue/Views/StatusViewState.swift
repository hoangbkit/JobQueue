import SwiftUI

public extension JobStatus {
    var color: Color {
        switch self {
        case .pending:    .orange
        case .processing: .blue
        case .cancelling: .red
        case .pausing:    .orange
        case .completed:  .green
        case .failed:     .red
        case .cancelled:  .gray
        case .unrecoverable: .purple
        }
    }

    var icon: String {
        switch self {
        case .pending:    "clock"
        case .processing: "waveform"
        case .cancelling: "xmark.circle"
        case .pausing:    "pause.circle"
        case .completed:  "checkmark.circle.fill"
        case .failed:     "exclamationmark.circle.fill"
        case .cancelled:  "xmark.circle.fill"
        case .unrecoverable: "exclamationmark.triangle.fill"
        }
    }

    var label: String {
        switch self {
        case .pending:    "Pending"
        case .processing: "Processing"
        case .cancelling: "Cancelling..."
        case .pausing:    "Pausing..."
        case .completed:  "Completed"
        case .failed:     "Failed"
        case .cancelled:  "Cancelled"
        case .unrecoverable: "Unrecoverable"
        }
    }
}

public extension JobQueueStatus {
    var color: Color {
        switch self {
        case .idle:       .secondary
        case .processing: .blue
        case .cancelling: .red
        case .pausing:    .orange
        case .paused:     .orange
        }
    }

    var icon: String {
        switch self {
        case .idle:       "tray"
        case .processing: "waveform"
        case .cancelling: "xmark.circle"
        case .pausing:    "pause.circle"
        case .paused:     "pause.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .idle:       "Idle"
        case .processing: "Synthesizing"
        case .cancelling: "Cancelling..."
        case .pausing:    "Pausing..."
        case .paused:     "Paused"
        }
    }
}
