import Foundation

enum MemoryKind: String, Codable, CaseIterable { case preference, context, commitment }
struct PAMemory: Codable, Identifiable, Equatable {
    var id = UUID()
    var registration: String
    var text: String
    var kind: MemoryKind
    var explicit = true
    var provenance: String
    var created = Date.now
    var reviewed = Date.now
    var resolved: Date?
    var sourceTurnID: String?
    var evidence: String?
    var sourceDate: Date?
    var conversationID: UUID? = nil
}
enum MemoryRules {
    static func needsReview(_ memory: PAMemory, now: Date = .now) -> Bool {
        !memory.explicit && now.timeIntervalSince(memory.reviewed) >= 90 * 86400
    }
    static func archived(_ memory: PAMemory, now: Date = .now) -> Bool {
        guard let resolved = memory.resolved else { return false }
        return now.timeIntervalSince(resolved) >= 30 * 86400
    }
    static func usable(_ memory: PAMemory, registration: String, now: Date = .now) -> Bool {
        memory.registration == registration && memory.resolved == nil && !needsReview(memory,now:now)
    }
    static func inScope(_ memory: PAMemory, conversationID: UUID?, includeTopics: Bool = false) -> Bool { includeTopics || memory.conversationID == nil || memory.conversationID == conversationID }
    static func explicitRequest(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in:.whitespacesAndNewlines)
        if ["remember this","remember this.","remember that","add this to memory","add this to memory.","save this to memory","save this to memory."].contains(trimmed.lowercased()) { return "" }
        for prefix in ["remember that ","remember this: ","remember: ","remember ","add this to memory: ","add to memory: ","save to memory: ","add this to memory ","add to memory ","save this to memory ","please remember that ","please remember "] where trimmed.lowercased().hasPrefix(prefix) {
            let value = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in:.whitespacesAndNewlines)
            return value.isEmpty ? nil : String(value.prefix(2000))
        }
        return nil
    }
}

struct MemorySelection {
    var records: [[String:String]]
    var eligibleCount: Int
}
enum MemoryRetrieval {
    static let byteLimit = 20_000
    private static let ignored = Set("the a an and or of to for in on at with is are was be been i me my you your we it that this what how do does can could should please about from have has need want tell know remember".split(separator:" ").map(String.init))
    private static func tokens(_ text: String) -> Set<String> {
        Set(text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_GB")).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 && !ignored.contains($0) })
    }
    static func record(_ memory: PAMemory) -> [String:String] {
        ["id":memory.id.uuidString,"scope":memory.conversationID?.uuidString ?? "shared","text":memory.text,"kind":memory.kind.rawValue,"certainty":memory.explicit ? "Explicitly provided or confirmed by user" : "Provisional; verify when relevant","provenance":memory.provenance,"evidence":memory.evidence ?? "","messageDate":memory.sourceDate?.ISO8601Format() ?? "unknown","reviewed":memory.reviewed.ISO8601Format()]
    }
    /// Local relevance retrieval never changes stored facts, certainty or scope.
    static func select(_ memories: [PAMemory], registration: String, conversationID: UUID? = nil, includeTopics: Bool = false, query: String? = nil, now: Date = .now, limit: Int = 40, bytes: Int = byteLimit) -> MemorySelection {
        let eligible = memories.filter { MemoryRules.usable($0,registration:registration,now:now) && MemoryRules.inScope($0,conversationID:conversationID,includeTopics:includeTopics) }
        let terms = tokens(query ?? "")
        func relevance(_ memory: PAMemory) -> Int { tokens(memory.text).intersection(terms).reduce(0) { $0 + min($1.count,12) } }
        func ordered(_ lhs: PAMemory, _ rhs: PAMemory) -> Bool {
            let a = relevance(lhs), b = relevance(rhs)
            if a != b { return a > b }
            if lhs.explicit != rhs.explicit { return lhs.explicit }
            if (lhs.kind == .preference) != (rhs.kind == .preference) { return lhs.kind == .preference }
            if (lhs.conversationID == conversationID) != (rhs.conversationID == conversationID) { return lhs.conversationID == conversationID }
            if lhs.reviewed != rhs.reviewed { return lhs.reviewed > rhs.reviewed }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let ranked = eligible.sorted(by:ordered)
        // Keep a small stable core of confirmed preferences, leaving room for old relevant facts.
        let preferences = eligible.filter { $0.explicit && $0.kind == .preference }.sorted(by:ordered)
        let pinned = Array(preferences.filter { $0.conversationID == nil }.prefix(6)) + Array(preferences.filter { conversationID != nil && $0.conversationID == conversationID }.prefix(6))
        var seen = Set<UUID>(), result: [[String:String]] = [], used = 2
        for memory in pinned + ranked where result.count < max(0,limit) {
            guard seen.insert(memory.id).inserted else { continue }
            let value = record(memory)
            guard let data = try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]), used + data.count + 1 <= bytes else { continue }
            result.append(value); used += data.count + 1
        }
        return MemorySelection(records:result,eligibleCount:eligible.count)
    }
}
