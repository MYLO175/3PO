import Foundation
import SwiftData

struct ReviewPreparedPayload:Codable,Equatable {
    var proposal:PADiscovery
    var approval:Data
    var source:ReviewWorkSource?
    var nativeRequest:NativeCreationRequest?
    var nativeFields:NativeEditDetails?
    var project:LifeItem?
}
struct ReviewConversationPresentation:Identifiable {var id:UUID}
struct ReviewPreparedRow:Identifiable {
    var id:String
    var title:String
    var detail:String
    var destination:String
    var action:ReviewWorkAction?
    var error:String?
}

@MainActor extension DashboardModel {
    var reviewStorageIdentity:String {container?.configurations.map{$0.url.absoluteString}.sorted().joined(separator:"|") ?? "unavailable"}
    func reviewWorkScope()->ReviewWorkScope {
        let wa=whatsapp.access(for:chatGPT.activeID)
        let choices=proactive.sourceSettingsScope(self)+"|"+String(wa.enabled)+"|"+String(wa.includeInSuggestions == true)+"|"+whatsapp.linkedIdentity+"|"+wa.chats.sorted().joined(separator:"|")
        return .init(registration:chatGPT.activeID,model:chatGPT.selectedModel,sourceChoices:choices,storage:reviewStorageIdentity)
    }
    func reviewPermits(_ source:ReviewWorkSource)->Bool {
        guard assistant.contextEnabled else {return false}
        if source.kind == "whatsapp" {
            let access=whatsapp.access(for:chatGPT.activeID)
            return access.enabled && access.includeInSuggestions == true && source.identity == whatsapp.linkedIdentity && source.chatID.map{access.chats.contains($0)} == true
        }
        return emailSummaries.enabled && source.accountID.map{id in !assistant.excludedAccounts.contains(id) && mailData.accounts.contains{$0.id == id}} == true
    }
    func reviewSource(_ record:PADiscovery)->ReviewWorkSource {
        let message=mailData.messages.first{$0.id == record.mailID} ?? emailSummaries.records.first{$0.id == record.mailID && $0.registration == record.registration}?.message
        return .init(key:record.sourceKind == "whatsapp" ? "whatsapp:"+(record.sourceIdentity ?? "")+":"+(record.sourceChatID ?? "")+":"+(record.sourceMessageID ?? record.mailID) : "mail:"+record.mailID,title:message?.subject ?? record.sourceTitle ?? "Review suggestion",kind:record.sourceKind ?? "mail",accountID:message?.accountID,messageID:record.mailID,identity:record.sourceIdentity,chatID:record.sourceChatID)
    }
    func reviewSource(_ conversation:AssistantConversation)->ReviewWorkSource? {
        guard let key=conversation.reviewKey else {return nil}
        return .init(key:key,title:conversation.title,kind:conversation.reviewSourceKind ?? "mail",accountID:conversation.reviewAccountID,messageID:conversation.reviewMessageID,identity:conversation.reviewSourceIdentity,chatID:conversation.reviewSourceChatID)
    }
    func reviewConversationAvailable(_ id:UUID)->Bool {assistant.conversation(id).flatMap(reviewSource).map(reviewPermits) == true}
    func openReviewConversation(_ records:[PADiscovery]) {
        guard let first=records.first,first.registration == chatGPT.activeID else {return}
        let source=reviewSource(first)
        guard reviewPermits(source) else {return}
        let seeds=records.map {record -> AssistantTurn in
            var turn=AssistantTurn(role:"assistant",content:(record.sourceTitle.map{$0+"\n"} ?? "")+record.message,completed:true,deliveryID:"discovery:"+record.id)
            turn.sourceMemoryIDs=record.memoryDependencies?.compactMap{UUID(uuidString:$0.id)}
            return turn
        }
        guard let id=assistant.openReview(key:source.key,title:source.title,sourceKind:source.kind,accountID:source.accountID,messageID:source.messageID,identity:source.identity,chatID:source.chatID,seeds:seeds) else {return}
        reviewPresentation = .init(id:id)
    }
    func reviewRecords(_ source:ReviewWorkSource)->[PADiscovery] {
        proactive.state.records.filter{record in record.registration == chatGPT.activeID && reviewSource(record).key == source.key && record.supersededBy == nil && record.retiredAt == nil && !record.dismissed}
    }
    func preparedCreationRequest(_ record:PADiscovery)->NativeCreationRequest? {
        guard record.nativeTarget == nil,["calendar","reminder"].contains(record.kind),let id=UUID(uuidString:record.id),let snapshot=preparedApprovalSnapshot(record) else {return nil}
        let source=reviewSource(record),kind:NativeItemKind=record.kind == "calendar" ? .event : .reminder
        return .init(id:id,kind:kind,registration:record.registration,title:String((record.sourceTitle ?? source.title).prefix(500)),notes:"Source: "+(record.sourceLabel ?? source.title)+"\n"+record.evidence,discoveryID:record.id,discoveryApproval:snapshot,evidence:record.message+"\n\n"+record.evidence,requiresDateSelection:kind == .event,suggestedStart:record.proposedDate?.date(),suggestedEnd:record.proposedDate?.end.flatMap{record.proposedDate?.date($0)},suggestedHasTime:record.proposedDate?.hasTime,suggestedTimeZone:record.proposedDate?.timeZoneID)
    }
    func prepareReviewRow(_ record:PADiscovery) async->ReviewPreparedRow {
        let title=record.sourceTitle ?? reviewSource(record).title
        var row=ReviewPreparedRow(id:record.id,title:title,detail:record.message,destination:"",action:nil)
        guard currentPreparedApproval(record),let approval=preparedApprovalSnapshot(record) else {row.error="This suggestion changed. Reopen Review for its current version.";return row}
        do {
            var payload=ReviewPreparedPayload(proposal:record,approval:approval,source:reviewSource(record))
            if ["project","projectTask"].contains(record.kind) {
                guard record.kind == "projectTask",let target=record.proposedProjectTask?.target,let id=UUID(uuidString:record.id) else {row.error="Review this space’s details separately before creating it.";return row}
                payload.project = .init(id:id,registration:record.registration,conversationID:target.conversationID,kind:.task,title:String(title.prefix(160)),parentID:target.id,notes:record.evidence,due:record.proposedDate?.localDay)
                row.destination="Task in "+target.title
                row.detail=(record.proposedDate?.localDay.map{"Due "+$0+"\n"} ?? "No deadline assigned\n")+record.message
            } else if let request=preparedCreationRequest(record) {
                guard !record.needsDateClarification,request.kind != .event || request.suggestedStart != nil else {row.error="The Calendar date needs clarification. Ask below before approving it.";return row}
                let scope=reviewWorkScope()
                let session:NativeEditSession
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") {
                    guard let fixture=ReviewInboxEvaluation.previewSession(.create(request)) else {throw ActionFailure.message("No source-free destination fixture is available.")}
                    session=fixture
                } else {session=try await eventKit.creationSession(request)}
                #else
                session=try await eventKit.creationSession(request)
                #endif
                try Task.checkCancellation()
                guard scope == reviewWorkScope(),currentPreparedApproval(record) else {throw ActionFailure.message("The account, destination choices or suggestion changed while preparing this plan.")}
                let fields=NativeCreationRules.applyingSuggestion(request,to:session.item)
                guard let destination=session.sources.first(where:{$0.id == fields.sourceID && $0.writable}),!(request.kind == .event ? assistant.excludedCalendars : assistant.excludedLists).contains(destination.id) else {throw ActionFailure.message("Choose an enabled writable destination before approving this action.")}
                payload.nativeRequest=request;payload.nativeFields=fields
                row.destination=(request.kind == .event ? "Calendar · " : "Reminders · ")+destination.label
                if request.kind == .event {
                    var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:fields.timeZoneID) ?? .current
                    let end=fields.allDay ? calendar.date(byAdding:.day,value:-1,to:fields.end) ?? fields.end : fields.end
                    row.detail=fields.start.formatted(date:.abbreviated,time:fields.allDay ? .omitted : .shortened)+" to "+end.formatted(date:.abbreviated,time:fields.allDay ? .omitted : .shortened)+"\n"+record.message
                } else {row.detail=fields.due.map{$0.formatted(date:.abbreviated,time:fields.hasTime ? .shortened : .omitted)+"\n"+record.message} ?? "No due date\n"+record.message}
            } else {row.error="This action needs its existing detail/occurrence review. You can ask about it below.";return row}
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            var concrete:[String:Any]=["approval":approval.base64EncodedString()]
            if let fields=payload.nativeFields,let object=try JSONSerialization.jsonObject(with:encoder.encode(fields)) as? [String:Any] {
                let keys:Set<String>=["kind","sourceID","title","notes","location","start","end","allDay","due","hasTime","timeZoneID","url","priority","alarms","availability"]
                concrete["native"]=object.filter{keys.contains($0.key) && (fields.kind == .event || !["start","end"].contains($0.key))}
            }
            if let item=payload.project,let object=try JSONSerialization.jsonObject(with:encoder.encode(item)) as? [String:Any] {concrete["project"]=object.filter{["id","registration","conversationID","kind","title","parentID","notes","due"].contains($0.key)}}
            let key=try JSONSerialization.data(withJSONObject:concrete,options:[.sortedKeys]).base64EncodedString()
            row.action = .init(id:record.id,title:title,destination:row.destination,coalescingKey:key,payload:try encoder.encode(payload))
        } catch {row.error=error.localizedDescription}
        return row
    }
    /// The accepted displayed creation is the authority. Background reassessment
    /// cannot substitute another payload or veto it through an evidence revision.
    func acceptedPreparedApproval(_ payload:ReviewPreparedPayload)->Bool {
        let proposal=payload.proposal
        guard proposal.registration == chatGPT.activeID,proposal.nativeTarget == nil,
              reviewPermits(payload.source ?? reviewSource(proposal)),preparedApprovalSnapshot(proposal) == payload.approval,
              let identity=UUID(uuidString:proposal.id) else {return false}
        if let request=payload.nativeRequest,let fields=payload.nativeFields {
            guard ["calendar","reminder"].contains(proposal.kind),!proposal.needsDateClarification,
                  request.id == identity,request.registration == proposal.registration,request.discoveryID == proposal.id,
                  request.discoveryApproval == payload.approval,fields.kind == request.kind,
                  request.kind == (proposal.kind == "calendar" ? NativeItemKind.event : .reminder),
                  !(fields.kind == .event ? assistant.excludedCalendars : assistant.excludedLists).contains(fields.sourceID),
                  request.kind != .event || request.suggestedStart != nil else {return false}
            return true
        }
        if let item=payload.project,let target=proposal.proposedProjectTask?.target {
            return proposal.kind == "projectTask" && item.id == identity && item.kind == .task && item.registration == proposal.registration && item.parentID == target.id && item.conversationID == target.conversationID
        }
        return false
    }
    func inspectReviewAction(_ job:ReviewWorkJob,_ action:ReviewWorkAction)->ReviewWorkActionResult? {
        guard let payload=try? JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload),payload.proposal.registration == job.scope.registration else {return .init(phase:.failed,message:"The captured action payload is unavailable.")}
        if let request=payload.nativeRequest {
            if let receipt=nativeCreations.receipt(request) {return .init(phase:.saved,message:"Created "+receipt.title,itemID:receipt.itemID,location:request.kind.rawValue)}
            if nativeCreations.state.claims[request.key] != nil {return .init(phase:.uncertain,message:"This save has an unconfirmed receipt. Check Calendar or Reminders; it will not be repeated.")}
            if action.phase == .uncertain {return .init(phase:.failed,message:"No native save was claimed. Reopen this exact plan before retrying.")}
        } else if let item=payload.project,let receipt=assistant.projects.receipt("project-suggestion:"+payload.proposal.id,registration:job.scope.registration) {
            return .init(phase:.saved,message:receipt.result,itemID:receipt.itemID?.uuidString ?? item.id.uuidString,location:"project")
        }
        return nil
    }
    func performReviewAction(_ job:ReviewWorkJob,_ action:ReviewWorkAction,valid:@escaping @MainActor ()->Bool)async throws->ReviewWorkActionResult {
        let payload=try JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload)
        let source=payload.source ?? job.source
        guard source.key == job.source.key,source.kind == job.source.kind,source.accountID == job.source.accountID,source.identity == job.source.identity,source.chatID == job.source.chatID else {throw ActionFailure.message("The captured source account does not match this Review request.")}
        guard action.id == payload.proposal.id,valid(),heartbeat.deviceAvailable,acceptedPreparedApproval(payload),job.scope.storage == reviewStorageIdentity else {throw ActionFailure.message("The captured action, account, source access or destination choices changed. Reopen this plan.")}
        if let known=inspectReviewAction(job,action) {return known}
        if let request=payload.nativeRequest,let captured=payload.nativeFields {
            let session=try await eventKit.creationSession(request)
            try Task.checkCancellation()
            guard valid(),heartbeat.deviceAvailable,session.sources.contains(where:{$0.id == captured.sourceID && $0.writable}) else {throw ActionFailure.message("The selected Calendar/list is no longer available or this request stopped.")}
            var edited=captured;edited.itemID=session.item.itemID;edited.occurrenceID=session.item.occurrenceID;edited.modified=session.item.modified;edited.writable=session.item.writable
            try await createNativeItem(request,baseline:session.item,edited:edited,dateSelected:true,additionalValidity:{valid() && self.heartbeat.deviceAvailable},acceptedSnapshot:payload)
        } else if let item=payload.project {
            try savePreparedProjectItem(item,proposal:payload.proposal,additionalValidity:{valid() && self.heartbeat.deviceAvailable},acceptedSnapshot:payload)
        } else {throw ActionFailure.message("No concrete creation was captured.")}
        guard let confirmed=inspectReviewAction(job,action),confirmed.phase == .saved else {throw ActionFailure.message("The save could not be confirmed. Inspect the original receipt before repeating it.")}
        return confirmed
    }
    func reviewWorkRuntime()->ReviewWorkRuntime {
        var runtime=ReviewWorkRuntime(scope:{self.reviewWorkScope()},ready:{self.reviewWorkReady},permits:{self.reviewPermits($0)},perform:{job,action,valid in try await self.performReviewAction(job,action,valid:valid)},inspect:{self.inspectReviewAction($0,$1)},converse:{job,valid in
            await withCheckedContinuation {continuation in
                var runtime=self.assistantRuntime()
                runtime.started={_ in}
                runtime.finished={outcome in
                    let classification=self.classifyAssistantOutcome(outcome)
                    continuation.resume(returning:.init(phase:classification.phase,message:classification.message,confirmedActions:classification.actions,error:classification.error))
                }
                let accepted=self.assistant.sendReview(runtime:runtime,conversationID:job.conversationID,prompt:job.human,humanTurnID:job.humanTurnID,responseTurnID:job.responseTurnID,query:job.source.title+" "+job.human,sourceContext:String(decoding:(try? JSONEncoder().encode(job.source)) ?? Data(),as:UTF8.self),humanControl:job.humanControl == true,selectionContext:self.reviewSelectionContext(job),submitted:job.created,focusAreas:job.focusAreas.compactMap(LifeArea.init(rawValue:)),valid:{valid() && self.heartbeat.deviceAvailable})
                if !accepted {continuation.resume(returning:.init(phase:.failed,message:self.assistant.error ?? "The assistant is unavailable. Your Review reply is retained.",error:self.assistant.error))}
            }
        },cancelConversation:{self.assistant.cancel()},changed:{self.reviewJobChanged($0)})
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") {
            runtime.ready={!self.heartbeat.busy && !self.assistant.busy && !self.writing}
            runtime.converse={_,_ in .init(phase:.failed,message:"This source-free preview does not call the AI. Your reply remains in the fictional review.",error:"AI is disabled for this preview.")}
            runtime.perform={job,action,valid in
                let payload=try JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload)
                guard payload.nativeRequest == nil,payload.project != nil else {throw ActionFailure.message("Apple writes are disabled in this source-free preview.")}
                return try await self.performReviewAction(job,action,valid:valid)
            }
        }
        #endif
        return runtime
    }
    var reviewWorkReady:Bool {
        let needsInference=reviewWork.jobs(chatGPT.activeID).first(where:{$0.phase == .queued})?.mode != .approval
        return !heartbeat.busy && !assistant.busy && !chatGPT.busy && (!needsInference || (!chatGPT.usagePaused && chatGPT.inferenceVerified)) && !writing && !proactive.busy && !emailSummaries.busy && emailSummaries.feedback.activeID == nil && !briefings.busy && !memoryLearning.busy && !sourceLearning.busy && !nativeSourceLearning.busy && !memoryMaintenance.busy && !lifeOrganisation.busy && !projectPlacement.busy && heartbeat.deviceAvailable && !heartbeat.composerActive
    }
    func scheduleReviewWork() {
        guard reviewQueuePump == nil,reviewWork.readable else {return}
        reviewQueuePump=Task { @MainActor [weak self] in
            guard let self else {return}
            defer {self.reviewQueuePump=nil}
            while !Task.isCancelled,self.reviewWork.readable,(self.reviewWork.waiting(self.chatGPT.activeID)>0 || self.reviewWork.busy) {
                if self.reviewWork.isPaused(self.chatGPT.activeID),!self.reviewWork.busy {return}
                self.reviewWork.drive(self.reviewWorkRuntime())
                do {try await Task.sleep(for:.milliseconds(250))} catch {return}
            }
        }
    }
    func reviewSelectionContext(_ job:ReviewWorkJob)->String {
        guard job.selectionActive == true else {return ""}
        if job.actions.isEmpty {return "The currently displayed prepared plan has NO selected actions. Selection is draft context, never independent authority. Do not interpret a mere acknowledgement as approval of unselected proposals; ask which action the human wants. They may explicitly request another plan."}
        struct Selected:Encodable {var title:String;var destination:String;var date:DiscoveryProposedDate?;var taskDue:String?}
        let selected=job.actions.compactMap {action->Selected? in
            guard let payload=try? JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload) else {return nil}
            return .init(title:action.title,destination:action.destination,date:payload.proposal.proposedDate,taskDue:payload.project?.due)
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let json=(try? encoder.encode(selected)).map{String(decoding:$0,as:UTF8.self)} ?? "[]"
        return "Captured UI context: the human selected only these historical prepared proposals. Unselected earlier proposals are not included in an acknowledgement. This is the plan actually shown for this reply; selection alone never authorises a save. Resolve the current human request against it, checking current support before new advice. Selected proposals: "+json
    }
    private func jobsAwaitingAnswer(_ id:UUID)->Bool {reviewWork.jobs(chatGPT.activeID,conversation:id).dropLast().last?.phase == .needsAnswer && reviewWork.waiting(chatGPT.activeID) == 1}
    func submitReview(_ text:String,conversationID:UUID,actions:[ReviewWorkAction],focus:[LifeArea],humanControl:Bool=false,selectionActive:Bool=false)->Bool {
        guard let conversation=assistant.conversation(conversationID),let source=reviewSource(conversation),reviewPermits(source),ConversationRules.acceptsPrompt(text) else {return false}
        let approval=["yes","yes please","yep","go ahead","do that","ok","okay","add these","approve"].contains(text.trimmingCharacters(in:.whitespacesAndNewlines).lowercased().trimmingCharacters(in:CharacterSet(charactersIn:".! "))) || text.trimmingCharacters(in:.whitespacesAndNewlines) == "👍"
        let concreteApproval=approval && !actions.isEmpty
        if concreteApproval {
            guard !actions.isEmpty,actions.allSatisfy({action in (try? JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload)).map(acceptedPreparedApproval) == true}) else {reviewWork.error="Choose a current concrete action first, or ask below for the missing detail.";return false}
        }
        let job=ReviewWorkJob(conversationID:conversationID,scope:reviewWorkScope(),source:source,mode:concreteApproval ? .approval : .conversation,human:text,humanControl:humanControl ? true : nil,selectionActive:selectionActive ? true : nil,focusAreas:focus.map(\.rawValue),actions:actions)
        guard reviewWork.submit(job) else {return false}
        if jobsAwaitingAnswer(conversationID) {reviewWork.continueWaiting(chatGPT.activeID)}
        reviewJobChanged(job);scheduleReviewWork();return true
    }
}
