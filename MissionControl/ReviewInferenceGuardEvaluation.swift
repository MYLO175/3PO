#if DEBUG
import Foundation

@MainActor private final class ReviewGuardNativeFixture:NativeSourceReading {
    var calendarValue:CalendarSnapshot
    var remindersValue:ReminderSnapshot
    var completed:[CompletedReminder]
    var calendarReads=0
    var reminderReads=0
    var onValidationRead:(()->Void)?
    init(now:Date) {
        let source=SourceOption(id:"fictional-calendar",title:"Fictional",account:"Fixture",writable:true)
        let event=AgendaEvent(id:"fictional-event@1",calendarID:source.id,title:"Orion prototype review",start:now,end:now.addingTimeInterval(3600),allDay:false,location:"Fictional lab",sourceLabel:source.label,modified:now)
        let task=TaskItem(id:"fictional-reminder",listID:"fictional-list",title:"Prepare Orion prototype",due:now,hasTime:true,sourceLabel:"Fictional list",writable:true,recurring:false,modified:now)
        calendarValue = .init(sources:[source],events:[event]);remindersValue = .init(sources:[],reminders:[task]);completed=[.init(item:task,completedAt:now)]
    }
    func calendar(from:Date,to:Date)async throws->CalendarSnapshot {calendarReads += 1;if calendarReads > 1 {onValidationRead?()};return calendarValue}
    func reminders()async throws->ReminderSnapshot {reminderReads += 1;return remindersValue}
    func completedReminders(excluded:Set<String>,now:Date)async throws->[CompletedReminder] {completed}
}
@MainActor private final class ReviewGuardHold {
    var gate:CheckedContinuation<Void,Never>?
    var calls=0
    var input:[String:Any]=[:]
    func infer(_ input:[String:Any])async->PAResponse {
        calls += 1;self.input=input
        await withCheckedContinuation{gate=$0}
        return .init(text:"",output:[],calls:[.init(id:"fictional-preparation",name:ProactiveResultRules.toolName,namespace:"pa",arguments:#"{"suggestions":[],"projectTasks":[],"handled":[],"resolved":[],"retirements":[]}"#)])
    }
    func release() {gate?.resume();gate=nil}
}
/// Suspends the actual production suggestion service inside its inference port.
/// All source reads use fictional ports and all stores are in-memory. The caller
/// merges these checks into the existing source-free signed evaluation report.
@MainActor enum ReviewInferenceGuardEvaluation {
    static func run()async throws->[String:Bool] {
        guard ["--validate-advice-context","--validate-review-inbox"].contains(where:ProcessInfo.processInfo.arguments.contains) else {throw IntegrationError.verification}
        var checks:[String:Bool]=[:]
        let modes=["unrelated-memory","selected-memory","unrelated-project","selected-project","native-hint","native-change","native-addition","native-after-cap","native-outside-window","native-repeated-hints","completion-health","completion-change","mail-flags","unrelated-assessment","selected-assessment","historical-ack-display","historical-ack-support","human-dismiss","pending-change","permission","account","model","stop"]
        for mode in modes {
            let now=Date.now,reader=ReviewGuardNativeFixture(now:Date.now),hold=ReviewGuardHold(),model=DashboardModel(nativeSources:reader)
            model.chatGPT.activeID="fictional-review-guard-"+mode;model.chatGPT.inferenceVerified=true;model.chatGPT.selectedModel="fictional-model"
            let owner=model.chatGPT.activeID,store=model.assistant.memory
            guard model.assistant.contextEnabled,store.enabled,model.emailSummaries.enabled,model.proactive.enabled else {throw ActionFailure.message("The fictional Review guard evaluation requires existing source/memory controls to be enabled; none were changed.")}
            let json:[String:Any]=["id":"fictional-mail","accountID":"fictional-account","account":"Fictional Mail","messageID":1,"internetMessageID":"fictional-mail@example.invalid","sender":"Fictional tutor","subject":"Orion prototype","received":now.ISO8601Format(),"unread":true,"replied":false,"flagged":false]
            func mail(_ changes:[String:Any]=[:])throws->MailMessage {try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:json.merging(changes,uniquingKeysWith:{$1})))}
            let message=try mail(),quote="Prepare the Orion prototype with four sensors."
            var summary=EmailSummary(id:message.id,registration:owner,fingerprint:EmailSummary.fingerprint(message),summary:quote,attention:true,reason:"Prepare the prototype",evidence:quote,bodyFingerprint:"fictional-body",message:message,worthReading:true,needsReply:false,actionEvidence:[quote],actionEvidenceVersion:EmailSummary.actionEvidenceVersion)
            let fact=PAMemory(registration:owner,text:"The Orion prototype uses four sensors.",kind:.context,provenance:"Fictional human")
            guard store.put(fact) else {throw IntegrationError.verification}
            let project=try model.assistant.projects.save(.init(registration:owner,kind:.space,title:"Orion prototype",status:.active),expected:nil)
            var summaries=[summary],messages=[message]
            if mode.hasPrefix("historical-ack") {
                let old=try mail(["id":"fictional-old-mail","messageID":2,"internetMessageID":"old@example.invalid","subject":"Older unrelated appointment"])
                var historical=EmailSummary(id:old.id,registration:owner,fingerprint:EmailSummary.fingerprint(old),summary:"Older concern",attention:false,reason:"Older concern",evidence:"Older appointment",bodyFingerprint:"old-body",message:old,dismissed:true,worthReading:false)
                historical.dismissedSourceVersion=ReviewAcknowledgementRules.emailVersion(old,historical);summaries.append(historical);messages.append(old)
            }
            model.mailData = .init(messages:messages,accounts:[.init(id:message.accountID,title:"Fictional Mail")],errors:[],timedOut:false)
            try model.emailSummaries.seedAdviceFixture(summaries)
            if mode == "pending-change" {
                let pending=PADiscovery(id:"fictional-pending",registration:owner,mailID:message.id,kind:"update",message:"Original pending concern",evidence:quote,created:now,scope:model.proactive.scope(model),sourceRevision:summary.fingerprint,sourceTitle:message.subject,sourceAssessmentRevision:summary.adviceRevision(replied:false))
                try model.proactive.seedAdviceFixture([pending],model:model)
            }
            if mode == "native-after-cap" {
                let first=reader.calendarValue.events[0]
                reader.calendarValue.events += (1...205).map{index in var item=first;item.id="fictional-later-\(index)";item.start=now.addingTimeInterval(Double(index+1)*3600);item.end=item.start.addingTimeInterval(1800);return item}
            }
            model.proactive.evaluationNativeAccess={true}
            model.proactive.evaluationInference={await hold.infer($0)}
            model.proactive.check(model,manual:true)
            for _ in 0..<40_000 {if hold.gate != nil || !model.proactive.busy {break};await Task.yield()}
            guard hold.gate != nil else {throw ActionFailure.message("Fictional Review \(mode) did not reach the held inference: \(model.proactive.error ?? model.proactive.sourceReadError ?? "not started")")}
            checks["Review \(mode) uses actual selected memory"]=(hold.input["paMemory"] as? String)?.contains(fact.id.uuidString) == true
            switch mode {
            case "unrelated-memory":_=store.put(.init(registration:owner,text:"Garden irrigation needs a valve.",kind:.context,provenance:"Fictional human"))
            case "selected-memory":var changed=fact;changed.text="The Orion prototype now uses six sensors.";_=store.put(changed)
            case "unrelated-project":_=try model.assistant.projects.save(.init(registration:owner,kind:.space,title:"Garden irrigation"),expected:nil)
            case "selected-project":var changed=project;changed.title="Orion changed plan";_=try model.assistant.projects.save(changed,expected:project.revision)
            case "native-hint":model.sourceRevision += 1
            case "native-change":reader.calendarValue.events[0].start += 900;model.sourceRevision += 1
            case "native-addition":var added=reader.calendarValue.events[0];added.id="fictional-added";reader.calendarValue.events.append(added);model.sourceRevision += 1
            case "native-after-cap":reader.calendarValue.events[205].title="Changed after cap";model.sourceRevision += 1
            case "native-outside-window":var added=reader.calendarValue.events[0];added.id="fictional-outside";added.start=now.addingTimeInterval(100*86400);added.end=added.start.addingTimeInterval(3600);reader.calendarValue.events.append(added);model.sourceRevision += 1
            case "native-repeated-hints":reader.onValidationRead={model.sourceRevision += 1};model.sourceRevision += 1
            case "completion-health":model.completedReminderHealth = .init(lastSuccess:now.addingTimeInterval(5),loading:true)
            case "completion-change":model.completedReminders=[]
            case "mail-flags":model.mailData = .init(messages:[try mail(["unread":false,"flagged":true,"mailboxName":"Archive"])],accounts:model.mailData.accounts,errors:[],timedOut:false)
            case "unrelated-assessment":var other=summary;other.id="fictional-other";other.message=try mail(["id":other.id,"internetMessageID":"other@example.invalid","subject":"Garden receipt"]);other.fingerprint=EmailSummary.fingerprint(other.message!);other.attention=false;other.worthReading=false;try model.emailSummaries.seedAdviceFixture([summary,other])
            case "selected-assessment":summary.evidence="Changed prototype evidence";try model.emailSummaries.seedAdviceFixture([summary])
            case "historical-ack-display":let changed=try mail(["id":"fictional-old-mail","messageID":2,"internetMessageID":"old@example.invalid","subject":"Recovered older display title"]);summaries[1].message=changed;summaries[1].fingerprint=EmailSummary.fingerprint(changed);model.mailData = .init(messages:[message,changed],accounts:model.mailData.accounts,errors:[],timedOut:false);try model.emailSummaries.seedAdviceFixture(summaries)
            case "historical-ack-support":summaries[1].observedBodyFingerprint="changed-old-body";try model.emailSummaries.seedAdviceFixture(summaries)
            case "human-dismiss":model.emailSummaries.dismiss(message.id,model:model,expectedRegistration:owner,expectedVersion:ReviewAcknowledgementRules.emailVersion(message,summary))
            case "pending-change":var changed=model.proactive.state.records;changed[0].message="Changed pending concern";try model.proactive.seedAdviceFixture(changed,model:model)
            case "permission":model.proactive.evaluationNativeAccess={false}
            case "account":model.chatGPT.activeID="fictional-foreign-owner"
            case "model":model.chatGPT.selectedModel="fictional-new-model"
            default:model.proactive.cancel()
            }
            hold.release()
            for _ in 0..<40_000 {if !model.proactive.busy {break};await Task.yield()}
            guard !model.proactive.busy else {throw ActionFailure.message("Fictional Review \(mode) did not settle.")}
            let rejected=["selected-memory","selected-project","native-change","native-addition","completion-change","selected-assessment","human-dismiss","pending-change","permission","account","model","stop"].contains(mode)
            checks["Review \(mode) preserves exact relevant guards without unrelated cancellation"]=(model.proactive.error != nil) == rejected
            checks["Review \(mode) has one fictional inference and no subscription calls"]=hold.calls == 1 && model.aiUsage.state.records.isEmpty
            if mode == "native-repeated-hints" {checks["Review bounds repeated unchanged native hints"]=reader.calendarReads == 4}
        }
        return checks
    }
}
#endif
