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
    func budgetStatus(_ registration:String)->String { "\(PAHeartbeatRules.callCount(state.accounts[registration] ?? .init(),day:BriefingRules.day(.now))) of \(dailyCallLimit) communication-review AI calls today" }
    func claimCall(_ registration:String) throws {
        let day=BriefingRules.day(clock())
        guard busy,registration == capturedRegistration,state.accounts[registration]?.phase == "assessing",day == capturedDay,controlsRevision == capturedControls,task?.isCancelled != true,!composerActive else { throw ActionFailure.message("Background-review account, day, controls or foreground ownership changed before inference.") }
        let prior=state.accounts[registration] ?? .init()
        state.accounts[registration]=try PAHeartbeatRules.claim(prior,day:day,limit:dailyCallLimit)
        do { try save() } catch { state.accounts[registration]=prior;throw error }
    }
    private var capturedRegistration:String?
    private var capturedDay:String?
    private var capturedControls:UUID?
    @ObservationIgnored private let clock:()->Date
    private(set) var controlsRevision = UUID()
    private(set) var busy = false
    private(set) var status = "Sources collect without AI. Background reviews run when due while 3PO is running and the Mac is awake."
    private(set) var state = PAHeartbeatState()
    private var statusRegistration:String?
    func reviewInProgress(_ run:PAReviewRun,registration:String)->Bool {
        busy && capturedRegistration == registration && state.accounts[registration]?.reviews?.last?.id == run.id
    }
    private func recordReview(_ registration:String,run:PAReviewRun) throws {
        let previous=state
        var account=state.accounts[registration] ?? .init(),runs=account.reviews ?? []
        if let i=runs.firstIndex(where:{$0.id == run.id}) {runs[i]=run} else {runs.append(run)}
        account.reviews=Array(runs.suffix(20));state.accounts[registration]=account
        do {try save()} catch {state=previous;throw error}
    }
    func statusFor(_ registration:String)->String {
        if readable,!busy,state.accounts[registration]?.phase == "paused" {
            let guidance="Background review is paused after an interrupted or failed assessment. Sources can still collect. Choose Review changed context now to resume."
            if statusRegistration == registration,!status.contains("Choose Review changed context now"),!status.isEmpty {return status+" "+guidance}
            return guidance
        }
        if readable,!busy,statusRegistration != registration,state.accounts[registration]?.mailLanes?.values.contains(where:{$0.issue != nil}) == true {return "The last review used available sources. Unavailable Mail accounts remain pending; source checks continue independently."}
        if let statusRegistration,statusRegistration != registration {return "Sources collect without AI. This account's review runs when due and idle."}
        return status
    }
    func scheduleStatus(_ model:DashboardModel)->String {
        let account=state.accounts[model.chatGPT.activeID] ?? .init(),now=clock()
        guard readable else {return "Waiting for saved review state"}
        guard enabled else {return "Automatic reviews are off"}
        if busy {return capturedRegistration == model.chatGPT.activeID ? "Review running" : "Waiting for the previous review to stop"}
        if account.phase == "paused" {return "Paused · resume explicitly"}
        if !model.assistant.contextEnabled {return "Waiting for PA context to be enabled"}
        if !model.chatGPT.inferenceVerified {return "Waiting for the subscription connection"}
        if model.chatGPT.usagePaused {return "Waiting for AI usage to resume"}
        let next=PAHeartbeatRules.nextReview(account,now:now,minutes:intervalMinutes,day:BriefingRules.day(now),allowance:dailyCallLimit)
        if next <= now {return composerActive ? "Due · waiting until you stop typing" : workBusy(model) ? "Due · waiting for other work to finish" : "Due · checked on the next idle minute"}
        return (account.retryReason == "allowance" ? "Allowance renews " : account.retryAfter != nil ? "Retry " : "Next review ")+next.formatted(date:Calendar.current.isDate(next,inSameDayAs:now) ? .omitted : .abbreviated,time:.shortened)
    }
    private func workBusy(_ model:DashboardModel)->Bool {
        model.assistant.busy || model.chatGPT.busy || model.projectPlacement.busy || model.briefings.busy || model.proactive.busy || model.emailSummaries.busy || model.sourceLearning.busy || model.nativeSourceLearning.busy || model.memoryMaintenance.busy || model.memoryLearning.busy || model.lifeOrganisation.busy || model.writing
    }
    func mailReviewStatus(_ model:DashboardModel)->String {
        let lanes=state.accounts[model.chatGPT.activeID]?.mailLanes ?? [:]
        return model.mailData.accounts.filter{!model.assistant.excludedAccounts.contains($0.id)}.compactMap{account in
            guard let lane=lanes[account.id] else {return nil}
            if let issue=lane.issue {return account.title+": waiting · "+String(issue.prefix(180))}
            if let assessed=lane.assessed {return account.title+": reviewed "+assessed.formatted(date:.abbreviated,time:.shortened)+(lane.pending ? " · more work pending" : "")}
            return account.title+(lane.pending ? ": waiting for review" : ": no review work waiting")
        }.joined(separator:"\n")
    }
    private let container: ModelContainer?
    private var task: Task<Void,Never>?
    private var readable = true
    init(container:ModelContainer?,clock:@escaping ()->Date = {Date.now}) {
        self.container = container
        self.clock=clock
        do {
            if let record=try container?.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first(where:{$0.key == "paHeartbeat"}) {
                state = try JSONDecoder().decode(PAHeartbeatState.self,from:record.data)
                state.accounts = state.accounts.mapValues{PAHeartbeatRules.recovered($0,now:clock())}
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
        guard manual || PAHeartbeatRules.due(prior,now:.now,minutes:intervalMinutes,day:BriefingRules.day(.now),allowance:dailyCallLimit) else { return }
        // Collection has its own no-AI polling. A due review must not consume its
        // interval while foreground work or disabled inference prevents assessment.
        guard manual || (!composerActive && model.assistant.contextEnabled && model.chatGPT.inferenceVerified && !model.chatGPT.usagePaused) else {return}
        // Let foreground work win; this local due check never runs inference.
        guard !workBusy(model) else { return }
        let controls=controlsRevision, scope=model.proactive.scope(model),day=BriefingRules.day(.now)
        busy=true;capturedRegistration=registration;capturedDay=day;capturedControls=controls;statusRegistration=registration;status="Collecting sources for background review…"
        task=Task {
            let began=Date.now,runID=UUID().uuidString,callsBefore=PAHeartbeatRules.callCount(prior,day:day)
            let itemsBefore=model.proactive.state.records.filter{$0.registration == registration}.count
            let draftsBefore=model.emailSummaries.records.filter{$0.registration == registration && $0.replyDraft != nil}.count
            let handledBefore=model.emailSummaries.records.filter{$0.registration == registration && $0.handling != nil}.count
            defer {
                let latest=state.accounts[registration] ?? .init()
                let ready=latest.mailLanes?.values.filter{$0.issue == nil && ($0.checked ?? .distantPast) >= began}.count ?? 0,waiting=latest.mailLanes?.values.filter{$0.issue != nil && ($0.checked ?? .distantPast) >= began}.count ?? 0
                let phase=latest.phase == "paused" ? "paused" : latest.pending == true ? "waiting" : latest.phase
                let run=PAReviewRun(id:runID,started:began,finished:.now,manual:manual,phase:phase,detail:String(status.prefix(600)),calls:max(0,PAHeartbeatRules.callCount(latest,day:day)-callsBefore),checkedAccounts:ready,waitingAccounts:waiting,preparedItems:max(0,model.proactive.state.records.filter{$0.registration == registration}.count-itemsBefore),drafts:max(0,model.emailSummaries.records.filter{$0.registration == registration && $0.replyDraft != nil}.count-draftsBefore),handled:max(0,model.emailSummaries.records.filter{$0.registration == registration && $0.handling != nil}.count-handledBefore))
                do {try recordReview(registration,run:run)} catch {status="Review finished, but its activity record could not be saved. Existing records are retained."}
                busy=false;capturedRegistration=nil;capturedDay=nil;capturedControls=nil
            }
            var account=PAHeartbeatRules.clearWait(prior)
            do {
                account.phase=prior.phase == "paused" ? "paused" : "refreshing"
                state.accounts[registration]=account; try save()
                try recordReview(registration,run:.init(id:runID,started:began,manual:manual,phase:account.phase,detail:"Collecting permitted sources; no AI request yet."))
                account=state.accounts[registration] ?? account
                let collectionStart=Date.now,deadline=Date.now.addingTimeInterval(180)
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
                    let pending=model.mailData.accounts.filter { account in
                        guard !model.assistant.excludedAccounts.contains(account.id),model.mailIndex.available(account.id) else {return false}
                        let monitor=model.mailIndex.monitors?.first{$0.accountID == account.id}
                        return monitor?.complete != true || (monitor?.end ?? .distantPast) < collectionStart.addingTimeInterval(-30)
                    }
                    if pending.isEmpty { break }
                    await model.refreshMail()
                }
                let access=model.whatsapp.access(for:registration)
                let wantsWhatsApp=whatsappEnabled && access.enabled && !access.chats.isEmpty
                let whatsappReady=wantsWhatsApp ? await model.whatsapp.refreshSnapshot() : false
                try Task.checkCancellation()
                guard (manual || enabled),controls == controlsRevision,registration == model.chatGPT.activeID,scope == model.proactive.scope(model),day == BriefingRules.day(.now) else { throw ActionFailure.message("Background-review account, day or source choices changed; no assessment started.") }
                var mailReview=MailReviewScope.capture(index:model.mailIndex,snapshot:model.mailData,excluded:model.assistant.excludedAccounts,since:collectionStart)
                var nativeReady=model.calendarHealth.error == nil && model.reminderHealth.error == nil && model.paOrientationHealth.error == nil
                let enabledMail=Set(model.mailData.accounts.filter{!model.assistant.excludedAccounts.contains($0.id)}.map(\.id))
                account.checked = .now
                account=PAHeartbeatRules.collectingMail(account,enabled:enabledMail,ready:mailReview.accountIDs,issues:mailReview.issues,now:.now)
                account.pending=mailReview.pending || !nativeReady || (wantsWhatsApp && !whatsappReady) || account.pending == true
                state.accounts[registration]=account;try save()
                let fingerprint=sourceFingerprint(model,mailAccounts:mailReview.accountIDs,whatsappReady:whatsappReady)
                let nativeFingerprint=sourceFingerprint(model,mailAccounts:[],whatsappReady:whatsappReady)
                let mailFingerprints=Dictionary(uniqueKeysWithValues:mailReview.accountIDs.map{($0,mailFingerprint(model,account:$0))})
                let pendingSources=model.emailSummaries.hasPendingIncoming(model,mailReview:mailReview) || (nativeReady && model.proactive.enabled && model.proactive.hasPendingSources(model,mailReview:mailReview,whatsappReady:whatsappReady))
                var availableAccount=account;availableAccount.pending=pendingSources
                let assess=PAHeartbeatRules.needsAssessment(availableAccount,fingerprint:fingerprint,manual:manual,pendingSources:pendingSources)
                guard assess,model.assistant.contextEnabled,model.chatGPT.inferenceVerified,!model.chatGPT.usagePaused,!composerActive else {
                    if !assess { status=account.phase == "paused" ? "Background review paused; Review changed context now resumes it." : "Background review checked; no new source material." }
                    else { status="Sources refreshed; AI assessment waits for enabled context, allowance and an idle composer." }
                    account = assess ? PAHeartbeatRules.deferred(account,now:.now,reason:.foreground) : PAHeartbeatRules.quiet(account,fingerprint:fingerprint,ready:mailReview.accountIDs,pending:mailReview.pending || !nativeReady || (wantsWhatsApp && !whatsappReady))
                    if mailReview.pending || !nativeReady || (wantsWhatsApp && !whatsappReady) {status += " " + waitingStatus(model,mailReview:mailReview,nativeReady:nativeReady,whatsappWaiting:wantsWhatsApp && !whatsappReady)}
                    state.accounts[registration]=account; try save();return
                }
                guard !workBusy(model),!composerActive else { account=PAHeartbeatRules.deferred(account,now:.now,reason:.foreground);state.accounts[registration]=account;try save();status="Sources refreshed; pending AI assessment waits for foreground work.";return }
                guard PAHeartbeatRules.callCount(account,day:BriefingRules.day(.now)) < dailyCallLimit else { throw HeartbeatBudgetExhausted() }
                account.phase="assessing"; state.accounts[registration]=account; try save()
                status="Assessing new permitted material…"
                // Existing classifier is serial, selective and preserves its
                // original monitoring start/decisions; this is not a new backlog.
                model.emailSummaries.process(model,resume:manual,heartbeat:true,mailReview:mailReview)
                while model.emailSummaries.busy {
                    try Task.checkCancellation();try await Task.sleep(for:.milliseconds(100))
                }
                try Task.checkCancellation()
                mailReview=mailReview.available(index:model.mailIndex,snapshot:model.mailData,excluded:model.assistant.excludedAccounts)
                account=state.accounts[registration] ?? account
                account=PAHeartbeatRules.collectingMail(account,enabled:enabledMail,ready:mailReview.accountIDs,issues:mailReview.issues,now:.now)
                state.accounts[registration]=account;try save()
                guard (manual || enabled),controls == controlsRevision,registration == model.chatGPT.activeID,scope == model.proactive.scope(model),day == BriefingRules.day(.now),nativeFingerprint == sourceFingerprint(model,mailAccounts:[],whatsappReady:whatsappReady),mailReview.accountIDs.allSatisfy({mailFingerprints[$0] == mailFingerprint(model,account:$0)}) else { throw ActionFailure.message("Participating sources changed during background review; completed assessments retained, no stale alert started.") }
                if PAHeartbeatRules.callCount(state.accounts[registration] ?? account,day:BriefingRules.day(.now)) >= dailyCallLimit { throw HeartbeatBudgetExhausted() }
                if model.emailSummaries.enabled && model.emailSummaries.paused { throw ActionFailure.message("Email assessment is paused. Check now when ready to resume.") }
                if nativeReady {model.proactive.check(model,manual:manual,heartbeat:true,heartbeatWhatsAppReady:whatsappReady,mailReview:mailReview)}
                while model.proactive.busy {
                    try Task.checkCancellation();try await Task.sleep(for:.milliseconds(100))
                }
                if nativeReady,model.proactive.sourceReadError != nil {nativeReady=false}
                try Task.checkCancellation()
                guard registration == model.chatGPT.activeID,controls == controlsRevision else { throw ActionFailure.message("Background-review ownership changed; completed source work retained.") }
                if nativeReady,let error=model.proactive.error { throw ActionFailure.message(error) }
                if nativeReady,model.proactive.enabled,model.proactive.state.accounts[registration]?.paused == true { throw ActionFailure.message("Proactive assessment is paused. Review changed context now to resume explicitly.") }
                let pendingAccounts=Set(mailReview.accountIDs.filter{id in
                    var one=mailReview;one.windows=one.windows.filter{$0.key == id}
                    return model.emailSummaries.hasPendingIncoming(model,mailReview:one) || !nativeReady || (model.proactive.enabled && model.proactive.hasPendingSources(model,mailReview:mailReview,whatsappReady:whatsappReady,mailAccountID:id))
                })
                account=PAHeartbeatRules.clearWait(state.accounts[registration] ?? account);account.phase="idle";account.assessed = .now
                account=PAHeartbeatRules.completedMail(account,fingerprints:mailFingerprints.filter{mailReview.accountIDs.contains($0.key)},pending:pendingAccounts,now:.now)
                let p=model.proactive.state.accounts[registration]
                account.pending=mailReview.pending || !nativeReady || (wantsWhatsApp && !whatsappReady) || !pendingAccounts.isEmpty || (model.proactive.enabled && (model.proactive.hasPendingSources(model,mailReview:mailReview,whatsappReady:whatsappReady) || (p?.day == BriefingRules.day(.now) && (p?.attempts ?? 0) >= 96)))
                account.fingerprint=sourceFingerprint(model,mailAccounts:mailReview.accountIDs,whatsappReady:whatsappReady);state.accounts[registration]=account;try save()
                status="Background review checked available sources at " + Date.now.formatted(date:.omitted,time:.shortened) + ". Useful proposals are saved in Review inbox. " + waitingStatus(model,mailReview:mailReview,nativeReady:nativeReady,whatsappWaiting:wantsWhatsApp && !whatsappReady)
                if !model.proactive.enabled { status += " Review proposals are disabled." }
                else if let p=model.proactive.state.accounts[registration],p.day == BriefingRules.day(.now),p.attempts >= 96 { status += " Daily comparison allowance reached; source checks continue." }
            } catch is HeartbeatBudgetExhausted {
                account=PAHeartbeatRules.deferred(state.accounts[registration] ?? account,now:.now,reason:.allowance);account.checked = .now;state.accounts[registration]=account;try? save();status=HeartbeatBudgetExhausted().localizedDescription
            } catch {
                account=PAHeartbeatRules.interrupted(state.accounts[registration] ?? account,now:.now,foreground:composerActive)
                if account.phase == "paused" { model.emailSummaries.cancel(); model.proactive.cancel() }
                account.checked = .now; state.accounts[registration]=account;try? save()
                status=error is CancellationError ? (account.phase == "paused" ? "Background review stopped; completed work retained. Review changed context now resumes assessment." : "Source check stopped before AI assessment; pending work will retry when idle.") : error.localizedDescription
            }
        }
    }
    private func waitingStatus(_ model:DashboardModel,mailReview:MailReviewScope,nativeReady:Bool,whatsappWaiting:Bool)->String {
        var issues=mailReview.issues.keys.sorted().map{id in (model.mailData.accounts.first{$0.id == id}?.title ?? "Mail account")+": "+(mailReview.issues[id] ?? "waiting")}
        if mailReview.discoveryFailed,issues.isEmpty {issues.append("Mail account list unavailable")}
        if !nativeReady {issues.append("Calendar/Reminders comparison pending; email assessment can continue")}
        if whatsappWaiting {issues.append("WhatsApp unavailable")}
        return issues.isEmpty ? "" : "Waiting: "+issues.joined(separator:" · ")+". Cached data and pending work are retained."
    }
    private func mailFingerprint(_ model:DashboardModel,account:String)->String {
        let values=model.mailData.messages.filter{$0.accountID == account}.map{$0.id+":"+EmailSummary.fingerprint($0)+":"+String($0.replied)}.sorted()
        return SHA256.hash(data:Data(values.joined(separator:"\n").utf8)).map{String(format:"%02x",$0)}.joined()
    }
    private func sourceFingerprint(_ model:DashboardModel,mailAccounts:Set<String>,whatsappReady:Bool) -> String {
        let a=model.assistant,registration=model.chatGPT.activeID
        let mail=mailAccounts.sorted().map{$0+":"+mailFingerprint(model,account:$0)}
        let access=model.whatsapp.access(for:registration)
        let wa=whatsappReady && whatsappEnabled && access.enabled && model.whatsapp.connected ? model.whatsapp.messages.filter{access.chats.contains($0.chat)}.map{SourceContextRules.revision($0)}.sorted() : []
        let calendar=model.paOrientation?.calendar ?? model.calendarData
        let events=calendar.events.filter{!a.excludedCalendars.contains($0.calendarID)}.map{$0.id+":"+$0.title+":"+$0.start.ISO8601Format()+":"+$0.end.ISO8601Format()}.sorted()
        let tasks=model.reminderData.reminders.filter{!a.excludedLists.contains($0.listID)}.map{$0.id+":"+$0.title+":"+($0.due?.ISO8601Format() ?? "")}.sorted()
        let life=a.projects.items(registration).map{$0.id.uuidString+":"+$0.revision.uuidString}.sorted()
        let value=[model.proactive.scope(model),String(whatsappEnabled),String(model.emailSummaries.enabled),String(model.proactive.enabled),model.chatGPT.selectedModel,EmailNativeEvidence.hash(model.completedReminders),EmailNativeEvidence.hash(model.emailSummaries.dismissalContext(model))]+mail+wa+events+tasks+life
        return SHA256.hash(data:Data(value.joined(separator:"\n").utf8)).map{String(format:"%02x",$0)}.joined()
    }
    private func save() throws {
        guard let container else { throw SummaryFailure.invalid }
        let context=container.mainContext,data=try JSONEncoder().encode(state)
        if let record=try context.fetch(FetchDescriptor<CachedDashboard>()).first(where:{$0.key == "paHeartbeat"}) { record.data=data;record.updated = .now }
        else { context.insert(CachedDashboard(key:"paHeartbeat",data:data)) }
        do {try context.save()} catch {context.rollback();throw error}
    }
    #if DEBUG
    /// Exercises the actual ownership guard and cache recovery without starting
    /// sources, inference, notifications or native changes. All receipts are fictional.
    static func evaluateScheduling() async throws->[String:Any] {
        guard ProcessInfo.processInfo.arguments.contains("--validate-review-inbox"),ProcessInfo.processInfo.arguments.contains("--scheduler-only") else {throw SummaryFailure.invalid}
        let preferences=UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        let store=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        var now=ISO8601DateFormatter().date(from:"2026-10-07T12:00:00Z")!
        let service=HeartbeatService(container:store,clock:{now}),registration="fictional-review-owner"
        let day=BriefingRules.day(now),run=PAReviewRun(id:"fictional-run",started:now,manual:false,phase:"assessing",detail:"Fictional review; no request is sent")
        var checks:[String:Bool]=[:]
        service.busy=true;service.capturedRegistration=registration;service.capturedDay=day;service.capturedControls=service.controlsRevision
        service.state.accounts[registration] = .init(checked:now,phase:"assessing",budgetDay:day,calls:0,pending:true,reviews:[run])
        try service.save();try service.claimCall(registration)
        checks["owned current-day call receipt persists before a request"] = service.state.accounts[registration]?.calls == 1
        func refused(_ owner:String=registration)->Bool {
            let before=service.state.accounts[registration]?.calls
            do {try service.claimCall(owner);return false} catch {return service.state.accounts[registration]?.calls == before}
        }
        checks["wrong account cannot claim a request"] = refused("another-fictional-owner")
        service.capturedControls=UUID();checks["changed controls cannot claim a late request"] = refused();service.capturedControls=service.controlsRevision
        let stopped=Task<Void,Never>{};stopped.cancel();service.task=stopped
        checks["cancelled parent cannot claim a late child request"] = refused();service.task=nil
        service.lastTyping=Date.now;checks["foreground typing blocks a late request"] = refused();service.lastTyping=nil
        now=now.addingTimeInterval(86400);checks["midnight cannot charge a captured job to a new day"] = refused();now=now.addingTimeInterval(-86400)
        service.busy=false;checks["finished job cannot claim another request"] = refused()
        let restored=HeartbeatService(container:store,clock:{now})
        checks["actual cache recovery pauses assessing work"] = restored.state.accounts[registration]?.phase == "paused"
        checks["actual cache recovery preserves calls and review identity"] = restored.state.accounts[registration]?.calls == 1 && restored.state.accounts[registration]?.reviews?.first?.id == run.id
        checks["unfinished restored run is not labelled running"] = !restored.reviewInProgress(run,registration:registration)
        service.busy=true;checks["only captured running account owns its activity"] = service.reviewInProgress(run,registration:registration) && !service.reviewInProgress(run,registration:"other")
        service.state.accounts[registration]!.calls=service.dailyCallLimit
        try service.save()
        checks["actual claim rejects an exhausted daily allowance"] = refused()
        var account=PAHeartbeatRules.interrupted(service.state.accounts[registration]!,now:now,foreground:true)
        checks["typing does not silently resume committed assessment"] = account.phase == "paused" && account.retryAfter == nil
        account.phase="refreshing";account=PAHeartbeatRules.interrupted(account,now:now,foreground:true)
        service.state.accounts[registration]=account;try service.save()
        let idle=HeartbeatService(container:store,clock:{now})
        checks["idle retry survives actual cache reopening"] = idle.state.accounts[registration]?.retryAfter == now.addingTimeInterval(60) && idle.state.accounts[registration]?.phase == "idle"
        account.phase="refreshing";service.state.accounts[registration]=account;try service.save()
        let collection=HeartbeatService(container:store,clock:{now})
        checks["crashed source collection recovers without a false AI pause"] = collection.state.accounts[registration]?.phase == "idle" && collection.state.accounts[registration]?.retryReason == "sources"
        checks["recovered collection retains consumed allowance"] = collection.state.accounts[registration]?.calls == service.dailyCallLimit
        account=PAHeartbeatRules.quiet(account,fingerprint:"fictional-quiet",ready:[],pending:false)
        service.state.accounts[registration]=account;try service.save()
        let quiet=HeartbeatService(container:store,clock:{now})
        checks["quiet completed check clears stale pending state in cache"] = quiet.state.accounts[registration]?.pending == false && quiet.state.accounts[registration]?.retryAfter == nil
        service.statusRegistration=registration;service.status="Fictional previous owner's review detail"
        checks["status from another account is not displayed"] = !service.statusFor("other-fictional-owner").contains("previous owner's")
        let badStore=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true)),badData=Data("not a heartbeat record".utf8)
        badStore.mainContext.insert(CachedDashboard(key:"paHeartbeat",data:badData));try badStore.mainContext.save()
        let unreadable=HeartbeatService(container:badStore,clock:{now})
        checks["unreadable review state blocks scheduling"] = !unreadable.readable && unreadable.statusFor(registration).contains("unavailable")
        checks["unreadable original cache is preserved"] = try badStore.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first?.data == badData
        checks["real settings remain unchanged"] = preferences.isEqual(to:UserDefaults.standard.dictionaryRepresentation())
        return ["checks":checks,"passed":checks.values.filter{$0}.count,"total":checks.count,"storage":"Fictional in-memory SwiftData; actual HeartbeatService guard and recovery","AIRequests":0,"nativeChanges":0]
    }
    #endif
}
