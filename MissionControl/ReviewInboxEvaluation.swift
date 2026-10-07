#if DEBUG
import Foundation
import SwiftUI

@MainActor enum ReviewInboxEvaluation {
    static func seed(_ model:DashboardModel)throws->PADiscovery {
        let account=model.chatGPT.activeID,now=Date.now,quote="The Orion prototype report deadline has moved to 20 October 2026."
        let messageJSON:[String:Any]=["id":"fictional-orion-mail","accountID":"fictional-mail","account":"Fictional Mail","messageID":1,"internetMessageID":"orion@example.invalid","sender":"Fictional tutor","subject":"Orion deadline change","received":now.ISO8601Format(),"unread":true,"replied":false,"flagged":false]
        let message=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:messageJSON))
        model.mailData = .init(messages:[message],accounts:[.init(id:message.accountID,title:message.account)],errors:[])
        let summary=EmailSummary(id:message.id,registration:account,fingerprint:EmailSummary.fingerprint(message),summary:"Orion report deadline moved.",attention:true,reason:"Deadline changed",evidence:quote,bodyFingerprint:"fictional-body",message:message)
        try model.emailSummaries.seedAdviceFixture([summary])
        let task=TaskItem(id:"fictional-orion",listID:"fictional-studies",title:"Submit Orion prototype report",due:Calendar.current.date(from:DateComponents(year:2026,month:10,day:16)),hasTime:false,sourceLabel:"Fictional Studies",writable:true,recurring:false,modified:now)
        model.reminderData = .init(sources:[.init(id:task.listID,title:task.sourceLabel,account:"Fictional",writable:true)],reminders:[task])
        let proposal=DiscoveryDateChange(target:.reminder(task),newDate:"2026-10-20",hasTime:false,connection:"Distinctive Orion prototype report matches the existing reminder.",timeZoneID:TimeZone.current.identifier)
        let record=PADiscovery(id:UUID().uuidString,registration:account,mailID:message.id,kind:"change",message:"Your tutor moved the Orion report deadline from 16 to 20 October. Review this reminder change?",evidence:quote,created:now,scope:"fixture",sourceRevision:summary.fingerprint,sourceAssessmentRevision:summary.adviceRevision(replied:false),proposedChange:proposal)
        try model.proactive.seedAdviceFixture([record],model:model)
        return model.proactive.state.records[0]
    }
    static func previewSession(_ target:NativeEditTarget)->NativeEditSession? {
        guard ProcessInfo.processInfo.arguments.contains("--preview-review-inbox"),case .reviewReminder(let task,_) = target else {return nil}
        return .init(item:.init(kind:.reminder,itemID:task.id,occurrenceID:task.id,sourceID:task.listID,title:task.title,notes:"Original fictional notes stay intact.",due:task.due,hasTime:task.hasTime,writable:true,modified:task.modified),sources:[.init(id:task.listID,title:task.sourceLabel,account:"Fictional",writable:true)])
    }
    static func run(_ model:DashboardModel)async throws->[String:Any] {
        let record=try seed(model),account=model.chatGPT.activeID,selected=model.chatGPT.selectedModel
        var checks:[String:Bool]=[:]
        checks["actual proposal visible with exact native snapshot"]=model.proactive.visible(record,model:model)
        model.reviewDiscovery(record)
        if case .reviewReminder(let item,let review)=model.editTarget {checks["review resolves original reminder and proposed date"]=item.id == record.proposedChange?.target.itemID && DateRules.localDate(review.date) == "2026-10-20"} else {checks["review resolves original reminder and proposed date"]=false}
        let original=model.reminderData
        model.reminderData.reminders[0].modified = .now.addingTimeInterval(10)
        checks["changed native revision rejects old proposal"] = !model.proactive.visible(record,model:model)
        model.reminderData=original
        try model.proactive.beginReview(record.id,model:model)
        checks["persistent pending claim blocks repeated approval"] = !model.proactive.canReview(record.id,model:model)
        try model.proactive.abortReview(record.id,registration:account)
        checks["known no-save abort permits fresh review"]=model.proactive.canReview(record.id,model:model)
        try model.proactive.beginReview(record.id,model:model);try model.proactive.finishReview(record.id,registration:account)
        checks["approved output leaves active inbox"] = !model.proactive.visible(model.proactive.state.records[0],model:model)
        checks["inbox recovery does not add a chat turn"] = model.assistant.feed?.turns.isEmpty ?? true
        model.proactive.recoverDelivery(model)
        checks["inbox stays separate from normal chat"] = model.assistant.feed?.turns.isEmpty ?? true
        // One current production prompt/decode request; only fictional selected WhatsApp messages.
        let texts=["The Orion prototype report deadline has moved to 20 October 2026.","Alex's meeting has moved to 21 October 2026.","If we moved the Vega report to 22 October it might help, but the deadline has NOT changed."]
        let candidates=texts.enumerated().map{DiscoveryCandidate(alias:"wa_\($0.offset)",mailID:"fictional-wa-\($0.offset)",evidence:"",followUpEvidence:"",sourceKind:"whatsapp",sourceChatID:"fictional-study",sourceMessageID:"fictional-\($0.offset)",sourceIdentity:"fictional-link",sourceRevision:"v1",sourceLabel:"Fictional studies",sourceText:$0.element)}
        var targets:[String:DiscoveryNativeTarget]=[:]
        for (index,title) in ["Submit Orion prototype report","Alex meeting","Alex meeting","Vega report"].enumerated() {
            var task=original.reminders[0];task.id="fictional-target-\(index)";task.title=title;targets["reminder_\(index)"] = .reminder(task)
        }
        let input:[String:Any]=["localDay":BriefingRules.day(.now),"timezone":TimeZone.current.identifier,"events":[],"reminders":targets.keys.sorted().map{["id":$0,"title":targets[$0]!.title,"due":targets[$0]!.originalDate,"hasTime":false,"writable":true] as [String:Any]},"whatsapp":texts.enumerated().map{["id":"wa_\($0.offset)","chat":"Studies","sender":"Tutor","sentByMe":false,"text":$0.element] as [String:Any]},"calendarCoverage":"Fictional full fixture","reminderCoverage":"Fictional full fixture","whatsappCoverage":"Three fictional messages. Alex targets are ambiguous. No previous identity link is asserted.","paMemory":"{}","emails":[],"recentGeneralChat":[],"deliveredSuggestions":[]]
        let data=try JSONSerialization.data(withJSONObject:input,options:[.sortedKeys])
        let response=try await model.chatGPT.streamResponse(input:[["role":"user","content":String(decoding:data,as:UTF8.self)]],instructions:ProactiveRules.heartbeatInstructions+" "+MemoryDependencyRules.instructions+" "+CommitmentRules.instructions+" "+ProactiveRules.changeInstructions,model:selected,purpose:.diagnostic) {_ in}
        let records=try ProactiveRules.decode(response,candidates:candidates,registration:account,scope:"fictional",now:.now,targets:targets)
        checks["AI notices unlinked changed Orion deadline"]=records.contains{$0.mailID == "fictional-wa-0" && $0.proposedChange?.target.itemID == "fictional-target-0" && $0.proposedChange?.newDate == "2026-10-20"}
        checks["ambiguous Alex match does not propose an edit"] = !records.contains{$0.mailID == "fictional-wa-1" && $0.proposedChange != nil}
        checks["hypothetical negated change does not propose an edit"] = !records.contains{$0.mailID == "fictional-wa-2" && $0.proposedChange != nil}
        checks["account model and native data preserved"]=account == model.chatGPT.activeID && selected == model.chatGPT.selectedModel && !model.writing && model.reminderData.reminders[0].due == original.reminders[0].due
        var nativeError=""
        do {let native=try await model.eventKit.validateReviewClaim();for (key,value) in native {checks[key]=value}}
        catch {checks["native approval and cleanup validation completed"]=false;nativeError=error.localizedDescription}
        return ["completed":Date.now.ISO8601Format(),"requests":1,"model":selected,"passed":checks.values.filter{$0}.count,"total":checks.count,"checks":checks,"nativeError":nativeError,"outputs":records.map{["kind":$0.kind,"message":$0.message,"source":$0.mailID,"newDate":$0.proposedChange?.newDate ?? "none"]},"storage":"Fictional messages/native snapshots and disposable SwiftData before source startup. Native validation attempts only one UUID-marked disposable Reminder and reports verified cleanup or an error; no personal settings changes. One narrow quality scenario, not sustained live scheduling."]
    }
}
struct ReviewInboxPreview:View {
    var model:DashboardModel
    @State private var ready=false
    var body:some View {
        VStack {Text("Fictional review inbox · disposable storage · no Apple writes").font(.caption);if ready {PATasksView(model:model);if model.proactive.canUndo {Button("Undo dismissed fixture") {model.proactive.undo(model)}}} }
            .padding(16).frame(width:600,height:660)
            .sheet(item:Binding(get:{model.editTarget},set:{model.editTarget=$0})){NativeItemEditor(model:model,target:$0)}
            .task {guard !ready else {return};_ = try? ReviewInboxEvaluation.seed(model);ready=true}
    }
}
#endif
