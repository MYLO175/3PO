import SwiftUI

struct AIActivityNavigation:Identifiable {var id=UUID();var registration:String;var widgetID:UUID;var projectID:UUID?}

@MainActor extension DashboardModel {
    func classifyAssistantOutcome(_ outcome:AssistantTurnOutcome)->(phase:ReviewWorkPhase,message:String,actions:Int,error:String?) {
        let phase=ReviewWorkPhase(rawValue:outcome.phase) ?? .failed
        let failures=outcome.errors.filter{!$0.isEmpty}
        let message=failures.isEmpty ? outcome.message : failures.joined(separator:" · ")
        return (phase,message,outcome.confirmedActions,failures.isEmpty ? nil : message)
    }
    func assistantActivityStarted(_ outcome:AssistantTurnOutcome) {
        guard AIActivityWork.includes(outcome.attemptedTools,confirmed:outcome.confirmedActions,unconfirmed:outcome.unconfirmedActions) else {return}
        let created=assistant.activityContext(outcome.conversationID)?.turnDates[outcome.humanTurnID] ?? .now
        _=aiActivity.upsert(.init(id:"action:"+outcome.responseTurnID.uuidString,registration:outcome.registration,kind:.action,state:.running,title:"3PO actions",message:AIActivityWork.running(AIActivityWork.descriptions[outcome.message] == nil ? outcome.attemptedTools : [outcome.message]),created:created,destination:.assistant(targetID:outcome.conversationID.uuidString)))
    }
    func heartbeatActivityStarted(_ registration:String,_ id:String,_ date:Date) {
        _=aiActivity.upsert(.init(id:"heartbeat:"+id,registration:registration,kind:.heartbeat,state:.running,title:"Heartbeat",message:"Preparing the heartbeat…",progress:0,created:date,destination:.heartbeat(targetID:id)))
    }
    func assistantActivityFinished(_ outcome:AssistantTurnOutcome) {
        guard AIActivityWork.includes(outcome.attemptedTools,confirmed:outcome.confirmedActions,unconfirmed:outcome.unconfirmedActions) else {return}
        let result=classifyAssistantOutcome(outcome)
        let state=AIActivityStatus(rawValue:result.phase.rawValue) ?? (result.phase == .completed ? .succeeded : .failed)
        let created=assistant.activityContext(outcome.conversationID)?.turnDates[outcome.humanTurnID] ?? .now
        let message=state == .succeeded ? AIActivityWork.completed(outcome.attemptedTools,receipts:outcome.receipts,confirmed:outcome.confirmedActions) : state == .uncertain ? "A save needs checking. "+(result.error ?? "Confirmed actions are retained; the unconfirmed action will not be repeated.") : result.message
        _=aiActivity.upsert(.init(id:"action:"+outcome.responseTurnID.uuidString,registration:outcome.registration,kind:.action,state:state,title:"3PO actions",message:message,created:created,finished:.now,destination:.assistant(targetID:outcome.conversationID.uuidString)))
    }
    func reviewJobChanged(_ job:ReviewWorkJob) {
        let state=AIActivityStatus(rawValue:job.phase.rawValue) ?? (job.phase == .completed ? .succeeded : .failed)
        let message=job.phase == .queued ? "Queued · "+job.source.title : job.phase == .running ? "Working on "+job.source.title : [job.message,job.error].compactMap{$0}.joined(separator:" · ")
        _=aiActivity.upsert(.init(id:"review:"+job.id.uuidString+":"+job.responseTurnID.uuidString,registration:job.scope.registration,kind:.review,state:state,title:job.source.title,message:message.isEmpty ? state.title : message,progress:job.mode == .approval && !job.actions.isEmpty ? Double(job.savedCount)/Double(job.actions.count) : nil,created:job.created,finished:job.finished,destination:.review(targetID:job.conversationID.uuidString)))
        if job.phase.isFinished,!reviewWork.busy {assistant.continueForegroundAfterReview(runtime:assistantRuntime())}
        if job.mode == .approval,job.phase.isFinished {
            _=assistant.appendReview(job.human,conversationID:job.conversationID,turnID:job.humanTurnID,human:true)
            _=assistant.appendReview(message,conversationID:job.conversationID,turnID:job.responseTurnID)
        }
    }
    func heartbeatActivityFinished(_ registration:String,_ run:PAReviewRun) {
        let failed=run.failure != nil || ["failed","interrupted","suspended","paused"].contains(run.phase)
        let state:AIActivityStatus=run.phase == "suspended" || run.phase == "interrupted" ? .interrupted : run.phase == "paused" ? .stopped : failed ? (run.briefUpdated == true ? .partial : .failed) : .succeeded
        let message=[run.summary,run.failure].compactMap{$0}.joined(separator:" · ")
        _=aiActivity.upsert(.init(id:"heartbeat:"+run.id,registration:registration,kind:.heartbeat,state:state,title:"Heartbeat",message:message,progress:state == .succeeded ? 1 : nil,created:run.started,finished:run.finished,destination:.heartbeat(targetID:run.id)))
        scheduleReviewWork()
    }
    var currentAIActivity:AIActivityRecord? {
        let registration=chatGPT.activeID
        if let id=reviewWork.activeID,let job=reviewWork.job(id),job.scope.registration == registration,reviewPermits(job.source) {
            let message=job.mode == .approval ? "Saving actions · \(job.savedCount) of \(job.actions.count)" : assistant.toolStatus.isEmpty ? "Thinking about "+job.source.title : assistant.toolStatus
            return .init(id:"review:"+job.id.uuidString+":"+job.responseTurnID.uuidString,registration:registration,kind:.review,state:.running,title:job.source.title,message:message,progress:job.mode == .approval && !job.actions.isEmpty ? Double(job.savedCount)/Double(job.actions.count) : nil,created:job.created,destination:.review(targetID:job.conversationID.uuidString))
        }
        if heartbeat.busy,heartbeat.activeRegistration == registration,let run=heartbeat.state.accounts[registration]?.reviews?.last,let id=heartbeat.ownedRunID {
            return .init(id:"heartbeat:"+id,registration:registration,kind:.heartbeat,state:.running,title:"Heartbeat",message:heartbeat.progress?.stage ?? heartbeat.status,progress:heartbeat.progress.map{Double($0.percentage)/100},created:run.started,destination:.heartbeat(targetID:id))
        }
        if assistant.busy,let id=assistant.requestConversationID,let turn=assistant.requestTurnID,let context=assistant.activityContext(id),context.reviewKey == nil,let active=aiActivity.records(registration).first(where:{$0.id == "action:"+turn.uuidString && $0.state == .running}) {
            return active
        }
        if let job=emailSummaries.feedback.items(registration).first(where:{$0.state == .learning || $0.state == .saving}),reviewPermits(.init(key:"mail:"+job.messageID,title:job.about,kind:"mail",accountID:job.accountID,messageID:job.messageID)) {
            return .init(id:"feedback:"+job.id.uuidString+(job.activityAttemptID.map{":"+$0.uuidString} ?? ""),registration:registration,kind:.feedback,state:.running,title:"Review feedback",message:job.state == .saving ? "Saving your feedback…" : "Interpreting your feedback…",created:job.created,destination:.feedback(targetID:job.id.uuidString))
        }
        return nil
    }
    func syncFeedbackActivity() {
        for job in emailSummaries.feedback.items(chatGPT.activeID) {
            let status:AIActivityStatus
            switch job.state {case .queued:status = .queued;case .learning,.saving:status = .running;case .saved:status = .succeeded;case .failed:status = .failed;case .interrupted:status = .interrupted;case .stopped:status = .stopped}
            let message=job.error ?? (status == .succeeded ? "Your feedback was saved" : status == .queued ? "Feedback queued for the next heartbeat" : "Working on your feedback…")
            _=aiActivity.upsert(.init(id:"feedback:"+job.id.uuidString+(job.activityAttemptID.map{":"+$0.uuidString} ?? ""),registration:job.registration,kind:.feedback,state:status,title:job.about.isEmpty ? "Review feedback" : job.about,message:message,created:job.created,destination:.feedback(targetID:job.id.uuidString)))
        }
    }
    func reviewCompletedActions(_ source:ReviewWorkSource)->Int {
        guard reviewPermits(source) else {return 0}
        let saved=Set(proactive.state.records.filter{$0.registration == chatGPT.activeID && reviewSource($0).key == source.key && reviewDiscoveryCompleted($0)}.map(\.id))
        let work=reviewWork.jobs(chatGPT.activeID).filter{$0.source.key == source.key}
        return saved.union(work.flatMap{$0.actions.filter{$0.phase == .saved}.map(\.id)}).count+work.filter{$0.mode == .conversation}.reduce(0){$0+$1.savedCount}
    }
    func openReviewSource(_ message:MailMessage) {
        let records=proactive.state.records.filter{$0.registration == chatGPT.activeID && $0.mailID == message.id && $0.sourceKind != "whatsapp"}
        if !records.isEmpty {openReviewConversation(records)}
    }
    func activityVisible(_ record:AIActivityRecord)->Bool {
        guard record.registration == chatGPT.activeID else {return false}
        if record.kind == .chat {
            guard record.id.hasPrefix("chat:"),let turn=UUID(uuidString:String(record.id.dropFirst(5))),case let .assistant(id)=record.destination,let id,let conversation=UUID(uuidString:id),let context=assistant.activityContext(conversation) else {return false}
            return AIActivityWork.includes(context.attemptedTools[turn] ?? [])
        }
        if case let .review(id)=record.destination,let id,let uuid=UUID(uuidString:id) {
            guard let context=assistant.activityContext(uuid),let key=context.reviewKey else {return false}
            return reviewPermits(.init(key:key,title:context.title,kind:context.reviewSourceKind ?? "mail",accountID:context.reviewAccountID,messageID:context.reviewMessageID,identity:context.reviewSourceIdentity,chatID:context.reviewSourceChatID))
        }
        if case let .feedback(id)=record.destination,let id,let uuid=UUID(uuidString:id),let job=emailSummaries.feedback.records.first(where:{$0.id == uuid && $0.registration == chatGPT.activeID}) {return reviewPermits(.init(key:"mail:"+job.messageID,title:job.about,kind:"mail",accountID:job.accountID,messageID:job.messageID))}
        return record.registration == chatGPT.activeID
    }
    func relatedActivityDestinations(_ record:AIActivityRecord)->[AIActivityDestination] {
        guard record.kind == .review,record.id.hasPrefix("review:"),let id=UUID(uuidString:String(record.id.dropFirst(7).prefix(36))),let job=reviewWork.job(id),job.scope.registration == chatGPT.activeID,reviewPermits(job.source) else {return []}
        var destinations:[AIActivityDestination]=[]
        for action in job.actions where action.phase == .saved || action.phase == .uncertain {
            guard let payload=try? JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload) else {continue}
            let destination:AIActivityDestination
            if let item=payload.project {destination = .project(targetID:item.parentID?.uuidString ?? item.id.uuidString)}
            else if payload.nativeRequest?.kind == .event {destination = .calendar(targetID:action.itemID)}
            else {destination = .reminders(targetID:action.itemID)}
            if !destinations.contains(where:{$0.title == destination.title}) {destinations.append(destination)}
        }
        return destinations
    }
    func openAIActivityDestination(_ destination:AIActivityDestination) {
        switch destination {
        case .review(let id): if let id,let uuid=UUID(uuidString:id),reviewConversationAvailable(uuid) {reviewPresentation = .init(id:uuid)}
        case .assistant: openAssistantComposer()
        case .heartbeat,.feedback:showingAIHeartbeat=true
        case .project(let id):showActivityWidget(.projects,project:id.flatMap(UUID.init(uuidString:)))
        case .calendar:showActivityWidget(.calendar)
        case .reminders:showActivityWidget(.reminders)
        }
    }
    func showActivityWidget(_ kind:WidgetKind,project:UUID?=nil) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox"),[WidgetKind.calendar,.reminders].contains(kind) {return}
        #endif
        if let page=workspace.state.pages.first(where:{$0.widgets.contains{$0.kind == kind}}) {workspace.select(page.id)}
        else {workspace.addPage(kind.title);workspace.addWidget(kind);if let widget=workspace.selected.widgets.first {workspace.fullPage(widget)}}
        if let widget=workspace.selected.widgets.first(where:{$0.kind == kind}) {activityNavigation = .init(registration:chatGPT.activeID,widgetID:widget.id,projectID:project)}
    }
}
private extension ReviewWorkPhase {var isFinished:Bool {self != .running && self != .queued}}

#if DEBUG
@MainActor enum AIActivityWorkPreview {
    static func seed(_ model:DashboardModel) {
        let registration=model.chatGPT.activeID,conversation=model.assistant.openPA() ?? UUID()
        _=model.aiActivity.upsert(.init(id:"chat:"+UUID().uuidString,registration:registration,kind:.chat,state:.succeeded,title:"3PO chat",message:"Hello! How can I help?",destination:.assistant(targetID:conversation.uuidString)))
        model.assistantActivityFinished(.init(registration:registration,conversationID:conversation,humanTurnID:UUID(),responseTurnID:UUID(),phase:"completed",message:"This ordinary greeting must stay out of activity",receipts:[],errors:[]))
        model.assistantActivityFinished(.init(registration:registration,conversationID:conversation,humanTurnID:UUID(),responseTurnID:UUID(),phase:"completed",message:"This general chat prose must not replace the action receipt",receipts:["Added two dated project tasks"],errors:[],confirmedActions:2,attemptedTools:["create_life_items"]))
        model.assistantActivityFinished(.init(registration:registration,conversationID:conversation,humanTurnID:UUID(),responseTurnID:UUID(),phase:"failed",message:"General reply prose",receipts:[],errors:["The requested Calendar update failed. No event was saved."],attemptedTools:["change_calendar"]))
        precondition(model.aiActivity.state.records.count == 3,"The greeting creates no new activity; legacy output is retained")
    }
}
#endif

/// Fine-grained observation keeps progress updates out of the dashboard tile tree.
struct DashboardAIActivityPill:View {
    var model:DashboardModel
    var palette:WorkspacePalette
    var openChat:()->Void
    var body:some View {
        AIActivityPill(store:model.aiActivity,registration:model.chatGPT.activeID,current:model.currentAIActivity,palette:palette,openChat:openChat,openDestination:model.openAIActivityDestination,isVisible:model.activityVisible,relatedDestinations:model.relatedActivityDestinations)
            .task {model.syncFeedbackActivity()}
            .onChange(of:model.chatGPT.activeID) {model.syncFeedbackActivity();model.scheduleReviewWork()}
            .onChange(of:model.emailSummaries.feedback.records) {model.syncFeedbackActivity()}
    }
}
