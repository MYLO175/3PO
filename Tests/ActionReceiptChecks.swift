import Foundation
import SwiftData

@MainActor private final class FictionalWriter: NativeActionWriting {
    var attempts = 0
    var fail = false
    func applyTool(_ draft: ActionDraft, reminder: TaskItem?, event: AgendaEvent?, marker: String, allowedCalendars: Set<String>, allowedLists: Set<String>, expectedDetails: NativeEditDetails?, valid: NativeWriteValidity?) async throws -> ActionResult {
        attempts += 1
        if fail { throw ActionFailure.message("Fictional uncertain native outcome") }
        return .init(message:"Fictional verified action",itemID:"fictional-native-item")
    }
    func deleteItem(baseline: NativeEditDetails, scope: NativeChangeScope, valid: NativeWriteValidity?, claim: NativeWriteClaim?) async throws -> String { attempts += 1;return "Fictional deletion" }
}
@MainActor private final class FictionalRuntime: NativeActionRuntime {
    let writer = FictionalWriter()
    var actionRegistration = "fixture"
    var actionContextEnabled = true
    var actionAssistantBusy = false
    var actionExcludedCalendars: Set<String> = []
    var actionExcludedLists: Set<String> = []
    var nativeActionWriter: any NativeActionWriting { writer }
    var writing = false
    var undoToken: String?
    var undoTitle = ""
    var refreshes = 0
    func clearNativeEditUndo() {}
    func recordAssistantEditUndo(_ receipt: NativeEditUndo) {}
    func showFeedback(_ text: String) {}
    func refresh(retryMail: Bool) { refreshes += 1 }
}
@main struct ActionReceiptChecks {
    @MainActor static func main() async throws {
        enum Injected: Error { case failure }
        func check(_ value: Bool) { precondition(value) }
        let container = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = LocalRecordRepository(container: container)
        var fail = true
        let injected = LocalRecordRepository(container: container) { _ in if fail { throw Injected.failure } }
        let ledger = ActionReceiptStore(container: container, repository: injected)
        var nativeAttempts = 0
        do { try ledger.begin("fictional-request"); nativeAttempts += 1; check(false) }
        catch Injected.failure { }
        check(nativeAttempts == 0 && ledger.entries.isEmpty)
        try repository.save("Other owner", key: "unrelated")
        let reopened = ActionReceiptStore(container: container)
        check(reopened.entries.isEmpty)
        fail = false
        try ledger.begin("fictional-request")
        check(ledger.entries.count == 1 && ledger.entries["fictional-request"]?.result == nil)
        let uncertain = ActionReceiptStore(container: container)
        do { try uncertain.begin("fictional-request"); check(false) }
        catch { check(uncertain.entries.count == 1) }
        ledger.entries["fictional-request"]?.result = "Native save verified"
        fail = true
        do { try ledger.save(); check(false) } catch Injected.failure { }
        let afterFailedCompletion = ActionReceiptStore(container: container)
        check(afterFailedCompletion.entries["fictional-request"]?.result == nil)
        do { try afterFailedCompletion.begin("fictional-request"); check(false) } catch { }
        fail = false; try ledger.save()
        let completed = ActionReceiptStore(container: container)
        check(completed.entries["fictional-request"]?.result == "Native save verified")
        completed.entries["fictional-request"]?.undone = true; try completed.save()
        try completed.begin("fictional-request")
        check(completed.entries["fictional-request"]?.undone == nil)
        try repository.write(["assistantActionLedger": Data("unreadable original".utf8)])
        let bad = ActionReceiptStore(container: container)
        check(!bad.readable)
        do { try bad.begin("new"); check(false) } catch { }
        try check(repository.read("assistantActionLedger") == Data("unreadable original".utf8))
        let actionContainer = try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let actionRepository = LocalRecordRepository(container:actionContainer)
        var failActionSave = true
        let actionFailure = LocalRecordRepository(container:actionContainer) { _ in if failActionSave {throw Injected.failure} }
        let actions = AssistantActions(container:actionContainer,repository:actionFailure)
        let runtime = FictionalRuntime(), request = UUID(), human = "Create a fictional reminder"
        let draft = ActionDraft(kind:.createReminder,title:"Fictional reminder")
        let calendars = CalendarSnapshot(sources:[],events:[])
        let reminders = ReminderSnapshot(sources:[.init(id:"list",title:"To do",account:"Fixture",writable:true)],reminders:[])
        do { _ = try await actions.performTool(draft,human:human,authorization:human,turnID:request,model:runtime,calendar:calendars,reminders:reminders);check(false) }
        catch Injected.failure { }
        check(runtime.writer.attempts == 0 && !runtime.writing)
        try actionRepository.save("Later save",key:"unrelated")
        check(ActionReceiptStore(container:actionContainer).entries.isEmpty)
        failActionSave = false;runtime.writer.fail = true
        do { _ = try await actions.performTool(draft,human:human,authorization:human,turnID:request,model:runtime,calendar:calendars,reminders:reminders);check(false) } catch { }
        check(runtime.writer.attempts == 1 && ActionReceiptStore(container:actionContainer).entries.count == 1)
        let reopenedActions = AssistantActions(container:actionContainer)
        do { _ = try await reopenedActions.performTool(draft,human:human,authorization:human,turnID:request,model:runtime,calendar:calendars,reminders:reminders);check(false) } catch { }
        check(runtime.writer.attempts == 1)
        runtime.writer.fail = false
        let successRequest = UUID()
        let output = try await reopenedActions.performTool(draft,human:human,authorization:human,turnID:successRequest,model:runtime,calendar:calendars,reminders:reminders)
        check(output == "Fictional verified action" && runtime.writer.attempts == 2 && runtime.refreshes == 1)
        let duplicate = try await reopenedActions.performTool(draft,human:human,authorization:human,turnID:successRequest,model:runtime,calendar:calendars,reminders:reminders)
        check(duplicate.hasPrefix("Already applied:") && runtime.writer.attempts == 2)
        print("Action receipt checks passed: actual begin failure, no native attempt, later save/reopen, persistent uncertain outcome, completion failure, Undo and corrupt-original preservation.")
    }
}
