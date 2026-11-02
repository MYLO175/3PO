import SwiftUI
import AppKit

struct ReviewInboxEmailCard:Identifiable {
    var message:MailMessage
    var summary:EmailSummary
    var discoveries:[PADiscovery]
    var handling:EmailHandling?
    var needsReview:Bool
    var id:String {message.id}
}
struct ReviewInboxProjection {
    var questions:[BriefingQuestion]
    var learningQuestions:[PALearningQuestion]
    var discoveries:[PADiscovery]
    var emails:[(MailMessage,EmailSummary)]
    var highlights:[(MailMessage,EmailSummary)]
    var emailCards:[ReviewInboxEmailCard]
    var standaloneDiscoveries:[PADiscovery]
    var handled:[(MailMessage,EmailSummary,EmailHandling)]
    var resolved:[(MailMessage,EmailSummary,EmailResolution)]
    var pending:[PAQueuedRequest]
    var pendingCount:Int
    var contextQuestions: [ContextProjectQuestion] = []
    var expiresAt: Date? = nil
}
extension DashboardModel {
    func reviewCreationClaim(_ item:PADiscovery)->NativeCreationClaim? {
        guard nativeCreations.readable,let id=UUID(uuidString:item.id) else {return nil}
        return nativeCreations.state.claims[item.registration+":"+id.uuidString]
    }
    func reviewDiscoveryCompleted(_ item:PADiscovery)->Bool {
        if item.nativeTarget != nil {return item.reviewState == "approved"}
        if ["project","projectTask"].contains(item.kind) {return !assistant.projects.readOnly && assistant.projects.receipt("project-suggestion:"+item.id,registration:item.registration) != nil}
        return reviewCreationClaim(item)?.receipt != nil
    }
    var reviewInbox:ReviewInboxProjection {preparedReview.value(self)}
    var reviewInboxPendingCount:Int {preparedReview.value(self).pendingCount}

}
struct ReviewInboxBadge:View {
    var count:Int
    var body:some View {
        if count > 0 {Text(count > 99 ? "99+" : String(count)).font(.system(size:10,weight:.semibold)).monospacedDigit().foregroundStyle(.white).padding(.horizontal,5).frame(minWidth:17,minHeight:17).background(Color.red,in:Capsule()).accessibilityLabel("\(count) items need review")}
    }
}
struct PATasksView: View {
    @Bindable var model: DashboardModel
    @AppStorage("settingsSelectedPage") private var settingsPage="General"
    @Environment(\.openSettings) private var openSettings
    @State private var sourceDiscovery:PADiscovery?
    @State private var showingActivity=false
    @State private var answering:BriefingQuestion?
    @State private var answer=""
    @State private var answerError:String?
    @State private var answeringLearning:PALearningQuestion?
    @State private var backgroundID:String?
    private func discoveryTitle(_ item:PADiscovery)->String? {
        item.sourceTitle ?? (item.needsDateClarification && item.sourceKind != "whatsapp" ? model.emailSummaries.records.first{$0.id == item.mailID && $0.registration == item.registration}?.message?.subject : nil)
    }
    private func dateLabel(_ date:Date?,hasTime:Bool,fallback:String)->String {date?.formatted(date:.abbreviated,time:hasTime ? .shortened : .omitted) ?? fallback}
    private var reviewBusy:Bool {model.heartbeat.busy || model.proactive.busy || model.emailSummaries.busy}
    private var reviewRetrying:Bool {
        model.heartbeat.state.accounts[model.inference.activeID]?.retryReason == "failure"
    }
    private var reviewStatus:String {
        let feedback=model.emailSummaries.feedback.items(model.inference.activeID).filter{model.emailSummaries.feedbackMemory($0,model:self.model) == nil}
        if feedback.contains(where:{$0.state == .learning || $0.state == .saving}) {return "Learning your feedback in the background…"}
        if feedback.contains(where:{$0.state == .queued}) {return "Feedback saved for the next heartbeat"}
        if reviewBusy {return "Reviewing your sources…"}
        if !model.heartbeat.readable {return "Review history unavailable. See Activity for details."}
        return model.heartbeat.scheduleStatus(model)
    }
    private func completedProposal(_ item:PADiscovery,source:ReviewWorkSource)->Bool {
        model.reviewDiscoveryCompleted(item) || item.reviewState == "approved" || model.reviewWork.jobs(item.registration).contains { job in
            job.source.key == source.key && job.actions.contains{$0.id == item.id && $0.phase == .saved}
        }
    }
    /// One Explore entry per source, on its last card; informational updates count too.
    private func lastSuggestionEntryIDs(_ values:[PADiscovery])->Set<String> {
        var last:[String:String]=[:]
        for item in values {last[item.registration+":"+model.reviewSource(item).key]=item.id}
        return Set(last.values)
    }
    /// Explore always opens the source's Review conversation. Without a saved suggestion it
    /// works as a quick chat about that source; the sparkles mark 3PO's own suggestions.
    @ViewBuilder private func exploreButton(suggested:Bool,completed:Int,open:@escaping ()->Void)->some View {
        Button(action:open) {
            if suggested {Label("Explore actions",systemImage:"sparkles")} else {Text("Explore actions")}
        }.help(suggested ? "See 3PO’s suggested actions, or ask it to do something else" : "Ask 3PO to do something with this")
        if completed > 0 {Label("\(completed) done",systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(.secondary).help("\(completed) action\(completed == 1 ? "" : "s") completed")}
    }
    private func discoveryExplore(_ item:PADiscovery)->(related:[PADiscovery],suggested:Bool,completed:Int) {
        let source=model.reviewSource(item)
        let current=model.reviewRecords(source)
        let related=current.isEmpty ? [item] : current
        let completed=model.reviewCompletedActions(source)
        let suggested=related.contains{$0.kind != "update" && ProactiveReviewRules.hasSuggestedAction($0) && !completedProposal($0,source:source)}
        return (related,suggested,completed > 0 ? completed : completedProposal(item,source:source) ? 1 : 0)
    }
    private func showsBackground(_ id:String)->Binding<Bool> {
        Binding(get:{backgroundID == id},set:{if !$0,backgroundID == id {backgroundID=nil}})
    }
    /// Background context opens from the card's right-click menu, so the card itself keeps
    /// to its title, source line and explanation.
    private func backgroundPanel<Content:View>(_ title:String="Background context",@ViewBuilder _ content:()->Content)->some View {
        VStack(alignment:.leading,spacing:12) {
            Text(title).font(.headline)
            content()
        }.padding(16).frame(width:420,alignment:.leading).fixedSize(horizontal:false,vertical:true)
    }
    private func discoveryConnection(_ item:PADiscovery)->String? {item.proposedChange?.connection ?? item.proposedProjectTask?.connection}
    @ViewBuilder private func backgroundUpdate(_ item:PADiscovery,emailTitle:String)->some View {
        VStack(alignment:.leading,spacing:4) {
            if let title=discoveryTitle(item),title != emailTitle {Text(title).font(.callout.weight(.semibold))}
            Text(PAProse.display(item.message)).font(.callout).textSelection(.enabled)
            Button("Source evidence") {backgroundID=nil;sourceDiscovery=item}.buttonStyle(.link).font(.caption)
        }
    }
    private func discoveryCardTitle(_ item:PADiscovery,details:ReviewSourceDetails?)->String {
        item.proposedChange?.target.title ?? item.proposedRemoval?.target.title ?? discoveryTitle(item) ?? details?.title ?? details?.location ?? "Review suggestion"
    }
    @ViewBuilder private func discoveryCard(_ item:PADiscovery,showsActionEntry:Bool)->some View {
        let details=model.preparedSourceDetails(item)
        let message=item.sourceKind == "whatsapp" ? nil : model.mailData.messages.first{$0.id == item.mailID}
        let explore=discoveryExplore(item)
        VStack(alignment:.leading,spacing:6) {
            Text(discoveryCardTitle(item,details:details)).font(.callout.weight(.semibold)).lineLimit(2)
            if let details {ReviewSourceLine(details:details)}
            Text(PAProse.display(item.message)).font(.callout)
            if let change=item.proposedChange {
                Label(dateLabel(change.target.start ?? change.target.due,hasTime:change.target.hasTime,fallback:"No date") + " → " + dateLabel(change.date(),hasTime:change.hasTime,fallback:change.newDate),systemImage:"calendar.badge.clock").font(.caption).foregroundStyle(.secondary)
            }
            if let removal=item.proposedRemoval {
                Label(dateLabel(removal.target.start,hasTime:removal.target.hasTime,fallback:"No date") + " · only this occurrence",systemImage:"calendar.badge.minus").font(.caption).foregroundStyle(.secondary)
            }
            if let project=item.proposedProjectTask {Label("Task in " + project.target.title,systemImage:"folder").font(.caption).foregroundStyle(.secondary)}
            if let date=item.proposedDate {Label(dateLabel(date.date(),hasTime:date.hasTime,fallback:date.start) + (date.end.map{" to " + dateLabel(date.date($0),hasTime:date.hasTime,fallback:$0)} ?? ""),systemImage:"calendar").font(.caption).foregroundStyle(.secondary)}
            if item.reviewState == "pending" || model.reviewCreationClaim(item).map({$0.receipt == nil}) == true {
                Label("Save needs checking; it will not be repeated",systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing:8) {
                if showsActionEntry {exploreButton(suggested:explore.suggested,completed:explore.completed) {model.openReviewConversation(explore.related)}}
                if let message {Button("View email") {model.select(message)}}
                ReviewFeedbackButton(model:model,topic:discoveryTitle(item) ?? item.message,email:model.preparedFeedbackEmail(item),isCurrent:{model.proactive.state.records.first(where:{$0.id == item.id}).map{ProactiveRules.reviewProjection($0) == item && model.proactive.preparedReviewAvailable($0,model:model)} == true})
                Spacer()
                Button("Dismiss") {model.proactive.dismiss(item,model:model)}.disabled(model.writing)
            }.controlSize(.small).padding(.top,4)
            if model.reviewApprovalErrorAccount == item.registration,model.reviewApprovalErrorID == item.id,let error=model.reviewApprovalError {Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
        }.taskCard()
        // Inside a dashboard tile the widget's own menu takes every right-click not marked like this.
        .keepsOwnRightClickMenu()
        .contextMenu {
            if showsActionEntry {Button("Explore actions") {model.openReviewConversation(explore.related)}}
            if let message {Button("View email") {model.select(message)}}
            if discoveryConnection(item) != nil {Button("Background context") {backgroundID=item.id}}
            Button("Source evidence") {sourceDiscovery=item}
            Divider()
            Button("Dismiss") {model.proactive.dismiss(item,model:model)}.disabled(model.writing)
        }
        .popover(isPresented:showsBackground(item.id),arrowEdge:.bottom) {
            backgroundPanel {Text(PAProse.display(discoveryConnection(item) ?? "")).font(.callout).textSelection(.enabled)}
        }
    }
    @State private var showingRelevance=false
    @Environment(\.widgetLayout) private var layout
    /// Everything waiting, one line each: questions open their answer, emails their message, suggestions their evidence.
    /// The second line is the full card's info line, never a status label.
    private func glanceItems(_ inbox:ReviewInboxProjection)->[ReviewGlanceItem] {
        inbox.questions.map {item in
            let sources=item.sourceIDs.compactMap{id in item.snapshot.sources.first{$0.id == id}}
            return ReviewGlanceItem(id:"q:\(item.id)",label:sources.isEmpty ? "Your answer would help 3PO" : "Based on " + sources.map(\.label).joined(separator:", "),title:PAProse.display(item.question)) {answering=item;answer="";answerError=nil}
        }
        + inbox.learningQuestions.map {item in ReviewGlanceItem(id:"l:\(item.id)",label:"Getting to know you",title:PAProse.display(item.text)) {answeringLearning=item;answer="";answerError=nil}}
        + inbox.standaloneDiscoveries.map {item in
            let details=model.preparedSourceDetails(item)
            return ReviewGlanceItem(id:"d:"+item.id,label:details.map{ReviewSourceLine.text($0)} ?? PAProse.display(item.message),title:discoveryCardTitle(item,details:details)) {sourceDiscovery=item}
        }
        + inbox.emailCards.map {card in ReviewGlanceItem(id:"e:"+card.id,label:ReviewSourceLine.text(.email(card.message)),title:card.message.subject.isEmpty ? "(No subject)" : card.message.subject) {model.select(card.message)}}
        + inbox.pending.map {item in ReviewGlanceItem(id:"p:\(item.id)",label:item.state == .needsAnswer ? "Your answer needed" : item.state == .completed ? "PA work ready" : "Delegated work",title:item.prompt,open:nil)}
    }
    private func glance(_ inbox:ReviewInboxProjection)->some View {
        let items=glanceItems(inbox)
        return VStack(alignment:.leading,spacing:layout == .small ? 8 : 10) {
            if items.isEmpty {ReviewEmptyState(compact:true)} else {
                HStack(alignment:.top,spacing:16) {
                    if layout == .medium {GlanceCount(value:inbox.pendingCount,label:"to review").frame(width:78,alignment:.leading)}
                    GlanceRows(items:items,rowHeight:34,empty:"Nothing waiting for review.",scrolls:layout == .tall) {item in
                        Button {item.open?()} label: {
                            VStack(alignment:.leading,spacing:1) {
                                Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                                Text(item.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(item.open == nil).help(item.title)
                    }
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
    /// The right-click menu, headed with when Review last checked or what it is doing now.
    @ViewBuilder private var menuItems: some View {
        Button("Run heartbeat") { model.heartbeat.check(model,manual:true) }.disabled(model.heartbeat.manualCheckBlockReason(model) != nil)
        Button("Review guidance…") { showingRelevance=true }
        Button("Background activity…") { showingActivity=true }
    }
    var body: some View {
        let inbox=model.reviewInbox
        return Group { if layout.compact {glance(inbox)} else {full(inbox)} }
        .widgetMenu("Review inbox",status:reviewStatus) { menuItems }
        .sheet(isPresented:$showingRelevance) {ReviewPolicyView(model:model)}
        .onChange(of:model.inference.activeID) {showingRelevance=false}
        .sheet(item:$answering) {question in
            VStack(alignment:.leading,spacing:16) {
                Text(question.question).font(.headline)
                TextEditor(text:$answer).frame(minHeight:100).font(.body)
                if let answerError {Text(answerError).font(.caption).foregroundStyle(.orange)}
                HStack {Button("Cancel") {answering=nil};Spacer();Button("Send answer") {
                    guard model.reviewInbox.questions.contains(where:{$0.id == question.id}) else {answerError="This question’s supporting context changed. Run a fresh heartbeat.";return}
                    let text="About your question “"+question.question+"”: "+answer.trimmingCharacters(in:.whitespacesAndNewlines)
                    if model.assistant.send(model:model,topicID:nil,prompt:text,focusAreas:[]) {
                        _ = model.briefings.resolveQuestion(question,model:model,answered:true);answering=nil
                    } else {answerError="Your PA is busy. Your answer is kept here; send it when ready."}
                }.disabled(answer.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.assistant.busy || model.inference.busy || model.writing || model.heartbeat.busy || ProcessInfo.processInfo.arguments.contains("--preview-review-inbox"))}
                Text("Your answer continues the PA conversation.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width:520)
        }
        .sheet(item:$answeringLearning) {question in
            VStack(alignment:.leading,spacing:16) {
                Text(question.text).font(.headline)
                TextEditor(text:$answer).frame(minHeight:100)
                if let answerError {Text(answerError).font(.caption).foregroundStyle(.orange)}
                HStack {Button("Cancel") {answeringLearning=nil};Spacer();Button("Send answer") {
                    guard model.reviewInbox.learningQuestions.contains(where:{$0.id == question.id}) else {answerError="This question is no longer available.";return}
                    if model.assistant.send(model:model,topicID:question.conversationID,prompt:"About your question “"+question.text+"”: "+answer.trimmingCharacters(in:.whitespacesAndNewlines),focusAreas:question.conversationID == nil ? [] : nil) {model.memoryLearning.answer(question);answeringLearning=nil}
                    else {answerError="Your PA is busy. Your answer is kept here."}
                }.disabled(answer.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.assistant.busy || model.inference.busy || model.writing || model.heartbeat.busy || ProcessInfo.processInfo.arguments.contains("--preview-review-inbox"))}
            }.padding(24).frame(width:520)
        }
        .sheet(item:$sourceDiscovery) { record in DiscoveryEvidenceView(record:record,model:model) }
        .sheet(isPresented:$showingActivity) {BackgroundActivityView(model:model)}
        .onChange(of:model.inference.activeID) { sourceDiscovery=nil;answering=nil;answeringLearning=nil;answer="";backgroundID=nil }
        .onChange(of:inbox.discoveries.map(\.id)) { if let sourceDiscovery,!inbox.discoveries.contains(where:{$0.id == sourceDiscovery.id}) { self.sourceDiscovery=nil } }
    }
    private func full(_ inbox:ReviewInboxProjection)->some View {
        let questions=inbox.questions,learningQuestions=inbox.learningQuestions,emailCards=inbox.emailCards,standaloneDiscoveries=inbox.standaloneDiscoveries,pending=inbox.pending
        let standaloneEntryIDs=lastSuggestionEntryIDs(standaloneDiscoveries)
        let limited=model.heartbeat.dailyCallLimit > 0 && model.heartbeat.state.accounts[model.inference.activeID]?.retryReason == "allowance"
        let nothingWaiting=emailCards.isEmpty && standaloneDiscoveries.isEmpty && pending.isEmpty && questions.isEmpty && learningQuestions.isEmpty && inbox.contextQuestions.isEmpty
        return VStack(alignment:.leading,spacing:12) {
            // The status line shows only when checks need attention; otherwise it heads the right-click menu.
            if reviewRetrying || limited {
                HStack(spacing:8) {
                    Text(reviewStatus).font(.caption).foregroundStyle(reviewRetrying ? Color.orange : Color.secondary)
                        .fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:0)
                    if limited { Button("Limit settings…") {settingsPage="Background";openSettings()}.buttonStyle(.borderless).font(.caption) }
                }
            }
            if nothingWaiting {ReviewEmptyState()} else {ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    if !questions.isEmpty || !learningQuestions.isEmpty || !inbox.contextQuestions.isEmpty {Text("Questions for you").font(.headline)}
                    ContextProjectQuestionsSection(model: model, questions: inbox.contextQuestions)
                    ForEach(questions) {item in
                        let sources=item.sourceIDs.compactMap{id in item.snapshot.sources.first{$0.id == id}}
                        VStack(alignment:.leading,spacing:6) {
                            Text(PAProse.display(item.question)).font(.callout.weight(.semibold))
                            Text(sources.isEmpty ? "Your answer would help 3PO" : "Based on " + sources.map(\.label).joined(separator:", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                .help(sources.map{$0.label + ($0.date.map{" · " + $0.formatted(date:.abbreviated,time:.shortened)} ?? "")}.joined(separator:"\n"))
                            HStack {Button("Answer") {answering=item;answer="";answerError=nil};Spacer();Button("Dismiss") {_ = model.briefings.resolveQuestion(item,model:model,answered:false)}}.controlSize(.small).padding(.top,4)
                        }.taskCard()
                    }
                    ForEach(learningQuestions) {item in
                        VStack(alignment:.leading,spacing:6) {
                            Text(PAProse.display(item.text)).font(.callout.weight(.semibold))
                            Text("Getting to know you").font(.caption).foregroundStyle(.secondary)
                            HStack {Button("Answer") {answeringLearning=item;answer="";answerError=nil};Spacer();Button("Dismiss") {model.memoryLearning.dismiss(item)}}.controlSize(.small).padding(.top,4)
                        }.taskCard().keepsOwnRightClickMenu()
                        .contextMenu {Button("Why 3PO is asking") {backgroundID="learning:"+item.id}}
                        .popover(isPresented:showsBackground("learning:"+item.id),arrowEdge:.bottom) {backgroundPanel("Why 3PO is asking") {Text(item.evidence).font(.callout).textSelection(.enabled)}}
                    }
                    if !standaloneDiscoveries.isEmpty { Text("From your background review").font(.headline) }
                    ForEach(standaloneDiscoveries) { item in
                        discoveryCard(item,showsActionEntry:standaloneEntryIDs.contains(item.id))
                    }
                    if !emailCards.isEmpty { Text("Emails to review").font(.headline) }
                    ForEach(emailCards) { card in
                        let message=card.message,summary=card.summary
                        let completedSource=ReviewWorkSource(key:"mail:"+message.id,title:message.subject,kind:"mail",accountID:message.accountID,messageID:message.id)
                        let completedActions=model.reviewCompletedActions(completedSource)
                        let proposals=card.discoveries.filter{$0.kind != "update"},updates=card.discoveries.filter{$0.kind == "update"}
                        let pendingProposals=proposals.filter{ProactiveReviewRules.hasSuggestedAction($0) && !completedProposal($0,source:completedSource)}
                        let hasSummaryDraft=summary.replyDraft.map{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty} == true && !proposals.contains{$0.replyDraft != nil} && !model.reviewSummaryDraftCompleted(message)
                        let hasBackground = !updates.isEmpty || summary.personalRelevance != nil || card.handling != nil || summary.keepInReview == true
                        let dismiss={model.emailSummaries.dismiss(message.id,model:model,expectedRegistration:summary.registration,expectedVersion:ReviewAcknowledgementRules.emailVersion(message,summary))}
                        VStack(alignment:.leading,spacing:6) {
                            Text(message.subject).font(.callout.weight(.semibold)).lineLimit(2)
                            ReviewSourceLine(details:.email(message))
                            Text(PAProse.display(summary.reason.isEmpty ? summary.summary : summary.reason)).font(.callout)
                            if summary.replyDraftEdited == true,summary.replyDraftCheckedBody != summary.bodyFingerprint {Text("Your saved reply draft is kept, but the email changed. Check it in Explore actions.").font(.caption).foregroundStyle(.orange)}
                            if proposals.contains(where:{$0.reviewState == "pending" || model.reviewCreationClaim($0).map({$0.receipt == nil}) == true}) {
                                Label("A save needs checking",systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                            }
                            HStack(spacing:8) {
                                exploreButton(suggested:!pendingProposals.isEmpty || hasSummaryDraft,completed:completedActions) {model.openReviewSource(message)}
                                Button("View email") {model.select(message)}
                                ReviewFeedbackButton(model:model,topic:message.subject,email:.init(message:message,summary:summary),isCurrent:{model.emailSummaries.feedbackSourceCurrent(message,summary:summary,model:model)})
                                Spacer()
                                Button("Dismiss",action:dismiss)
                            }.controlSize(.small).padding(.top,4)
                        }.taskCard().keepsOwnRightClickMenu()
                        .contextMenu {
                            Button("Explore actions") {model.openReviewSource(message)}
                            Button("View email") {model.select(message)}
                            if hasBackground {Button("Background context") {backgroundID="mail:"+message.id}}
                            if card.handling != nil {Button("Keep in review") {model.emailSummaries.keepForReview(summary.id,model:model)}}
                            if summary.keepInReview == true {Button("Use inferred status") {model.emailSummaries.keepForReview(summary.id,model:model,keep:false)}}
                            Divider()
                            Button("Dismiss",action:dismiss)
                        }
                        .popover(isPresented:showsBackground("mail:"+message.id),arrowEdge:.bottom) {
                            backgroundPanel {
                                if let relevance=summary.personalRelevance {Label(relevance.reason,systemImage:"person.crop.circle.badge.checkmark").font(.callout)}
                                if let handling=card.handling {
                                    Text("Inferred connection to “"+handling.native.title+"” · "+handling.reason).font(.callout).textSelection(.enabled)
                                    Button("Keep in review") {backgroundID=nil;model.emailSummaries.keepForReview(summary.id,model:model)}.controlSize(.small)
                                }
                                if summary.keepInReview == true {HStack {Text("Kept in review by you").font(.callout);Button("Use inferred status") {backgroundID=nil;model.emailSummaries.keepForReview(summary.id,model:model,keep:false)}.controlSize(.small)}}
                                ForEach(updates) {item in backgroundUpdate(item,emailTitle:message.subject)}
                            }
                        }
                    }
                    if !pending.isEmpty { Text("Delegated work").font(.headline) }
                    ForEach(pending) { item in
                        VStack(alignment:.leading,spacing:6) {
                            Label(item.state == .completed ? "PA work ready" : item.state == .needsAnswer ? "Your answer needed" : item.state == .running ? "PA working" : item.state == .interrupted ? "Check interrupted work" : "Queued for your PA",systemImage:"bubble.left.and.bubble.right").font(.caption).foregroundStyle(.secondary)
                            Text(item.prompt).lineLimit(3)
                            if let result=item.result { DisclosureGroup("Result") { Text(result).textSelection(.enabled) } }
                            if let focus=item.focusAreas,!focus.isEmpty { Text(focus.map(\.title).joined(separator:" · ")).font(.caption2).foregroundStyle(.secondary) }
                            if item.state != .running { HStack { if item.state == .waiting { Button("Continue queue") { model.assistant.resumeQueue(model:model) }.disabled(model.assistant.busy || model.inference.busy || model.inference.usagePaused) }; Button("Remove") { model.assistant.discardQueued(item.id) } }.controlSize(.small) }
                        }.taskCard()
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.scrollEdgeFade()}
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
}
/// Nothing waiting: a large tick and one line, centred in the tile.
private struct ReviewEmptyState:View {
    var compact=false
    @Environment(\.workspacePalette) private var palette
    var body:some View {
        VStack(spacing:compact ? 8 : 14) {
            Image(systemName:"checkmark.circle").font(.system(size:compact ? 30 : 56,weight:.light)).foregroundStyle(palette[.accent])
            Text("Nothing waiting for review").font(compact ? .callout.weight(.medium) : .title3.weight(.semibold)).foregroundStyle(palette[.text].opacity(0.75))
        }.multilineTextAlignment(.center).frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityElement(children:.combine)
    }
}
private struct ReviewGlanceItem:Identifiable {
    var id:String
    var label:String
    var title:String
    var open:(()->Void)?
}
private extension View {
    func taskCard()->some View { padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12)) }
}

struct CalendarRemovalReviewSheet:View {
    var model:DashboardModel
    var session:CalendarRemovalReviewSession
    @Environment(\.dismiss) private var dismiss
    @State private var saving=false
    @State private var error:String?
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Label("Remove this Calendar occurrence?",systemImage:"calendar.badge.minus").font(.title2.weight(.semibold))
            Text(session.baseline.title).font(.headline)
            Text(session.baseline.start.formatted(date:.complete,time:session.baseline.allDay ? .omitted : .shortened))
            Text("This event repeats. Approval removes only the occurrence shown above. Other occurrences stay in Calendar.").font(.callout)
            Text(PAProse.display(session.record.message)).textSelection(.enabled)
            DisclosureGroup("Source evidence") {Text(session.record.evidence).font(.callout).textSelection(.enabled)}
            Text("Removal cannot be undone in 3PO.").font(.caption).foregroundStyle(.secondary)
            if let error {Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)}
            HStack {
                Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction).disabled(saving)
                Spacer()
                Button(saving ? "Approving…" : "Approve this occurrence") {Task {
                    saving=true;defer {saving=false}
                    do {try await model.saveCalendarRemoval(session.record,baseline:session.baseline,selectedModel:session.selectedModel,sourceScope:session.sourceScope,occurrenceConfirmed:true);dismiss()}
                    catch {self.error=error.localizedDescription}
                }}.disabled(saving || model.writing || model.assistant.busy || !model.proactive.canReview(session.record.id,model:model))
            }
        }.padding(24).frame(width:520).interactiveDismissDisabled(saving)
    }
}

struct ReviewHistoryView:View {
    @Bindable var model:DashboardModel
    var body:some View {
        let handled=model.reviewInbox.handled,resolved=model.reviewInbox.resolved
        let retired=model.proactive.state.records.filter{$0.registration == model.inference.activeID && $0.retiredAt != nil}
        DisclosureGroup("Review history") {
            VStack(alignment:.leading,spacing:12) {
                Text("Saved background decisions that an action was planned or addressed. A later heartbeat can reconsider them. Keep in review restores the email.").font(.caption).foregroundStyle(.secondary)
                ForEach(handled,id:\.0.id) {message,summary,value in
                    VStack(alignment:.leading,spacing:6) {Text(message.subject).font(.callout.weight(.semibold));Text(PAProse.display(value.reason)).font(.caption);Text(value.native.title).font(.caption).foregroundStyle(.secondary);HStack {Button("View email") {model.select(message)};Button("Keep in review") {model.emailSummaries.keepForReview(summary.id,model:model)}}.controlSize(.small)}.taskCard()
                }
                ForEach(resolved,id:\.0.id) {message,summary,value in
                    VStack(alignment:.leading,spacing:6) {Text(message.subject).font(.callout.weight(.semibold));Text(PAProse.display(value.reason)).font(.caption);DisclosureGroup("Evidence") {Text("Earlier request: “"+value.requestQuote+"”");Text("Confirmation: “"+value.confirmation.quote+"”");if let confirmation=model.emailSummaries.sourceAssessments(model).first(where:{$0.0.id == value.confirmation.messageID})?.0 {Button("View confirmation") {model.select(confirmation)}}}.font(.caption);HStack {Button("View email") {model.select(message)};Button("Keep in review") {model.emailSummaries.keepForReview(summary.id,model:model)}}.controlSize(.small)}.taskCard()
                }
                ForEach(retired) {item in
                    VStack(alignment:.leading,spacing:6) {Text(item.sourceTitle ?? item.message).font(.callout.weight(.semibold));Text(item.retirementReason ?? "Retired during a heartbeat.").font(.caption);Button("Keep in review") {model.proactive.restoreRetired(item,model:model)}.controlSize(.small);if let date=item.retiredAt {Text("Reviewed " + date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)}}.taskCard()
                }
                if handled.isEmpty && resolved.isEmpty && retired.isEmpty {Text("No saved addressed items.").font(.caption).foregroundStyle(.secondary)}
                Text("Dismiss acknowledges the displayed concern. Undo restores it. Feedback is saved separately in PA memory.").font(.caption).foregroundStyle(.secondary)
            }.padding(.top,8)
        }.padding(12)
    }
}
