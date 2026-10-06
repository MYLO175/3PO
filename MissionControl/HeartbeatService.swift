import Foundation
import CryptoKit
import Observation
import SwiftData

@MainActor @Observable final class HeartbeatService {
    var enabled = UserDefaults.standard.object(forKey:"paHeartbeatEnabled") == nil || UserDefaults.standard.bool(forKey:"paHeartbeatEnabled") {
        didSet { UserDefaults.standard.set(enabled,forKey:"paHeartbeatEnabled"); controlsRevision = UUID(); if !enabled { cancel() } }
    }
    var notificationsEnabled = UserDefaults.standard.object(forKey:"paHeartbeatNotifications") == nil || UserDefaults.standard.bool(forKey:"paHeartbeatNotifications") {
        didSet { UserDefaults.standard.set(notificationsEnabled,forKey:"paHeartbeatNotifications"); controlsRevision = UUID() }
    }
    var whatsappEnabled = UserDefaults.standard.object(forKey:"paHeartbeatWhatsApp") == nil || UserDefaults.standard.bool(forKey:"paHeartbeatWhatsApp") {
        didSet { UserDefaults.standard.set(whatsappEnabled,forKey:"paHeartbeatWhatsApp"); controlsRevision = UUID(); cancel() }
    }
    var intervalMinutes=UserDefaults.standard.object(forKey:"paHeartbeatMinutes") as? Int ?? PAHeartbeatRules.defaultMinutes {
        didSet { if ![15,30,60,120].contains(intervalMinutes) { intervalMinutes=60 };UserDefaults.standard.set(intervalMinutes,forKey:"paHeartbeatMinutes");controlsRevision=UUID();cancel() }
    }
    var dailyCallLimit=UserDefaults.standard.object(forKey:"paHeartbeatCallLimit") as? Int ?? 64 {
        didSet { dailyCallLimit=min(96,max(8,dailyCallLimit));UserDefaults.standard.set(dailyCallLimit,forKey:"paHeartbeatCallLimit");controlsRevision=UUID();cancel() }
    }
    var dailyUpdateLimit=UserDefaults.standard.object(forKey:"paHeartbeatUpdateLimit") as? Int ?? 3 {
        didSet { dailyUpdateLimit=min(10,max(1,dailyUpdateLimit));UserDefaults.standard.set(dailyUpdateLimit,forKey:"paHeartbeatUpdateLimit");controlsRevision=UUID();cancel() }
    }
    func budgetStatus(_ registration:String)->String { "\(PAHeartbeatRules.callCount(state.accounts[registration] ?? .init(),day:BriefingRules.day(.now))) of \(dailyCallLimit) communication-review AI calls today" }
    func claimCall(_ registration:String) throws {
        guard busy,registration == capturedRegistration,state.accounts[registration]?.phase == "assessing" else { throw ActionFailure.message("Background-review ownership changed before inference.") }
        let prior=state.accounts[registration] ?? .init()
        state.accounts[registration]=try PAHeartbeatRules.claim(prior,day:BriefingRules.day(.now),limit:dailyCallLimit)
        do { try save() } catch { state.accounts[registration]=prior;throw error }
    }
    private var capturedRegistration:String?
    private(set) var controlsRevision = UUID()
    private(set) var busy = false
    private(set) var status = "Sources collect without AI. Background reviews run when due while 3PO is running and the Mac is awake."
    private(set) var state = PAHeartbeatState()
    private let container: ModelContainer?
    private var task: Task<Void,Never>?
    private var readable = true
    init(container:ModelContainer?) {
        self.container = container
        do {
            if let record=try container?.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first(where:{$0.key == "paHeartbeat"}) {
                state = try JSONDecoder().decode(PAHeartbeatState.self,from:record.data)
                state.accounts = state.accounts.mapValues(PAHeartbeatRules.recovered)
            }
        } catch { readable = false; status = "Saved background-review state unavailable; original record retained." }
    }
    private var lastTyping: Date?
    var composerActive: Bool { lastTyping.map { Date.now.timeIntervalSince($0) < 120 } ?? false }
    func userStartedTyping() { lastTyping = .now; cancel() }
    func cancel() { task?.cancel() }
    func check(_ model:DashboardModel,manual:Bool = false) {
        let registration=model.chatGPT.activeID
        guard readable,(manual || enabled),!busy,!registration.isEmpty,!ProcessInfo.processInfo.arguments.contains("--sample") else { return }
        let prior=state.accounts[registration] ?? PAHeartbeatAccount()
        guard manual || PAHeartbeatRules.due(prior,now:.now,minutes:intervalMinutes) else { return }
        // Let foreground work win; this local due check never runs inference.
        guard !model.assistant.busy,!model.chatGPT.busy,!model.projectPlacement.busy,!model.briefings.busy,!model.proactive.busy,!model.emailSummaries.busy,!model.sourceLearning.busy,!model.memoryLearning.busy,!model.lifeOrganisation.busy,!model.writing else { return }
        let controls=controlsRevision, scope=model.proactive.scope(model)
        busy=true;capturedRegistration=registration; status="Collecting sources for background review…"
        task=Task {
            defer { busy=false;capturedRegistration=nil }
            var account=prior
            do {
                account.phase=prior.phase == "paused" ? "paused" : "refreshing"
                state.accounts[registration]=account; try save()
                let deadline=Date.now.addingTimeInterval(180)
                while model.mailHealth.loading || model.calendarHealth.loading || model.reminderHealth.loading {
                    try Task.checkCancellation()
                    guard Date.now < deadline else { throw ActionFailure.message("Sources are still busy; background review retained for the next check.") }
                    try await Task.sleep(for:.milliseconds(100))
                }
                await model.refreshCalendar(); await model.refreshReminders(); await model.refreshPAOrientation()
                model.weather.startRefresh()
                if manual { model.mailIndex.resume() }
                await model.refreshMail()
                // Finish a bounded arrival burst before assessment, with no month
                // rebuild. Completed accounts do not repeat their fresh range.
                for _ in 0..<8 {
                    try Task.checkCancellation()
                    guard Date.now < deadline else { break }
                    let pending=model.mailData.accounts.filter { !model.assistant.excludedAccounts.contains($0.id) && model.mailIndex.monitor($0.id) != nil && model.mailIndex.available($0.id) }
                    if pending.isEmpty { break }
                    await model.refreshMail()
                }
                let access=model.whatsapp.access(for:registration)
                let wantsWhatsApp=whatsappEnabled && access.enabled && !access.chats.isEmpty
                let whatsappReady=wantsWhatsApp ? await model.whatsapp.refreshSnapshot() : false
                try Task.checkCancellation()
                guard (manual || enabled),controls == controlsRevision,registration == model.chatGPT.activeID,scope == model.proactive.scope(model) else { throw ActionFailure.message("Background-review account or source choices changed; no assessment started.") }
                let pendingMail=model.mailData.accounts.filter { !model.assistant.excludedAccounts.contains($0.id) && (model.mailIndex.monitor($0.id) != nil || model.mailIndex.accountErrors?[$0.id] != nil) }
                account.checked = .now
                if model.mailHealth.error != nil || !pendingMail.isEmpty || model.calendarHealth.error != nil || model.reminderHealth.error != nil {
                    state.accounts[registration]=account; try save()
                    status="Sources partly refreshed; cached data retained. AI review waits for a complete permitted-source check."
                    return
                }
                let fingerprint=sourceFingerprint(model)
                let assess=PAHeartbeatRules.needsAssessment(account,fingerprint:fingerprint,manual:manual) || (account.phase != "paused" && account.phase != "assessing" && model.emailSummaries.hasPendingIncoming(model))
                guard assess,model.assistant.contextEnabled,model.chatGPT.inferenceVerified,!model.chatGPT.usagePaused,!composerActive else {
                    if !assess { status=account.phase == "paused" ? "Background review paused; Review changed context now resumes it." : "Background review checked; no new source material." }
                    else { status="Sources refreshed; AI assessment waits for enabled context, allowance and an idle composer." }
                    account.phase=account.phase == "paused" ? "paused" : "idle"
                    state.accounts[registration]=account; try save();return
                }
                guard !model.assistant.busy,!model.projectPlacement.busy,!model.briefings.busy,!model.chatGPT.busy,!model.memoryLearning.busy,!model.sourceLearning.busy,!model.lifeOrganisation.busy,!model.proactive.busy,!model.emailSummaries.busy,!model.writing,!composerActive else { account.phase="idle";state.accounts[registration]=account;try save();status="Sources refreshed; pending AI assessment waits for foreground work.";return }
                guard PAHeartbeatRules.callCount(account,day:BriefingRules.day(.now)) < dailyCallLimit else { throw HeartbeatBudgetExhausted() }
                account.phase="assessing"; state.accounts[registration]=account; try save()
                status="Assessing new permitted material…"
                // Existing classifier is serial, selective and preserves its
                // original monitoring start/decisions; this is not a new backlog.
                model.emailSummaries.process(model,resume:manual,heartbeat:true)
                while model.emailSummaries.busy {
                    try Task.checkCancellation();try await Task.sleep(for:.milliseconds(100))
                }
                try Task.checkCancellation()
                guard (manual || enabled),controls == controlsRevision,registration == model.chatGPT.activeID,scope == model.proactive.scope(model),fingerprint == sourceFingerprint(model) else { throw ActionFailure.message("Sources changed during background review; completed assessments retained, no stale alert started.") }
                if PAHeartbeatRules.callCount(state.accounts[registration] ?? account,day:BriefingRules.day(.now)) >= dailyCallLimit { throw HeartbeatBudgetExhausted() }
                if model.emailSummaries.enabled && model.emailSummaries.paused { throw ActionFailure.message("Email assessment is paused. Check now when ready to resume.") }
                model.proactive.check(model,manual:manual,heartbeat:true,heartbeatWhatsAppReady:whatsappReady)
                while model.proactive.busy {
                    try Task.checkCancellation();try await Task.sleep(for:.milliseconds(100))
                }
                try Task.checkCancellation()
                guard registration == model.chatGPT.activeID,controls == controlsRevision else { throw ActionFailure.message("Background-review ownership changed; completed source work retained.") }
                if let error=model.proactive.error { throw ActionFailure.message(error) }
                if model.proactive.enabled,model.proactive.state.accounts[registration]?.paused == true { throw ActionFailure.message("Proactive assessment is paused. Review changed context now to resume explicitly.") }
                account=state.accounts[registration] ?? account;account.phase="idle";account.assessed = .now;let p=model.proactive.state.accounts[registration];account.pending=model.proactive.enabled && p?.day == BriefingRules.day(.now) && ((p?.delivered ?? 0) >= dailyUpdateLimit || (p?.attempts ?? 0) >= 96); if !wantsWhatsApp || whatsappReady { account.fingerprint=fingerprint }; state.accounts[registration]=account;try save()
                status="Background review checked at " + Date.now.formatted(date:.omitted,time:.shortened) + (wantsWhatsApp && !whatsappReady ? ". WhatsApp unavailable; no WhatsApp material assessed." : ". Only worthwhile updates are delivered.")
                if !model.proactive.enabled { status += " Proactive updates are disabled." }
                else if let p=model.proactive.state.accounts[registration],p.day == BriefingRules.day(.now),p.delivered >= dailyUpdateLimit || p.attempts >= 96 { status += " Daily comparison/update limit reached; source checks continue." }
            } catch is HeartbeatBudgetExhausted {
                account=state.accounts[registration] ?? account;account.phase="idle";account.pending=true;account.checked = .now;state.accounts[registration]=account;try? save();status=HeartbeatBudgetExhausted().localizedDescription
            } catch {
                let latest=state.accounts[registration] ?? account;account.budgetDay=latest.budgetDay;account.calls=latest.calls
                if account.phase == "assessing" { account.phase="paused"; model.emailSummaries.cancel(); model.proactive.cancel() }
                account.checked = .now; state.accounts[registration]=account;try? save()
                status=error is CancellationError ? "Background review stopped; completed work retained. Review changed context now resumes assessment." : error.localizedDescription
            }
        }
    }
    private func sourceFingerprint(_ model:DashboardModel) -> String {
        let a=model.assistant,registration=model.chatGPT.activeID
        let mail=model.mailData.messages.filter{!a.excludedAccounts.contains($0.accountID)}.map { $0.id+":"+EmailSummary.fingerprint($0)+":"+String($0.replied) }.sorted()
        let access=model.whatsapp.access(for:registration)
        let wa=whatsappEnabled && access.enabled && model.whatsapp.connected ? model.whatsapp.messages.filter{access.chats.contains($0.chat)}.map{SourceContextRules.revision($0)}.sorted() : []
        let calendar=model.paOrientation?.calendar ?? model.calendarData
        let events=calendar.events.filter{!a.excludedCalendars.contains($0.calendarID)}.map{$0.id+":"+$0.title+":"+$0.start.ISO8601Format()+":"+$0.end.ISO8601Format()}.sorted()
        let tasks=model.reminderData.reminders.filter{!a.excludedLists.contains($0.listID)}.map{$0.id+":"+$0.title+":"+($0.due?.ISO8601Format() ?? "")}.sorted()
        let life=a.projects.items(registration).map{$0.id.uuidString+":"+$0.revision.uuidString}.sorted()
        let value=[model.proactive.scope(model),String(whatsappEnabled),String(model.emailSummaries.enabled),String(model.proactive.enabled),model.chatGPT.selectedModel]+mail+wa+events+tasks+life
        return SHA256.hash(data:Data(value.joined(separator:"\n").utf8)).map{String(format:"%02x",$0)}.joined()
    }
    private func save() throws {
        guard let container else { throw SummaryFailure.invalid }
        let context=container.mainContext,data=try JSONEncoder().encode(state)
        if let record=try context.fetch(FetchDescriptor<CachedDashboard>()).first(where:{$0.key == "paHeartbeat"}) { record.data=data;record.updated = .now }
        else { context.insert(CachedDashboard(key:"paHeartbeat",data:data)) }
        do {try context.save()} catch {context.rollback();throw error}
    }
}
