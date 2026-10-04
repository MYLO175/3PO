import SwiftUI
import AppKit
struct PATasksView: View {
    @Bindable var model: DashboardModel
    @State private var editing: EmailSummary?
    @State private var draft=""
    @State private var copied=false
    @State private var draftSaved=false
    private var emails:[(MailMessage,EmailSummary)] {
        model.emailSummaries.highlights(model).filter { EmailHighlightRules.needsAction($0.1,replied:$0.0.replied) }.map { message,summary in
            var value=summary
            if message.replied || EmailSummary.fingerprint(message) != summary.fingerprint { value.replyDraft=nil }
            return (message,value)
        }
    }
    private var discoveries:[PADiscovery] { model.proactive.state.records.filter { model.proactive.visible($0,model:model) } }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Label("Tasks for you",systemImage:"tray.full").font(.title3.weight(.semibold))
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    ForEach(model.assistant.queue.items.filter { $0.registration == model.chatGPT.activeID }) { item in
                        VStack(alignment:.leading,spacing:6) {
                            Label(item.state == .running ? "PA working" : item.state == .interrupted ? "Check interrupted work" : "Queued for your PA",systemImage:"bubble.left.and.bubble.right").font(.caption).foregroundStyle(.secondary)
                            Text(item.prompt).lineLimit(3)
                            Text(item.topicID.flatMap { model.assistant.conversation($0)?.title } ?? "General").font(.caption2).foregroundStyle(.secondary)
                            if item.state != .running { HStack { if item.state == .waiting { Button("Continue queue") { model.assistant.resumeQueue(model:model) }.disabled(model.assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) }; Button("Remove") { model.assistant.discardQueued(item.id) } }.controlSize(.small) }
                        }.taskCard()
                    }
                    ForEach(discoveries) { item in
                        VStack(alignment:.leading,spacing:8) {
                            Text(item.message).textSelection(.enabled)
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
                                Button("Original") { model.select(message) }
                                Spacer(); Button("Dismiss") { model.emailSummaries.dismiss(message.id,model:model) }
                            }.controlSize(.small)
                        }.taskCard()
                    }
                    if emails.isEmpty && discoveries.isEmpty && !model.assistant.queue.items.contains(where:{$0.registration == model.chatGPT.activeID}) {
                        ContentUnavailableView("Nothing to hand back yet",systemImage:"checkmark.circle",description:Text("Useful suggestions and prepared replies appear here as enabled incoming-mail monitoring runs."))
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .sheet(item:$editing) { summary in
            VStack(alignment:.leading,spacing:14) {
                Text("Review reply draft").font(.title2.weight(.semibold))
                Text(summary.message?.subject ?? "Email reply").foregroundStyle(.secondary)
                TextEditor(text:$draft).onChange(of:draft) { copied=false; draftSaved=false }.font(.body).frame(minHeight:240)
                Text("Check details and placeholders before using this draft.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Close") { editing=nil }; Spacer(); Button(draftSaved ? "Saved" : "Save draft") { draftSaved=model.emailSummaries.saveReplyDraft(draft,summary:summary,model:model) }; Button(copied ? "Copied" : "Copy draft") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(draft,forType:.string); copied=true } }
            }.padding(24).frame(width:560)
        }.onChange(of:model.chatGPT.activeID) { editing=nil; draft="" }.onChange(of:model.assistant.excludedAccounts) { if let account=editing?.message?.accountID,model.assistant.excludedAccounts.contains(account) { editing=nil; draft="" } }
    }
}
private extension View {
    func taskCard()->some View { padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12)) }
}
