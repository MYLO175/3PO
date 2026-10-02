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
