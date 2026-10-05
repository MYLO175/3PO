import Foundation
import CryptoKit

enum ActionKind: String, Codable { case createReminder, editReminder, completeReminder, createEvent, editEvent, deleteEvent, deleteReminder }
struct ActionDraft: Codable {
    var kind: ActionKind
    var target: String?
    var destination: String?
    var title: String?
    var due: String?
    var hasTime: Bool?
    var start: String?
    var end: String?
    var allDay: Bool?
    var scope: String?
    var notes: String?
    var location: String?
    var options: String?
}
enum ActionFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
enum ActionRules {
    static func validate(_ draft: ActionDraft) throws {
        switch draft.kind {
        case .createReminder, .editReminder, .completeReminder:
            guard draft.start == nil, draft.end == nil, draft.allDay == nil, (draft.scope == nil || draft.scope == "reminderSeries" && draft.kind == .editReminder), draft.location == nil else { throw ActionFailure.message("Reminder action included unsupported event fields.") }
            if draft.kind == .completeReminder { guard draft.target != nil, draft.title == nil, draft.destination == nil, draft.due == nil, draft.hasTime == nil, draft.notes == nil, draft.options == nil, draft.scope == nil else { throw ActionFailure.message("Completion must identify one reminder without editing it.") } }
            if draft.kind == .editReminder { guard draft.target != nil, draft.title != nil || draft.due != nil || draft.destination != nil || draft.notes != nil || draft.options != nil else { throw ActionFailure.message("Specify the reminder change.") } }
            if draft.kind == .createReminder { guard draft.target == nil, draft.title != nil, draft.hasTime != true || draft.due != nil else { throw ActionFailure.message("Specify the new reminder, including a date for any due time.") } }
        case .createEvent, .editEvent:
            guard draft.due == nil, draft.hasTime == nil, draft.scope == nil || draft.scope == "occurrence" || draft.scope == "futureEvents" else { throw ActionFailure.message("Unsupported event fields or recurring scope.") }
            if draft.kind == .createEvent { guard draft.target == nil, draft.start != nil, draft.end != nil, draft.allDay != nil, draft.scope == nil else { throw ActionFailure.message("Specify event start, end and whether it is all-day.") } }
            if draft.kind == .editEvent { guard draft.target != nil, draft.title != nil || draft.start != nil || draft.end != nil || draft.allDay != nil || draft.destination != nil || draft.notes != nil || draft.location != nil || draft.options != nil else { throw ActionFailure.message("Specify the event change.") } }
        case .deleteEvent, .deleteReminder:
            guard draft.target != nil, draft.destination == nil, draft.title == nil, draft.due == nil, draft.hasTime == nil, draft.start == nil, draft.end == nil, draft.allDay == nil, draft.notes == nil, draft.location == nil, draft.options == nil else { throw ActionFailure.message("Deletion must identify one item and its scope without other changes.") }
            guard draft.kind == .deleteEvent ? draft.scope == nil || ["occurrence","futureEvents"].contains(draft.scope!) : draft.scope == nil || draft.scope == "reminderSeries" else { throw ActionFailure.message("Unsupported deletion scope.") }
        }
    }
    static func date(_ value: String, dateOnly: Bool, calendar: Calendar = .current) throws -> Date {
        if dateOnly {
            let fields = value.split(separator: "-").compactMap { Int($0) }
            guard value.count == 10, fields.count == 3,
                  let date = calendar.date(from: DateComponents(year: fields[0], month: fields[1], day: fields[2])),
                  DateRules.localDate(date, calendar: calendar) == value else { throw ActionFailure.message("Specify a valid calendar date (YYYY-MM-DD).") }
            return date
        }
        guard value.contains("T"), value.range(of: #"(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { throw ActionFailure.message("Specify an unambiguous time and timezone.") }
        let format = ISO8601DateFormatter()
        if let date = format.date(from: value) { return date }
        format.formatOptions.insert(.withFractionalSeconds)
        guard let date = format.date(from: value) else { throw ActionFailure.message("The requested time is invalid.") }
        return date
    }
    static func key(registration: String, request: String, selectedTarget: String = "") -> String {
        let data = Data((registration + "\n" + request.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + selectedTarget).utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
