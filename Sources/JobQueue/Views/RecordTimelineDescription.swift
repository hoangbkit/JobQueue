import Foundation

public extension JobRecord {
    var timelineDescription: String {
        let created = Self.timelineDateFormatter.string(from: createdAt)
        let time: (Date) -> String = { Self.timelineTimeFormatter.string(from: $0) }

        switch status {
        case .pending:
            return created
        case .processing:
            guard let startedAt else { return created }
            return "\(created) · started \(time(startedAt))"
        case .pausing:
            guard let startedAt else { return created }
            return "\(created) · stopping synthesis started \(time(startedAt))"
        case .cancelling:
            guard let startedAt else { return created }
            return "\(created) · cancelling synthesis started \(time(startedAt))"
        case .completed:
            guard let startedAt, let completedAt else { return created }
            return "\(created) · finished \(time(completedAt)) · took \(Self.duration(completedAt.timeIntervalSince(startedAt)))"
        case .failed:
            guard let completedAt else { return created }
            return "\(created) · failed at \(time(completedAt))"
        case .cancelled:
            guard let completedAt else { return created }
            return "\(created) · cancelled at \(time(completedAt))"
        case .unrecoverable:
            guard let completedAt else { return created }
            return "\(created) · unrecoverable at \(time(completedAt))"
        }
    }

    private static let timelineDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MMM-dd HH:mm"
        return formatter
    }()

    private static let timelineTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func duration(_ interval: TimeInterval) -> String {
        String(format: "%.1fs", interval)
    }
}
