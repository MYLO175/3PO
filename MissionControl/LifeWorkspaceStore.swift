import Foundation
import SwiftData
import Observation

struct LifeWorkspaceEditUndo {
    var before: LifeItem
    var savedRevision: UUID
    var created = Date.now
}

@MainActor @Observable final class LifeWorkspaceStore {
    private(set) var state = LifeWorkspaceState()
    private(set) var revision = UUID()
    private(set) var error: String?
    private let container: ModelContainer?
    private var writable = true
    private var edits: [String:LifeWorkspaceEditUndo] = [:]
    var readOnly: Bool { !writable || container == nil }
    func undoEdit(_ registration: String) -> LifeWorkspaceEditUndo? {
        guard let ticket = edits[registration], state.items.contains(where: { $0.id == ticket.before.id && $0.registration == registration && $0.revision == ticket.savedRevision }) else { return nil }
        return ticket
    }
    func undoDate(_ registration: String) -> Date? { undoEdit(registration)?.created }
    func undo(_ registration: String, receipt: LifeWorkspaceReceipt? = nil) throws {
        guard let ticket = undoEdit(registration) else { throw LifeWorkspaceFailure.message("No unchanged project edit remains to undo. Creation and relationship changes are outside this Undo.") }
        _ = try save(ticket.before, expected:ticket.savedRevision, receipt:receipt); edits.removeValue(forKey:registration)
    }
    init(container: ModelContainer?) {
        self.container = container
        do {
            if let record = try container?.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first(where: { $0.key == "lifeWorkspace" }) {
                let value = try JSONDecoder().decode(LifeWorkspaceState.self, from: record.data)
                try LifeWorkspaceRules.validate(value); state = value
            }
        } catch { writable = false; self.error = "Projects could not be read. Their saved record is preserved; editing is disabled." }
    }
    func items(_ registration: String, topic: UUID? = nil, includeTopics: Bool = false) -> [LifeItem] {
        state.items.filter { LifeWorkspaceRules.scoped($0, registration: registration, topic: topic, includeTopics: includeTopics) }
            .sorted { $0.created == $1.created ? $0.id.uuidString < $1.id.uuidString : $0.created < $1.created }
    }
    func receipt(_ key: String?, registration: String) -> LifeWorkspaceReceipt? {
        key.flatMap { key in state.receipts.first { $0.id == key && $0.registration == registration } }
    }
    @discardableResult func save(_ value: LifeItem, expected: UUID?, receipt: LifeWorkspaceReceipt? = nil) throws -> LifeItem {
        if let prior = self.receipt(receipt?.id, registration: value.registration), let id = prior.itemID, let item = state.items.first(where: { $0.id == id && $0.registration == value.registration }) { return item }
        var candidate = state, item = value
        var before: LifeItem?
        if let index = candidate.items.firstIndex(where: { $0.id == item.id }) {
            let old = candidate.items[index]
            guard old.registration == item.registration && old.conversationID == item.conversationID && old.revision == expected else { throw LifeWorkspaceFailure.message("This item changed while you were editing. Reopen it before saving.") }
            item.created = old.created; item.updated = .now; item.revision = UUID(); candidate.items[index] = item
            before = old
        } else {
            guard expected == nil else { throw LifeWorkspaceFailure.message("The item is no longer available.") }
            if candidate.items.contains(where: { $0.registration == item.registration && $0.conversationID == item.conversationID && $0.parentID == item.parentID && $0.kind == item.kind && LifeWorkspaceRules.key($0.title) == LifeWorkspaceRules.key(item.title) }) {
                throw LifeWorkspaceFailure.message("That item already exists here. Open it rather than adding another copy.")
            }
            item.updated = .now; candidate.items.append(item)
        }
        try addReceipt(receipt, to: &candidate); try persist(candidate)
        if let before { edits[item.registration] = .init(before:before, savedRevision:item.revision) }
        return item
    }
    /// Batch creation is atomic, including references to earlier entries in the same batch.
    func create(_ items: [LifeItem], receipt: LifeWorkspaceReceipt) throws -> [LifeItem] {
        if self.receipt(receipt.id, registration: receipt.registration) != nil {
            throw LifeWorkspaceFailure.message("This batch is already saved. Read projects to inspect it; do not recreate it.")
        }
        guard (1...12).contains(items.count), items.allSatisfy({ $0.registration == receipt.registration }) else { throw LifeWorkspaceFailure.message("Create between one and twelve items for this account.") }
        var candidate = state
        for item in items {
            guard !candidate.items.contains(where: { $0.id == item.id || ($0.registration == item.registration && $0.conversationID == item.conversationID && $0.kind == item.kind && $0.parentID == item.parentID && LifeWorkspaceRules.key($0.title) == LifeWorkspaceRules.key(item.title)) }) else { throw LifeWorkspaceFailure.message("An item in this batch already exists here. Read the current structure before adding it.") }
            candidate.items.append(item)
        }
        try addReceipt(receipt, to: &candidate); try persist(candidate); return items
    }
    @discardableResult func link(_ value: LifeItemLink, expected: UUID, receipt: LifeWorkspaceReceipt? = nil) throws -> LifeItemLink {
        guard let owner = state.items.first(where: { $0.id == value.from && $0.registration == value.registration && $0.conversationID == value.conversationID }), owner.revision == expected else { throw LifeWorkspaceFailure.message("Read the current project before linking it.") }
        if let existing = state.links.first(where: { $0.from == value.from && $0.relation == value.relation && $0.target == value.target }) {
            if let receipt, self.receipt(receipt.id, registration: value.registration) == nil { var candidate = state; try addReceipt(receipt, to: &candidate); try persist(candidate) }
            return existing
        }
        var candidate = state; candidate.links.append(value)
        try addReceipt(receipt, to: &candidate); try persist(candidate); return value
    }
    func unlink(_ id: UUID, registration: String, expectedRevision: UUID, receipt: LifeWorkspaceReceipt? = nil) throws {
        if self.receipt(receipt?.id, registration: registration) != nil { return }
        guard revision == expectedRevision, state.links.contains(where: { $0.id == id && $0.registration == registration }) else { throw LifeWorkspaceFailure.message("This relationship changed. Read it again before removing it.") }
        var candidate = state; candidate.links.removeAll { $0.id == id && $0.registration == registration }
        try addReceipt(receipt, to: &candidate); try persist(candidate)
    }
    private func addReceipt(_ receipt: LifeWorkspaceReceipt?, to value: inout LifeWorkspaceState) throws {
        guard let receipt else { return }
        guard !value.receipts.contains(where: { $0.id == receipt.id }) else { throw LifeWorkspaceFailure.message("This operation already has a saved receipt. Read its result before continuing.") }
        // Bound operation ledger without dropping interrupted/new work.
        if value.receipts.count >= 2000 { value.receipts.removeFirst(value.receipts.count - 1999) }
        value.receipts.append(receipt)
    }
    private func persist(_ value: LifeWorkspaceState) throws {
        guard writable, let container else { throw LifeWorkspaceFailure.message(error ?? "Project storage is unavailable. Your changes have not been saved.") }
        try LifeWorkspaceRules.validate(value)
        do {
            let context = container.mainContext, data = try JSONEncoder().encode(value)
            if let record = try context.fetch(FetchDescriptor<CachedDashboard>()).first(where: { $0.key == "lifeWorkspace" }) { record.data = data; record.updated = .now }
            else { context.insert(CachedDashboard(key: "lifeWorkspace", data: data)) }
            try context.save(); state = value; revision = UUID(); error = nil
        } catch { container.mainContext.rollback(); self.error = "Projects could not be saved. Your editing draft is kept."; throw LifeWorkspaceFailure.message(self.error!) }
    }
}
