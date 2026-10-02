import SwiftUI
import AppKit

struct AssistantPanel: View {
    @Bindable var model: DashboardModel
    @Bindable var assistant: AssistantService
    @Binding var readingMode: Bool
    var supportsReadingMode = true
    @State private var dictation = DictationService()
    @State private var showDictation = false
    @State private var showMemory = false
    @State private var showBriefing = false
    var body: some View {
        VStack(spacing: 8) {
            Divider()
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Label("Assistant",systemImage:"sparkles").font(.headline)
                    Spacer()
                    Button("Your PA") { assistant.openPA() }.disabled(assistant.busy)
                    Button("Memory") { showMemory = true }
                    if supportsReadingMode { Button { readingMode.toggle() } label: { Image(systemName:readingMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }.help(readingMode ? "Compact chat" : "Expand chat") }
                }
                HStack {
                    if !assistant.conversations.isEmpty {
                        Picker("Conversation",selection:$assistant.activeID) { ForEach(assistant.conversations) { Text($0.title).tag(Optional($0.id)) } }.labelsHidden().frame(maxWidth:280).disabled(assistant.busy)
                    }
                    Button("New topic") { assistant.newConversation() }.disabled(assistant.busy).keyboardShortcut("n",modifiers:.command)
                    Spacer(minLength:0)
                }
                Text(assistant.contextEnabled ? "Enabled sources · shared memory" : "Apple source context off").font(.caption).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if assistant.active?.turns.isEmpty ?? true {
                            VStack(alignment:.leading,spacing:12) {
                                Text("A little clarity for your day").font(.headline)
                                Text("Ask about what's coming up, find an email, or tell me what needs doing.").font(.callout).foregroundStyle(.secondary)
                                HStack {
                                    ForEach(["What should I focus on today?","What's coming up this week?"],id:\.self) { suggestion in
                                        Button(suggestion) { assistant.draft = suggestion }.controlSize(.small)
                                    }
                                }
                            }.padding(.vertical,12)
                        }
                        ForEach(assistant.active?.turns ?? []) { turn in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(turn.role == "user" ? "You" : "Mission Control").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                if turn.content.isEmpty {
                                    Text(assistant.busy ? "Thinking…" : "This request didn't complete.").foregroundStyle(.secondary)
                                } else if turn.role == "assistant" {
                                    Text((try? AttributedString(markdown:turn.content,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(turn.content)).textSelection(.enabled).lineSpacing(3)
                                } else { Text(turn.content).textSelection(.enabled) }
                                if turn.deliveryID != nil { Button("Briefing and sources") { showBriefing = true }.controlSize(.small) }
                                if turn.role == "assistant" && !turn.completed && !assistant.busy && !turn.content.isEmpty { Text("Partial response").font(.caption).foregroundStyle(.orange) }
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(turn.role == "user" ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:10)).id(turn.id)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.onChange(of: assistant.active?.turns.last?.content) { if let id = assistant.active?.turns.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            if !model.mailLookup.status.isEmpty {
                HStack {
                    Text(model.mailLookup.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Menu("Mail sources") { ForEach(model.mailLookup.results) { message in Button(message.account + " · " + message.subject) { model.select(message) } } }
                    if model.mailLookup.hasMore { Button("Continue mail search") { assistant.draft = "Continue the email search."; assistant.send(model:model) }.disabled(assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) }
                }
            }
            if let error = assistant.error, !model.chatGPT.usagePaused { DisclosureGroup("Request didn’t complete") { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }.font(.caption) }
            if model.chatGPT.usagePaused {
                HStack {
                    Text("Subscription access was rejected; saved sources remain available.").font(.caption).foregroundStyle(.secondary)
                    Button("Check access") { model.chatGPT.testConnection() }.disabled(model.chatGPT.busy || assistant.busy)
                    Button("Usage") { NSWorkspace.shared.open(URL(string:"https://chatgpt.com/settings/usage")!) }
                }
                DisclosureGroup("Access details") { Text(model.chatGPT.message).font(.caption).foregroundStyle(.orange) }.font(.caption)
            }
            if model.chatGPT.busy && !assistant.busy {
                HStack(spacing:6) {
                    ProgressView().controlSize(.mini)
                    Text(model.briefings.busy ? "Preparing your overview or briefing… You can draft a message while it finishes." : model.emailSummaries.busy ? "Checking incoming mail… You can draft a message while it finishes." : "Checking your ChatGPT connection…").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack {
                Button { showDictation = true } label: { Image(systemName:"mic") }.help("Dictate a message").accessibilityLabel("Dictate a message").disabled(assistant.busy)
                TextField("Message Mission Control", text: $assistant.draft,axis:.vertical).lineLimit(1...4).textFieldStyle(.plain).padding(9).background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(Color.primary.opacity(0.08))).onSubmit { assistant.send(model:model) }.disabled(assistant.busy)
                if assistant.busy { ProgressView().controlSize(.small); Button("Stop") { assistant.cancel() } }
                else { Button("Send") { assistant.send(model:model) }.disabled(assistant.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (MemoryRules.explicitRequest(assistant.draft) == nil && (!model.chatGPT.inferenceVerified || model.chatGPT.busy || model.chatGPT.usagePaused))) }
            }
            if assistant.error?.contains("Choose the specific target") == true {
                Picker("Specific action target", selection: $model.assistantActions.selectedTarget) {
                    Text("Choose an item").tag("")
                    ForEach(model.assistantActions.targets) { Text($0.label).tag($0.id) }
                }
            }
        }.onChange(of:model.chatGPT.usagePaused) { _, paused in
            if !paused, assistant.error?.contains("subscription_sharing_usage_limit_exceeded") == true { assistant.error = nil }
        }.sheet(isPresented:$showBriefing) { ScrollView { BriefingView(model:model,briefings:model.briefings) }.padding(20).frame(width:650,height:600) }.sheet(isPresented:$showMemory) { PAMemoryView(memory:assistant.memory,registration:model.chatGPT.activeID) }.sheet(isPresented:$showDictation) {
            DictationView(dictation:dictation) { text in assistant.draft = assistant.draft.isEmpty ? text : assistant.draft + " " + text }
        }.padding(.horizontal, 20).padding(.vertical, 10)
    }
}
struct AssistantSourceSettings: View {
    @Bindable var model: DashboardModel
    @Bindable var assistant: AssistantService
    var body: some View {
        Section("Assistant preferences and sources") {
            Toggle("Enable assistant source context", isOn: $assistant.contextEnabled)
            Text("When enabled, assistant requests send the enabled calendar and reminder snapshots, recent email headers and saved email summaries to OpenAI using your ChatGPT plan. Email body processing is enabled separately under Incoming email monitoring. Dashboard refresh itself makes no AI requests.").font(.caption)
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
