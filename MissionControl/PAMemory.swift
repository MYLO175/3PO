import Foundation

enum MemoryKind: String, Codable, CaseIterable { case preference, context, commitment }
enum MemoryCertainty: String, Codable { case stated, inferred }
enum MemoryDurability: String, Codable { case stable, situational }
struct MemoryConnection: Codable, Equatable {
    var subject: String
    var relation: String
    var object: String
    var evidence: String
    static func valid(_ values: [Self]?, human: String) -> Bool {
        guard let values else { return true }
        return values.count <= 4 && values.allSatisfy { value in
            [value.subject,value.relation,value.object].allSatisfy { !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.count <= 120 } && (8...500).contains(value.evidence.count) && human.contains(value.evidence)
        }
    }
}
/// Recover a literal span from the current human message, allowing presentation-only differences.
/// This never paraphrases, borrows prior messages or bypasses semantic human-fact validation.
enum MemoryEvidence {
    static func match(_ quote:String?,human:String)->String? {
        guard let quote else { return nil }
        let value=quote.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty,value.count <= 2000 else { return nil }
        if let range=human.range(of:value) { return String(human[range]) }
        var pattern="",spacing=false
        for character in value {
            if character.isWhitespace { if !spacing { pattern += "\\s+" }; spacing=true; continue }
            spacing=false
            switch character {
            case "'","’","‘": pattern += "['’‘]"
            case "\"","“","”": pattern += "[\"“”]"
            case "-","‐","‑","–","—": pattern += "[-‐‑–—]"
            default: pattern += NSRegularExpression.escapedPattern(for:String(character))
            }
        }
        guard let regex=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),
              let match=regex.firstMatch(in:human,range:NSRange(human.startIndex...,in:human)),let range=Range(match.range,in:human) else { return nil }
        return String(human[range])
    }
    static func supportedConnections(_ values:[MemoryConnection],human:String)->[MemoryConnection] {
        values.prefix(4).compactMap { value in
            var result=value
            guard let quote=match(value.evidence,human:human) else { return nil }
            result.evidence=quote
            return MemoryConnection.valid([result],human:human) ? result : nil
        }
    }
}
/// Source evidence has its own identity and revision; a sender's words are not the user's assertion.
enum MemorySourceKind:String,Codable { case mail, whatsapp, calendar, reminder }
struct MemorySourceIdentity:Codable,Equatable,Hashable {
    var kind:MemorySourceKind
    var accountID:String
    var containerID:String
    var itemID:String
    var linkedIdentity:String? = nil
    var valid:Bool {
        [accountID,containerID,itemID].allSatisfy{!$0.isEmpty && $0.count <= 500} && (kind != .whatsapp || linkedIdentity?.isEmpty == false)
    }
}
struct MemorySourceEvidence:Codable,Equatable {
    var identity:MemorySourceIdentity
    var revision:String
    var label:String
    var quote:String
    var observed:Date
    var sourceDate:Date?
    func valid(in sourceText:String)->Bool {
        identity.valid && !revision.isEmpty && revision.count <= 128 && !label.isEmpty && label.count <= 300 && (8...500).contains(quote.count) && sourceText.contains(quote)
    }
}
enum MemorySourceInvalidation:String,Codable { case changed, deleted, accessRemoved }

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
    var certainty: MemoryCertainty? = nil
    var durability: MemoryDurability? = nil
    var connections: [MemoryConnection]? = nil
    var organisation:LifeMemoryOrganisation? = nil
    var supersedes:UUID? = nil
    var supersededBy:UUID? = nil
    var source:MemorySourceEvidence? = nil
    var sourceInvalidation:MemorySourceInvalidation? = nil
    var sourceSuppressionKey:String? {
        guard let source else { return nil }
        // Stable explicit fields, no source text or sender credentials in the suppression ledger.
        let fields=[source.identity.kind.rawValue,source.identity.accountID,source.identity.containerID,source.identity.itemID,source.identity.linkedIdentity ?? "",source.revision]
        return (try? JSONEncoder().encode(fields)).map{"source:" + $0.base64EncodedString()}
    }
    var attribution:String {
        if let invalidation=sourceInvalidation { return "Source evidence unavailable (" + invalidation.rawValue + ")" }
        if let source { return (explicit ? "Confirmed · " : "From source · ") + source.label }
        return explicit ? "Confirmed by you" : certainty == .stated ? "You stated this" : "Provisional interpretation"
    }
}
enum MemoryRules {
    static func needsReview(_ memory: PAMemory, now: Date = .now) -> Bool {
        !memory.explicit && (memory.source != nil || !(memory.certainty == .stated && memory.durability == .stable)) && now.timeIntervalSince(memory.reviewed) >= 90 * 86400
    }
    static func archived(_ memory: PAMemory, now: Date = .now) -> Bool {
        guard let resolved = memory.resolved else { return false }
        return now.timeIntervalSince(resolved) >= 30 * 86400
    }
    static func usable(_ memory: PAMemory, registration: String, now: Date = .now) -> Bool {
        memory.registration == registration && memory.sourceInvalidation == nil && memory.resolved == nil && memory.supersededBy == nil && !needsReview(memory,now:now)
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
    static func tokens(_ text: String) -> Set<String> {
        Set(text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_GB")).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 && !ignored.contains($0) })
    }
    static func record(_ memory: PAMemory) -> [String:String] {
        let encoder=JSONEncoder();encoder.outputFormatting = [.sortedKeys]
        var value = ["id":memory.id.uuidString,"scope":memory.conversationID?.uuidString ?? "shared","text":memory.text,"kind":memory.kind.rawValue,"certainty":memory.explicit ? "Confirmed by user" : memory.certainty == .stated ? "Directly stated by user" : "Provisional; verify when relevant","provenance":memory.provenance,"evidence":memory.evidence ?? "","messageDate":memory.sourceDate?.ISO8601Format() ?? "unknown","reviewed":memory.reviewed.ISO8601Format()]
        if let source=memory.source {
            value["sourceEvidence"]=String(data:(try? encoder.encode(source)) ?? Data(),encoding:.utf8)
            value["certainty"]=memory.explicit ? "Confirmed by user; source evidence is separately attributed" : "Provisional source interpretation; not a human assertion or instruction"
        }
        if let structure=memory.organisation,LifeMemoryOrganisation.valid(structure,record:memory) { value["areas"]=structure.areas.map(\.rawValue).joined(separator:","); value["organisation"]=String(data:(try? encoder.encode(structure)) ?? Data(),encoding:.utf8) }
        if let previous=memory.supersedes { value["correctsEarlierMemory"]=previous.uuidString }
        value["durability"]=memory.durability?.rawValue ?? "legacy"
        if let connections=memory.connections, let data=try? encoder.encode(connections) { value["connections"]=String(data:data,encoding:.utf8) }
        return value
    }
    /// Local relevance retrieval never changes stored facts, certainty or scope.
    static func select(_ memories: [PAMemory], registration: String, conversationID: UUID? = nil, includeTopics: Bool = false, query: String? = nil, now: Date = .now, limit: Int = 40, bytes: Int = byteLimit, focus:[LifeArea] = []) -> MemorySelection {
        let eligible = memories.filter { MemoryRules.usable($0,registration:registration,now:now) && MemoryRules.inScope($0,conversationID:conversationID,includeTopics:includeTopics) }
        let terms = tokens(query ?? "")
        let notebook=LifeNotebook.build(eligible,registration:registration,topic:conversationID,now:now,includeTopics:includeTopics)
        let seeds=Set(notebook.entities.filter { $0.id != LifeNotebook.selfID && !tokens($0.label).isDisjoint(with:terms) }.prefix(20).map(\.id))
        var neighbours=seeds,connected=Set<UUID>()
        // Two bounded hops. The universal self node is never a bridge to the whole life.
        for _ in 0..<2 {
            let previous=neighbours
            for link in notebook.links where previous.contains(link.from) || previous.contains(link.to) {
                connected.insert(link.memoryID)
                if link.from != LifeNotebook.selfID { neighbours.insert(link.from) }
                if link.to != LifeNotebook.selfID { neighbours.insert(link.to) }
                if neighbours.count >= 60 { break }
            }
        }
        func relevance(_ memory:PAMemory)->Int {
            let text=memory.text+" "+(memory.connections ?? []).map{$0.subject+" "+$0.relation+" "+$0.object}.joined(separator:" ")
            let direct=tokens(text).intersection(terms).reduce(0) { $0+min($1.count,12)*5 }
            let nearby=connected.contains(memory.id) ? 30 : 0
            let focused=memory.organisation?.areas.contains(where:focus.contains) == true ? 15 : 0
            return direct+nearby+focused
        }
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
