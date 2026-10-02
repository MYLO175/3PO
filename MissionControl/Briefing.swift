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
}
struct BriefingState: Codable {
    var records: [DailyBriefing] = []
    var notificationClaims: Set<String> = []
    var paused = false
    var overviews: [String:DailyBriefing]? = nil
    var overviewPaused: Bool? = nil
    var overviewFingerprints: [String:String]? = nil
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
