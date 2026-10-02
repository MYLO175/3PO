import SwiftUI

struct AssistantPanel: View {
    @Bindable var model: DashboardModel
    @Bindable var assistant: AssistantService
    var body: some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                Label("Assistant", systemImage: "sparkles").font(.headline)
                if !assistant.conversations.isEmpty {
                    Picker("Conversation", selection: $assistant.activeID) { ForEach(assistant.conversations) { Text($0.title).tag(Optional($0.id)) } }.labelsHidden().frame(maxWidth: 280).disabled(assistant.busy)
                }
                Button("New chat") { assistant.newConversation() }.disabled(assistant.busy)
                Spacer()
                Text(assistant.contextEnabled ? "Enabled source snapshots · headers only" : "AI source context off").font(.caption).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if assistant.active?.turns.isEmpty ?? true { Text("Ask about your day. Enable source context in Settings when you want the assistant to use your calendar, reminders and recent email headers.").foregroundStyle(.secondary) }
                        ForEach(assistant.active?.turns ?? []) { turn in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(turn.role == "user" ? "You" : "Mission Control").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(turn.content.isEmpty ? "Thinking…" : turn.content).textSelection(.enabled).id(turn.content)
                                if turn.role == "assistant" && !turn.completed && !assistant.busy { Text("Partial response").font(.caption).foregroundStyle(.orange) }
                            }.frame(maxWidth: .infinity, alignment: .leading).id(turn.id)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.onChange(of: assistant.active?.turns.last?.content) { if let id = assistant.active?.turns.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            if let error = assistant.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                TextField("Message Mission Control", text: $assistant.draft).onSubmit { assistant.send(context: assistant.snapshot(model)) }.disabled(assistant.busy)
                if assistant.busy { ProgressView().controlSize(.small); Button("Stop") { assistant.cancel() } }
                else { Button("Send") { assistant.send(context: assistant.snapshot(model)) }.disabled(assistant.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.chatGPT.inferenceVerified) }
            }
        }.padding(.horizontal, 20).padding(.vertical, 10)
    }
}
struct AssistantSourceSettings: View {
    @Bindable var model: DashboardModel
    @Bindable var assistant: AssistantService
    var body: some View {
        Section("Assistant preferences and sources") {
            Toggle("Enable assistant source context", isOn: $assistant.contextEnabled)
            Text("When enabled, assistant requests send the enabled calendar and reminder snapshots and recent email headers to OpenAI using your ChatGPT plan. Email body processing and automatic daily summaries come in the next increment. Dashboard refresh itself makes no AI requests.").font(.caption)
            TextField("Assistant preferences", text: $assistant.preferences, axis: .vertical).lineLimit(3...6)
            sourceMenu("AI calendars", sources: model.calendarData.sources, excluded: $assistant.excludedCalendars)
            sourceMenu("AI reminder lists", sources: model.reminderData.sources, excluded: $assistant.excludedLists)
            sourceMenu("AI email accounts", sources: model.mailData.accounts.map { SourceOption(id: $0.id, title: $0.title, account: "", writable: false) }, excluded: $assistant.excludedAccounts)
        }
    }
    private func sourceMenu(_ title: String, sources: [SourceOption], excluded: Binding<Set<String>>) -> some View {
        Menu(title) {
            ForEach(sources) { source in
                Toggle(source.label, isOn: Binding(get: { !excluded.wrappedValue.contains(source.id) }, set: { enabled in if enabled { excluded.wrappedValue.remove(source.id) } else { excluded.wrappedValue.insert(source.id) } }))
            }
        }
    }
}
