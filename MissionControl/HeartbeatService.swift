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
    private(set) var controlsRevision = UUID()
    private(set) var busy = false
    private(set) var status = "Every 30 minutes while 3PO is running."
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
        } catch { readable = false; status = "Saved heartbeat state unavailable; original record retained." }
    }
    private var lastTyping: Date?
    var composerActive: Bool { lastTyping.map { Date.now.timeIntervalSince($0) < 120 } ?? false }
    func userStartedTyping() { lastTyping = .now; cancel() }
    func cancel() { task?.cancel() }
    func check(_ model:DashboardModel,manual:Bool = false) {
        let registration=model.chatGPT.activeID
        guard readable,(manual || enabled),!busy,!registration.isEmpty,!ProcessInfo.processInfo.arguments.contains("--sample") else { return }
        let prior=state.accounts[registration] ?? PAHeartbeatAccount()
        guard manual || PAHeartbeatRules.due(prior,now:.now) else { return }
        // Let foreground work win; this local due check never runs inference.
        guard !model.assistant.busy,!model.chatGPT.busy,!model.projectPlacement.busy,!model.briefings.busy,!model.proactive.busy,!model.emailSummaries.busy,!model.sourceLearning.busy,!model.memoryLearning.busy,!model.lifeOrganisation.busy,!model.writing else { return }
        let controls=controlsRevision, scope=model.proactive.scope(model)
        busy=true; status="Refreshing heartbeat sources…"
        task=Task {
            defer { busy=false }
            var account=prior
            do {
                account.phase=prior.phase == "paused" ? "paused" : "refreshing"
                state.accounts[registration]=account; try save()
                let deadline=Date.now.addingTimeInterval(180)
                while model.mailHealth.loading || model.calendarHealth.loading || model.reminderHealth.loading {
                    try Task.checkCancellation()
                    guard Date.now < deadline else { throw ActionFailure.message("Sources are still busy; heartbeat retained for the next check.") }
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
                guard (manual || enabled),controls == controlsRevision,registration == model.chatGPT.activeID,scope == model.proactive.scope(model) else { throw ActionFailure.message("Heartbeat account or source choices changed; no assessment started.") }
                let pendingMail=model.mailData.accounts.filter { !model.assistant.excludedAccounts.contains($0.id) && (model.mailIndex.monitor($0.id) != nil || model.mailIndex.accountErrors?[$0.id] != nil) }
                account.checked = .now
                if model.mailHealth.error != nil || !pendingMail.isEmpty || model.calendarHealth.error != nil || model.reminderHealth.error != nil {
                    state.accounts[registration]=account; try save()
                    status="Sources partly refreshed; cached data retained. AI heartbeat waits for a complete permitted-source check."
                    return
                }
                let fingerprint=sourceFingerprint(model)
                let assess=PAHeartbeatRules.needsAssessment(account,fingerprint:fingerprint,manual:manual) || (account.phase != "paused" && account.phase != "assessing" && model.emailSummaries.hasPendingIncoming(model))
                guard assess,model.assistant.contextEnabled,model.chatGPT.inferenceVerified,!model.chatGPT.usagePaused,!composerActive else {
                    if !assess { status=account.phase == "paused" ? "Heartbeat assessment paused; Check now resumes it." : "Heartbeat checked; no new source material." }
                    else { status="Sources refreshed; AI assessment waits for enabled context, allowance and an idle composer." }
                    account.phase=account.phase == "paused" ? "paused" : "idle"
                    state.accounts[registration]=account; try save();return
                }
                account.phase="assessing"; state.accounts[registration]=account; try save()
                status="Assessing new permitted material…"
                // Existing classifier is serial, selective and preserves its
                // original monitoring start/decisions; this is not a new backlog.
                model.emailSummaries.process(model,resume:manual,heartbeat:true)
                while model.emailSummaries.busy {
                    try Task.checkCancellation();try await Task.sleep(for:.milliseconds(100))
                }
                try Task.checkCancellation()
                guard (manual || enabled),controls == controlsRevision,registration == model.chatGPT.activeID,scope == model.proactive.scope(model),fingerprint == sourceFingerprint(model) else { throw ActionFailure.message("Sources changed during heartbeat; completed assessments retained, no stale alert started.") }
                if model.emailSummaries.enabled && model.emailSummaries.paused { throw ActionFailure.message("Email assessment is paused. Check now when ready to resume.") }
                model.proactive.check(model,manual:manual,heartbeat:true,heartbeatWhatsAppReady:whatsappReady)
                while model.proactive.busy {
                    try Task.checkCancellation();try await Task.sleep(for:.milliseconds(100))
                }
                try Task.checkCancellation()
                guard registration == model.chatGPT.activeID,controls == controlsRevision else { throw ActionFailure.message("Heartbeat ownership changed; completed source work retained.") }
                if let error=model.proactive.error { throw ActionFailure.message(error) }
                if model.proactive.enabled,model.proactive.state.accounts[registration]?.paused == true { throw ActionFailure.message("Proactive assessment is paused. Check heartbeat now to resume explicitly.") }
                account.phase="idle"; if !wantsWhatsApp || whatsappReady { account.fingerprint=fingerprint }; state.accounts[registration]=account;try save()
                status="Heartbeat checked at " + Date.now.formatted(date:.omitted,time:.shortened) + (wantsWhatsApp && !whatsappReady ? ". WhatsApp unavailable; no WhatsApp material assessed." : ". Only worthwhile updates are delivered.")
                if !model.proactive.enabled { status += " Proactive updates are disabled." }
                else if let p=model.proactive.state.accounts[registration],p.day == BriefingRules.day(.now),p.delivered >= 3 || p.attempts >= 8 { status += " Daily comparison/update limit reached; source checks continue." }
            } catch {
                if account.phase == "assessing" { account.phase="paused"; model.emailSummaries.cancel(); model.proactive.cancel() }
                account.checked = .now; state.accounts[registration]=account;try? save()
                status=error is CancellationError ? "Heartbeat stopped; completed work retained. Check now resumes assessment." : error.localizedDescription
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
        let value=[model.proactive.scope(model),String(whatsappEnabled),String(model.emailSummaries.enabled),model.chatGPT.selectedModel]+mail+wa+events+tasks
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
