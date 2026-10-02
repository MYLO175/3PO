import Foundation

struct SourceRGB: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
}

struct SourceOption: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var account: String
    var writable: Bool
    var color: SourceRGB? = nil
    var label: String { account.isEmpty ? title : "\(title) · \(account)" }
}
struct AgendaEvent: Identifiable, Codable {
    var id: String
    var calendarID: String
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var location: String
    var sourceLabel: String
}
struct TaskItem: Identifiable, Codable {
    var id: String
    var listID: String
    var title: String
    var due: Date?
    var hasTime: Bool
    var sourceLabel: String
    var writable: Bool
    var recurring: Bool
}
struct CalendarSnapshot: Codable { var sources: [SourceOption]; var events: [AgendaEvent] }
struct ReminderSnapshot: Codable { var sources: [SourceOption]; var reminders: [TaskItem] }
struct SourceHealth: Codable {
    var lastSuccess: Date?
    var error: String?
    var loading = false
    var detail: String {
        if loading { return "Refreshing…" }
        if let error { return (lastSuccess == nil ? "" : "Stale · ") + error }
        if let lastSuccess { return "Updated " + lastSuccess.formatted(date: .omitted, time: .shortened) }
        return "Not connected"
    }
}
enum DateRules {
    static func localDate(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func reminderDue(_ item: TaskItem, calendar: Calendar = .current) -> String {
        guard let due = item.due else { return "undated" }
        return item.hasTime ? due.ISO8601Format() : localDate(due, calendar: calendar)
    }
    static func day(_ date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)!
    }
    static func overlaps(_ event: AgendaEvent, day date: Date, calendar: Calendar = .current) -> Bool {
        let interval = day(date, calendar: calendar)
        return event.start < interval.end && (event.end > interval.start || (event.end == event.start && event.start >= interval.start))
    }
    static func group(_ item: TaskItem, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let due = item.due else { return "Undated" }
        let today = calendar.startOfDay(for: now)
        if due < today || (item.hasTime && due < now) { return "Overdue" }
        if calendar.isDate(due, inSameDayAs: now) { return "Today" }
        return "Upcoming"
    }
    static func ordered(_ items: [TaskItem]) -> [TaskItem] {
        items.sorted { ($0.due ?? .distantFuture, $0.title, $0.id) < ($1.due ?? .distantFuture, $1.title, $1.id) }
    }
    static func occurrenceID(_ identifier: String, start: Date) -> String { identifier + "@" + String(start.timeIntervalSince1970) }
}
enum IntegrationError: LocalizedError {
    case denied(String), missing, readOnly, verification
    var errorDescription: String? {
        switch self {
        case .denied(let name): return "\(name) access denied. Enable Mission Control in System Settings → Privacy & Security."
        case .missing: return "The item changed or disappeared. Refresh and try again."
        case .readOnly: return "This source is read-only."
        case .verification: return "The saved change could not be verified. Refresh before retrying."
        }
    }
}
