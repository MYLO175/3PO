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
    var response=#"{"suggestions":[],"projectTasks":[],"handled":[],"resolved":[],"retirements":[]}"#
    func infer(_ input:[String:Any])async->PAResponse {
        calls += 1;self.input=input
        await withCheckedContinuation{gate=$0}
        return .init(text:"",output:[],calls:[.init(id:"fictional-preparation",name:ProactiveResultRules.toolName,namespace:"pa",arguments:response)])
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
        let modes=["unrelated-memory","selected-memory","unrelated-project","selected-project","native-hint","native-change","native-addition","native-after-cap","native-outside-window","native-repeated-hints","completion-health","completion-change","mail-flags","unrelated-assessment","selected-assessment","historical-ack-display","historical-ack-support","human-dismiss","unrelated-dismiss","selected-source-dismiss","individual-dismiss","undo-independent","pending-change","permission","account","model","stop","memory-controls-cycle","learning-controls-cycle","historical-row-current","historical-row-source-stale","historical-row-changed","historical-row-retire-stale-source","historical-row-retire-changed"]
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
            let siblingQuote="Water the garden seedlings with two litres."
            if mode == "individual-dismiss" {summary.actionEvidence=[quote,"Calibrate the Orion prototype sensors."]}
            var summaries=[summary],messages=[message]
            var dismissedSummary:EmailSummary?,dismissedProposal:PADiscovery?,restoredProposal:PADiscovery?
            if ["unrelated-dismiss","selected-source-dismiss","undo-independent"].contains(mode) {
                let other=try mail(["id":"fictional-garden-mail","messageID":2,"internetMessageID":"garden@example.invalid","subject":"Garden seedlings","received":now.addingTimeInterval(-86400).ISO8601Format()])
                let sibling=EmailSummary(id:other.id,registration:owner,fingerprint:EmailSummary.fingerprint(other),summary:siblingQuote,attention:mode == "selected-source-dismiss",reason:"Garden seedlings",evidence:siblingQuote,bodyFingerprint:"garden-body",message:other,worthReading:false,needsReply:false,actionEvidence:[siblingQuote],actionEvidenceVersion:EmailSummary.actionEvidenceVersion)
                summaries.append(sibling);messages.append(other)
                let fresh:[String:Any]=["mailID":"mail_0","kind":"update","message":"Fresh independent prototype information.","evidenceID":"mail_0:primary"]
                var rows=[fresh]
                var handled:[[String:Any]]=[]
                var resolved:[[String:Any]]=[]
                if mode == "selected-source-dismiss" {
                    rows.append(["mailID":"mail_1","kind":"update","message":"The garden seedlings need watering.","evidenceID":"mail_1:primary"])
                    handled=[["mailID":"mail_0","targetID":"reminder_0","requestEvidenceID":"mail_0:primary","allActionsAddressed":true,"reason":"The supplied prototype reminder covers this request."]]
                    resolved=[["mailID":"mail_0","confirmationID":"mail_1","requestEvidenceID":"mail_0:primary","confirmationEvidenceID":"mail_1:primary","allActionsAddressed":true,"reason":"Dismissal must not turn a garden message into prototype completion."]]
                }
                hold.response=String(decoding:try JSONSerialization.data(withJSONObject:["suggestions":rows,"projectTasks":[],"handled":handled,"resolved":resolved,"retirements":[]]),as:UTF8.self)
            }
            if mode.hasPrefix("historical-ack") {
                let old=try mail(["id":"fictional-old-mail","messageID":2,"internetMessageID":"old@example.invalid","subject":"Older unrelated appointment"])
                var historical=EmailSummary(id:old.id,registration:owner,fingerprint:EmailSummary.fingerprint(old),summary:"Older concern",attention:false,reason:"Older concern",evidence:"Older appointment",bodyFingerprint:"old-body",message:old,dismissed:true,worthReading:false)
                historical.dismissedSourceVersion=ReviewAcknowledgementRules.emailVersion(old,historical);summaries.append(historical);messages.append(old)
            }
            if mode.hasPrefix("historical-row") {
                let old=try mail(["id":"fictional-old-source","messageID":2,"internetMessageID":"old-source@example.invalid","subject":"Earlier Orion prototype","received":now.addingTimeInterval(-86400).ISO8601Format()])
                let historical=EmailSummary(id:old.id,registration:owner,fingerprint:EmailSummary.fingerprint(old),summary:quote,attention:false,reason:"Earlier historical context",evidence:quote,bodyFingerprint:"old-source-body",message:old,worthReading:true,needsReply:false)
                summaries.append(historical);messages.append(old)
            }
            model.mailData = .init(messages:messages,accounts:[.init(id:message.accountID,title:"Fictional Mail")],errors:[],timedOut:false)
            try model.emailSummaries.seedAdviceFixture(summaries)
            if mode == "individual-dismiss" || mode == "undo-independent" {
                let original=mode == "individual-dismiss" ? summary : summaries[1]
                let originalMessage=mode == "individual-dismiss" ? message : messages[1]
                let pending=PADiscovery(id:"fictional-dismissed-pending",registration:owner,mailID:original.id,kind:"reminder",message:"Original pending concern",evidence:original.evidence,created:now.addingTimeInterval(-86400),scope:model.proactive.scope(model),sourceRevision:original.fingerprint,sourceTitle:mode == "individual-dismiss" ? "Prepare Orion prototype" : "Water garden seedlings",sourceAssessmentRevision:original.adviceRevision(replied:false),sourceDate:originalMessage.received,sourceContentVersion:ReviewAcknowledgementRules.emailVersion(originalMessage,original))
                try model.proactive.seedAdviceFixture([pending],model:model)
                if mode == "undo-independent" {
                    restoredProposal=model.proactive.state.records.first
                    model.proactive.dismiss(ProactiveRules.reviewProjection(model.proactive.state.records[0]),model:model)
                } else {
                    let duplicate:[String:Any]=["mailID":"mail_0","kind":"reminder","title":"Prepare Orion prototype","message":"Original pending concern","evidenceID":"mail_0:action_0"]
                    let sibling:[String:Any]=["mailID":"mail_0","kind":"reminder","title":"Calibrate Orion sensors","message":"Calibrate the prototype sensors.","evidenceID":"mail_0:action_1"]
                    hold.response=String(decoding:try JSONSerialization.data(withJSONObject:["suggestions":[duplicate,sibling],"projectTasks":[],"handled":[],"resolved":[],"retirements":[]]),as:UTF8.self)
                }
            }
            if mode == "pending-change" {
                let pending=PADiscovery(id:"fictional-pending",registration:owner,mailID:message.id,kind:"update",message:"Original pending concern",evidence:quote,created:now,scope:model.proactive.scope(model),sourceRevision:summary.fingerprint,sourceTitle:message.subject,sourceAssessmentRevision:summary.adviceRevision(replied:false))
                try model.proactive.seedAdviceFixture([pending],model:model)
            }
            if mode.hasPrefix("historical-row") {
                let old=summaries[1],oldMessage=messages[1]
                let pending=PADiscovery(id:"fictional-historical-pending",registration:owner,mailID:old.id,kind:"reminder",message:"Original pending Orion concern",evidence:quote,created:now.addingTimeInterval(-86400),scope:model.proactive.scope(model),sourceRevision:old.fingerprint,sourceTitle:"Prepare Orion prototype",sourceAssessmentRevision:old.adviceRevision(replied:false),sourceDate:oldMessage.received)
                try model.proactive.seedAdviceFixture([pending],model:model)
                let fresh:[String:Any]=["mailID":"mail_0","kind":"update","message":"Fresh independent prototype information.","evidenceID":"mail_0:primary"]
                let replacement:[String:Any]=["mailID":"mail_0","kind":"reminder","title":"Updated prototype reminder","message":"A later source updates this exact earlier prototype concern.","evidenceID":"mail_0:primary","replaces":["review_0"],"replacementReason":"The newer prototype message updates the earlier concern."]
                let retirement:[[String:Any]]=mode.contains("retire") ? [["reviewID":"review_0","targetID":"reminder_0","reason":"The exact issued prototype reminder already covers this proposed reminder."]] : []
                hold.response=String(decoding:try JSONSerialization.data(withJSONObject:["suggestions":[fresh,replacement],"projectTasks":[],"handled":[],"resolved":[],"retirements":retirement]),as:UTF8.self)
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
            case "unrelated-dismiss","selected-source-dismiss":
                let target=mode == "unrelated-dismiss" ? summaries[1] : summary
                let source=mode == "unrelated-dismiss" ? messages[1] : message
                model.emailSummaries.dismiss(source.id,model:model,expectedRegistration:owner,expectedVersion:ReviewAcknowledgementRules.emailVersion(source,target))
                dismissedSummary=model.emailSummaries.records.first{$0.id == source.id}
            case "individual-dismiss":
                model.proactive.dismiss(ProactiveRules.reviewProjection(model.proactive.state.records[0]),model:model)
                dismissedProposal=model.proactive.state.records.first
            case "undo-independent":model.proactive.undo(model)
            case "memory-controls-cycle":store.enabled=false;store.enabled=true
            case "learning-controls-cycle":let original=store.learningEnabled;store.learningEnabled.toggle();store.learningEnabled=original
            case "historical-row-current":break
            case "historical-row-source-stale","historical-row-retire-stale-source":summaries[1].observedBodyFingerprint="changed-historical-body";try model.emailSummaries.seedAdviceFixture(summaries)
            case "historical-row-changed","historical-row-retire-changed":var changed=model.proactive.state.records;changed[0].message="Newer pending snapshot must be retained";try model.proactive.seedAdviceFixture(changed,model:model)
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
            let rejected=["selected-memory","selected-project","native-change","native-addition","completion-change","selected-assessment","permission","account","model","stop","memory-controls-cycle","learning-controls-cycle"].contains(mode)
            checks["Review \(mode) preserves exact relevant guards without unrelated cancellation"]=(model.proactive.error != nil) == rejected
            checks["Review \(mode) has one fictional inference and no subscription calls"]=hold.calls == 1 && model.aiUsage.state.records.isEmpty
            if !rejected {
                let progress=model.proactive.state.accounts[owner]
                checks["Review \(mode) commits its completed comparison"]=progress?.paused == false
                checks["Review \(mode) retains completion fingerprint or explicit row diagnostics"]=progress?.fingerprint != nil || progress?.validationIssues?.isEmpty == false
            }
            if ["unrelated-dismiss","selected-source-dismiss","individual-dismiss","undo-independent"].contains(mode) {
                let saved=model.proactive.state.records,progress=model.proactive.state.accounts[owner]
                checks["Review \(mode) completes without attention-only diagnostics"]=progress?.paused == false && progress?.fingerprint != nil && progress?.validationIssues?.isEmpty != false
                if let dismissedSummary {
                    let current=model.emailSummaries.records.first{$0.id == dismissedSummary.id}
                    checks["Review \(mode) preserves the exact latest whole-email Dismiss"]=current.map{ReviewInferenceGuard.fingerprint($0)} == ReviewInferenceGuard.fingerprint(dismissedSummary) && current?.dismissed == true
                }
                if mode == "unrelated-dismiss" || mode == "undo-independent" {
                    checks["Review \(mode) saves the independent fresh source"]=saved.contains{$0.mailID == message.id && $0.kind == "update"}
                }
                if mode == "selected-source-dismiss" {
                    checks["Review selected-source Dismiss withholds only that source's returned proposals"]=saved.allSatisfy{$0.mailID != message.id} && saved.contains{$0.mailID == messages[1].id}
                    checks["Review selected-source Dismiss cannot acquire handling or resolution"]=model.emailSummaries.records.first{$0.id == message.id}.map{$0.handling == nil && $0.resolution == nil} == true
                }
                if let dismissedProposal {
                    checks["Review individual Dismiss keeps its original canonical record"]=saved.first{$0.id == dismissedProposal.id} == dismissedProposal && dismissedProposal.dismissed
                    checks["Review individual Dismiss suppresses only the typed duplicate"]=saved.count == 2 && saved.contains{$0.sourceTitle == "Calibrate Orion sensors" && !$0.dismissed} && saved.filter{$0.sourceTitle == "Prepare Orion prototype"}.count == 1
                }
                if let restoredProposal {
                    checks["Review Undo retains only the explicitly restored original identity"]=saved.first{$0.id == restoredProposal.id} == restoredProposal && saved.filter{$0.mailID == restoredProposal.mailID}.count == 1
                    checks["Review Undo does not replay old output or start another request"]=hold.calls == 1 && saved.count == 2
                }
            }
            if mode.hasPrefix("historical-row") {
                let saved=model.proactive.state.records
                let fresh=saved.first{$0.mailID == message.id && $0.kind == "update"}
                checks["Review \(mode) preserves supported fresh sibling"]=fresh != nil && fresh?.comparisonSourceIDs?.isEmpty != false && fresh?.whatsappDependencies?.isEmpty != false
                checks["Review \(mode) retains historical canonical identity"]=saved.contains{$0.id == "fictional-historical-pending" && $0.mailID == "fictional-old-source"}
                if mode == "historical-row-current" {
                    let replacement=saved.first{$0.replaces == ["fictional-historical-pending"]}
                    checks["Review actual replacement retains only its claimed prior source"]=replacement?.comparisonSourceIDs == ["fictional-historical-pending"] && saved.first{$0.id == "fictional-historical-pending"}?.supersededBy == replacement?.id
                    summaries[1].observedBodyFingerprint="later-historical-source-loss";try model.emailSummaries.seedAdviceFixture(summaries)
                    checks["Review unrelated fresh output survives later historical source loss"]=fresh.map{model.proactive.reviewEvidenceAvailable($0.id,model:model)} == true
                    checks["Review claimed replacement keeps its exact historical support"]=replacement.map{!model.proactive.reviewEvidenceAvailable($0.id,model:model)} == true
                } else {
                    checks["Review \(mode) rejects stale replacement with diagnostics"]=saved.allSatisfy{$0.replaces?.contains("fictional-historical-pending") != true} && model.proactive.state.accounts[owner]?.validationIssues?.isEmpty == false
                    let historical=saved.first{$0.id == "fictional-historical-pending"}
                    checks["Review \(mode) retires only an unchanged exact proposal"]=mode == "historical-row-retire-stale-source" ? historical?.retiredAt != nil : historical?.retiredAt == nil && historical?.supersededBy == nil
                }
            }
            if mode == "native-repeated-hints" {checks["Review bounds repeated unchanged native hints"]=reader.calendarReads == 4}
        }
        return checks
    }
}
#endif
