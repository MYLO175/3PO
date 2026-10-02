import SwiftUI
struct EmailOverviewView: View {
    @Bindable var model: DashboardModel
    @Bindable var summaries: EmailSummaryService
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summaries.coverage(model)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(summaries.paused ? "Resume summaries" : "Summarise next 3") { summaries.process(model, resume: true) }.disabled(!summaries.enabled || model.chatGPT.usagePaused || summaries.busy || model.chatGPT.busy || !model.chatGPT.inferenceVerified)
                if summaries.busy { ProgressView().controlSize(.small); Button("Stop") { summaries.cancel() } }
            }
            if model.chatGPT.usagePaused { Text("Subscription processing paused. Check usage and Test connection in Settings before resuming.").font(.caption).foregroundStyle(.orange) }
            if !summaries.enabled { Text("Enable automatic email summaries in Settings to read enabled inbox bodies using your ChatGPT plan. Original messages remain available under Sources.").font(.callout).foregroundStyle(.secondary) }
            if let error = summaries.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if summaries.paused && summaries.error == nil { Text("Processing paused. Resume when subscription access is available.").font(.caption).foregroundStyle(.orange) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    let available = summaries.eligible(model).compactMap { message -> (MailMessage, EmailSummary)? in guard let summary = summaries.current(message, model: model) else { return nil }; return (message, summary) }
                    ForEach(available.filter { $0.1.attention || Calendar.current.isDateInToday($0.0.received) }, id: \.0.id) { message, summary in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(summary.attention ? "Needs attention" : "Today").font(.caption.weight(.semibold)).foregroundStyle(summary.attention ? Color.orange : Color.secondary)
                            Text(summary.summary).textSelection(.enabled)
                            if summary.attention { Text(summary.reason).font(.callout); Text("“\(summary.evidence)”").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                            Button("\(message.account) · \(message.subject)") { model.select(message) }.buttonStyle(.link).lineLimit(2)
                        }
                        Divider()
                    }
                    if available.isEmpty { Text("No summaries yet. Coverage is partial until indexing finishes.").foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
struct EmailSummarySettings: View {
    @Bindable var model: DashboardModel
    @Bindable var summaries: EmailSummaryService
    var body: some View {
        Section("Automatic email summaries") {
            Toggle("Process enabled inboxes automatically", isOn: $summaries.enabled)
            Text("Sends headers and relevant plain-text bodies from AI-enabled email accounts to OpenAI using your ChatGPT plan. Uses the selected assistant model at Medium. No attachments or sending. Reads at most three new messages or changed headers per five-minute batch, saves each summary, and pauses on an error or usage limit. Existing summaries are reused; coverage shows the remaining backlog.").font(.caption)
            Text("Account controls are under AI email accounts above. Dashboard mailbox filters only change the source view. Briefing controls are below.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
