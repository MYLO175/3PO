import SwiftUI
import AppKit
struct PATasksView: View {
    @Bindable var model: DashboardModel
    @State private var reviewingProject:PADiscovery?
    @State private var editing: EmailSummary?
    @State private var draft=""
    @State private var copied=false
    @State private var draftSaved=false
    @State private var sourceDiscovery:PADiscovery?
    @State private var showingActivity=false
    @State private var answering:BriefingQuestion?
    @State private var answer=""
    @State private var answerError:String?
    @State private var answeringLearning:PALearningQuestion?
    private var learningQuestions:[PALearningQuestion] {(model.memoryLearning.state.questions ?? []).filter{model.memoryLearning.visible($0,assistant:model.assistant)}}
    private var questions:[BriefingQuestion] {model.briefings.pendingQuestions(model)}
    private var emails:[(MailMessage,EmailSummary)] {
        model.emailSummaries.highlights(model).filter { EmailHighlightRules.needsAction($0.1,replied:$0.0.replied) && model.emailSummaries.handling($0.1,message:$0.0,model:model) == nil }.map { message,summary in
            var value=summary
            if message.replied || EmailSummary.fingerprint(message) != summary.fingerprint { value.replyDraft=nil }
            return (message,value)
        }
    }
    private var handled:[(MailMessage,EmailSummary,EmailHandling)] {
        model.emailSummaries.highlights(model).compactMap {message,summary in model.emailSummaries.handling(summary,message:message,model:model).map{(message,summary,$0)} }
    }
    private var discoveries:[PADiscovery] { model.proactive.state.records.filter { model.proactive.visible($0,model:model) }.map(ProactiveRules.reviewProjection) }
    private var pending:[PAQueuedRequest] { PAQueueRules.handoffs(model.assistant.queue.items,registration:model.chatGPT.activeID) }
    private func discoveryTitle(_ item:PADiscovery)->String? {
        item.sourceTitle ?? (item.needsDateClarification && item.sourceKind != "whatsapp" ? model.emailSummaries.highlights(model).first{$0.0.id == item.mailID}?.0.subject : nil)
    }
    private func dateLabel(_ date:Date?,hasTime:Bool,fallback:String)->String {date?.formatted(date:.abbreviated,time:hasTime ? .shortened : .omitted) ?? fallback}
    private var reviewBusy:Bool {model.heartbeat.busy || model.proactive.busy || model.emailSummaries.busy}
    private var reviewRetrying:Bool {
        model.heartbeat.state.accounts[model.chatGPT.activeID]?.retryReason == "failure"
    }
    private var reviewStatus:String {
        if reviewBusy {return "Reviewing your sources…"}
        if !model.heartbeat.readable {return "Review history unavailable. See Activity for details."}
        return model.heartbeat.scheduleStatus(model)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label("Review inbox",systemImage:"tray.full").font(.title3.weight(.semibold))
                Spacer()
                Button { showingActivity=true } label:{Image(systemName:"clock.arrow.circlepath")}
                    .buttonStyle(.borderless).help("Background activity and details").accessibilityLabel("Background activity")
                Button { model.heartbeat.check(model,manual:true) } label:{Image(systemName:"waveform.path.ecg")}
                    .buttonStyle(.borderless).help(model.heartbeat.manualCheckHelp(model)).accessibilityLabel("Run heartbeat")
                    .disabled(model.heartbeat.manualCheckBlockReason(model) != nil)
            }
            HStack(spacing:8) {
                if reviewBusy {ProgressView().controlSize(.mini)}
                Text(reviewStatus).font(.caption).foregroundStyle(reviewRetrying ? Color.orange : Color.secondary)
                    .fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:0)
            }
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    if !questions.isEmpty || !learningQuestions.isEmpty {Text("Questions for you").font(.headline)}
                    ForEach(questions) {item in
                        VStack(alignment:.leading,spacing:8) {
                            Label("Your answer would help",systemImage:"questionmark.bubble").font(.caption).foregroundStyle(.secondary)
                            Text(item.question).font(.callout).textSelection(.enabled)
                            DisclosureGroup("Context") {ForEach(item.sourceIDs,id:\.self) {id in if let source=item.snapshot.sources.first(where:{$0.id == id}) {Text(source.label + (source.date.map{" · " + $0.formatted(date:.abbreviated,time:.shortened)} ?? "")).font(.caption).textSelection(.enabled)}}}
                            HStack {Button("Answer") {answering=item;answer="";answerError=nil};Spacer();Button("Dismiss") {_ = model.briefings.resolveQuestion(item,model:model,answered:false)}}.controlSize(.small)
                        }.taskCard()
                    }
                    ForEach(learningQuestions) {item in
                        VStack(alignment:.leading,spacing:8) {
                            Label("Getting to know you",systemImage:"questionmark.bubble").font(.caption).foregroundStyle(.secondary)
                            Text(item.text).font(.callout)
                            DisclosureGroup("Why I’m asking") {Text(item.evidence).font(.caption).textSelection(.enabled)}
                            HStack {Button("Answer") {answeringLearning=item;answer="";answerError=nil};Spacer();Button("Dismiss") {model.memoryLearning.dismiss(item)}}.controlSize(.small)
                        }.taskCard()
                    }
                    if !discoveries.isEmpty { Text("From your background review").font(.headline) }
                    ForEach(discoveries) { item in
                        VStack(alignment:.leading,spacing:8) {
                            if let change=item.proposedChange {
                                Label("Needs approval · " + (change.target.kind == "event" ? "Calendar" : "Reminders"),systemImage:"calendar.badge.clock").font(.caption.weight(.semibold))
                                Text(change.target.title).font(.callout.weight(.semibold))
                                Text(dateLabel(change.target.start ?? change.target.due,hasTime:change.target.hasTime,fallback:"No date") + " → " + dateLabel(change.date(),hasTime:change.hasTime,fallback:change.newDate)).font(.callout).textSelection(.enabled)
                                Text("Inferred connection · " + change.connection).font(.caption).foregroundStyle(.secondary)
                            }
                            Label(item.kind == "reply" ? "Reply draft" : item.kind == "update" ? "Update" : item.kind == "change" ? "Date change" : "Missing plan",systemImage:item.kind == "calendar" ? "calendar.badge.plus" : "checklist").font(.caption).foregroundStyle(.secondary)
                            if let title=discoveryTitle(item) { Text(title).font(.callout.weight(.semibold)) }
                            Text(item.message).textSelection(.enabled)
                            if let details=model.proactive.sourceDetails(item,model:model) {ReviewSourceLabel(details:details,showsTitle:true)}
                            if let reply=item.replyDraft {
                                Text(reply).font(.callout).textSelection(.enabled).padding(10).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
                                Text("Check the details before using this draft.").font(.caption2).foregroundStyle(.secondary)
                                Button("Copy draft") {NSPasteboard.general.clearContents();NSPasteboard.general.setString(reply,forType:.string)}.controlSize(.small)
                            }
                            Button("Source evidence") { sourceDiscovery=item }.buttonStyle(.borderless).font(.caption)
                            HStack { if item.kind == "project" { if model.assistant.projects.receipt("project-suggestion:"+item.id,registration:item.registration) == nil { Button("Review space…") { reviewingProject=item } } else { Label("Created",systemImage:"checkmark.circle") } } else if !["update","reply"].contains(item.kind) {
                                if item.reviewState == "pending" { Text("Save needs checking in Apple; it will not be repeated.").font(.caption).foregroundStyle(.orange) }
                                else if item.proposedChange != nil {
                                    Button(model.approvingDiscoveryID == item.id ? "Approving…" : "Approve") { Task {await model.approveDiscovery(item)} }.disabled(!model.proactive.canReview(item.id,model:model) || model.writing || model.assistant.busy)
                                    Button("View/edit") {model.reviewDiscovery(item)}.disabled(!model.proactive.canReview(item.id,model:model) || model.writing)
                                } else { Button("Review suggestion") { model.reviewDiscovery(item) }.disabled(!model.proactive.canReview(item.id,model:model) || model.writing) }
                            }; Spacer(); Button("Dismiss") { model.proactive.dismiss(item) }.disabled(model.writing) }.controlSize(.small)
                            if model.reviewApprovalErrorAccount == item.registration,model.reviewApprovalErrorID == item.id,let error=model.reviewApprovalError {Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
                        }.taskCard()
                    }
                    if !emails.isEmpty { Text("Email work").font(.headline) }
                    ForEach(emails,id:\.0.id) { message,summary in
                        VStack(alignment:.leading,spacing:8) {
                            Label(summary.replyDraft == nil ? "Needs attention" : "Reply draft ready",systemImage:summary.replyDraft == nil ? "checklist" : "pencil.line").font(.caption).foregroundStyle(.secondary)
                            Text(message.subject).font(.callout.weight(.semibold)).lineLimit(2)
                            ReviewSourceLabel(details:.email(message))
                            Text(summary.reason.isEmpty ? summary.summary : summary.reason).font(.callout).textSelection(.enabled)
                            if summary.keepInReview == true {HStack {Text("Kept in review by you").font(.caption).foregroundStyle(.secondary);Button("Allow planned status") {model.emailSummaries.keepForReview(summary.id,model:model,keep:false)}.buttonStyle(.borderless).font(.caption)}}
                            if let reply=summary.replyDraft {
                                VStack(alignment:.leading,spacing:5) {
                                    Text("Suggested reply").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    if summary.replyDraftEdited == true,summary.replyDraftCheckedBody != summary.bodyFingerprint {Text("Your saved draft is preserved, but the email changed. Review its details.").font(.caption).foregroundStyle(.orange)}
                                    Text(reply).font(.callout).textSelection(.enabled)
                                    Text("Check placeholders and details before using it.").font(.caption2).foregroundStyle(.secondary)
                                }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
                            }
                            if summary.replyDraft == nil,EmailReplyDraftRules.canReply(summary,message:message) {
                                Text(EmailReplyDraftRules.needsBackgroundDraft(summary,message:message) ? "Reply preparation pending" : "Check details before preparing a reply").font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                if let reply=summary.replyDraft { Button("Review draft") { editing=summary; draft=reply; copied=false; draftSaved=false } }
                                else if EmailReplyDraftRules.canReply(summary,message:message) {
                                    Button("Prepare now") { model.emailSummaries.prepareReply(message,summary:summary,model:model) }.disabled(model.emailSummaries.busy || model.assistant.busy || model.chatGPT.busy || model.proactive.busy || model.writing)
                                }
                                Button("Original") { model.select(message) }
                                Spacer(); Button("Dismiss") { model.emailSummaries.dismiss(message.id,model:model) }
                            }.controlSize(.small)
                        }.taskCard()
                    }
                    if !handled.isEmpty {
                        DisclosureGroup("Already planned or addressed (\(handled.count))") {
                            ForEach(handled,id:\.0.id) { message,summary,handling in
                                VStack(alignment:.leading,spacing:6) {
                                    Label(handling.label,systemImage:handling.native.completedAt == nil ? "calendar.badge.checkmark" : "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                                    Text(message.subject).font(.callout.weight(.semibold))
                                    ReviewSourceLabel(details:.email(message))
                                    Text("Inferred connection to “"+handling.native.title+"” · "+handling.reason).font(.callout).textSelection(.enabled)
                                    HStack {Button("Original") {model.select(message)};Button("Keep in review") {model.emailSummaries.keepForReview(summary.id,model:model)}}.controlSize(.small)
                                }.taskCard()
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
                            if item.state != .running { HStack { if item.state == .waiting { Button("Continue queue") { model.assistant.resumeQueue(model:model) }.disabled(model.assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) }; Button("Remove") { model.assistant.discardQueued(item.id) } }.controlSize(.small) }
                        }.taskCard()
                    }
                    if emails.isEmpty && discoveries.isEmpty && pending.isEmpty && handled.isEmpty && questions.isEmpty && learningQuestions.isEmpty {
                        ContentUnavailableView("Nothing waiting for review",systemImage:"checkmark.circle",description:Text("Proposed changes, useful updates and prepared work appear here when enabled sources reveal something useful."))
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .sheet(item:$answering) {question in
            VStack(alignment:.leading,spacing:16) {
                Text(question.question).font(.headline)
                TextEditor(text:$answer).frame(minHeight:100).font(.body)
                if let answerError {Text(answerError).font(.caption).foregroundStyle(.orange)}
                HStack {Button("Cancel") {answering=nil};Spacer();Button("Send answer") {
                    guard questions.contains(where:{$0.id == question.id}) else {answerError="This question’s supporting context changed. Run a fresh heartbeat.";return}
                    let text="About your question “"+question.question+"”: "+answer.trimmingCharacters(in:.whitespacesAndNewlines)
                    if model.assistant.send(model:model,topicID:nil,prompt:text,focusAreas:[]) {
                        _ = model.briefings.resolveQuestion(question,model:model,answered:true);answering=nil
                    } else {answerError="Your PA is busy. Your answer is kept here; send it when ready."}
                }.disabled(answer.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.assistant.busy || model.chatGPT.busy || model.writing || model.heartbeat.busy || ProcessInfo.processInfo.arguments.contains("--preview-review-inbox"))}
                Text("Your answer continues the PA conversation.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width:520)
        }
        .sheet(item:$answeringLearning) {question in
            VStack(alignment:.leading,spacing:16) {
                Text(question.text).font(.headline)
                TextEditor(text:$answer).frame(minHeight:100)
                if let answerError {Text(answerError).font(.caption).foregroundStyle(.orange)}
                HStack {Button("Cancel") {answeringLearning=nil};Spacer();Button("Send answer") {
                    guard learningQuestions.contains(where:{$0.id == question.id}) else {answerError="This question is no longer available.";return}
                    if model.assistant.send(model:model,topicID:question.conversationID,prompt:"About your question “"+question.text+"”: "+answer.trimmingCharacters(in:.whitespacesAndNewlines),focusAreas:question.conversationID == nil ? [] : nil) {model.memoryLearning.answer(question);answeringLearning=nil}
                    else {answerError="Your PA is busy. Your answer is kept here."}
                }.disabled(answer.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.assistant.busy || model.chatGPT.busy || model.writing || model.heartbeat.busy || ProcessInfo.processInfo.arguments.contains("--preview-review-inbox"))}
            }.padding(24).frame(width:520)
        }
        .sheet(item:$sourceDiscovery) { record in DiscoveryEvidenceView(record:record,model:model) }
        .sheet(isPresented:$showingActivity) {BackgroundActivityView(model:model)}
        .sheet(item:$reviewingProject) { record in LifeItemEditor(model:model,item:.init(registration:record.registration,kind:.space,title:String((record.sourceTitle ?? "New space").prefix(160)),notes:record.evidence),close:{reviewingProject=nil},reviewedSuggestion:record) }
        .sheet(item:$editing) { summary in
            VStack(alignment:.leading,spacing:14) {
                Text("Review reply draft").font(.title2.weight(.semibold))
                Text(summary.message?.subject ?? "Email reply").foregroundStyle(.secondary)
                if let message=emails.first(where:{$0.1.id == summary.id && $0.1.fingerprint == summary.fingerprint})?.0 {ReviewSourceLabel(details:.email(message))}
                TextEditor(text:$draft).onChange(of:draft) { copied=false; draftSaved=false }.font(.body).frame(minHeight:240)
                Text("Check details and placeholders before using this draft.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Close") { editing=nil }; Spacer(); Button(draftSaved ? "Saved" : "Save draft") { draftSaved=model.emailSummaries.saveReplyDraft(draft,summary:summary,model:model) }; Button(copied ? "Copied" : "Copy draft") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(draft,forType:.string); copied=true } }
            }.padding(24).frame(width:560)
        }.onChange(of:model.chatGPT.activeID) { editing=nil; draft="";sourceDiscovery=nil;reviewingProject=nil;answering=nil;answeringLearning=nil;answer="" }
        .onChange(of:discoveries.map(\.id)) { if let sourceDiscovery,!discoveries.contains(where:{$0.id == sourceDiscovery.id}) { self.sourceDiscovery=nil } }.onChange(of:model.assistant.excludedAccounts) { if let account=editing?.message?.accountID,model.assistant.excludedAccounts.contains(account) { editing=nil; draft="" } }
    }
}
private extension View {
    func taskCard()->some View { padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12)) }
}
