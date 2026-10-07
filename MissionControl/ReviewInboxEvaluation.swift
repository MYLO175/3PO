#if DEBUG
import Foundation
import SwiftUI
import EventKit

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
    // Runs the real inbox coordinator without inference, against one UUID-marked native fixture.
    static func runApproval(_ model:DashboardModel) async throws->[String:Any] {
        var record=try seed(model),checks:[String:Bool]=[:],cleanupError="",failure=""
        let fixture=try await model.eventKit.makeApprovalFixture(excluded:model.assistant.excludedLists)
        func stage(_ item:NativeEditDetails)throws {
            let task=TaskItem(id:item.itemID,listID:item.sourceID,title:item.title,due:item.due,hasTime:item.hasTime,sourceLabel:"Disposable validation",writable:item.writable,recurring:item.recurring,modified:item.modified)
            model.reminderData = .init(sources:[.init(id:task.listID,title:task.sourceLabel,account:"Fixture",writable:true)],reminders:[task])
            record.proposedChange?.target = .reminder(task);record.reviewState=nil;record.dismissed=false
            try model.proactive.seedAdviceFixture([record],model:model)
        }
        do {
            try stage(fixture.item)
            checks["proposal alone leaves native item untouched"] = try await model.eventKit.readApprovalFixture(fixture) == fixture.item
            model.proactive.dismiss(record)
            checks["Dismiss preserves complete native item and does not claim a save"] = try await model.eventKit.readApprovalFixture(fixture) == fixture.item && model.proactive.state.records[0].dismissed && model.proactive.state.records[0].reviewState == nil
            model.proactive.undo(model)
            // Saved assessment headers deliberately survive mail-page eviction; withdraw the account too.
            let mail=model.mailData;model.mailData = .init(messages:[],accounts:[],errors:[])
            await model.approveDiscovery(record)
            checks["withdrawn source refuses approval without native mutation"] = try await model.eventKit.readApprovalFixture(fixture) == fixture.item
            model.mailData=mail
            try await model.eventKit.changeApprovalFixture(fixture)
            let changed=try await model.eventKit.readApprovalFixture(fixture)
            await model.approveDiscovery(record)
            checks["outside native edit refuses old approval and remains intact"] = try await model.eventKit.readApprovalFixture(fixture) == changed && model.proactive.state.records[0].reviewState == nil && model.reviewApprovalError != nil
            try stage(changed)
            await model.approveDiscovery(record)
            let saved=try await model.eventKit.readApprovalFixture(fixture)
            checks["Approve applies exactly the proposed reminder date"] = DateRules.localDate(saved.due ?? .distantPast) == record.proposedChange?.newDate && !saved.hasTime
            var expected=changed;expected.due=record.proposedChange?.date();expected.hasTime=false;expected.modified=saved.modified
            checks["Approve preserves every other native field"] = saved == expected
            checks["verified approval persisted and removed from active inbox"] = model.proactive.state.records[0].reviewState == "approved" && !model.proactive.visible(model.proactive.state.records[0],model:model)
            checks["simple approval needs no second form"] = model.editTarget == nil
            await model.approveDiscovery(record)
            checks["second approval does not repeat the native save"] = try await model.eventKit.readApprovalFixture(fixture) == saved
            _ = try await model.undoAssistantAppleChange()
            let restored=try await model.eventKit.readApprovalFixture(fixture)
            var expectedRestore=changed;expectedRestore.modified=restored.modified
            checks["supported Undo restores original native fields"] = restored == expectedRestore
            checks["approval never creates normal chat messages"] = model.assistant.feed?.turns.isEmpty ?? true
            checks["write ownership released after approval"] = !model.writing && model.approvingDiscoveryID == nil
        } catch {failure=error.localizedDescription}
        do {try await model.eventKit.removeApprovalFixture(fixture);checks["marked fixture removed and absence verified"]=true}
        catch {cleanupError=error.localizedDescription;checks["marked fixture removed and absence verified"]=false}
        return ["completed":Date.now.ISO8601Format(),"requests":0,"passed":checks.values.filter{$0}.count,"total":checks.count,"checks":checks,"error":failure,"cleanupError":cleanupError,"storage":"Disposable SwiftData, fictional Mail evidence and one exact UUID-marked native Reminder; no source startup, inference or settings changes."]
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
struct ReviewApprovalFixture {
    var item:NativeEditDetails
    var marker:String
}
extension EventKitService {
    func makeApprovalFixture(excluded:Set<String>) throws->ReviewApprovalFixture {
        guard EKEventStore.authorizationStatus(for:.reminder) == .fullAccess,EKEventStore.authorizationStatus(for:.event) == .fullAccess else {throw IntegrationError.denied("Existing Calendar and Reminders permissions required; no new prompt.")}
        store.reset()
        guard let list=store.calendars(for:.reminder).first(where:{$0.allowsContentModifications && !excluded.contains($0.calendarIdentifier)}) else {throw IntegrationError.readOnly}
        let marker="Mission Control approval validation "+UUID().uuidString
        let item=EKReminder(eventStore:store);item.calendar=list;item.title=marker;item.notes=marker
        item.dueDateComponents=Calendar.current.dateComponents([.year,.month,.day],from:Calendar.current.startOfDay(for:.now))
        try store.save(item,commit:true)
        let id=item.calendarItemIdentifier;store.reset()
        guard let persisted=store.calendarItem(withIdentifier:id) as? EKReminder else {throw IntegrationError.verification}
        return .init(item:editorDetails(persisted),marker:marker)
    }
    func readApprovalFixture(_ fixture:ReviewApprovalFixture)throws->NativeEditDetails {
        store.reset();guard let item=store.calendarItem(withIdentifier:fixture.item.itemID) as? EKReminder,item.title == fixture.marker,item.notes?.hasPrefix(fixture.marker) == true else {throw IntegrationError.verification}
        return editorDetails(item)
    }
    func changeApprovalFixture(_ fixture:ReviewApprovalFixture)throws {
        _ = try readApprovalFixture(fixture)
        guard let item=store.calendarItem(withIdentifier:fixture.item.itemID) as? EKReminder else {throw IntegrationError.missing}
        item.notes=fixture.marker+" external edit";try store.save(item,commit:true)
    }
    func removeApprovalFixture(_ fixture:ReviewApprovalFixture)throws {
        _ = try readApprovalFixture(fixture)
        guard let item=store.calendarItem(withIdentifier:fixture.item.itemID) as? EKReminder else {throw IntegrationError.missing}
        try store.remove(item,commit:true);store.reset()
        guard store.calendarItem(withIdentifier:fixture.item.itemID) == nil else {throw IntegrationError.verification}
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
