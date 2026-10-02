import Foundation
import Observation
import SwiftData

@MainActor @Observable final class PAMemoryStore {
    private(set) var records: [PAMemory] = []
    private(set) var error: String?
    var enabled = UserDefaults.standard.object(forKey:"paMemoryEnabled") as? Bool ?? true { didSet { UserDefaults.standard.set(enabled,forKey:"paMemoryEnabled") } }
    private let container: ModelContainer?
    private var writable = true
    init(container: ModelContainer?) {
        self.container = container
        do {
            if let record = try container?.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first(where:{ $0.key == "paMemory" }) {
                records = try JSONDecoder().decode([PAMemory].self,from:record.data)
                guard Set(records.map(\.id)).count == records.count else { throw WorkspaceFailure.invalid }
            }
        } catch { writable = false; self.error = "Memory could not be read. The saved record is preserved; changes are disabled." }
    }
    func items(_ registration: String) -> [PAMemory] { records.filter { $0.registration == registration }.sorted { $0.reviewed > $1.reviewed } }
    @discardableResult func put(_ memory: PAMemory) -> Bool {
        guard !memory.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, !memory.registration.isEmpty else { return false }
        var value = memory; value.text = String(value.text.prefix(2000)); value.reviewed = .now
        return change { values in if let i = values.firstIndex(where:{ $0.id == value.id }) { values[i] = value } else { values.append(value) } }
    }
    @discardableResult func forget(_ id: UUID) -> Bool { change { $0.removeAll { $0.id == id } } }
    @discardableResult func resolve(_ id: UUID) -> Bool { change { if let i = $0.firstIndex(where:{ $0.id == id }) { $0[i].resolved = .now } } }
    @discardableResult func reopen(_ id: UUID) -> Bool { change { if let i = $0.firstIndex(where:{ $0.id == id }) { $0[i].resolved = nil; $0[i].reviewed = .now } } }
    func context(_ registration: String) -> [[String:String]] {
        guard enabled else { return [] }
        return items(registration).filter { MemoryRules.usable($0,registration:registration) }.prefix(40).map {
            ["id":$0.id.uuidString,"text":$0.text,"kind":$0.kind.rawValue,"certainty":$0.explicit ? "Explicitly provided by user" : "Provisional; verify when relevant","provenance":$0.provenance,"reviewed":$0.reviewed.ISO8601Format()]
        }
    }
    private func change(_ mutation: (inout [PAMemory]) -> Void) -> Bool {
        guard writable, let container else { error = "Memory storage is unavailable; nothing was changed."; return false }
        let old = records; mutation(&records)
        do {
            let context = container.mainContext, data = try JSONEncoder().encode(records)
            if let record = try context.fetch(FetchDescriptor<CachedDashboard>()).first(where:{ $0.key == "paMemory" }) { record.data = data; record.updated = .now }
            else { context.insert(CachedDashboard(key:"paMemory",data:data)) }
            try context.save(); error = nil; return true
        } catch { container.mainContext.rollback(); records = old; self.error = "Memory change could not be saved."; return false }
    }
}
