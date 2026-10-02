import SwiftUI
import AppKit

struct AssistantPanel: View {
    @Bindable var model: DashboardModel
    @Bindable var assistant: AssistantService
    @Binding var readingMode: Bool
    var supportsReadingMode = true
    var widgetID: UUID? = nil
    var configuration: Binding<WidgetConfiguration>? = nil
    @FocusState private var composerFocused: Bool
    private var selectedID: UUID? {
        let preferred = configuration.map { $0.wrappedValue.conversationSelections?[model.chatGPT.activeID] ?? $0.wrappedValue.conversationID } ?? assistant.activeID
        return ConversationRules.selection(preferred,in:assistant.conversations,registration:model.chatGPT.activeID)
    }
    private var selected: AssistantConversation? { assistant.conversation(selectedID) }
    private var sendingHere: Bool { assistant.busy && assistant.requestConversationID == selectedID }
    private var errorHere: Bool { assistant.errorConversationID == nil || assistant.errorConversationID == selectedID }
    private var draft: Binding<String> {
        Binding(get:{ if let widgetID { return assistant.drafts.text(registration:model.chatGPT.activeID,widget:widgetID,conversation:selectedID) }; return assistant.draft },set:{ text in
            if let widgetID { assistant.drafts.set(text,registration:model.chatGPT.activeID,widget:widgetID,conversation:selectedID) } else { assistant.draft = text }
        })
    }
    private func select(_ id: UUID?) {
        assistant.drafts.flush()
        if let configuration, let id {
            var value = configuration.wrappedValue
            var selections = value.conversationSelections ?? [:]; selections[model.chatGPT.activeID] = id
            value.conversationSelections = selections; value.conversationID = id; configuration.wrappedValue = value
        } else { assistant.activeID = id }
    }
    private func send() {
        let value = draft.wrappedValue, id = selectedID, registration = model.chatGPT.activeID
        if assistant.send(model:model,conversationID:id,prompt:value) {
            if let widgetID { assistant.drafts.set("",registration:registration,widget:widgetID,conversation:id) } else { assistant.draft = "" }
            assistant.drafts.flush()
        }
    }
    private func showDraft() {
        if let widgetID { assistant.drafts.show(registration:model.chatGPT.activeID,widget:widgetID,conversation:selectedID) }
        if !draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { model.memoryLearning.cancel() }
    }
    @State private var dictation = DictationService()
    @State private var showDictation = false
    @State private var showMemory = false
    @State private var showTopic = false
    @State private var topicName = ""
    @State private var topicFocus = ""
    @State private var showBriefing = false
    var body: some View {
        VStack(spacing: 8) {
            Divider()
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Label("Assistant",systemImage:"sparkles").font(.headline)
                    Spacer()
                    Button("Home") { if let id = assistant.openPA() { select(id) } }
                    Button("Memory") { showMemory = true }
                    if supportsReadingMode { Button { readingMode.toggle() } label: { Image(systemName:readingMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }.help(readingMode ? "Compact chat" : "Expand chat") }
                }
                HStack {
                    if !assistant.conversations.isEmpty {
                        Picker("Conversation",selection:Binding(get:{ selectedID },set:{ select($0) })) { ForEach(assistant.conversations) { Text($0.isPrimary == true ? "Home" : $0.title).tag(Optional($0.id)) } }.labelsHidden().frame(maxWidth:280)
                    }
                    Button("New topic") { if let id = assistant.newConversation() { select(id) } }.disabled(assistant.busy).keyboardShortcut(composerFocused ? KeyboardShortcut("n",modifiers:.command) : nil)
                    if selected?.isPrimary != true && selectedID != nil { Button { topicName = selected?.title ?? ""; topicFocus = selected?.focus ?? ""; showTopic = true } label: { Image(systemName:"slider.horizontal.3") }.help("Topic focus").accessibilityLabel("Topic focus").disabled(assistant.busy) }
                    Spacer(minLength:0)
                }
                Text(assistant.contextEnabled ? (selected?.isPrimary == true ? "Your PA · shared memory" : "Topic context · shared preferences") : "Apple source context off").font(.caption).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if selected?.turns.isEmpty ?? true {
                            VStack(alignment:.leading,spacing:12) {
                                Text("A little clarity for your day").font(.headline)
                                Text("Ask about what's coming up, find an email, or tell me what needs doing.").font(.callout).foregroundStyle(.secondary)
                                VStack(alignment:.leading,spacing:6) {
                                    ForEach(["What should I focus on today?","What's coming up this week?"],id:\.self) { suggestion in
                                        Button(suggestion) { draft.wrappedValue = suggestion }.controlSize(.small)
                                    }
                                }
                            }.padding(.vertical,12)
                        }
                        ForEach(selected?.turns ?? []) { turn in
                            HStack(alignment:.top) {
                            if turn.role == "user" { Spacer(minLength:35) }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(turn.role == "user" ? "You" : "Your PA").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                if turn.content.isEmpty {
                                    Text(sendingHere ? "Thinking…" : "This request didn't complete.").foregroundStyle(.secondary)
                                } else if turn.role == "assistant" {
                                    Text((try? AttributedString(markdown:turn.content,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(turn.content)).textSelection(.enabled).lineSpacing(3)
                                } else { Text(turn.content).textSelection(.enabled) }
                                if turn.deliveryID?.contains(":morning:") == true { Button("Briefing and sources") { showBriefing = true }.controlSize(.small) }
                                if turn.role == "assistant" && !turn.completed && !sendingHere && !turn.content.isEmpty { Text("Partial response").font(.caption).foregroundStyle(.orange) }
                                if let date = turn.created { Text(date.formatted(date:.omitted,time:.shortened)).font(.caption2).foregroundStyle(.secondary) }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(turn.role == "user" ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                            if turn.role != "user" { Spacer(minLength:20) }
                            }.id(turn.id)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.onChange(of: selected?.turns.last?.content) { if let id = selected?.turns.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                .onChange(of:selectedID) { if let id = selected?.turns.last?.id { proxy.scrollTo(id,anchor:.bottom) } }
                .onAppear { if let id = selected?.turns.last?.id { proxy.scrollTo(id,anchor:.bottom) } }
            }
            if assistant.mailSearchConversationID == selectedID && !model.mailLookup.status.isEmpty {
                HStack {
                    Text(model.mailLookup.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Menu("Mail sources") { ForEach(model.mailLookup.results) { message in Button(message.account + " · " + message.subject) { model.select(message) } } }
                    if model.mailLookup.hasMore { Button("Continue mail search") { draft.wrappedValue = "Continue the email search."; send() }.disabled(assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) }
                }
            }
            if let error = assistant.error, errorHere, !model.chatGPT.usagePaused { DisclosureGroup("Request didn’t complete") { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }.font(.caption) }
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
                    Text(model.briefings.busy ? "Preparing today’s brief… You can draft a message while it finishes." : model.memoryLearning.busy ? "Learning conversation context… Start drafting to pause learning." : model.emailSummaries.busy ? "Checking incoming mail… You can draft a message while it finishes." : "Checking your ChatGPT connection…").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            if assistant.busy && !sendingHere { Text("Your PA is replying in another chat. You can keep drafting here.").font(.caption).foregroundStyle(.secondary) }
            if let error = assistant.drafts.error, widgetID != nil { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button { showDictation = true } label: { Image(systemName:"mic") }.help("Dictate a message").accessibilityLabel("Dictate a message").disabled(widgetID != nil && !assistant.drafts.writable)
                TextField("Message Mission Control", text: draft,axis:.vertical).lineLimit(1...4).textFieldStyle(.plain).padding(9).background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(Color.primary.opacity(0.08))).onSubmit { send() }.focused($composerFocused).disabled(widgetID != nil && !assistant.drafts.writable)
                if sendingHere { ProgressView().controlSize(.small); Button("Stop") { assistant.cancel() } }
                else { Button("Send") { send() }.disabled(assistant.busy || (widgetID != nil && !assistant.drafts.writable) || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (MemoryRules.explicitRequest(draft.wrappedValue) == nil && (!model.chatGPT.inferenceVerified || model.chatGPT.busy || model.chatGPT.usagePaused))) }
            }
            if errorHere && assistant.error?.contains("Choose the specific target") == true {
                Picker("Specific action target", selection: $model.assistantActions.selectedTarget) {
                    Text("Choose an item").tag("")
                    ForEach(model.assistantActions.targets) { Text($0.label).tag($0.id) }
                }
            }
        }.onAppear {
            if selectedID == nil { assistant.openPA() }
            showDraft()
        }.onDisappear { if let widgetID { assistant.drafts.hide(widget:widgetID) }; assistant.drafts.flush() }
        .onChange(of:selectedID) { showDraft() }
        .onChange(of:model.chatGPT.activeID) { assistant.drafts.flush(); showDraft() }
        .onChange(of:draft.wrappedValue) { _, draft in
            if !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && model.memoryLearning.busy { model.memoryLearning.cancel() }
        }.onChange(of:model.chatGPT.usagePaused) { _, paused in
            if !paused, assistant.error?.contains("subscription_sharing_usage_limit_exceeded") == true { assistant.error = nil }
        }.sheet(isPresented:$showBriefing) { ScrollView { BriefingView(model:model,briefings:model.briefings) }.padding(20).frame(width:650,height:600) }.sheet(isPresented:$showMemory) { PAMemoryView(memory:assistant.memory,registration:model.chatGPT.activeID,conversationID:selected?.isPrimary == true ? nil : selectedID,topicTitle:selected?.title,learning:model.memoryLearning,assistant:assistant,checkContext:{ model.memoryLearning.check(model,manual:true) }) }.sheet(isPresented:$showTopic) {
            VStack(alignment:.leading,spacing:16) {
                Text("Topic focus").font(.title2.weight(.semibold))
                TextField("Topic name",text:$topicName)
                TextField("For example: Help me plan my engineering study and exams",text:$topicFocus,axis:.vertical).lineLimit(4...8)
                Text("This focus and the topic’s own memories guide replies here. Shared PA preferences still apply. Other topics’ memories and chats are not supplied.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Cancel") { showTopic = false }; Spacer(); Button("Save topic") { if let selectedID, assistant.configureTopic(selectedID,title:topicName,focus:topicFocus) { showTopic = false } }.disabled(assistant.busy || topicName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
            }.padding(24).frame(width:480)
        }.sheet(isPresented:$showDictation) {
            DictationView(dictation:dictation) { text in draft.wrappedValue = draft.wrappedValue.isEmpty ? text : draft.wrappedValue + " " + text }
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
