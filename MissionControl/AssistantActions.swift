import Foundation
import Observation
import SwiftData

struct ActionTarget: Identifiable { var id: String; var label: String }
private struct ActionLedgerEntry: Codable { var result: String?; var attempted = Date.now; var itemID: String?; var fixtureTitle: String?; var undoToken: String?; var undone: Bool? }

@MainActor @Observable final class AssistantActions {
    var targets: [ActionTarget] = []
    var selectedTarget = ""
    private var ledger: [String:ActionLedgerEntry] = [:]
    private let container: ModelContainer?
    private var storageAvailable = true
    init(container: ModelContainer?) {
        self.container = container
        do { if let record = try container?.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first(where: { $0.key == "assistantActionLedger" }) { ledger = try JSONDecoder().decode([String:ActionLedgerEntry].self, from: record.data) } }
        catch { storageAvailable = false }
    }
    private func save() throws {
        guard storageAvailable, let container else { throw ActionFailure.message("Action storage is unavailable; no write was attempted.") }
        let context = container.mainContext, data = try JSONEncoder().encode(ledger)
        if let record = try context.fetch(FetchDescriptor<CachedDashboard>()).first(where: { $0.key == "assistantActionLedger" }) { record.data = data; record.updated = .now }
        else { context.insert(CachedDashboard(key: "assistantActionLedger", data: data)) }
        try context.save()
    }
    /// Executes a completed model tool call using only identities issued in this turn.
    /// The latest human message authorises the operation; imported records never do.
    func performTool(_ draft: ActionDraft, human: String, authorization: String?, turnID: UUID, model: DashboardModel, calendar: CalendarSnapshot, reminders: ReminderSnapshot, expectedDetails: NativeEditDetails? = nil, valid: NativeWriteValidity? = nil) async throws -> String {
        try PAToolProtocol.evidence(authorization,human:human)
        try ActionRules.validate(draft)
        guard model.assistant.contextEnabled, !model.writing, !ProcessInfo.processInfo.arguments.contains("--sample") else { throw ActionFailure.message("Apple writes are unavailable; no change attempted.") }
        let reminder = reminders.reminders.first { $0.id == draft.target }, event = calendar.events.first { $0.id == draft.target }
        switch draft.kind {
        case .editReminder,.completeReminder,.deleteReminder: guard reminder != nil else { throw ActionFailure.message("Read the reminder's exact identity before changing it.") }
        case .editEvent,.deleteEvent: guard event != nil else { throw ActionFailure.message("Read the event's exact occurrence before changing it.") }
        default: break
        }
        if !selectedTarget.isEmpty, let target = draft.target, target != selectedTarget { throw ActionFailure.message("The tool target differs from your selected item.") }
        // Canonical operation key deduplicates repeated calls even if their call IDs differ.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let canonical = String(data:try encoder.encode(draft),encoding:.utf8)!
        let key = ActionRules.key(registration:model.chatGPT.activeID,request:turnID.uuidString,selectedTarget:canonical)
        if let prior = ledger[key], prior.undone != true {
            if let result = prior.result { return "Already applied: " + result }
            throw ActionFailure.message("This operation already has a pending receipt. Check the original; no repeated save.")
        }
        let allowedCalendars = Set(calendar.sources.filter { !model.assistant.excludedCalendars.contains($0.id) && $0.writable }.map(\.id))
        let allowedLists = Set(reminders.sources.filter { !model.assistant.excludedLists.contains($0.id) && $0.writable }.map(\.id))
        if let destination = draft.destination {
            let allowed = draft.kind == .createEvent || draft.kind == .editEvent ? allowedCalendars : allowedLists
            guard allowed.contains(destination) else { throw ActionFailure.message("Destination is not an enabled writable source issued by a read tool.") }
        }
        try Task.checkCancellation()
        model.writing = true; defer { model.writing = false }
        ledger[key] = ActionLedgerEntry()
        do { try save() } catch { ledger.removeValue(forKey:key); throw error }
        let result = try await model.eventKit.applyTool(draft,reminder:reminder,event:event,marker:key,allowedCalendars:allowedCalendars,allowedLists:allowedLists,expectedDetails:expectedDetails,valid:valid)
        ledger[key]?.result = result.message; ledger[key]?.itemID = result.itemID; ledger[key]?.undoToken = result.undoToken
        #if DEBUG
        if let title = draft.title, (draft.kind == .createReminder || draft.kind == .createEvent), title.hasPrefix("Mission Control tool validation "), UUID(uuidString:String(title.dropFirst("Mission Control tool validation ".count))) != nil, draft.notes == nil { ledger[key]?.fixtureTitle = title }
        if let itemID = result.itemID, let title = draft.title {
            for (originalKey, original) in ledger where original.itemID == itemID && original.fixtureTitle != nil { ledger[originalKey]?.fixtureTitle = title }
        }
        #endif
        if let token = result.undoToken { model.undoToken = token; model.undoTitle = reminder?.title ?? "Reminder" }
        if draft.scope == "futureEvents" || draft.scope == "reminderSeries" || draft.kind == .deleteEvent || draft.kind == .deleteReminder || (draft.kind == .editEvent || draft.kind == .editReminder) && result.nativeUndo == nil { model.clearNativeEditUndo() }
        if let undo = result.nativeUndo { model.recordAssistantEditUndo(undo) }
        model.showFeedback(result.message); selectedTarget = ""; model.refresh(retryMail:false)
        do { try save() } catch { return result.message + " Apple save verified, but receipt storage failed. Check the original before repeating." }
        return result.message
    }
    func performNativeDeletion(baseline: NativeEditDetails, scope: NativeChangeScope, requestID: UUID, model: DashboardModel) async throws -> String {
        let key=ActionRules.key(registration:model.chatGPT.activeID,request:requestID.uuidString,selectedTarget:baseline.occurrenceID + ":delete:" + scope.rawValue)
        if let prior=ledger[key] { if let result=prior.result {return result};throw ActionFailure.message("A deletion is already recorded as pending. Check Apple Calendar or Reminders; it will not be repeated.") }
        try NativeEditRules.validateDeletion(scope,baseline:baseline)
        ledger[key]=ActionLedgerEntry();do {try save()} catch {ledger.removeValue(forKey:key);throw error}
        let result=try await model.eventKit.deleteItem(baseline:baseline,scope:scope)
        ledger[key]?.result=result;ledger[key]?.itemID=baseline.itemID
        do {try save()} catch {throw ActionFailure.message(result + " Native deletion verified, but receipt storage failed; check the original before repeating.")}
        return result
    }
    func recordUndo(token: String) throws {
        for (key, entry) in ledger where entry.undoToken == token { ledger[key]?.undone = true }
        try save()
    }
    #if DEBUG
    func cleanupFixtures(_ model: DashboardModel) async throws -> String {
        for (key, entry) in ledger where entry.fixtureTitle != nil {
            guard let id = entry.itemID, let title = entry.fixtureTitle else { continue }
            try await model.eventKit.removeActionFixture(id:id,title:title,marker:key)
            ledger[key]?.fixtureTitle = nil
            try save()
        }
        model.refresh(retryMail:false)
        return "Tracked assistant action fixtures cleaned and absence verified."
    }
    #endif
}
