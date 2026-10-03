import Foundation

enum NativeItemKind: String, Codable { case event, reminder }
enum NativeEditTarget: Identifiable {
    case event(AgendaEvent), reminder(TaskItem)
    case create(NativeCreationRequest)
    var id: String { switch self { case .event(let value): return "event:" + value.id; case .reminder(let value): return "reminder:" + value.id; case .create(let request): return "create:" + request.id.uuidString } }
}
struct NativeEditDetails: Equatable {
    var kind: NativeItemKind
    var itemID: String
    var occurrenceID: String
    var sourceID: String
    var title: String
    var notes: String
    var location: String = ""
    var start: Date = .distantPast
    var end: Date = .distantPast
    var allDay = false
    var due: Date?
    var hasTime = false
    var timeZoneID: String = TimeZone.current.identifier
    var recurring = false
    var writable = false
    var modified: Date?
    var canEdit: Bool { writable && !(kind == .reminder && recurring) }
}
struct NativeEditSession { var item: NativeEditDetails; var sources: [SourceOption] }
struct NativeEventMoveProposal {
    var occurrenceID: String
    var sourceID: String
    var originalStart: Date
    var originalEnd: Date
    var start: Date
}
enum NativeEditRules {
    static func moved(_ baseline: NativeEditDetails, proposal: NativeEventMoveProposal) throws -> NativeEditDetails {
        guard baseline.kind == .event, !baseline.allDay, baseline.canEdit,
              baseline.occurrenceID == proposal.occurrenceID, baseline.sourceID == proposal.sourceID,
              baseline.start == proposal.originalStart, baseline.end == proposal.originalEnd else { throw IntegrationError.missing }
        var edited = baseline; edited.start = proposal.start; edited.end = proposal.start.addingTimeInterval(baseline.end.timeIntervalSince(baseline.start))
        try validate(edited,baseline:baseline); return edited
    }
    static func validate(_ value: NativeEditDetails, baseline: NativeEditDetails) throws {
        guard baseline.canEdit else { throw IntegrationError.readOnly }
        guard value.itemID == baseline.itemID, value.kind == baseline.kind, value.occurrenceID == baseline.occurrenceID else { throw IntegrationError.missing }
        guard !value.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, value.title.count <= 500,
              value.notes.count <= 50_000, value.location.count <= 2000 else { throw ActionFailure.message("Enter a title of up to 500 characters, location up to 2,000 and notes up to 50,000.") }
        if value.kind == .event {
            guard value.end > value.start, value.end.timeIntervalSince(value.start) <= 366 * 86400 else { throw ActionFailure.message("The event must end after it starts and last no more than a year.") }
            if value.allDay { guard Calendar.current.startOfDay(for:value.start) == value.start, Calendar.current.startOfDay(for:value.end) == value.end else { throw ActionFailure.message("All-day events use whole calendar days.") } }
            if baseline.recurring && value.sourceID != baseline.sourceID { throw ActionFailure.message("Moving a recurring occurrence to another calendar is deferred. Edit its details in its current calendar.") }
        } else if value.due == nil && value.hasTime { throw ActionFailure.message("Choose a due date before adding a time.") }
    }
    static func allDay(_ item: NativeEditDetails, enabled: Bool, calendar: Calendar = .current) -> NativeEditDetails {
        guard item.allDay != enabled else { return item }
        var result = item; result.allDay = enabled
        if enabled {
            result.start = calendar.startOfDay(for:item.start)
            let endDay = calendar.startOfDay(for:item.end)
            let firstExclusive = calendar.date(byAdding:.day,value:1,to:result.start)!
            result.end = item.end == endDay ? max(firstExclusive,endDay) : calendar.date(byAdding:.day,value:1,to:max(result.start,endDay))!
        } else {
            result.start = calendar.date(bySettingHour:9,minute:0,second:0,of:item.start)!
            result.end = result.start.addingTimeInterval(3600)
        }
        result.timeZoneID = calendar.timeZone.identifier; return result
    }
}
