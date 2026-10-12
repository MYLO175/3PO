import Foundation
import SwiftData

struct ActionLedgerEntry: Codable {
    var result: String?
    var attempted = Date.now
    var itemID: String?
    var fixtureTitle: String?
    var undoToken: String?
    var undone: Bool?
    var fixtureNotes: String?
    var clearedMarker: Bool?
}

/// Durable action history. Claiming storage succeeds before any native operation
/// starts; a native operation with unknown outcome retains its pending claim.
@MainActor final class ActionReceiptStore {
    var entries: [String: ActionLedgerEntry] = [:]
    private(set) var readable = true
    private let repository: LocalRecordRepository?
    init(container: ModelContainer?, repository: LocalRecordRepository? = nil) {
        self.repository = repository ?? container.map { LocalRecordRepository(container: $0) }
        do {
            if let bytes = try self.repository?.read("assistantActionLedger") {
                entries = try JSONDecoder().decode([String: ActionLedgerEntry].self, from: bytes)
            }
        } catch { readable = false }
    }
    func save() throws {
        guard readable, let repository else { throw ActionFailure.message("Action storage is unavailable; no write was attempted.") }
        try repository.save(entries, key: "assistantActionLedger")
    }
    func begin(_ key: String) throws {
        if let prior = entries[key], prior.undone != true {
            throw ActionFailure.message("This operation already has a receipt. Check the original; no repeated save.")
        }
        let before = entries
        entries[key] = ActionLedgerEntry()
        do { try save() }
        catch { entries = before; throw error }
    }
}
