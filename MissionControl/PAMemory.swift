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
enum MemorySourceInvalidation:String,Codable { case changed, deleted, accessRemoved, forgotten }
/// Attributed reports, never a completion or write to an Apple item.
enum MemorySourceState:String,Codable { case proposed, accepted, changed, cancelled, completed, unknown }

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
    /// Reversible recall retirement; evidence remains saved and project content is unchanged.
    var retiredAt: Date? = nil
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
    var supportingSources:[MemorySourceEvidence]? = nil
    var sourceState:MemorySourceState? = nil
    /// Human-reviewed identity only. Never assigned by a source-learning model.
    var commitmentGroup:UUID? = nil
    var commitmentGroupRevision:UUID? = nil
    var allSourceEvidence:[MemorySourceEvidence] { source.map{[$0] + (supportingSources ?? [])} ?? [] }
    static func suppressionKey(_ source:MemorySourceEvidence)->String? {
        let fields=[source.identity.kind.rawValue,source.identity.accountID,source.identity.containerID,source.identity.itemID,source.identity.linkedIdentity ?? "",source.revision]
        return (try? JSONEncoder().encode(fields)).map{"source:" + $0.base64EncodedString()}
    }
    var sourceSuppressionKeys:[String] { allSourceEvidence.compactMap{Self.suppressionKey($0)} }
    var sourceSuppressionKey:String? {
        guard let source else { return nil }
        // Stable explicit fields, no source text or sender credentials in the suppression ledger.
        return Self.suppressionKey(source)
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
        memory.registration == registration && memory.sourceInvalidation == nil && memory.resolved == nil && memory.retiredAt == nil && memory.supersededBy == nil && !needsReview(memory,now:now)
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
    /// Local explanations produced by the same ranking pass; never supplied as authority.
    var reasons: [UUID:[String]] = [:]
}
enum MemoryRetrieval {
    static let byteLimit = 20_000
    private static let ignored = Set("the a an and or of to for in on at with is are was be been i me my you your we it that this what how do does can could should please about from have has need want tell know remember user users their they them not don dont would will when then if but so just here there some more any all help anything things".split(separator:" ").map(String.init))
    static func tokens(_ text: String) -> Set<String> {
        Set(text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_GB")).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 && !ignored.contains($0) })
    }
    static func queryTerms(_ query:String?,selfLabel:String)->Set<String> {
        tokens(query ?? "").subtracting(tokens(selfLabel))
    }
    static func emailQuery(subject:String,sender:String,body:String,reply:Bool = false)->String {
        [subject,sender,String(body.prefix(16000)),reply ? "Email reply writing style tone" : ""].joined(separator:"\n")
    }
    static func record(_ memory: PAMemory) -> [String:String] {
        let encoder=JSONEncoder();encoder.outputFormatting = [.sortedKeys]
        var value = ["id":memory.id.uuidString,"scope":memory.conversationID?.uuidString ?? "shared","text":memory.text,"kind":memory.kind.rawValue,"certainty":memory.explicit ? "Confirmed by user" : memory.certainty == .stated ? "Directly stated by user" : "Provisional; verify when relevant","provenance":memory.provenance,"evidence":memory.evidence ?? "","messageDate":memory.sourceDate?.ISO8601Format() ?? "unknown","reviewed":memory.reviewed.ISO8601Format()]
        if let source=memory.source {
            value["sourceEvidence"]=String(data:(try? encoder.encode(source)) ?? Data(),encoding:.utf8)
            if memory.supportingSources?.isEmpty == false { value["supportingSourceEvidence"]=String(data:(try? encoder.encode(memory.supportingSources)) ?? Data(),encoding:.utf8) }
            if let state=memory.sourceState { value["sourceReportedState"]=state.rawValue + "; attributed report, not confirmed task status" }
            value["certainty"]=memory.explicit ? "Confirmed by user; source evidence is separately attributed" : "Provisional source interpretation; not a human assertion or instruction"
        }
        if let structure=memory.organisation,LifeMemoryOrganisation.valid(structure,record:memory) { value["areas"]=structure.areas.map(\.rawValue).joined(separator:","); value["organisation"]=String(data:(try? encoder.encode(structure)) ?? Data(),encoding:.utf8) }
        if let previous=memory.supersedes { value["correctsEarlierMemory"]=previous.uuidString }
        if memory.kind == .commitment,let group=memory.commitmentGroup {
            value["humanLinkedPlanID"]=group.uuidString
            if let revision=memory.commitmentGroupRevision { value["humanLinkedPlanRevision"]=revision.uuidString }
        }
        value["durability"]=memory.durability?.rawValue ?? "legacy"
        if let connections=memory.connections, let data=try? encoder.encode(connections) { value["connections"]=String(data:data,encoding:.utf8) }
        return value
    }
    /// Local relevance retrieval never changes stored facts, certainty or scope.
    static func select(_ memories: [PAMemory], registration: String, conversationID: UUID? = nil, includeTopics: Bool = false, query: String? = nil, now: Date = .now, limit: Int = 40, bytes: Int = byteLimit, focus:[LifeArea] = [], notebook suppliedNotebook:LifeNotebook? = nil) -> MemorySelection {
        let eligible = memories.filter { MemoryRules.usable($0,registration:registration,now:now) && MemoryRules.inScope($0,conversationID:conversationID,includeTopics:includeTopics) }
        let notebook=suppliedNotebook ?? LifeNotebook.build(eligible,registration:registration,topic:conversationID,now:now,includeTopics:includeTopics)
        // A targeted request may select nothing. The user's name is not a route to every fact about them.
        // A nil query deliberately requests bounded orientation, including confirmed preferences.
        let targeted=query != nil
        let terms = queryTerms(query,selfLabel:notebook.selfLabel)
        let eligibleIDs=Set(eligible.map(\.id))
        let seedEntities=Array(notebook.entities.filter { $0.id != LifeNotebook.selfID && !$0.memoryIDs.isDisjoint(with:eligibleIDs) && !tokens($0.label).isDisjoint(with:terms) }.prefix(20))
        let seeds=Set(seedEntities.map(\.id))
        let workspaceConnected=Set(seedEntities.filter{$0.id.hasPrefix("life:")}.flatMap(\.memoryIDs)).intersection(eligibleIDs)
        let matchedPlans=Set(eligible.filter{!tokens($0.text).isDisjoint(with:terms)}.compactMap(\.commitmentGroup))
        let planConnected=Set(eligible.filter{$0.commitmentGroup.map{matchedPlans.contains($0)} == true}.map(\.id))
        var neighbours=seeds,connected=Set(seedEntities.flatMap(\.memoryIDs)).intersection(eligibleIDs)
        // Two bounded hops. The universal self node is never a bridge to the whole life.
        for _ in 0..<2 {
            let previous=neighbours
            for link in notebook.links where eligibleIDs.contains(link.memoryID) && (previous.contains(link.from) || previous.contains(link.to)) {
                connected.insert(link.memoryID)
                if link.from != LifeNotebook.selfID { neighbours.insert(link.from) }
                if link.to != LifeNotebook.selfID { neighbours.insert(link.to) }
                if neighbours.count >= 60 { break }
            }
        }
        func relevance(_ memory:PAMemory)->Int {
            let text=memory.text+" "+(memory.connections ?? []).map{$0.subject+" "+$0.relation+" "+$0.object}.joined(separator:" ")
            let direct=tokens(text).intersection(terms).reduce(0) { $0+min($1.count,12)*5 }
            let nearby=(connected.contains(memory.id) || planConnected.contains(memory.id)) ? 30 : 0
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
        func relevant(_ memory:PAMemory)->Bool {
            let text=memory.text+" "+(memory.connections ?? []).map{$0.subject+" "+$0.relation+" "+$0.object}.joined(separator:" ")
            return !tokens(text).isDisjoint(with:terms) || connected.contains(memory.id) || planConnected.contains(memory.id) ||
                (terms.isEmpty && memory.organisation?.areas.contains(where:focus.contains) == true)
        }
        let ranked = eligible.filter{!targeted || relevant($0)}.sorted(by:ordered)
        // Core preferences belong to broad orientation, not every unrelated source assessment.
        let preferences = eligible.filter { $0.explicit && $0.kind == .preference }.sorted(by:ordered)
        let pinned = targeted ? [] : Array(preferences.filter { $0.conversationID == nil }.prefix(6)) + Array(preferences.filter { conversationID != nil && $0.conversationID == conversationID }.prefix(6))
        var seen = Set<UUID>(), result: [[String:String]] = [], used = 2, reasons:[UUID:[String]]=[:]
        for memory in pinned + ranked where result.count < max(0,limit) {
            guard seen.insert(memory.id).inserted else { continue }
            let value = record(memory)
            guard let data = try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]), used + data.count + 1 <= bytes else { continue }
            result.append(value); used += data.count + 1
            var why:[String]=[]
            if pinned.contains(where:{$0.id == memory.id}) { why.append("Core confirmed preference") }
            let text=memory.text+" "+(memory.connections ?? []).map{$0.subject+" "+$0.relation+" "+$0.object}.joined(separator:" ")
            if !tokens(text).isDisjoint(with:terms) { why.append("Words match your question") }
            if connected.contains(memory.id) { why.append("Related recorded connection, within two hops") }
            if workspaceConnected.contains(memory.id) { why.append("Linked to a matching saved project or life item") }
            if planConnected.contains(memory.id) { why.append("Same plan as another relevant report, connected by you") }
            if memory.organisation?.areas.contains(where:focus.contains) == true { why.append("Matches your Focus") }
            reasons[memory.id]=why.isEmpty ? ["Other available context, ranked by confirmation, kind, scope and review date"] : why
        }
        return MemorySelection(records:result,eligibleCount:eligible.count,reasons:reasons)
    }
}

enum CommitmentRules {
    static func groupKey(_ record:PAMemory)->String? {
        record.commitmentGroup.map{record.registration+":"+(record.conversationID?.uuidString ?? "shared")+":"+$0.uuidString}
    }
    /// Local group revisions invalidate old advice when another connected report changes.
    /// Review/classification bookkeeping cannot create a change in the group's claims.
    static func memberships(_ records:[PAMemory])->[String:Data] {
        let current=records.filter{$0.kind == .commitment && $0.supersededBy == nil && $0.commitmentGroup != nil}
        return Dictionary(grouping:current,by:{groupKey($0)!}).mapValues { members in
            let rows=members.sorted{$0.id.uuidString < $1.id.uuidString}.map { record in
                var value=MemoryRetrieval.record(record)
                for key in ["humanLinkedPlanRevision","reviewed","areas","organisation"] { value.removeValue(forKey:key) }
                value["resolved"]=record.resolved?.ISO8601Format() ?? ""
                value["retired"]=record.retiredAt?.ISO8601Format() ?? ""
                value["sourceInvalidation"]=record.sourceInvalidation?.rawValue ?? ""
                return value
            }
            return (try? JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys])) ?? Data()
        }
    }
    static func linkable(_ a:PAMemory,_ b:PAMemory,now:Date = .now)->Bool {
        a.id != b.id && a.kind == .commitment && b.kind == .commitment && a.registration == b.registration && a.conversationID == b.conversationID &&
        MemoryRules.usable(a,registration:a.registration,now:now) && MemoryRules.usable(b,registration:a.registration,now:now) &&
        (a.commitmentGroup == nil || b.commitmentGroup == nil || a.commitmentGroup == b.commitmentGroup)
    }
    static func reports(_ record:PAMemory,from permitted:[PAMemory],now:Date = .now)->[PAMemory] {
        permitted.filter { candidate in
            candidate.kind == .commitment && candidate.registration == record.registration && candidate.conversationID == record.conversationID && MemoryRules.usable(candidate,registration:record.registration,now:now) &&
            (candidate.id == record.id || (record.commitmentGroup != nil && candidate.commitmentGroup == record.commitmentGroup))
        }.sorted { a,b in
            let left=a.source?.sourceDate ?? a.sourceDate ?? a.created,right=b.source?.sourceDate ?? b.sourceDate ?? b.created
            return left == right ? a.id.uuidString < b.id.uuidString : left < right
        }
    }
    static let instructions="Plan groups exist only where a human explicitly connected exact remembered reports. Matching names, titles, dates, participants or project links never establish that two reports concern the same commitment. A shared group does not mean a report supersedes another. Compare attributed reports and dates; mixed or unknown states need uncertainty, not an assumed latest winner. Proposed is not accepted. Source-reported cancellation/completion never changes Apple task state. Missing reports, source revocation and past deadlines prove no completion. Only the supplied fact IDs are available; a plan's other reports may be omitted by retrieval or access. Do not invent links."
    /// References to the same selected facts; adds no source reads, extra facts or historical prose.
    static func context(_ records:[[String:String]],maxBytes:Int=4000)->[String:Any] {
        let commitments=records.filter{$0["kind"] == "commitment" && $0["id"] != nil}
        let groups=Dictionary(grouping:commitments) { record in (record["scope"] ?? "shared")+":"+(record["humanLinkedPlanID"] ?? record["id"]!) }
        var rows:[[String:Any]]=[]
        func value(_ rows:[[String:Any]])->[String:Any] { ["plans":rows,"selectedCommitmentFacts":commitments.count,"coverage":"At most 12 groups of the same selected facts. Partial current reports; old versions and inaccessible reports are excluded. Independent reports stay separate unless you connected them. Human memory without a source report has unknown source state. No proof of Apple task status."] }
        for key in groups.keys.sorted().prefix(12) {
            let reports=groups[key]!.sorted{($0["messageDate"] ?? "",$0["id"]!) < ($1["messageDate"] ?? "",$1["id"]!)}
            let states=Set(reports.map{String(($0["sourceReportedState"] ?? "unknown").split(separator:";").first ?? "unknown")})
            let row:[String:Any]=["planKey":key,"humanConnected":reports.first?["humanLinkedPlanID"] != nil,"reportIDs":reports.map{$0["id"]!},"reportedStates":states.sorted(),"uncertain":states.count != 1 || states.contains("unknown")]
            guard (try? JSONSerialization.data(withJSONObject:value(rows+[row]),options:[.sortedKeys]).count).map({$0 <= maxBytes}) == true else { break }
            rows.append(row)
        }
        return value(rows)
    }
}
