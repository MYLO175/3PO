import SwiftUI
struct EmailOverviewView: View {
    @Bindable var model: DashboardModel
    @Bindable var summaries: EmailSummaryService
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summaries.coverage(model)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(summaries.paused ? "Resume mail monitoring" : "Check new mail") { summaries.process(model, resume: true) }.disabled(!summaries.enabled || model.chatGPT.usagePaused || summaries.busy || model.chatGPT.busy || !model.chatGPT.inferenceVerified)
                if summaries.busy { ProgressView().controlSize(.small); Button("Stop") { summaries.cancel() } }
            }
            if summaries.rejectedCount(model) > 0 {
                HStack {
                    Text("\(summaries.rejectedCount(model)) messages skipped because AI output failed validation. Coverage remains partial.").font(.caption).foregroundStyle(.orange)
                    Button("Retry skipped") { summaries.retryRejected(model) }.disabled(summaries.busy || !summaries.enabled || model.chatGPT.usagePaused || model.chatGPT.busy || !model.chatGPT.inferenceVerified)
                }
            }
            if model.chatGPT.usagePaused { Text("Subscription processing paused. Check usage and Test connection in Settings before resuming.").font(.caption).foregroundStyle(.orange) }
            if !summaries.enabled { Text("Enable automatic email summaries in Settings to read enabled inbox bodies using your ChatGPT plan. Original messages remain available under Sources.").font(.callout).foregroundStyle(.secondary) }
            if let error = summaries.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if summaries.paused && summaries.error == nil { Text("Processing paused. Resume retries a bounded batch; completed summaries are saved.").font(.caption).foregroundStyle(.orange) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    let available = summaries.memories(model)
                    ForEach(available, id: \.0.id) { message, summary in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(summary.followUpDate.map { "Follow-up · " + $0 } ?? "Retained from email").font(.caption.weight(.semibold)).foregroundStyle(summary.attention ? Color.orange : Color.secondary)
                            Text(summary.summary).textSelection(.enabled)
                            if summary.attention { Text(summary.reason).font(.callout); Text("“\(summary.evidence)”").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                            Button("Dismiss follow-up") { summaries.dismiss(message.id,model:model) }.font(.caption)
                            Button("\(message.account) · \(message.subject)") { model.select(message) }.buttonStyle(.link).lineLimit(2)
                        }
                        Divider()
                    }
                    if available.isEmpty { Text("No retained email follow-ups. Monitoring considers incoming mail; older messages are available on request.").foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
struct EmailSummarySettings: View {
    @Bindable var model: DashboardModel
    @Bindable var summaries: EmailSummaryService
    var body: some View {
        Section("Incoming email monitoring") {
            Toggle("Assess incoming mail automatically", isOn: $summaries.enabled)
            Picker("Email summary model", selection: $summaries.modelID) {
                Text("Use assistant model").tag("")
                ForEach(model.chatGPT.models) { Text($0.name).tag($0.id) }
            }.disabled(summaries.busy)
            Picker("Email reasoning", selection: $summaries.effort) {
                Text("Low").tag("low"); Text("Medium").tag("medium"); Text("High").tag("high")
            }.disabled(summaries.busy)
            Text("Sends headers and relevant plain-text bodies from AI-enabled email accounts to OpenAI using your ChatGPT plan. Email model/reasoning controls are independent of chat; choose an available Luna model at High for bounded classification if desired. No attachments or sending. Starts from today, without analysing the historical inbox. Assesses up to 20 incoming headers and reads at most three selected bodies per five-minute batch, saves each summary, and skips invalid model output while continuing other messages. Read, connection, storage and usage-limit errors pause processing. Retry skipped explicitly allows another bounded attempt. Ignorable mail is not shown. Relevant future follow-ups are retained until dismissed; existing assessments are reused.").font(.caption)
            Text("Account controls are under AI email accounts above. Dashboard mailbox filters only change the source view. Briefing controls are below.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
