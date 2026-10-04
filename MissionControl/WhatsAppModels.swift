import Foundation

struct WhatsAppReadMessage: Codable, Identifiable {
    let id: String
    let chat: String
    let sender: String
    let text: String
    let sentByMe: Bool
    let time: Double
}
struct WhatsAppChat: Codable, Identifiable {
    let id: String
    let name: String
    let group: Bool
}
struct WhatsAppAccess: Codable, Equatable {
    var enabled = false
    var chats: Set<String> = []
    var includeInBrief: Bool? = nil
    var briefEnabled: Bool { enabled && includeInBrief == true && !chats.isEmpty }
}
struct WhatsAppBriefSnapshot {
    let messages: [WhatsAppReadMessage]
    let total: Int
    let start: Date
    let end: Date
}
struct WhatsAppSourceScope: Equatable {
    let registration: String
    let linkedIdentity: String
    let revision: UUID
}
enum WhatsAppReadRules {
    static func accessKey(registration: String, linkedIdentity: String) -> String? {
        guard !registration.isEmpty, !linkedIdentity.isEmpty else { return nil }
        return registration + ":" + linkedIdentity
    }
    static func access(_ saved: [String:WhatsAppAccess], registration: String, linkedIdentity: String) -> WhatsAppAccess {
        guard let key=accessKey(registration:registration,linkedIdentity:linkedIdentity) else { return .init() }
        return saved[key] ?? .init()
    }
    static func validSearchRange(start: Date, end: Date, calendar: Calendar = .current) -> Bool {
        guard start < end, calendar.startOfDay(for:start) == start, calendar.startOfDay(for:end) == end,
              let days=calendar.dateComponents([.day],from:start,to:end).day else { return false }
        return (1...90).contains(days)
    }
    // A bounded snapshot for the existing daily job, never a historical indexing pass.
    static func brief(_ messages: [WhatsAppReadMessage], access: WhatsAppAccess, now: Date) -> WhatsAppBriefSnapshot {
        let start=now.addingTimeInterval(-48*3600)
        let matches=messages.filter { access.briefEnabled && access.chats.contains($0.chat) && $0.time >= start.timeIntervalSince1970*1000 && $0.time <= now.timeIntervalSince1970*1000 }
            .sorted { $0.time == $1.time ? $0.id < $1.id : $0.time > $1.time }
        return .init(messages:Array(matches.prefix(40)),total:matches.count,start:start,end:now)
    }
    static func search(_ messages: [WhatsAppReadMessage], allowed: Set<String>, chat: String?, query: String, start: Date, end: Date, offset: Int) -> (page: [WhatsAppReadMessage], total: Int) {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let matches = messages.filter { item in
            let date=Date(timeIntervalSince1970:item.time/1000)
            return allowed.contains(item.chat) && (chat == nil || chat == item.chat) && date >= start && date < end && terms.allSatisfy { (item.text + " " + item.sender).lowercased().contains($0) }
        }.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time > $1.time }
        return (Array(matches.dropFirst(max(0,offset)).prefix(30)),matches.count)
    }
}

struct WhatsAppReadEvent: Decodable {
    var status: String?
    var connected: Bool?
    var png: String?
    var messages: [WhatsAppReadMessage]?
    var coverage: String?
    var chats: [WhatsAppChat]?
    var identity: String?
    var revoked: Bool?
}
