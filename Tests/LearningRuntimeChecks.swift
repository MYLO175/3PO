import Foundation
import SwiftData

@MainActor private final class FictionalInference: PAInferenceConnection {
    var activeID = "fixture"
    var selectedModel = "fictional"
    var busy = false
    var usagePaused = false
    var inferenceVerified = true
    var hasSession = true
    var answer = "{\"memories\":[]}"
    var calls = 0
    var onCall: (() -> Void)?
    func streamResponse(input: [[String:String]], instructions: String, model: String?, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> String {
        calls += 1; onCall?(); return answer
    }
    func toolResponse(input: [[String:Any]], instructions: String, tools: [[String:Any]], model: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse { fatalError("Learning cannot execute foreground tools") }
}
@MainActor private final class FictionalAssistant: LearningAssistantReading {
    let connection: any PAInferenceConnection
    let memory: PAMemoryStore
    var busy = false
    var hasDraft = false
    var contextEnabled = true
    var contextRevision = UUID()
    var topics: [AssistantConversation] = []
    var excludedCalendars = Set<String>()
    var excludedLists = Set<String>()
    var excludedAccounts = Set<String>()
    var turns: [MemoryLearningTurn] = []
    var acknowledged = 0
    init(_ connection: any PAInferenceConnection, memory: PAMemoryStore) { self.connection = connection; self.memory = memory }
    func learningTurns() -> [MemoryLearningTurn] { turns }
    func acknowledgeLearned(_ learned: [LearnedMemory]) { acknowledged += learned.count }
}
@MainActor private final class FictionalWhatsApp: WhatsAppLearningReading {
    var messages: [WhatsAppReadMessage] = []
    var chats: [WhatsAppChat] = [.init(id:"chat", name:"Fictional", group:true)]
    var accessValue = WhatsAppAccess(enabled:true, chats:["chat"], learnContext:true)
    var revision = UUID()
    func scope(for registration: String) -> WhatsAppSourceScope { .init(registration:registration, linkedIdentity:"fictional-device", revision:revision) }
    func access(for registration: String) -> WhatsAppAccess { accessValue }
}

@main struct LearningRuntimeChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); count += 1 }
        let suite = "3PO.learning-fixture." + UUID().uuidString
        let settings = UserDefaults(suiteName:suite)!
        defer { settings.removePersistentDomain(forName:suite) }
        let preferencesBeforeConstruction = NSDictionary(dictionary:settings.persistentDomain(forName:suite) ?? [:])
        let container = try ModelContainer(for:CachedDashboard.self, configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let inference = FictionalInference(), memory = PAMemoryStore(container:container, settings:settings)
        let assistant = FictionalAssistant(inference, memory:memory), whatsapp = FictionalWhatsApp()
        let budget = LearningBudget(container:container)
        var now = Date.now, writing = false, activity = LearningActivity(), sourceRevision = 0
        var native: [NativeLearningItem] = []
        let runtime = LearningRuntime(assistant:assistant, inference:inference, learningBudget:budget, whatsapp:whatsapp, now:{now}, activity:{activity}, writing:{writing}, sourceRevision:{sourceRevision}, nativeItems:{kind,_ in kind == .reminder ? native : nil})
        let conversation = MemoryLearningService(container:container, settings:settings)
        let sources = NativeSourceLearningService(container:container)
        let messages = SourceContextLearningService(container:container)
        let organisation = LifeOrganisationService(container:container, settings:settings)
        let maintenance = MemoryMaintenanceService(container:container)
        check(preferencesBeforeConstruction.isEqual(to:settings.persistentDomain(forName:suite) ?? [:]), "Constructing memory and learning services must not persist default controls")
        func wait(_ isBusy: () -> Bool) async {
            for _ in 0..<10_000 { if !isBusy() { return }; await Task.yield() }
            preconditionFailure("A fictional service failed to finish")
        }
        assistant.turns = [.init(id:"intro", text:"I study Materials Engineering", created:now)]
        inference.answer = "{\"memories\":[{\"turnID\":\"intro\",\"text\":\"Studies Materials Engineering\",\"kind\":\"context\",\"evidence\":\"I study Materials Engineering\",\"certainty\":\"stated\",\"durability\":\"stable\"}]}"
        conversation.check(runtime)
        await wait { conversation.busy }
        check(inference.calls == 1 && memory.records.count == 1 && assistant.acknowledged == 1, "Actual conversation learning must persist a supported human fact")
        check(budget.receipts("fixture")[.conversation] == now, "Actual claim must use the supplied clock")
        check(PAMemoryStore(container:container, settings:settings).records.map(\.id) == memory.records.map(\.id), "The learned identity must survive reopen")
        assistant.turns.append(.init(id:"second", text:"My project is about optics", created:now))
        assistant.hasDraft = true; now.addTimeInterval(1800)
        conversation.check(runtime)
        check(inference.calls == 1 && !conversation.busy, "Foreground draft prevents a learning claim")
        assistant.hasDraft = false; activity.otherWorkBusy = true
        conversation.check(runtime)
        check(inference.calls == 1, "Other background work prevents overlap")
        activity.otherWorkBusy = false; inference.answer = "{\"memories\":[]}"
        inference.onCall = { inference.activeID = "changed" }
        conversation.check(runtime)
        await wait { conversation.busy }
        check(inference.calls == 2 && conversation.error != nil && memory.records.count == 1, "Account drift rejects late learning output")
        inference.activeID = "fixture"; inference.onCall = nil; now.addTimeInterval(1800)
        conversation.check(runtime)
        check(inference.calls == 2 && !conversation.busy, "Failed conversation claim remains paused")
        conversation.check(runtime, manual:true)
        await wait { conversation.busy }
        check(inference.calls == 3 && conversation.error == nil, "Human review explicitly resumes one paused pass")

        sources.setEnabled(true, kind:.reminder, model:runtime)
        check(inference.calls == 3, "Opt-in baselines cached content without inference")
        native = [.init(identity:.init(kind:.reminder, accountID:"fixture", containerID:"list", itemID:"item"), revision:"one", label:"Fictional task", text:"Prepare the optics report", date:now, changed:now)]
        inference.answer = "{\"facts\":[]}"
        sources.check(runtime, kind:.reminder)
        await wait { sources.busy }
        check(inference.calls == 4 && sources.error == nil, "Actual native learning consumes one permitted cached delta")
        check(budget.receipts("fixture")[.nativeSources] == now, "Native receipt uses the same shared budget and clock")
        now.addTimeInterval(1800); native[0].revision = "two"; native[0].changed = now
        inference.onCall = { sourceRevision += 1 }
        sources.check(runtime, kind:.reminder)
        await wait { sources.busy }
        check(inference.calls == 5 && sources.error != nil, "Source revision drift rejects native output")
        inference.onCall = nil; now.addTimeInterval(1800)
        sources.check(runtime, kind:.reminder)
        check(inference.calls == 5 && !sources.busy, "Failed native claim is never silently replayed")

        // Use explicit human review for remaining services; automatic daily slots
        // were consumed above and must retain their original shared allowance.
        whatsapp.messages = [.init(id:"message", chat:"chat", sender:"contact", text:"Please prepare the optics report", sentByMe:false, time:now.timeIntervalSince1970 * 1000)]
        messages.check(runtime, manual:true)
        await wait { messages.busy }
        check(inference.calls == 6 && messages.error == nil, "Actual WhatsApp service accepts a selected cached batch through its reader port")
        inference.answer = "{\"entries\":[]}"
        organisation.check(runtime, manual:true)
        await wait { organisation.busy }
        check(inference.calls == 7 && organisation.error == nil, "Actual organisation runs without dashboard or source access")
        inference.answer = "{\"proposals\":[]}"
        maintenance.check(runtime, manual:true)
        await wait { maintenance.busy }
        check(inference.calls == 8 && maintenance.error == nil, "Actual maintenance proposes review without a dashboard")
        check(memory.records.count == 1, "Empty source/organisation/review output cannot invent facts")
        check(budget.receipts("fixture")[.organisation] == nil && budget.receipts("fixture")[.maintenance] == nil && budget.receipts("fixture")[.whatsapp] == nil, "Manual passes cannot advance automatic fairness receipts")
        writing = true; conversation.check(runtime, manual:true)
        check(inference.calls == 8, "Native writing prevents competing learning work")
        writing = false
        assistant.turns.append(.init(id:"third", text:"I value careful preparation", created:now))
        inference.answer = "{\"memories\":[{\"turnID\":\"third\",\"text\":\"Values careful preparation\",\"kind\":\"preference\",\"evidence\":\"I value careful preparation\"}]}"
        inference.onCall = { assistant.busy = true }
        conversation.check(runtime, manual:true)
        await wait { conversation.busy }
        check(inference.calls == 9 && conversation.error != nil && memory.records.count == 1, "A foreground request without a draft still rejects late learning output")
        check(MemoryLearningService(container:container, settings:settings).state.accounts["fixture"]?.paused == true, "Foreground interruption keeps the durable failed claim paused after reopen")
        print("PASS \(count) actual learning-service checks: injected providers/clock, persistence, foreground priority, source/account drift, pauses, explicit recovery; no dashboard, credentials or personal sources.")
    }
}
