import SwiftUI
import AppKit

struct AssistantPanel: View {
    @Environment(\.workspacePalette) private var palette
    @Bindable var model: DashboardModel
    @Bindable var assistant: AssistantService
    @Binding var readingMode: Bool
    var supportsReadingMode = true
    var widgetID: UUID? = nil
    var configuration: Binding<WidgetConfiguration>? = nil
    @FocusState private var composerFocused: Bool
    private var selectedID: UUID? { assistant.feed?.id }
    private var selected: AssistantConversation? {
        guard var feed = assistant.feed else { return nil }
        feed.turns = ConversationRules.thread(feed:feed,topic:topic)
        return feed
    }
    private var selectedTopicID: UUID? {
        let value = configuration?.wrappedValue
        return ConversationRules.topicSelection(value?.paTopicSelections?[model.chatGPT.activeID],legacy:value.map { $0.conversationSelections?[model.chatGPT.activeID] ?? $0.conversationID } ?? assistant.topicID,in:assistant.conversations,registration:model.chatGPT.activeID)
    }
    private var topic: AssistantConversation? { assistant.conversation(selectedTopicID) }
    private var draftKey: UUID? { selectedTopicID ?? selectedID }
    private var sendingHere: Bool { assistant.busy && assistant.requestConversationID == selectedID && assistant.requestTopicID == selectedTopicID }
    private var errorHere: Bool { assistant.errorConversationID == nil || (assistant.errorConversationID == selectedID && assistant.errorTopicID == selectedTopicID) }
    private var draft: Binding<String> {
        Binding(get:{ if let widgetID { return assistant.drafts.text(registration:model.chatGPT.activeID,widget:widgetID,conversation:draftKey) }; return assistant.draft },set:{ text in
            if let widgetID { assistant.drafts.set(text,registration:model.chatGPT.activeID,widget:widgetID,conversation:draftKey) } else { assistant.draft = text }
        })
    }
    private func turnVisible(_ turn: AssistantTurn) -> Bool {
        guard let delivery = turn.deliveryID else { return true }
        if delivery.hasPrefix("discovery:") {
            guard let record = model.proactive.record(delivery:delivery,model:model) else { return false }
            return model.proactive.visible(record,model:model)
        }
        if delivery.hasPrefix("learn-question:") {
            guard let record = model.memoryLearning.question(delivery:delivery,registration:model.chatGPT.activeID) else { return false }
            return model.memoryLearning.visible(record,assistant:assistant)
        }
        return true
    }
    private func select(_ id: UUID?) {
        assistant.drafts.flush()
        if let configuration {
            var value = configuration.wrappedValue
            var modes = value.paTopicSelections ?? [:]; modes[model.chatGPT.activeID] = id?.uuidString ?? ""
            value.paTopicSelections = modes; configuration.wrappedValue = value
        } else { assistant.topicID = id }
    }
    private func editTopic(_ id: UUID?) {
        editingTopicID = id; editorRegistration = model.chatGPT.activeID
        topicName = assistant.conversation(id)?.title ?? ""; topicFocus = assistant.conversation(id)?.focus ?? ""; showTopic = true
    }
    private func send() {
        let value = draft.wrappedValue, contextID = selectedTopicID, key = draftKey, registration = model.chatGPT.activeID
        if assistant.send(model:model,topicID:contextID,prompt:value) {
            if let widgetID { assistant.drafts.set("",registration:registration,widget:widgetID,conversation:key) } else { assistant.draft = "" }
            assistant.drafts.flush()
        }
    }
    private func showDraft() {
        if let widgetID { assistant.drafts.show(registration:model.chatGPT.activeID,widget:widgetID,conversation:draftKey) }
        if !draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { model.memoryLearning.cancel(); model.proactive.cancel() }
    }
    @State private var dictation = DictationService()
    @State private var showDictation = false
    @State private var showMemory = false
    @State private var showTopic = false
    @State private var showTopicChoices = false
    @State private var editingTopicID: UUID?
    @State private var editorRegistration = ""
    @State private var topicName = ""
    @State private var topicFocus = ""
    @State private var showBriefing = false
    @ViewBuilder private func discoveryActions(_ record: PADiscovery, compact: Bool = false) -> some View {
        if compact {
            HStack { reviewDiscoveryButtons(record) }
            HStack { discoverySourceButtons(record) }
        } else {
            HStack { reviewDiscoveryButtons(record); discoverySourceButtons(record) }
        }
    }
    private func discoveryClaim(_ record: PADiscovery) -> NativeCreationClaim? {
        guard let id = UUID(uuidString:record.id) else { return nil }
        return model.nativeCreations.state.claims[record.registration + ":" + id.uuidString]
    }
    @ViewBuilder private func reviewDiscoveryButtons(_ record: PADiscovery) -> some View {
        if let claim = discoveryClaim(record) {
            Label(claim.receipt == nil ? "Check save outcome" : "Created",systemImage:claim.receipt == nil ? "exclamationmark.circle" : "checkmark.circle").font(.caption).foregroundStyle(.secondary)
        } else {
            Button(record.kind == "calendar" ? "Review event" : "Review reminder") { model.reviewDiscovery(record) }.disabled(model.writing)
            Menu("Instead…") {
                Button(record.kind == "calendar" ? "Remind me instead…" : "Review as an event…") { model.reviewDiscovery(record,as:record.kind == "calendar" ? .reminder : .event) }
            }.disabled(model.writing)
        }
    }
    @ViewBuilder private func discoverySourceButtons(_ record: PADiscovery) -> some View {
        Button("Source email") { if let message = model.emailSummaries.highlights(model).first(where:{ $0.0.id == record.mailID })?.0 { model.select(message) } }
        Button("Dismiss") { model.proactive.dismiss(record) }
    }
    private func topicChoice(_ title: String, id: UUID?) -> some View {
        Button { select(id); showTopicChoices = false } label: {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                if selectedTopicID == id { Image(systemName:"checkmark").font(.caption) }
            }.padding(.horizontal,8).padding(.vertical,6).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing:8) {
                Label("Your PA",systemImage:"sparkles").font(.title3.weight(.semibold)).fixedSize()
                Spacer(minLength:4)
                Button { showTopicChoices.toggle() } label: {
                    HStack(spacing:6) {
                        Text(topic?.title ?? "General").lineLimit(1)
                        Image(systemName:"chevron.down").font(.system(size:9,weight:.semibold))
                    }.font(.caption.weight(.medium)).padding(.horizontal,10).padding(.vertical,6)
                        .background(palette[.assistantBubble],in:Capsule())
                }.buttonStyle(.plain).fixedSize(horizontal:false,vertical:true).frame(maxWidth:150,alignment:.trailing)
                    .help("Choose a PA topic").accessibilityLabel("PA topic: " + (topic?.title ?? "No topic"))
                    .popover(isPresented:$showTopicChoices,arrowEdge:.bottom) {
                        VStack(alignment:.leading,spacing:4) {
                            Text("PA topic").font(.caption).foregroundStyle(.secondary).padding(.bottom,4)
                            topicChoice("General",id:nil)
                            ScrollView { VStack(alignment:.leading,spacing:4) {
                                ForEach(assistant.topics) { topic in topicChoice(topic.title,id:topic.id) }
                            } }.frame(maxHeight:240)
                            Divider()
                            Button("Add topic…") { showTopicChoices = false; editTopic(nil) }.buttonStyle(.borderless)
                        }.padding(12).frame(width:220)
                    }
                Menu {
                    Button("Memory…") { showMemory = true }
                    if let selectedTopicID { Button("Edit topic focus…") { editTopic(selectedTopicID) } }
                    Button("Add topic…") { editTopic(nil) }
                    Text(assistant.contextEnabled ? "Apple source context enabled" : "Apple source context off")
                } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Topic options").accessibilityLabel("Topic options").disabled(assistant.busy)
                if supportsReadingMode { Button { readingMode.toggle() } label: { Image(systemName:readingMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }.help(readingMode ? "Compact chat" : "Expand chat") }
            }.buttonStyle(.borderless).controlSize(.small)
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
                        ForEach((selected?.turns ?? []).filter(turnVisible)) { turn in
                            let replyingHere = turn.role == "assistant" && sendingHere && assistant.requestTurnID == turn.id
                            HStack(alignment:.top) {
                            if turn.role == "user" { Spacer(minLength:35) }
                            VStack(alignment: .leading, spacing: 5) {
                                if turn.content.isEmpty {
                                    Text(replyingHere ? (assistant.toolStatus.isEmpty ? "Thinking…" : assistant.toolStatus) : "This request didn't complete.").foregroundStyle(.secondary)
                                } else if turn.role == "assistant", turn.deliveryID?.hasPrefix("learned:") == true {
                                    HStack {
                                        Label("Provisional memory",systemImage:"brain").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Review") { showMemory = true }.controlSize(.small)
                                    }
                                    Text(turn.content.components(separatedBy:"\n\n").first ?? turn.content).lineLimit(3).textSelection(.enabled)
                                    DisclosureGroup("Details") { Text(turn.content).textSelection(.enabled) }.font(.caption)
                                } else if turn.role == "assistant" {
                                    Text((try? AttributedString(markdown:turn.content,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(turn.content)).textSelection(.enabled).lineSpacing(3).id(turn.completed)
                                } else { Text(turn.content).textSelection(.enabled) }
                                if replyingHere && !turn.content.isEmpty {
                                    Text(assistant.toolStatus.isEmpty ? "Thinking…" : assistant.toolStatus).font(.caption).foregroundStyle(.secondary)
                                }
                                if turn.deliveryID?.contains(":morning:") == true { Button("Briefing and sources") { showBriefing = true }.controlSize(.small) }
                                if let delivery = turn.deliveryID, let record = model.proactive.record(delivery:delivery,model:model) {
                                    ViewThatFits(in:.horizontal) {
                                    discoveryActions(record)
                                    VStack(alignment:.leading,spacing:6) { discoveryActions(record,compact:true) }
                                    }.controlSize(.small)

                                }
                                if let delivery = turn.deliveryID, let question = model.memoryLearning.question(delivery:delivery,registration:model.chatGPT.activeID) {
                                    DisclosureGroup("Why I’m asking") { Text("“" + question.evidence + "”").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }.font(.caption)
                                    Button("Dismiss question") { model.memoryLearning.dismiss(question) }.controlSize(.small)
                                }
                                if turn.role == "assistant" && !turn.completed && assistant.requestTurnID != turn.id && !turn.content.isEmpty { Text("Partial response").font(.caption).foregroundStyle(.orange) }
                                if let date = turn.created { Text(date.formatted(date:.omitted,time:.shortened)).font(.caption2).foregroundStyle(.secondary) }
                            }.font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children:.contain).accessibilityLabel(turn.role == "user" ? "Your message" : "PA message").background(palette[turn.role == "user" ? .userBubble : .assistantBubble],in:RoundedRectangle(cornerRadius:10))
                            if turn.role != "user" { Spacer(minLength:20) }
                            }.id(turn.id)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.onChange(of: selected?.turns.last?.content) { if let id = selected?.turns.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                .onChange(of:selectedID) { if let id = selected?.turns.last?.id { proxy.scrollTo(id,anchor:.bottom) } }
                .onChange(of:selectedTopicID) { if let id = selected?.turns.last?.id { proxy.scrollTo(id,anchor:.bottom) } }
                .onAppear { if let id = selected?.turns.last?.id { proxy.scrollTo(id,anchor:.bottom) } }
            }
            if model.memoryLearning.canUndoQuestion(model.chatGPT.activeID) { HStack { Text("Question dismissed").font(.caption).foregroundStyle(.secondary); Button("Undo") { model.memoryLearning.undoQuestion(model.chatGPT.activeID) }.controlSize(.small); Spacer() } }
            if assistant.mailSearchConversationID == selectedID && assistant.mailSearchTopicID == selectedTopicID, let lookup = assistant.visibleMailLookup, !lookup.status.isEmpty {
                HStack {
                    Text(lookup.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Menu("Mail sources") { ForEach(lookup.results) { message in Button(message.account + " · " + message.subject) { model.select(message) } } }
                    if lookup.hasUnavailable { Button("Retry unavailable reads") { draft.wrappedValue = "Retry unavailable mail reads."; send() }.disabled(assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) }
                    if lookup.hasMore { Button("Continue mail search") { draft.wrappedValue = "Continue the email search."; send() }.disabled(assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) }
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
                    Text(model.briefings.busy ? "Preparing today’s brief… You can draft a message while it finishes." : model.memoryLearning.busy ? "Learning conversation context… Start drafting to pause learning." : model.proactive.busy ? "Checking useful suggestions… Start drafting to pause the check." : model.emailSummaries.busy ? "Checking incoming mail… You can draft a message while it finishes." : "Checking your ChatGPT connection…").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            let queued=assistant.queue.items.filter { $0.registration == model.chatGPT.activeID && $0.topicID == selectedTopicID }
            if !queued.isEmpty {
                DisclosureGroup("Queued requests (\(queued.count))") {
                    ForEach(queued) { item in
                        HStack(alignment:.top) {
                            VStack(alignment:.leading) { Text(item.prompt).lineLimit(2); Text(item.state == .interrupted ? "Interrupted — check the transcript before submitting again" : item.state == .running ? "Working…" : "Waiting").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if item.state != .running { Button { assistant.discardQueued(item.id) } label:{ Image(systemName:"xmark") }.buttonStyle(.plain).help("Remove queued request") }
                        }
                    }
                    Button("Continue waiting requests") { assistant.resumeQueue(model:model) }.disabled(assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused)
                }.font(.caption)
            }
            if let queueError=assistant.queue.error { Text(queueError).font(.caption).foregroundStyle(.orange) }
            if let error = assistant.drafts.error, widgetID != nil { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button { showDictation = true } label: { Image(systemName:"mic") }.help("Dictate a message").accessibilityLabel("Dictate a message").disabled(widgetID != nil && !assistant.drafts.writable)
                TextField("Message your PA", text: draft,axis:.vertical).lineLimit(1...4).textFieldStyle(.plain).padding(9).background(palette[.input],in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(palette[.border])).onSubmit { send() }.focused($composerFocused).disabled(widgetID != nil && !assistant.drafts.writable)
                Button(sendingHere && draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "Stop" : assistant.busy ? "Queue" : "Send") { if sendingHere && draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { assistant.cancel() } else { send() } }
                    .frame(width:56)
                    .disabled(!sendingHere && ((widgetID != nil && !assistant.drafts.writable) || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!model.chatGPT.inferenceVerified || (!assistant.busy && model.chatGPT.busy) || model.chatGPT.usagePaused)))
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
        }.task(id:model.assistantFocusRequest?.id) {
            guard let request = model.assistantFocusRequest, request.widgetID == widgetID else { return }
            // Navigation first mounts the selected widget and its saved draft.
            await Task.yield()
            guard !Task.isCancelled, model.assistantFocusRequest == request else { return }
            composerFocused = true
            model.assistantFocusRequest = nil
        }.onDisappear { if let widgetID { assistant.drafts.hide(widget:widgetID) }; assistant.drafts.flush() }
        .onChange(of:selectedID) { showDraft() }
        .onChange(of:selectedTopicID) { showDraft() }
        .onChange(of:model.chatGPT.activeID) { assistant.drafts.flush(); assistant.openPA(); showTopic = false; showTopicChoices = false; showMemory = false; showDraft() }
        .onChange(of:draft.wrappedValue) { _, draft in
            if !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && model.memoryLearning.busy { model.memoryLearning.cancel() }
        }.onChange(of:model.chatGPT.usagePaused) { _, paused in
            if !paused, assistant.error?.contains("subscription_sharing_usage_limit_exceeded") == true { assistant.error = nil }
        }.sheet(isPresented:$showBriefing) { ScrollView { BriefingView(model:model,briefings:model.briefings) }.padding(20).frame(width:650,height:600) }.sheet(isPresented:$showMemory) { PAMemoryView(memory:assistant.memory,registration:model.chatGPT.activeID,conversationID:selectedTopicID,topicTitle:topic?.title,learning:model.memoryLearning,assistant:assistant,checkContext:{ model.memoryLearning.check(model,manual:true) }) }.sheet(isPresented:$showTopic) {
            TopicFocusEditor(assistant:assistant,topicID:$editingTopicID,registration:$editorRegistration,name:$topicName,focus:$topicFocus,onSelected:select)
        }.sheet(isPresented:$showDictation) {
            DictationView(dictation:dictation) { text in draft.wrappedValue = draft.wrappedValue.isEmpty ? text : draft.wrappedValue + " " + text }
        }.padding(16)
    }
}
// Bindings let a newly presented sheet read the current context, rather than a stale presentation closure.
private struct TopicFocusEditor: View {
    @Bindable var assistant: AssistantService
    @Binding var topicID: UUID?
    @Binding var registration: String
    @Binding var name: String
    @Binding var focus: String
    var onSelected: (UUID?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saveFailed = false
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(topicID == nil ? "Add a topic" : "Topic focus").font(.title2.weight(.semibold))
            TextField("Topic name",text:$name)
            TextField("For example: Help me plan my engineering study and exams",text:$focus,axis:.vertical).lineLimit(4...8)
            Text("A topic adds focus and its own memories to your PA. It has its own ongoing thread. Shared preferences still apply; other topics’ context stays separate.").font(.caption).foregroundStyle(.secondary)
            if saveFailed { Text("The topic could not be saved. Your changes are still here.").font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }; Spacer()
                Button("Save topic") {
                    guard registration == assistant.connection.activeID else { return }
                    if let topicID { if assistant.configureTopic(topicID,title:name,focus:focus) { dismiss() } else { saveFailed = true } }
                    else if let id = assistant.createTopic(title:name,focus:focus) { onSelected(id); dismiss() }
                    else { saveFailed = true }
                }.disabled(assistant.busy || registration != assistant.connection.activeID || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width:480)
    }
}
struct AssistantSourceSettings: View {
    @Bindable var model: DashboardModel
    @Bindable var assistant: AssistantService
    var body: some View {
        Section("Assistant preferences and sources") {
            Toggle("Enable assistant source context", isOn: $assistant.contextEnabled)
            Text("When enabled, assistant requests send the enabled calendar and reminder snapshots, recent email headers and saved email summaries to OpenAI using your ChatGPT plan. Email body processing is enabled separately under Incoming email monitoring. Dashboard refresh itself makes no AI requests.").font(.caption)
            Text("PA calendar: " + model.paOrientationHealth.detail).font(.caption).foregroundStyle(.secondary)
            if let orientation = model.paOrientation {
                Text(orientation.coverage(enabledCount:orientation.calendar.events.filter { !assistant.excludedCalendars.contains($0.calendarID) }.count)).font(.caption).foregroundStyle(.secondary)
            }
            TextField("Assistant preferences", text: $assistant.preferences, axis: .vertical).lineLimit(3...6)
            Toggle("Quiet proactive suggestions",isOn:$model.proactive.enabled)
            Text(model.proactive.status(model)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Check suggestions once") { model.proactive.check(model,manual:true) }.disabled(model.chatGPT.busy || model.proactive.busy || model.chatGPT.usagePaused)
                if model.proactive.canUndo { Button("Undo dismissed suggestion") { model.proactive.undo(model) } }
            }
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
