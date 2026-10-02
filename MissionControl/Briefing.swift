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
}
struct DailyBriefing: Codable, Identifiable {
    var id: String
    var registration: String
    var day: String
    var created: Date
    var items: [BriefingItem]
    var sources: [BriefingSource]
    var coverage: String
}
struct BriefingState: Codable {
    var records: [DailyBriefing] = []
    var notificationClaims: Set<String> = []
    var paused = false
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
        guard !value.items.isEmpty, value.items.count <= 20, value.items.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.count <= 1500 && $0.sourceIDs.count <= 12 && Set($0.sourceIDs).count == $0.sourceIDs.count && Set($0.sourceIDs).isSubset(of: allowedSources) }) else { throw SummaryFailure.invalid }
        return value.items.map { .init(text: $0.text, sourceIDs: $0.sourceIDs) }
    }
}
