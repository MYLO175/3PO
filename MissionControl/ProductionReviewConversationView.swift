import SwiftUI

struct ProductionReviewConversationView:View {
    @Bindable var model:DashboardModel
    let conversationID:UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workspacePalette) private var palette
    @State private var rows:[ReviewPreparedRow]=[]
    @State private var selected=Set<String>()
    @State private var preparing=true
    @State private var draft=""
    private var conversation:AssistantConversation? {model.assistant.conversation(conversationID)}
    private var jobs:[ReviewWorkJob] {model.reviewWork.jobs(model.chatGPT.activeID,conversation:conversationID)}
    private var discussed:Bool {jobs.contains{$0.mode == .conversation}}
    private var usable:Bool {model.reviewConversationAvailable(conversationID)}
    private var selectedActions:[ReviewWorkAction] {rows.filter{selected.contains($0.id) && !isSaved($0) && !isReserved($0)}.compactMap(\.action)}
    private var turns:[AssistantTurn] {conversation?.turns.filter{$0.role == "user" || ($0.deliveryID == nil && $0.role == "assistant")} ?? []}
    private var opening:String {
        if let id=conversation?.reviewMessageID,let summary=model.emailSummaries.records.first(where:{$0.id == id && $0.registration == model.chatGPT.activeID}) {return summary.summary}
        return conversation?.turns.first(where:{$0.deliveryID != nil})?.content ?? "Review the suggested actions below."
    }
    private var completedCount:Int {
        let approvalIDs=Set(jobs.flatMap{$0.actions.filter{$0.phase == .saved}.map(\.id)})
        let oldRows=rows.filter{row in model.proactive.state.records.first{$0.id == row.id}.map(model.reviewDiscoveryCompleted) == true}.map(\.id)
        return approvalIDs.union(oldRows).count+jobs.filter{$0.mode == .conversation}.reduce(0){$0+$1.savedCount}
    }
    var body:some View {
        VStack(spacing:0) {
            HStack(alignment:.top,spacing:14) {
                Image(systemName:"bubble.left.and.text.bubble.right").font(.title2).foregroundStyle(palette[.accent]).padding(.top,3)
                VStack(alignment:.leading,spacing:5) {Text(conversation?.title ?? "Review suggestion").font(.title3.weight(.semibold)).lineLimit(2);Text("Discuss a plan with 3PO").font(.caption).foregroundStyle(.secondary)}
                Spacer(minLength:8)
                Button("Done") {dismiss()}.keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            if usable {
                ScrollViewReader {scroll in
                    ScrollView {
                        VStack(alignment:.leading,spacing:16) {
                            Text(PAProse.display(opening)).font(.callout).lineSpacing(4).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                            if completedCount > 0 {Label("\(completedCount) action\(completedCount == 1 ? "" : "s") completed",systemImage:"checkmark.circle.fill").font(.callout.weight(.semibold)).foregroundStyle(palette[.accent])}
                            if preparing {HStack {ProgressView().controlSize(.small);Text("Preparing saved actions…").font(.caption).foregroundStyle(.secondary)}}
                            if !discussed,!rows.isEmpty {
                                Text(completedCount > 0 ? "Saved actions and remaining suggestions" : "Would you like me to add these actions?").font(.headline)
                                ForEach(rows) {row in preparedRow(row)}
                                if rows.contains(where:{$0.action != nil && !isSaved($0)}) {
                                    HStack(spacing:12) {
                                        Text("Select actions and press the tick, or ask for a change below.").font(.caption).foregroundStyle(.secondary)
                                        Spacer(minLength:8)
                                        Text("\(selectedActions.count) selected").font(.caption).foregroundStyle(.secondary)
                                        Button {approveSelected()} label:{Image(systemName:"checkmark").font(.headline).frame(width:30,height:30)}
                                            .buttonStyle(.borderedProminent).clipShape(Circle())
                                            .disabled(preparing || selectedActions.isEmpty || !model.reviewWork.readable)
                                            .help("Add selected actions")
                                            .accessibilityLabel("Approve selected actions")
                                    }
                                }
                            }
                            if turns.isEmpty || !discussed {
                                Button("Suggest a fuller plan") {send("Explain what matters in this source and suggest a complete plan. Look for the relevant existing project and propose dated tasks there as well as useful Calendar entries. Distinguish confirmed dates, provisional windows and missing deadlines. Tell me what you can do and ask before making changes.",actions:[],control:true)}.buttonStyle(.borderless)
                            }
                            ForEach(turns) {turn in
                                VStack(alignment:.leading,spacing:5) {
                                    Text(turn.role == "user" ? "You" : "3PO").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Text(PAProse.display(turn.content.isEmpty ? "Thinking…" : turn.content)).font(.callout).lineSpacing(3).textSelection(.enabled)
                                    if let errors=turn.unresolvedToolErrors,!errors.isEmpty {Label(errors.joined(separator:" · "),systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange)}
                                }.padding(13).frame(maxWidth:.infinity,alignment:.leading).background(palette[.accent].opacity(turn.role == "user" ? 0.12 : 0.05),in:RoundedRectangle(cornerRadius:12))
                            }
                            ForEach(jobs.filter{$0.pending || $0.phase != .completed}) {job in jobRow(job)}
                            Color.clear.frame(height:1).id("end")
                        }.padding(22)
                    }.onChange(of:jobs.map{String(describing:$0.phase)}) {scroll.scrollTo("end",anchor:.bottom)}
                }
                Divider()
                VStack(alignment:.leading,spacing:8) {
                    if model.heartbeat.busy {Label("Your reply will run after the heartbeat finishes",systemImage:"clock").font(.caption).foregroundStyle(.secondary)}
                    if let error=model.reviewWork.error {Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
                    HStack(alignment:.bottom,spacing:10) {
                        TextField("Ask for a change, or reply…",text:$draft,axis:.vertical).textFieldStyle(.plain).lineLimit(1...4).padding(12).background(palette[.widget],in:RoundedRectangle(cornerRadius:11)).overlay(RoundedRectangle(cornerRadius:11).stroke(palette[.border].opacity(0.65))).onSubmit {sendDraft()}
                        Button {sendDraft()} label:{Image(systemName:"arrow.up").font(.headline).frame(width:30,height:30)}.buttonStyle(.borderedProminent).clipShape(Circle()).disabled(draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !model.reviewWork.readable).accessibilityLabel("Send Review reply")
                    }
                    Text("You can leave this review while 3PO works. This conversation stays with this source.").font(.caption2).foregroundStyle(.secondary)
                }.padding(18)
            } else {ContentUnavailableView("Source access changed",systemImage:"lock",description:Text("Enable this source in 3PO’s settings to view its saved review conversation.")).frame(maxWidth:.infinity,maxHeight:.infinity)}
        }.frame(width:700,height:model.reviewSheetHeight).foregroundStyle(palette[.text]).background(palette[.canvas]).tint(palette[.accent])
        .task {
            draft=model.reviewWork.draft(model.chatGPT.activeID,conversation:conversationID)
            guard let conversation,let source=model.reviewSource(conversation),usable else {preparing=false;return}
            for record in model.reviewRecords(source) where record.nativeTarget == nil && !["reply","update"].contains(record.kind) {
                let row=await model.prepareReviewRow(record)
                guard !Task.isCancelled,usable else {return}
                rows.append(row)
                if row.action != nil,!model.reviewDiscoveryCompleted(record) {selected.insert(row.id)}
            }
            preparing=false
        }.onChange(of:draft) {_,value in model.reviewWork.setDraft(value,registration:model.chatGPT.activeID,conversation:conversationID)}
    }
    private func isSaved(_ row:ReviewPreparedRow)->Bool {
        model.proactive.state.records.first{$0.id == row.id}.map(model.reviewDiscoveryCompleted) == true || jobs.contains{$0.actions.contains{$0.id == row.id && $0.phase == .saved}}
    }
    private func isReserved(_ row:ReviewPreparedRow)->Bool {
        jobs.contains {job in job.mode == .approval && job.actions.contains{$0.id == row.id && (job.pending || $0.phase != .waiting)}}
    }
    @ViewBuilder private func preparedRow(_ row:ReviewPreparedRow)->some View {
        let saved=isSaved(row)
        HStack(alignment:.top,spacing:10) {
            if saved {Image(systemName:"checkmark.circle.fill").foregroundStyle(palette[.accent])}
            else if row.action != nil {Toggle("",isOn:Binding(get:{selected.contains(row.id)},set:{if $0 {selected.insert(row.id)} else {selected.remove(row.id)}})).labelsHidden().toggleStyle(.checkbox).disabled(isReserved(row))}
            else {Image(systemName:"questionmark.circle").foregroundStyle(.secondary)}
            VStack(alignment:.leading,spacing:5) {Text(PAProse.display(row.title)).font(.callout.weight(.medium));if !row.destination.isEmpty {Text(row.destination).font(.caption.weight(.medium)).foregroundStyle(palette[.accent])};Text(PAProse.display(row.detail)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled);if let error=row.error,!saved {Text(error).font(.caption).foregroundStyle(.orange)}}
            Spacer(minLength:0)
            if saved {Text("Completed").font(.caption).foregroundStyle(.secondary)}
        }.padding(13).background(palette[.widget],in:RoundedRectangle(cornerRadius:11)).overlay(RoundedRectangle(cornerRadius:11).stroke(palette[.border].opacity(0.45)))
    }
    private func jobRow(_ job:ReviewWorkJob)->some View {
        VStack(alignment:.leading,spacing:8) {
            Label(job.phase == .queued ? "Queued: "+job.human : job.phase == .running ? "3PO is working…" : job.message ?? job.phase.rawValue,systemImage:job.pending ? "clock" : "exclamationmark.circle").font(.callout)
            if let error=job.error {Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
            ForEach(job.actions.filter{$0.phase == .failed || $0.phase == .uncertain}) {action in
                Label(PAProse.display(action.title)+" · "+(action.phase == .uncertain ? "Save needs checking" : "Failed"),systemImage:"exclamationmark.circle").font(.caption.weight(.medium)).foregroundStyle(.orange)
            }
            HStack {
                if job.pending {Button("Stop") {model.reviewWork.stop(job.id)}}
                if [.partial,.failed,.interrupted,.uncertain,.stopped].contains(job.phase) {
                    Button("Check saved receipts") {_=model.reviewWork.reconcile(job.id,runtime:model.reviewWorkRuntime())}
                    if !job.actions.contains(where:{$0.phase == .uncertain || $0.phase == .working}),model.reviewWork.activeID != job.id,job.phase != .uncertain {
                        Button("Retry remaining work") {if model.reviewWork.retry(job.id) {model.scheduleReviewWork()}}
                    }
                }
                Spacer()
            }.controlSize(.small)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.orange.opacity(job.pending ? 0.04 : 0.08),in:RoundedRectangle(cornerRadius:11))
    }
    private func approveSelected() {
        let actions=selectedActions
        guard !preparing,!actions.isEmpty,model.reviewWork.readable else {return}
        _=model.submitReview("yes",conversationID:conversationID,actions:actions,focus:[],selectionActive:true)
    }
    private func sendDraft() {send(draft,actions:discussed ? [] : selectedActions)}
    private func send(_ text:String,actions:[ReviewWorkAction],control:Bool=false) {
        let approval=["yes","yes please","yep","go ahead","do that","ok","okay","add these","approve","👍"].contains(text.trimmingCharacters(in:.whitespacesAndNewlines).lowercased().trimmingCharacters(in:CharacterSet(charactersIn:".! ")))
        if approval,!discussed,actions.isEmpty,!rows.isEmpty {model.reviewWork.error="Select an action first, or ask 3PO for a different plan.";return}
        if model.submitReview(text,conversationID:conversationID,actions:actions,focus:[],humanControl:control,selectionActive:!discussed && !rows.isEmpty) {draft=""}
    }
}
