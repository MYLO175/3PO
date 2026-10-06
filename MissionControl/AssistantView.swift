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
    @State private var showRename = false
    @FocusState private var composerFocused: Bool
    private var selectedID: UUID? { assistant.feed?.id }
    private var selected: AssistantConversation? {
        guard var feed = assistant.feed else { return nil }
        feed.turns = ConversationRules.thread(feed:feed,topic:topic).filter { $0.profileSessionID == nil }
        return feed
    }
    private var selectedTopicID:UUID? { nil }
    private var focusAreas:[LifeArea] {
        if configuration == nil { return LifeFocusRules.normalised(assistant.standaloneFocusSelections[model.chatGPT.activeID] ?? []) }
        if let saved=configuration?.wrappedValue.lifeFocusSelections?[model.chatGPT.activeID] { return LifeFocusRules.normalised(saved) }
        let legacy=configuration?.wrappedValue.paTopicSelections?[model.chatGPT.activeID].flatMap(UUID.init(uuidString:))
        return assistant.conversation(legacy)?.notebookAreas ?? []
    }
    private var focusBinding:Binding<[LifeArea]> { Binding(get:{focusAreas},set:{areas in
        guard let configuration else { assistant.standaloneFocusSelections[model.chatGPT.activeID]=areas.map(\.rawValue);return }
        var value=configuration.wrappedValue
        if value.lifeFocusSelections == nil { value.lifeFocusSelections=[:] }
        value.lifeFocusSelections?[model.chatGPT.activeID]=areas.map(\.rawValue);configuration.wrappedValue=value
    }) }
    private var topic: AssistantConversation? { assistant.conversation(selectedTopicID) }
    private var draftKey: UUID? { selectedTopicID ?? selectedID }
    private var sendingHere: Bool { assistant.busy && !assistant.profileBusy(selectedTopicID) && assistant.requestConversationID == selectedID && assistant.requestTopicID == selectedTopicID }
    private var errorHere: Bool { assistant.errorProfileSessionID == nil && (assistant.errorConversationID == nil || (assistant.errorConversationID == selectedID && assistant.errorTopicID == selectedTopicID)) }
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
    private func send() {
        let value = draft.wrappedValue, contextID = selectedTopicID, key = draftKey, registration = model.chatGPT.activeID
        if assistant.send(model:model,topicID:contextID,prompt:value,focusAreas:focusAreas) {
            if let widgetID { assistant.drafts.set("",registration:registration,widget:widgetID,conversation:key) } else { assistant.draft = "" }
            assistant.drafts.flush()
        }
    }
    private func showDraft() {
        if let widgetID { assistant.drafts.show(registration:model.chatGPT.activeID,widget:widgetID,conversation:draftKey) }
        if !draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { model.memoryLearning.cancel(); model.proactive.cancel();model.heartbeat.userStartedTyping() }
    }
    @State private var dictation = DictationService()
    @State private var showDictation = false
    @State private var showMemory = false
    @State private var showProfileSetup = false
    @State private var showBriefing = false
    @State private var visibleTurnLimit=40
    private var visibleTurns:[AssistantTurn] { (selected?.turns ?? []).filter(turnVisible) }
    private var displayedTurns:[AssistantTurn] { Array(visibleTurns.suffix(visibleTurnLimit)) }
    private func divider(_ turn:AssistantTurn)->String? { guard let index=visibleTurns.firstIndex(where:{$0.id == turn.id}) else { return nil };return ConversationRules.separator(before:turn,previous:index > 0 ? visibleTurns[index-1] : nil,previousHuman:visibleTurns.prefix(index).last{$0.role == "user"}) }
    @State private var sourceDiscovery:PADiscovery?
    @State private var reviewingProject:PADiscovery?
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
        } else if record.kind == "project" {
            if model.assistant.projects.receipt("project-suggestion:"+record.id,registration:record.registration) != nil { Label("Created",systemImage:"checkmark.circle").font(.caption) }
            else { Button("Review project…") { reviewingProject=record }.disabled(model.writing || model.assistant.projects.readOnly) }
        } else if ["calendar","reminder"].contains(record.kind) {
            Button(record.kind == "calendar" ? "Review event" : "Review reminder") { model.reviewDiscovery(record) }.disabled(model.writing)
            Menu("Instead…") {
                Button(record.kind == "calendar" ? "Remind me instead…" : "Review as an event…") { model.reviewDiscovery(record,as:record.kind == "calendar" ? .reminder : .event) }
            }.disabled(model.writing)
        }
    }
    @ViewBuilder private func discoverySourceButtons(_ record: PADiscovery) -> some View {
        Button(record.sourceKind == "whatsapp" ? "Source message" : "Source email") { if record.sourceKind == "whatsapp" { sourceDiscovery=record } else if let message = model.emailSummaries.highlights(model).first(where:{ $0.0.id == record.mailID })?.0 { model.select(message) } }
        Button("Dismiss") { model.proactive.dismiss(record) }
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing:8) {
                Label(assistant.displayName,systemImage:"sparkles").font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength:4)
                LifeFocusPicker(selection:focusBinding).frame(maxWidth:160,alignment:.trailing)
                Menu {
                    Button("Name your PA…") { showRename = true }
                    Button("Memory…") { showMemory = true }
                    Button(assistant.setupActive(selectedTopicID) ? "Continue memory setup…" : "Set up my PA…") { showProfileSetup=true }
                    Text(assistant.contextEnabled ? "Apple source context enabled" : "Apple source context off")
                } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("PA options").accessibilityLabel("PA options").disabled(assistant.busy)
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
                        if visibleTurns.count > visibleTurnLimit { Button("Earlier conversation (\(visibleTurns.count-visibleTurnLimit) messages)") { visibleTurnLimit+=40 }.font(.caption).frame(maxWidth:.infinity) }
                        if visibleTurnLimit > 40 { Button("Collapse older conversation") { visibleTurnLimit=40 }.font(.caption).frame(maxWidth:.infinity) }
                        ForEach(displayedTurns) { turn in
                            if let separator=divider(turn) { Text(separator).font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth:.infinity).padding(.vertical,6) }
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
                                if turn.completed, turn.role == "assistant",turn.id == selected?.turns.last?.id,let choices=turn.choices {
                                    ViewThatFits(in:.horizontal) {
                                        HStack { ForEach(choices,id:\.self) { choice in Button(choice) { draft.wrappedValue=choice; send() }.disabled(assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) } }
                                        VStack(alignment:.leading) { ForEach(choices,id:\.self) { choice in Button(choice) { draft.wrappedValue=choice; send() }.disabled(assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) } }
                                    }.controlSize(.small)
                                }
                                if let notes=turn.memoryNotes,!notes.isEmpty {
                                    DisclosureGroup("Memory tool notes") { ForEach(Array(notes.enumerated()),id:\.offset) { _,note in Text(note).font(.caption).foregroundStyle(.orange).textSelection(.enabled) } }
                                        .font(.caption)
                                }
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
                .onChange(of:selectedID) { visibleTurnLimit=40;if let id = selected?.turns.last?.id { proxy.scrollTo(id,anchor:.bottom) } }
                .onChange(of:selectedTopicID) { visibleTurnLimit=40;if let id = selected?.turns.last?.id { proxy.scrollTo(id,anchor:.bottom) } }
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
            let queued=assistant.queue.items.filter { $0.registration == model.chatGPT.activeID && $0.topicID == selectedTopicID && $0.state != .completed }
            if !queued.isEmpty {
                DisclosureGroup("Queued requests (\(queued.count))") {
                    ForEach(queued) { item in
                        HStack(alignment:.top) {
                            VStack(alignment:.leading) { Text(item.prompt).lineLimit(2); Text(item.state == .interrupted ? "Interrupted — check the transcript before submitting again" : item.state == .running ? "Working…" : item.state == .needsAnswer ? "Waiting for your answer in chat" : "Waiting").font(.caption).foregroundStyle(.secondary) }
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
                TextField(PAIdentity.placeholder(assistant.displayName), text: draft,axis:.vertical).lineLimit(1...4).textFieldStyle(.plain).padding(9).background(palette[.input],in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(palette[.border])).onSubmit { send() }.focused($composerFocused).disabled(widgetID != nil && !assistant.drafts.writable)
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
        .onChange(of:selectedTopicID) { showProfileSetup=false; showDraft() }
        .onChange(of:model.chatGPT.activeID) { assistant.drafts.flush(); assistant.openPA(); showMemory = false; showProfileSetup=false;sourceDiscovery=nil; showDraft() }
        .onChange(of:model.proactive.state.records.filter { model.proactive.visible($0,model:model) }.map(\.id)) { if let sourceDiscovery,!model.proactive.visible(sourceDiscovery,model:model) { self.sourceDiscovery=nil } }
        .onChange(of:draft.wrappedValue) { _, draft in
            if !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && model.memoryLearning.busy { model.memoryLearning.cancel() }
        }.onChange(of:model.chatGPT.usagePaused) { _, paused in
            if !paused, assistant.error?.contains("subscription_sharing_usage_limit_exceeded") == true { assistant.error = nil }
        }.sheet(item:$reviewingProject) { record in
            LifeItemEditor(model:model,item:.init(registration:record.registration,kind:.project,title:String((record.sourceTitle ?? "New project").prefix(160)),notes:record.evidence),close:{reviewingProject=nil},reviewedSuggestion:record)
        }.sheet(isPresented:$showRename) { PANameEditor(assistant:assistant) }.sheet(isPresented:$showBriefing) { ScrollView { BriefingView(model:model,briefings:model.briefings) }.padding(20).frame(width:650,height:600) }.sheet(isPresented:$showMemory) { PAMemoryView(memory:assistant.memory,registration:model.chatGPT.activeID,conversationID:selectedTopicID,topicTitle:topic?.title,learning:model.memoryLearning,assistant:assistant,checkContext:{ model.memoryLearning.check(model,manual:true) },organisation:model.lifeOrganisation,organiseContext:{ model.lifeOrganisation.check(model,manual:true,topic:selectedTopicID) }) }.sheet(item:$sourceDiscovery) { record in DiscoveryEvidenceView(record:record) }.sheet(isPresented:$showProfileSetup) {
            PAProfileSetupPanel(model:model,assistant:assistant,topicID:selectedTopicID,registration:model.chatGPT.activeID)
        }.sheet(isPresented:$showDictation) {
            DictationView(dictation:dictation) { text in draft.wrappedValue = draft.wrappedValue.isEmpty ? text : draft.wrappedValue + " " + text }
        }.padding(16)
    }
}
struct AssistantSourceSettings: View {
    @Bindable var model: DashboardModel
    @Bindable var assistant: AssistantService
    var body: some View {
        Section("Assistant preferences and sources") {
            LabeledContent("PA name",value:assistant.displayName)
            PANameSetting(assistant:assistant)
            Toggle("Enable assistant source context", isOn: $assistant.contextEnabled)
            Text("When enabled, assistant requests send the enabled calendar and reminder snapshots, recent email headers and saved email summaries to OpenAI using your ChatGPT plan. Email body processing is enabled separately under Incoming email monitoring. Dashboard refresh itself makes no AI requests.").font(.caption)
            Text("PA calendar: " + model.paOrientationHealth.detail).font(.caption).foregroundStyle(.secondary)
            if let orientation = model.paOrientation {
                Text(orientation.coverage(enabledCount:orientation.calendar.events.filter { !assistant.excludedCalendars.contains($0.calendarID) }.count)).font(.caption).foregroundStyle(.secondary)
            }
            TextField("Assistant preferences", text: $assistant.preferences, axis: .vertical).lineLimit(3...6)
            Text(model.sourceLearning.status(model)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Check recent WhatsApp context") { model.sourceLearning.check(model,manual:true) }.disabled(model.chatGPT.busy || model.sourceLearning.busy || model.chatGPT.usagePaused || model.whatsapp.access(for:model.chatGPT.activeID).learnContext != true)
                if model.sourceLearning.busy { Button("Stop learning") { model.sourceLearning.cancel() } }
            }
            if let error=model.sourceLearning.error { Text(error).font(.caption).foregroundStyle(.orange) }
            Toggle("Automatic PA assessment",isOn:$model.heartbeat.enabled)
            Picker("AI assessment interval",selection:$model.heartbeat.intervalMinutes) { Text("15 minutes").tag(15);Text("30 minutes").tag(30);Text("1 hour").tag(60);Text("2 hours").tag(120) }
            Picker("Daily heartbeat AI requests",selection:$model.heartbeat.dailyCallLimit) { ForEach([8,16,32,64,96],id:\.self) { Text(String($0)).tag($0) } }
            Picker("Daily worthwhile updates",selection:$model.heartbeat.dailyUpdateLimit) { ForEach([1,3,6,10],id:\.self) { Text(String($0)).tag($0) } }
            Text(model.heartbeat.budgetStatus(model.chatGPT.activeID)).font(.caption).foregroundStyle(.secondary)
            Toggle("Check selected WhatsApp chats",isOn:$model.heartbeat.whatsappEnabled)
            Toggle("Notify for worthwhile heartbeat updates",isOn:$model.heartbeat.notificationsEnabled)
            Text(model.heartbeat.status).font(.caption).foregroundStyle(.secondary)
            Text("Mail collects every five minutes independently of AI assessment. Changed or pending material uses the daily AI-request allowance, including email classification and comparison. Source checks continue at the limit. WhatsApp uses received selected-chat text, not full history. Notifications use existing macOS permission. Runs while 3PO is open; catches up on wake.").font(.caption).foregroundStyle(.secondary)
            Button("Check heartbeat now") { model.heartbeat.check(model,manual:true) }.disabled(model.heartbeat.busy || model.assistant.busy || model.chatGPT.busy)
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
