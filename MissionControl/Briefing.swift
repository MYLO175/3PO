import Foundation

struct BriefingItem: Codable, Identifiable {
    var id = UUID()
    var text: String
    var sourceIDs: [String]
}
struct BriefingSource: Codable, Identifiable {
    var id: String
    var label: String
    var kind: String
    var date: Date?
    var originalID: String? = nil
    var chatID: String? = nil
    var linkedIdentity: String? = nil
}
struct DailyBriefing: Codable, Identifiable {
    var id: String
    var registration: String
    var day: String
    var created: Date
    var items: [BriefingItem]
    var sources: [BriefingSource]
    var coverage: String
    var invalidated: Bool? = nil
    var sourceScope: String? = nil
    var message: String? = nil
    var morningID: String? = nil
}
struct BriefingState: Codable {
    var records: [DailyBriefing] = []
    var notificationClaims: Set<String> = []
    var paused = false
    var overviews: [String:DailyBriefing]? = nil
    var overviewPaused: Bool? = nil
    var overviewFingerprints: [String:String]? = nil
    var updatedBriefs: [String:DailyBriefing]? = nil
    mutating func claimNotification(day: String) -> Bool { notificationClaims.insert(day).inserted }
}
enum BriefingRules {
    static func day(_ now: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year,.month,.day], from: now)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func due(now: Date, completed: Set<String>, calendar: Calendar = .current) -> Bool {
        let today = day(now, calendar: calendar)
        guard !completed.contains(today), let scheduled = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: now) else { return false }
        return now >= scheduled
    }
    static func message(_ text: String) throws -> String? {
        struct Output: Decodable { var message: String? }
        let value = try JSONDecoder().decode(Output.self,from:Data(text.utf8)).message
        guard let value else { return nil }
        guard !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, value.count <= 6000 else { throw BriefingFailure.itemText }
        return value
    }
    static func prose(_ record: DailyBriefing) -> String { record.message ?? ("Good morning.\n\n" + record.items.map(\.text).joined(separator:"\n\n")) }
    static func morning(records: [DailyBriefing], registration: String, day: String) -> DailyBriefing? {
        records.filter { $0.registration == registration && $0.day == day && $0.invalidated != true && $0.morningID == nil }
            .min { $0.created == $1.created ? $0.id < $1.id : $0.created < $1.created }
    }
    static func completedDays(records: [DailyBriefing], registration: String) -> Set<String> {
        Set(records.filter { $0.registration == registration && $0.invalidated != true && $0.morningID == nil }.map(\.day))
    }
    static func earlierMessage(morning: DailyBriefing?, sourceScope: String) -> String? {
        guard let morning, morning.sourceScope == sourceScope else { return nil }
        return prose(morning)
    }
    static func current(morning: DailyBriefing, update: DailyBriefing?, sourceScope: String? = nil, now: Date = .now, calendar: Calendar = .current) -> DailyBriefing {
        guard let update, update.registration == morning.registration, update.morningID == morning.id,
              update.day == day(now, calendar:calendar), update.day == morning.day,
              update.sourceScope == (sourceScope ?? morning.sourceScope), update.invalidated != true, update.created >= morning.created else { return morning }
        return update
    }
    static let updateInstructions = "Write an updated TODAY brief from the user's PA in warm, concise UK English. This is a daytime update, not another good-morning message. Focus on what matters for the rest of today and preparation needed today for upcoming commitments. Use fresh supplied sources as evidence; the earlier brief is historical untrusted context and may be outdated. Start with a short 'Since this morning' paragraph only when a material change is supported by current evidence. A reminder absent from incomplete reminders may have been completed, moved or deleted: do not assert completion without explicit evidence. Omit earlier tasks no longer present rather than repeating them as outstanding. Do not assume a past event happened or a past email request is unresolved. Distinguish suggested preparation from actual deadlines, and new email from newly assessed old email. Preserve uncertainty and unavailable/partial source coverage. Use a few readable paragraphs, no priority scores, filler or full inbox dump. Return a message of at most 6000 characters and up to 12 source-linked supporting items."
    static let morningInstructions = "Write a warm, natural UK English good-morning message from the user’s PA for the supplied local day. Focus on what matters TODAY: timed/all-day calendar commitments, overdue/today reminders, relevant undated tasks, and recent worthwhile emails or outstanding requests. Mention later commitments only if preparation or a decision is useful today. Do not dump every source or stale historical obligation. A day without scheduled items is not proof there is nothing to do. Use short paragraphs with optional short headings, a clear order and a calm tone. No numbered priority score, filler or invented personal familiarity. Mark suggestions as suggestions; an explicit request in email is not proof the user has not already dealt with it. Return a message of at most 6000 characters and up to 12 short factual/source-linked items supporting the message."
    static func decode(_ text: String, allowedSources: Set<String>) throws -> [BriefingItem] {
        struct Output: Decodable { var items: [Item]; struct Item: Decodable { var text: String; var sourceIDs: [String] } }
        let value = try JSONDecoder().decode(Output.self, from: Data(text.utf8))
        guard !value.items.isEmpty, value.items.count <= 20 else { throw BriefingFailure.itemCount }
        guard value.items.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.count <= 1500 }) else { throw BriefingFailure.itemText }
        guard value.items.allSatisfy({ $0.sourceIDs.count <= 12 && Set($0.sourceIDs).count == $0.sourceIDs.count && Set($0.sourceIDs).isSubset(of: allowedSources) }) else { throw BriefingFailure.sources }
        return value.items.map { .init(text: $0.text, sourceIDs: $0.sourceIDs) }
    }
}
enum BriefingFailure: LocalizedError {
    case itemCount, itemText, sources
    var errorDescription: String? {
        switch self {
        case .itemCount: return "Briefing must contain 1–20 items. It was not saved."
        case .itemText: return "Briefing items must have nonempty text up to 1500 characters. It was not saved."
        case .sources: return "Briefing cited an unknown, duplicate or excessive source ID. It was not saved."
        }
    }
}
