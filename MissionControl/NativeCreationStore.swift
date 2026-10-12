import Foundation
import Observation
import SwiftData

@MainActor @Observable final class NativeCreationStore {
    private(set) var state = NativeCreationState()
    private(set) var readable = true
    private let container: ModelContainer?
    init(container: ModelContainer?) {
        self.container = container
        do {
            if let record = try LocalRecordRepository.read("nativeCreationClaims", container: container) { state = try JSONDecoder().decode(NativeCreationState.self,from: record); guard state.version == 1 else { throw IntegrationError.verification } }
        } catch { readable = false }
    }
    func receipt(_ request: NativeCreationRequest) -> NativeCreationReceipt? { state.claims[request.key]?.receipt }
    func begin(_ request: NativeCreationRequest) throws {
        guard readable else { throw ActionFailure.message("Saved creation receipts are unavailable; no Apple item created.") }
        guard NativeCreationRules.allowed(state,key:request.key) else {
            throw ActionFailure.message(receipt(request) == nil ? "This save's outcome needs checking in Apple Calendar or Reminders before another attempt. It will not be repeated automatically." : "This item was already created; no duplicate added.")
        }
        let previous = state; state.claims[request.key] = .init(started:.now)
        do { try save() } catch { state = previous; throw ActionFailure.message("Could not save the creation checkpoint; no Apple item created.") }
    }
    func complete(_ request: NativeCreationRequest, receipt: NativeCreationReceipt) throws {
        guard state.claims[request.key] != nil, state.claims[request.key]?.receipt == nil, receipt.requestID == request.id, receipt.registration == request.registration, receipt.kind == request.kind else { throw IntegrationError.verification }
        let previous = state; state.claims[request.key]?.receipt = receipt
        do { try save() } catch { state = previous; throw ActionFailure.message("Apple saved the item, but its local receipt could not be saved. Check Apple Calendar or Reminders; do not create it again.") }
    }
    private func save() throws {
        guard let container else { throw IntegrationError.verification }
        try LocalRecordRepository(container: container).save(state, key: "nativeCreationClaims")
    }
}
