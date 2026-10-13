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
    var turnID: UUID?
    var registration: String?
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
    /// Counts confirmed outputs from fresh durable bytes, never dirty in-memory completion fields.
    func summary(registration: String, turnID: UUID) -> ActionTurnReceiptSummary {
        guard readable, let repository else { return .init(confirmed: 0, pending: 0, readable: false) }
        do {
            let saved = try repository.decode("assistantActionLedger", as: [String: ActionLedgerEntry].self) ?? [:]
            let owned = saved.values.filter { $0.registration == registration && $0.turnID == turnID && $0.undone != true }
            return .init(confirmed: owned.filter { $0.result != nil }.count,
                         pending: owned.filter { $0.result == nil }.count, readable: true)
        } catch { return .init(confirmed: 0, pending: 0, readable: false) }
    }
    func complete(_ key: String, result: String, itemID: String?, undoToken: String? = nil,
                  fixtureTitle: String? = nil, fixtureNotes: String? = nil) throws {
        guard var entry = entries[key], entry.result == nil else { throw ActionFailure.message("The native operation's pending receipt is unavailable; check the original before continuing.") }
        let before = entries
        entry.result = result; entry.itemID = itemID; entry.undoToken = undoToken
        entry.fixtureTitle = fixtureTitle; entry.fixtureNotes = fixtureNotes
        entries[key] = entry
        do { try save() } catch { entries = before; throw error }
    }
    func begin(_ key: String, turnID: UUID? = nil, registration: String? = nil) throws {
        if let prior = entries[key], prior.undone != true {
            throw ActionFailure.message("This operation already has a receipt. Check the original; no repeated save.")
        }
        let before = entries
        entries[key] = ActionLedgerEntry(turnID: turnID, registration: registration)
        do { try save() }
        catch { entries = before; throw error }
    }
}

/// A read-only count of operation receipts, not authority to retry pending native saves.
struct ActionTurnReceiptSummary {
    var confirmed: Int
    var pending: Int
    var readable: Bool
}

/// Stops inference after a durable claim when native save/readback or receipt storage is unconfirmed.
struct PANativeActionUncertainty: LocalizedError {
    var operationKey: String
    var nativeReadbackVerified: Bool = false
    var message: String
    var errorDescription: String? { message }
    func stoppedReply(receipts: [String]) -> String {
        ([receipts.joined(separator: "\n"), message].filter { !$0.isEmpty }).joined(separator: "\n\n")
    }
}
