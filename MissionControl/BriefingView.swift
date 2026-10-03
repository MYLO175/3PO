import SwiftUI
struct BriefingView: View {
    @Bindable var model: DashboardModel
    @Bindable var briefings: BriefingService
    @State private var selectedRecord = ""
    var body: some View {
        DisclosureGroup("Morning briefing") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Prepare today") { briefings.check(model, manual: true) }.disabled(!briefings.enabled || model.chatGPT.usagePaused || briefings.busy || model.chatGPT.busy || !model.chatGPT.inferenceVerified)
                    if briefings.busy { ProgressView().controlSize(.small); Button("Stop") { briefings.cancel() } }
                }
                if let error = briefings.error { Text(error).font(.caption).foregroundStyle(.orange) }
                if briefings.state.paused && briefings.error == nil { Text("Briefing paused. Prepare today retries once when access is available.").font(.caption).foregroundStyle(.orange) }
                let records = briefings.records(model)
                if !records.isEmpty {
                    Picker("Saved briefing", selection: $selectedRecord) {
                        Text("Latest").tag("")
                        ForEach(records) { Text($0.day).tag($0.id) }
                    }
                }
                if let record = records.first(where: { $0.id == selectedRecord }) ?? records.first {
                    Text(record.day).font(.headline)
                    Text(record.coverage).font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(record.items) { item in
                                Text(item.text).textSelection(.enabled)
                                ForEach(item.sourceIDs, id: \.self) { id in
                                    if let source = record.sources.first(where: { $0.id == id }) {
                                        if source.kind == "mail", let message = model.mailData.messages.first(where: { $0.id == (source.originalID ?? id) }) ?? model.emailSummaries.memories(model).first(where: { $0.0.id == (source.originalID ?? id) })?.0, !model.assistant.excludedAccounts.contains(message.accountID) {
                                            Button(source.label) { model.select(message) }.buttonStyle(.link).font(.caption)
                                        } else { Text(source.label).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                                Divider()
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 220)
                } else { Text(briefings.enabled ? "No saved briefing yet. Scheduled for 7:30; missed runs catch up while the app is awake and running." : "Enable the daily briefing in Settings.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
struct BriefingSettings: View {
    @Bindable var model: DashboardModel
    @Bindable var briefings: BriefingService
    var body: some View {
        Section("7:30 morning briefing") {
            Toggle("Prepare a daily briefing", isOn: $briefings.enabled)
            Text("Runs in this app while your Mac is awake. A missed 7:30 run catches up at the next launch/wake. Calendar and reminders follow assistant source-context controls. Email uses saved summaries from enabled email processing; incomplete coverage is shown. Sends these enabled source snapshots and saved summaries to OpenAI through your ChatGPT plan. Each morning message is saved once; errors pause until you choose Prepare today. Update brief in the widget explicitly prepares a fresh daytime version without another chat message or notification.").font(.caption)
            Button("Allow briefing notifications") { briefings.requestNotifications() }
            #if DEBUG
            Button("Send test notification (no AI)") { briefings.testNotification() }
            #endif
            Text(briefings.notificationStatus).font(.caption).foregroundStyle(.secondary)
        }
    }
}
