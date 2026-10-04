import SwiftUI
import AppKit
struct PATasksView: View {
    @Bindable var model: DashboardModel
    @State private var editing: EmailSummary?
    @State private var draft=""
    @State private var copied=false
    @State private var draftSaved=false
    @State private var sourceDiscovery:PADiscovery?
    private var emails:[(MailMessage,EmailSummary)] {
        model.emailSummaries.highlights(model).filter { EmailHighlightRules.needsAction($0.1,replied:$0.0.replied) }.map { message,summary in
            var value=summary
            if message.replied || EmailSummary.fingerprint(message) != summary.fingerprint { value.replyDraft=nil }
            return (message,value)
        }
    }
    private var discoveries:[PADiscovery] { model.proactive.state.records.filter { model.proactive.visible($0,model:model) } }
    private var pending:[PAQueuedRequest] { PAQueueRules.handoffs(model.assistant.queue.items,registration:model.chatGPT.activeID) }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Label("Tasks for you",systemImage:"tray.full").font(.title3.weight(.semibold));Spacer();Button { model.proactive.check(model,manual:true) } label:{Image(systemName:"arrow.clockwise")}.buttonStyle(.borderless).help("Check for useful suggestions").disabled(model.proactive.busy || model.assistant.busy || model.chatGPT.busy || model.writing) }
            if model.proactive.busy || model.emailSummaries.busy { Text(model.proactive.busy ? "Looking for useful suggestions…" : "Preparing email work…").font(.caption).foregroundStyle(.secondary) }
            if let error=model.proactive.error ?? model.emailSummaries.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3) }
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    ForEach(discoveries) { item in
                        VStack(alignment:.leading,spacing:8) {
                            Label(item.sourceKind == "whatsapp" ? "WhatsApp · " + (item.sourceLabel ?? "Selected chat") : "Missing plan",systemImage:item.kind == "calendar" ? "calendar.badge.plus" : "checklist").font(.caption).foregroundStyle(.secondary)
                            if let title=item.sourceTitle { Text(title).font(.callout.weight(.semibold)) }
                            Text(item.message).textSelection(.enabled)
                            Button("Source evidence") { sourceDiscovery=item }.buttonStyle(.borderless).font(.caption)
                            HStack { Button("Review suggestion") { model.reviewDiscovery(item) }; Spacer(); Button("Dismiss") { model.proactive.dismiss(item) } }.controlSize(.small)
                        }.taskCard()
                    }
                    ForEach(emails,id:\.0.id) { message,summary in
                        VStack(alignment:.leading,spacing:8) {
                            Label(summary.replyDraft == nil ? "Needs attention" : "Reply draft ready",systemImage:summary.replyDraft == nil ? "checklist" : "pencil.line").font(.caption).foregroundStyle(.secondary)
                            Text(message.subject).font(.callout.weight(.semibold)).lineLimit(2)
                            Text(summary.reason.isEmpty ? summary.summary : summary.reason).font(.callout).textSelection(.enabled)
                            HStack {
                                if let reply=summary.replyDraft { Button("Review draft") { editing=summary; draft=reply; copied=false; draftSaved=false } }
                                else if summary.needsReply == true { Button("Draft reply") { model.emailSummaries.prepareReply(message,summary:summary,model:model) }.disabled(model.emailSummaries.busy || model.assistant.busy || model.chatGPT.busy || model.proactive.busy || model.writing) }
                                Button("Original") { model.select(message) }
                                Spacer(); Button("Dismiss") { model.emailSummaries.dismiss(message.id,model:model) }
                            }.controlSize(.small)
                        }.taskCard()
                    }
                    ForEach(pending) { item in
                        VStack(alignment:.leading,spacing:6) {
                            Label(item.state == .completed ? "PA work ready" : item.state == .needsAnswer ? "Your answer needed" : item.state == .running ? "PA working" : item.state == .interrupted ? "Check interrupted work" : "Queued for your PA",systemImage:"bubble.left.and.bubble.right").font(.caption).foregroundStyle(.secondary)
                            Text(item.prompt).lineLimit(3)
                            if let result=item.result { DisclosureGroup("Result") { Text(result).textSelection(.enabled) } }
                            if let focus=item.focusAreas,!focus.isEmpty { Text(focus.map(\.title).joined(separator:" · ")).font(.caption2).foregroundStyle(.secondary) }
                            if item.state != .running { HStack { if item.state == .waiting { Button("Continue queue") { model.assistant.resumeQueue(model:model) }.disabled(model.assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) }; Button("Remove") { model.assistant.discardQueued(item.id) } }.controlSize(.small) }
                        }.taskCard()
                    }
                    if emails.isEmpty && discoveries.isEmpty && pending.isEmpty {
                        ContentUnavailableView("No tasks to review",systemImage:"checkmark.circle",description:Text("Unanswered emails, prepared reply drafts and missing plans appear here when your enabled sources reveal something useful. Completed chat replies stay in the PA conversation."))
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .sheet(item:$sourceDiscovery) { record in DiscoveryEvidenceView(record:record) }
        .sheet(item:$editing) { summary in
            VStack(alignment:.leading,spacing:14) {
                Text("Review reply draft").font(.title2.weight(.semibold))
                Text(summary.message?.subject ?? "Email reply").foregroundStyle(.secondary)
                TextEditor(text:$draft).onChange(of:draft) { copied=false; draftSaved=false }.font(.body).frame(minHeight:240)
                Text("Check details and placeholders before using this draft.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Close") { editing=nil }; Spacer(); Button(draftSaved ? "Saved" : "Save draft") { draftSaved=model.emailSummaries.saveReplyDraft(draft,summary:summary,model:model) }; Button(copied ? "Copied" : "Copy draft") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(draft,forType:.string); copied=true } }
            }.padding(24).frame(width:560)
        }.onChange(of:model.chatGPT.activeID) { editing=nil; draft="";sourceDiscovery=nil }
        .onChange(of:discoveries.map(\.id)) { if let sourceDiscovery,!discoveries.contains(where:{$0.id == sourceDiscovery.id}) { self.sourceDiscovery=nil } }.onChange(of:model.assistant.excludedAccounts) { if let account=editing?.message?.accountID,model.assistant.excludedAccounts.contains(account) { editing=nil; draft="" } }
    }
}
private extension View {
    func taskCard()->some View { padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12)) }
}
