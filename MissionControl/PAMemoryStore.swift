import Foundation
import Observation
import SwiftData

@MainActor @Observable final class PAMemoryStore {
    private(set) var state = MemoryEnvelope()
    var records: [PAMemory] { state.records }
    private(set) var error: String?
    private(set) var revision = UUID()
    var enabled = UserDefaults.standard.object(forKey:"paMemoryEnabled") as? Bool ?? true { didSet { UserDefaults.standard.set(enabled,forKey:"paMemoryEnabled"); revision = UUID() } }
    var learningEnabled = UserDefaults.standard.object(forKey:"paMemoryLearningEnabled") as? Bool ?? true { didSet { UserDefaults.standard.set(learningEnabled,forKey:"paMemoryLearningEnabled") } }
    private let container: ModelContainer?
    private var writable = true
    @ObservationIgnored var sourceIsPermitted:(PAMemory)->Bool = { _ in false }
    var permittedRecords:[PAMemory] { records.filter{$0.source == nil || sourceIsPermitted($0)} }
    init(container: ModelContainer?) {
        self.container = container
        do {
            if let record = try container?.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first(where:{ $0.key == "paMemory" }) {
                state = try MemoryEnvelope.decode(record.data)
                guard Set(records.map(\.id)).count == records.count else { throw MemoryLearningFailure.invalid }
            }
        } catch { writable = false; self.error = "Memory could not be read. The saved record is preserved; changes are disabled." }
    }
    func items(_ registration: String) -> [PAMemory] { records.filter { $0.registration == registration }.sorted { $0.reviewed > $1.reviewed } }
    func suppressed(_ registration: String) -> Set<String> { state.suppressed[registration] ?? [] }
    @discardableResult func put(_ memory: PAMemory) -> Bool {
        guard !memory.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, !memory.registration.isEmpty else { return false }
        var value = memory; value.text = String(value.text.prefix(2000)); value.reviewed = .now
        return change { state in if let i = state.records.firstIndex(where:{ $0.id == value.id }) { state.records[i] = value } else { state.records.append(value) } }
    }
    @discardableResult func forget(_ id: UUID) -> Bool {
        let family=versionFamily(id),ids=Set(family.map(\.id))
        return change { state in
            for memory in family { if let turn=memory.sourceTurnID { state.suppressed[memory.registration,default:[]].insert(turn) };if let key=memory.sourceSuppressionKey { state.suppressed[memory.registration,default:[]].insert(key) } }
            state.records.removeAll { ids.contains($0.id) }
        }
    }
    /// Forget a current belief's whole correction lineage; an explicitly selected earlier version only removes that version.
    func versionFamily(_ id:UUID)->[PAMemory] {
        guard let record=records.first(where:{$0.id == id}) else { return [] }
        guard record.supersededBy == nil else { return [record] }
        let byID=Dictionary(records.filter{$0.registration == record.registration}.map{($0.id,$0)},uniquingKeysWith:{first,_ in first})
        var result=[record],seen:Set<UUID>=[id],cursor=record
        while let previous=cursor.supersedes,seen.insert(previous).inserted,let value=byID[previous] { result.append(value);cursor=value }
        return result
    }
    @discardableResult func restoreForgotten(_ records:[PAMemory])->Bool {
        guard !records.isEmpty,Set(records.map(\.id)).count == records.count,records.allSatisfy({record in !self.records.contains(where:{$0.id == record.id})}) else { error="Memory changed after Forget; restoration stopped.";return false }
        return change { state in state.records.append(contentsOf:records) }
    }
    /// Only an executor with a captured source snapshot can call this. No ingestion is enabled by this API.
    /// Human memories cannot be overwritten by a source fact, even if the wording matches.
    @discardableResult func putSource(_ value:PAMemory,sourceText:String,expectedRevision:UUID)->Bool {
        putSources([value],sourceTexts:[value.id:sourceText],expectedRevision:expectedRevision)
    }
    @discardableResult func putSources(_ values:[PAMemory],sourceTexts:[UUID:String],expectedRevision:UUID)->Bool {
        guard revision == expectedRevision,values.count <= 4,Set(values.map(\.id)).count == values.count,
              values.allSatisfy({ value in
            guard let source=value.source,let sourceText=sourceTexts[value.id] else { return false }
            return source.valid(in:sourceText) && !value.registration.isEmpty && value.sourceInvalidation == nil && value.sourceTurnID == nil && value.conversationID == nil && !value.explicit && value.certainty == .inferred && value.durability == .situational && value.kind != .preference && !value.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && value.text.count <= 500 && value.evidence == source.quote && MemoryConnection.valid(value.connections,human:sourceText) && value.organisation?.selfName == nil && value.organisation?.manual != true && (value.organisation.map({LifeMemoryOrganisation.valid($0,record:value)}) ?? true) && value.supersedes == nil && value.supersededBy == nil && !records.contains(where:{$0.id == value.id})
        }) else { error="Source memory failed its evidence or captured-state checks.";return false }
        let fresh=values.filter { value in !(value.sourceSuppressionKey.map{state.suppressed[value.registration,default:[]].contains($0)} ?? false) && !records.contains(where:{$0.registration == value.registration && MemoryLearningRules.normalised($0.text) == MemoryLearningRules.normalised(value.text) && ($0.explicit || ($0.source?.identity == value.source?.identity && $0.source?.revision == value.source?.revision))}) }
        guard !fresh.isEmpty else { return true }
        return change { state in state.records.append(contentsOf:fresh) }
    }
    /// Invalidate only the exact observed version, so delayed edits cannot hide a newer belief.
    @discardableResult func invalidateSource(_ identity:MemorySourceIdentity,registration:String,previousRevision:String,reason:MemorySourceInvalidation)->Bool {
        let ids=Set(records.filter{$0.registration == registration && $0.source?.identity == identity && $0.source?.revision == previousRevision && $0.sourceInvalidation == nil}.map(\.id))
        guard !ids.isEmpty else { return true }
        return change { state in for index in state.records.indices where ids.contains(state.records[index].id) { state.records[index].sourceInvalidation=reason } }
    }
    @discardableResult func accept(_ id: UUID) -> Bool { change { state in if let i = state.records.firstIndex(where:{ $0.id == id }) { state.records[i].explicit = true; state.records[i].reviewed = .now } } }
    @discardableResult func resolve(_ id: UUID) -> Bool { change { state in if let i = state.records.firstIndex(where:{ $0.id == id }) { state.records[i].resolved = .now } } }
    @discardableResult func reopen(_ id: UUID) -> Bool { change { state in if let i = state.records.firstIndex(where:{ $0.id == id }) { state.records[i].resolved = nil; state.records[i].reviewed = .now } } }
    /// Correct a current belief atomically, keeping the original ID, wording and evidence as history.
    @discardableResult func correct(_ id:UUID,with replacement:PAMemory)->Bool {
        guard let old=records.first(where:{$0.id == id}),old.supersededBy == nil,old.registration == replacement.registration,
              replacement.id != id,!records.contains(where:{$0.id == replacement.id}),!replacement.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { error="This is no longer the current memory, or its replacement is invalid.";return false }
        var next=replacement;next.text=String(next.text.prefix(2000));next.supersedes=id;next.supersededBy=nil;next.created = .now;next.reviewed = .now
        return change { state in if let index=state.records.firstIndex(where:{$0.id == id}) { state.records[index].supersededBy=next.id;state.records.append(next) } }
    }
    /// Restoration is itself a new correction, avoiding cycles or loss of intervening evidence.
    @discardableResult func restoreVersion(_ id:UUID)->Bool {
        guard let original=records.first(where:{$0.id == id}),original.supersededBy != nil else { return false }
        var current=original,seen=Set<UUID>()
        while let next=current.supersededBy {
            guard seen.insert(current.id).inserted,seen.count <= 100,let record=records.first(where:{$0.id == next && $0.registration == original.registration}) else { error="This memory history is incomplete; nothing was changed.";return false }
            current=record
        }
        var restored=original;restored.id=UUID();restored.conversationID=current.conversationID;restored.explicit=true;restored.certainty = .stated
        restored.resolved=nil;restored.source=nil;restored.sourceInvalidation=nil;restored.sourceTurnID=nil;restored.provenance="Earlier version restored by you";restored.sourceDate = .now
        if restored.conversationID != nil { restored.organisation?.selfName=nil }
        return correct(current.id,with:restored)
    }
    @discardableResult func merge(_ learned: [LearnedMemory], registration: String, sourceDates: [String:Date] = [:], sourceTopics: [String:UUID] = [:]) -> Bool {
        change { state in
            for entry in learned where !state.suppressed[registration,default:[]].contains(entry.turnID) {
                // Revisiting an old human turn must not resurrect its corrected belief under new prose.
                // Other distinct evidence in that rich turn remains eligible to be learned.
                guard !state.records.contains(where:{ old in
                    old.registration == registration && old.conversationID == sourceTopics[entry.turnID] && old.sourceTurnID == entry.turnID && old.supersededBy != nil &&
                    (MemoryLearningRules.normalised(old.text) == MemoryLearningRules.normalised(entry.text) || old.evidence.map{MemoryLearningRules.normalised($0) == MemoryLearningRules.normalised(entry.evidence)} == true)
                }) else { continue }
                guard !state.records.contains(where:{  $0.source == nil && $0.registration == registration && $0.conversationID == sourceTopics[entry.turnID] && $0.supersededBy == nil && $0.resolved == nil && MemoryLearningRules.normalised($0.text) == MemoryLearningRules.normalised(entry.text) }) else { continue }
                state.records.append(PAMemory(registration:registration,text:entry.text,kind:entry.kind,explicit:false,provenance:"Learned from your conversation",sourceTurnID:entry.turnID,evidence:entry.evidence,sourceDate:sourceDates[entry.turnID],conversationID:sourceTopics[entry.turnID],certainty:entry.certainty,durability:entry.durability,connections:entry.connections,organisation:entry.organisation))
            }
        }
    }
    @discardableResult func organise(_ id:UUID,value:LifeMemoryOrganisation,expectedRevision:UUID)->Bool {
        organise([LifeOrganisationEntry(id:id,organisation:value)],expectedRevision:expectedRevision)
    }
    @discardableResult func organise(_ entries:[LifeOrganisationEntry],expectedRevision:UUID)->Bool {
        guard revision == expectedRevision,Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ entry in records.first(where:{$0.id == entry.id}).map { LifeMemoryOrganisation.valid(entry.organisation,record:$0) && $0.organisation?.manual != true && entry.organisation.manual != true } ?? false }) else { error="Memory changed, organisation is pinned, or classification was invalid."; return false }
        guard !entries.isEmpty else { return true }
        return change { state in for entry in entries { if let index=state.records.firstIndex(where:{$0.id == entry.id}) { state.records[index].organisation=entry.organisation } } }
    }
    /// A local organisation edit is explicitly pinned and never changes the original fact/evidence.
    @discardableResult func setOrganisation(_ id:UUID,value:LifeMemoryOrganisation?)->Bool {
        guard let record=records.first(where:{$0.id == id}),value.map({LifeMemoryOrganisation.valid($0,record:record)}) ?? true else { return false }
        return change { state in if let index=state.records.firstIndex(where:{$0.id == id}) { var value=value; value?.manual=true; state.records[index].organisation=value } }
    }
    func notebook(_ registration:String,topic:UUID? = nil,includeTopics:Bool=false)->LifeNotebook { LifeNotebook.build(enabled ? permittedRecords : [],registration:registration,topic:topic,includeTopics:includeTopics) }
    func selection(_ registration: String, conversationID: UUID? = nil, includeTopics: Bool = false, query: String? = nil, focus:[LifeArea] = [],includeSources:Bool = true) -> MemorySelection {
        guard enabled else { return MemorySelection(records:[],eligibleCount:0) }
        return MemoryRetrieval.select(includeSources ? permittedRecords : records.filter{$0.source == nil},registration:registration,conversationID:conversationID,includeTopics:includeTopics,query:query,focus:focus)
    }
    func context(_ registration: String, conversationID: UUID? = nil, includeTopics: Bool = false, query: String? = nil,includeSources:Bool = true) -> [[String:String]] {
        selection(registration,conversationID:conversationID,includeTopics:includeTopics,query:query,includeSources:includeSources).records
    }
    private func change(_ mutation: (inout MemoryEnvelope) -> Void) -> Bool {
        guard writable, let container else { error = "Memory storage is unavailable; nothing was changed."; return false }
        let old = state; mutation(&state)
        do {
            let context = container.mainContext, data = try JSONEncoder().encode(state)
            if let record = try context.fetch(FetchDescriptor<CachedDashboard>()).first(where:{ $0.key == "paMemory" }) { record.data = data; record.updated = .now }
            else { context.insert(CachedDashboard(key:"paMemory",data:data)) }
            try context.save(); revision = UUID(); error = nil; return true
        } catch { container.mainContext.rollback(); state = old; self.error = "Memory change could not be saved."; return false }
    }
}
