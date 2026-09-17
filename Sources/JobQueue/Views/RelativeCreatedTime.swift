import Foundation

enum JobRelativeCreatedTime {
    struct Display {
        let primary: String
        let secondary: String?
    }

    static func display(from date: Date, relativeTo now: Date = Date()) -> Display {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return Display(primary: timeFormatter.string(from: date), secondary: nil)
        }
        if calendar.isDateInYesterday(date) {
            return Display(primary: "Yesterday", secondary: timeFormatter.string(from: date))
        }
        return Display(primary: dateFormatter.string(from: date), secondary: timeFormatter.string(from: date))
    }

    static func exactString(from date: Date) -> String {
        exactFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let exactFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
