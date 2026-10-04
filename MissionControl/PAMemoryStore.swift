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
        change { state in
            if let memory = state.records.first(where:{ $0.id == id }), let turn = memory.sourceTurnID { state.suppressed[memory.registration,default:[]].insert(turn) }
            state.records.removeAll { $0.id == id }
        }
    }
    @discardableResult func accept(_ id: UUID) -> Bool { change { state in if let i = state.records.firstIndex(where:{ $0.id == id }) { state.records[i].explicit = true; state.records[i].reviewed = .now } } }
    @discardableResult func resolve(_ id: UUID) -> Bool { change { state in if let i = state.records.firstIndex(where:{ $0.id == id }) { state.records[i].resolved = .now } } }
    @discardableResult func reopen(_ id: UUID) -> Bool { change { state in if let i = state.records.firstIndex(where:{ $0.id == id }) { state.records[i].resolved = nil; state.records[i].reviewed = .now } } }
    @discardableResult func merge(_ learned: [LearnedMemory], registration: String, sourceDates: [String:Date] = [:], sourceTopics: [String:UUID] = [:]) -> Bool {
        change { state in
            for entry in learned where !state.suppressed[registration,default:[]].contains(entry.turnID) {
                guard !state.records.contains(where:{  $0.registration == registration && $0.conversationID == sourceTopics[entry.turnID] && MemoryLearningRules.normalised($0.text) == MemoryLearningRules.normalised(entry.text) }) else { continue }
                state.records.append(PAMemory(registration:registration,text:entry.text,kind:entry.kind,explicit:false,provenance:"Learned from your conversation",sourceTurnID:entry.turnID,evidence:entry.evidence,sourceDate:sourceDates[entry.turnID],conversationID:sourceTopics[entry.turnID],certainty:entry.certainty,durability:entry.durability,connections:entry.connections))
            }
        }
    }
    func selection(_ registration: String, conversationID: UUID? = nil, includeTopics: Bool = false, query: String? = nil) -> MemorySelection {
        guard enabled else { return MemorySelection(records:[],eligibleCount:0) }
        return MemoryRetrieval.select(records,registration:registration,conversationID:conversationID,includeTopics:includeTopics,query:query)
    }
    func context(_ registration: String, conversationID: UUID? = nil, includeTopics: Bool = false, query: String? = nil) -> [[String:String]] {
        selection(registration,conversationID:conversationID,includeTopics:includeTopics,query:query).records
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
