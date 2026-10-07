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
    @State private var composerFocused = false
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
    private var imageDraftWidget:UUID { widgetID ?? UUID(uuidString:"00000000-0000-0000-0000-000000000001")! }
    private var attachedImages:[ChatImageAttachment] { assistant.drafts.images(registration:model.chatGPT.activeID,widget:imageDraftWidget,conversation:draftKey) }
    private var composerEmpty:Bool { draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && attachedImages.isEmpty }
    @State private var imageError:String?
    @State private var composerHeight:CGFloat=22
    private func pasteImage(_ board:NSPasteboard) {
        let registration=model.chatGPT.activeID,key=draftKey,widget=imageDraftWidget
        var added:[ChatImageAttachment]=[]
        do {
            guard attachedImages.count < ChatImageStore.maxImages else { throw ChatImageFailure.size }
            added=try assistant.images.paste(board,registration:registration)
            guard attachedImages.count+added.count <= ChatImageStore.maxImages else { throw ChatImageFailure.size }
            guard assistant.drafts.setImages(attachedImages+added,registration:registration,widget:widget,conversation:key) else { throw ChatImageFailure.storage }
            imageError=nil;model.memoryLearning.cancel();model.sourceLearning.cancel();model.nativeSourceLearning.cancel();model.memoryMaintenance.cancel();model.proactive.cancel();model.heartbeat.userStartedTyping()
        } catch { added.forEach(assistant.images.discard);imageError=error.localizedDescription }
    }
    private func removeImage(_ image:ChatImageAttachment) {
        if assistant.drafts.setImages(attachedImages.filter{$0.id != image.id},registration:model.chatGPT.activeID,widget:imageDraftWidget,conversation:draftKey) {
            assistant.images.discard(image);imageError=nil
        }
    }
    private func send() {
        let attachments=attachedImages
        let value = draft.wrappedValue, contextID = selectedTopicID, key = draftKey, registration = model.chatGPT.activeID
        if assistant.send(model:model,topicID:contextID,prompt:value,focusAreas:focusAreas,images:attachments) {
            if let widgetID { assistant.drafts.set("",registration:registration,widget:widgetID,conversation:key) } else { assistant.draft = "" }
            _ = assistant.drafts.setImages([],registration:registration,widget:imageDraftWidget,conversation:key)
            imageError=nil
            assistant.drafts.flush()
        }
    }
    private func showDraft() {
        assistant.drafts.show(registration:model.chatGPT.activeID,widget:imageDraftWidget,conversation:draftKey)
        imageError=nil
        if !composerEmpty { model.memoryLearning.cancel();model.sourceLearning.cancel();model.nativeSourceLearning.cancel();model.memoryMaintenance.cancel(); model.proactive.cancel();model.heartbeat.userStartedTyping() }
    }
    @State private var dictation = DictationService()
    @State private var showDictation = false
    @State private var showMemory = false
    @State private var inspectingContext:PAContextCapture?
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
                                if let images=turn.images { ForEach(images) { image in PAImagePreview(image:image,store:assistant.images,registration:model.chatGPT.activeID) } }
                                if turn.content.isEmpty && (turn.images ?? []).isEmpty {
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
                                    let content=PAIntentFailure.correctedLegacyReply(turn.content,errors:turn.toolErrors)
                                    Text((try? AttributedString(markdown:content,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(content)).textSelection(.enabled).lineSpacing(3).id(turn.completed)
                                } else if !turn.content.isEmpty { Text(turn.content).textSelection(.enabled) }
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
                                if let errors=turn.toolErrors,!errors.isEmpty {
                                    DisclosureGroup("What went wrong") { ForEach(Array(errors.enumerated()),id:\.offset) { _,reason in Text(reason).font(.caption).textSelection(.enabled) } }.font(.caption)
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
                                if let capture=turn.contextCapture { Button("Context details") { inspectingContext=capture }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary) }
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
                            VStack(alignment:.leading) { Text(item.prompt.isEmpty ? "Attached image" : item.prompt).lineLimit(2);if let images=item.images,!images.isEmpty { Text("\(images.count) attached image(s)").font(.caption) }; Text(item.state == .interrupted ? "Interrupted — check the transcript before submitting again" : item.state == .running ? "Working…" : item.state == .needsAnswer ? "Waiting for your answer in chat" : "Waiting").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if item.state != .running { Button { assistant.discardQueued(item.id) } label:{ Image(systemName:"xmark") }.buttonStyle(.plain).help("Remove queued request") }
                        }
                    }
                    Button("Continue waiting requests") { assistant.resumeQueue(model:model) }.disabled(assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused)
                }.font(.caption)
            }
            if let queueError=assistant.queue.error { Text(queueError).font(.caption).foregroundStyle(.orange) }
            if let error = assistant.drafts.error, widgetID != nil { Text(error).font(.caption).foregroundStyle(.orange) }
            if let imageError { Text(imageError).font(.caption).foregroundStyle(.orange) }
            if !attachedImages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment:.top,spacing:10) {
                        ForEach(attachedImages) { image in
                            VStack(spacing:3) {
                                PAImagePreview(image:image,store:assistant.images,registration:model.chatGPT.activeID,compact:true)
                                Button { removeImage(image) } label:{ Label("Remove",systemImage:"xmark") }.font(.caption).buttonStyle(.plain).accessibilityLabel("Remove attached image")
                            }
                        }
                    }
                }.frame(height:88)
            }
            HStack {
                Button { showDictation = true } label: { Image(systemName:"mic") }.help("Dictate a message").accessibilityLabel("Dictate a message").disabled(widgetID != nil && !assistant.drafts.writable)
                ZStack(alignment:.topLeading) {
                    if draft.wrappedValue.isEmpty { Text(PAIdentity.placeholder(assistant.displayName)).foregroundStyle(.secondary).padding(.top,2).allowsHitTesting(false) }
                    PAChatComposer(text:draft,focused:Binding(get:{composerFocused},set:{composerFocused=$0}),height:$composerHeight,scope:ChatDraftRules.key(registration:model.chatGPT.activeID,widget:imageDraftWidget,conversation:draftKey),enabled:assistant.drafts.writable,textColor:NSColor(palette[.text]),pasteImage:pasteImage,submit:send)
                        .frame(height:composerHeight)
                }.padding(9).background(palette[.input],in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(palette[.border]))
                Button(sendingHere && composerEmpty ? "Stop" : assistant.busy ? "Queue" : "Send") { if sendingHere && composerEmpty { assistant.cancel() } else { send() } }
                    .frame(width:56)
                    .disabled(!sendingHere && ((widgetID != nil && !assistant.drafts.writable) || composerEmpty || (!model.chatGPT.inferenceVerified || (!assistant.busy && model.chatGPT.busy) || model.chatGPT.usagePaused)))
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
        }.onDisappear { assistant.drafts.hide(widget:imageDraftWidget); assistant.drafts.flush() }
        .onChange(of:selectedID) { showDraft() }
        .onChange(of:selectedTopicID) { showProfileSetup=false; showDraft() }
        .onChange(of:model.chatGPT.activeID) { assistant.drafts.flush(); assistant.openPA(); showMemory = false; inspectingContext=nil;showProfileSetup=false;sourceDiscovery=nil; showDraft() }
        .onChange(of:model.proactive.state.records.filter { model.proactive.visible($0,model:model) }.map(\.id)) { if let sourceDiscovery,!model.proactive.visible(sourceDiscovery,model:model) { self.sourceDiscovery=nil } }
        .onChange(of:draft.wrappedValue) { _, draft in
            if !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && model.memoryLearning.busy { model.memoryLearning.cancel() }
        }.onChange(of:model.chatGPT.usagePaused) { _, paused in
            if !paused, assistant.error?.contains("subscription_sharing_usage_limit_exceeded") == true { assistant.error = nil }
        }.sheet(item:$reviewingProject) { record in
            LifeItemEditor(model:model,item:.init(registration:record.registration,kind:.project,title:String((record.sourceTitle ?? "New project").prefix(160)),notes:record.evidence),close:{reviewingProject=nil},reviewedSuggestion:record)
        }.sheet(isPresented:$showRename) { PANameEditor(assistant:assistant) }.sheet(isPresented:$showBriefing) { ScrollView { BriefingView(model:model,briefings:model.briefings) }.padding(20).frame(width:650,height:600) }.sheet(isPresented:$showMemory) { PAMemoryView(memory:assistant.memory,registration:model.chatGPT.activeID,conversationID:selectedTopicID,topicTitle:topic?.title,learning:model.memoryLearning,assistant:assistant,checkContext:{ model.memoryLearning.check(model,manual:true) },organisation:model.lifeOrganisation,organiseContext:{ model.lifeOrganisation.check(model,manual:true,topic:selectedTopicID) },model:model,focusAreas:focusAreas) }.sheet(item:$inspectingContext) { capture in PAContextCaptureView(capture:capture,model:model,registration:model.chatGPT.activeID) }.sheet(item:$sourceDiscovery) { record in DiscoveryEvidenceView(record:record,model:model) }.sheet(isPresented:$showProfileSetup) {
            PAProfileSetupPanel(model:model,assistant:assistant,topicID:selectedTopicID,registration:model.chatGPT.activeID)
        }.sheet(isPresented:$showDictation) {
            DictationView(dictation:dictation) { text in draft.wrappedValue = draft.wrappedValue.isEmpty ? text : draft.wrappedValue + " " + text }
        }.padding(16)
    }
}
struct AssistantSourceSettings: View {
    enum Page { case assistant, background, memory }
    @Bindable var model: DashboardModel
    @Bindable var assistant: AssistantService
    @Environment(\.openWindow) private var openWindow
    var page: Page = .assistant
    @State private var showingActivity=false
    var body: some View {
        Group {
            switch page {
            case .assistant:
                Section("Assistant") {
                    LabeledContent("PA name",value:assistant.displayName)
                    PANameSetting(assistant:assistant)
                    TextField("Assistant preferences", text: $assistant.preferences, axis: .vertical).lineLimit(3...6)
                    Toggle("Use source context in assistant replies", isOn: $assistant.contextEnabled)
                    Text("When on, a reply may send the enabled Calendar and Reminders snapshots, recent email headers, saved email summaries, and separately enabled WhatsApp context to OpenAI through your ChatGPT connection. Dashboard refresh itself makes no AI requests.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Assistant source scope") {
                    sourceMenu("Calendar sources", sources: model.calendarData.sources, excluded: $assistant.excludedCalendars)
                    sourceMenu("Reminder lists", sources: model.reminderData.sources, excluded: $assistant.excludedLists)
                    sourceMenu("Mail accounts", sources: model.mailData.accounts.map { SourceOption(id: $0.id, title: $0.title, account: "", writable: false) }, excluded: $assistant.excludedAccounts)
                    Text("These choices control source context sent with assistant requests. Incoming email assessment, WhatsApp access, learning, task suggestions, and morning brief inclusion have separate controls.").font(.caption).foregroundStyle(.secondary)
                    Text("Calendar status: " + model.paOrientationHealth.detail).font(.caption).foregroundStyle(.secondary)
                    if let orientation = model.paOrientation {
                        Text(orientation.coverage(enabledCount:orientation.calendar.events.filter { !assistant.excludedCalendars.contains($0.calendarID) }.count)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Review inbox") {
                    Toggle("Prepare review items",isOn:$model.proactive.enabled)
                    Text(model.proactive.status(model)).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Check suggestions once") { model.proactive.check(model,manual:true) }.disabled(model.chatGPT.busy || model.proactive.busy || model.chatGPT.usagePaused)
                        if model.proactive.canUndo { Button("Undo dismissed suggestion") { model.proactive.undo(model) } }
                    }
                }
            case .background:
                Section("Background review") {
                    Toggle("Review changed context automatically",isOn:$model.heartbeat.enabled)
                    Picker("Review interval",selection:$model.heartbeat.intervalMinutes) { Text("15 minutes").tag(15);Text("30 minutes").tag(30);Text("1 hour").tag(60);Text("2 hours").tag(120) }
                    Toggle("Include email assessment",isOn:$model.emailSummaries.enabled)
                    Toggle("Include selected WhatsApp chats",isOn:$model.heartbeat.whatsappEnabled)
                    Toggle("Notify when review items are ready",isOn:$model.heartbeat.notificationsEnabled)
                    let progress=model.heartbeat.state.accounts[model.chatGPT.activeID]
                    LabeledContent("Last source check",value:progress?.checked?.formatted(date:.abbreviated,time:.shortened) ?? "Not recorded")
                    LabeledContent("Last completed review",value:progress?.assessed?.formatted(date:.abbreviated,time:.shortened) ?? "Not recorded")
                    LabeledContent("Automatic review",value:model.heartbeat.scheduleStatus(model))
                    if progress?.pending == true { Text("Changed or unfinished review work is waiting.").font(.caption).foregroundStyle(.secondary) }
                    Text(model.heartbeat.statusFor(model.chatGPT.activeID)).font(.caption).foregroundStyle(.secondary)
                    Text("Sources collect without AI. At each review, checked Mail accounts can continue while others wait; their cached data and pending work are kept. Email assessment can run while a Calendar/Reminders comparison is waiting. Proposals appear in Review inbox and require your approval. There is no daily cap on useful items. Reviews run while 3PO is open and your Mac is awake.").font(.caption).foregroundStyle(.secondary)
                    Button("Open Review inbox") {model.workspace.showReviewInbox();openWindow(id:"dashboard")}.disabled(model.workspace.readOnly)
                    Button("Background activity") {showingActivity=true}
                    Button("Review changed context now") { model.heartbeat.check(model,manual:true) }.disabled(model.heartbeat.busy || model.assistant.busy || model.chatGPT.busy)
                    let mailReviewStatus=model.heartbeat.mailReviewStatus(model)
                    if !mailReviewStatus.isEmpty {Text(mailReviewStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)}
                }
                Section("Other background work") {
                    Text("Communication review uses the interval above. Morning briefs have their own schedule under Morning brief below. Conversation/source learning, memory organisation and optional memory review are controlled in Memory. Explicitly queued PA work uses Continue queue. These jobs share idle time but do not all use this interval or allowance.").font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Advanced review limits") {
                    Picker("AI calls for email and communication review",selection:$model.heartbeat.dailyCallLimit) { ForEach([8,16,32,64,96],id:\.self) { Text(String($0)).tag($0) } }
                    Text(model.heartbeat.budgetStatus(model.chatGPT.activeID)).font(.caption).foregroundStyle(.secondary)
                    Text("One review can use several model calls. This cap applies to email and proactive communication review; it is not a cap for every app job or a measure of your ChatGPT subscription allowance.").font(.caption).foregroundStyle(.secondary)
                }
            case .memory:
                Section("Saved memory") {
                    Toggle("Use saved memory in PA replies",isOn:Binding(get:{assistant.memory.enabled},set:{assistant.memory.enabled=$0}))
                    Toggle("Allow memory learning",isOn:Binding(get:{assistant.memory.learningEnabled},set:{assistant.memory.learningEnabled=$0})).disabled(!assistant.memory.enabled)
                    Text("Human memories keep their evidence and correction history. Imported messages are attributed to their source and remain provisional. Forgetting a saved memory prevents the same evidence from being learned again.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Optional WhatsApp context learning") {
                    Text(model.sourceLearning.status(model)).font(.caption).foregroundStyle(.secondary)
                    Text("This is separate from receiving chats, including them in a brief, task suggestions, and ordinary PA source context. It runs only for chats and linked identity you enabled in WhatsApp → PA chat access.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Review recent WhatsApp context") { model.sourceLearning.check(model,manual:true) }.disabled(model.chatGPT.busy || model.sourceLearning.busy || model.chatGPT.usagePaused || model.whatsapp.access(for:model.chatGPT.activeID).learnContext != true)
                        if model.sourceLearning.busy { Button("Stop learning") { model.sourceLearning.cancel() } }
                    }
                    if let error=model.sourceLearning.error { Text(error).font(.caption).foregroundStyle(.orange) }
                }
                Section("Optional source memory") {
                    Text("Learning is separate from source access and Refresh. New opt-ins keep existing content as a baseline; Review once can assess a small existing batch. All source memories stay attributed and provisional. These controls belong to the signed-in account.").font(.caption).foregroundStyle(.secondary)
                    ForEach(NativeLearningRules.kinds,id:\.rawValue) { kind in
                        VStack(alignment:.leading,spacing:6) {
                            Toggle("Learn from " + NativeSourceLearningService.title(kind),isOn:Binding(get:{model.nativeSourceLearning.enabled(kind,registration:model.chatGPT.activeID)},set:{model.nativeSourceLearning.setEnabled($0,kind:kind,model:model)}))
                            Text(model.nativeSourceLearning.status(kind,model:model)).font(.caption).foregroundStyle(.secondary)
                            Text(NativeSourceLearningService.coverage(kind)).font(.caption).foregroundStyle(.secondary)
                            Button("Review " + NativeSourceLearningService.title(kind) + " once") { model.nativeSourceLearning.check(model,kind:kind,manual:true) }
                                .disabled(!model.nativeSourceLearning.enabled(kind,registration:model.chatGPT.activeID) || !assistant.memory.enabled || !assistant.memory.learningEnabled || !assistant.contextEnabled || model.chatGPT.busy || model.nativeSourceLearning.busy || model.sourceLearning.busy || model.chatGPT.usagePaused)
                        }
                    }
                    Text("At most 8 items and 4 facts per pass. Conversation, source learning and organisation share 4 automatic passes/day with a 30-minute gap. Review once is an explicit extra assessment, not a permission to edit Apple apps.").font(.caption).foregroundStyle(.secondary)
                    if model.nativeSourceLearning.busy { Button("Stop source learning") { model.nativeSourceLearning.cancel() } }
                    if let error=model.nativeSourceLearning.error { Text(error).font(.caption).foregroundStyle(.orange) }
                }
            }
        }.sheet(isPresented:$showingActivity) {BackgroundActivityView(model:model)}
    }
    private func sourceMenu(_ title: String, sources: [SourceOption], excluded: Binding<Set<String>>) -> some View {
        Menu(title) {
            ForEach(sources) { source in
                Toggle(source.label, isOn: Binding(get: { !excluded.wrappedValue.contains(source.id) }, set: { enabled in if enabled { excluded.wrappedValue.remove(source.id) } else { excluded.wrappedValue.insert(source.id) } }))
            }
        }
    }
}

struct BackgroundActivityView:View {
    @Bindable var model:DashboardModel
    @Environment(\.dismiss) private var dismiss
    private var registration:String {model.chatGPT.activeID}
    private var runs:[PAReviewRun] {Array((model.heartbeat.state.accounts[registration]?.reviews ?? []).reversed())}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {Text("Background activity").font(.title2.weight(.semibold));Spacer();Button("Done") {dismiss()}.keyboardShortcut(.cancelAction)}
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    activitySection("Communication review") {
                        VStack(alignment:.leading,spacing:8) {
                            Text(model.heartbeat.statusFor(registration)).textSelection(.enabled)
                            Text(model.heartbeat.budgetStatus(registration)).font(.caption).foregroundStyle(.secondary)
                            Text(model.heartbeat.scheduleStatus(model)).font(.callout)
                            Text("This is app review usage, separate from your subscription allowance and other AI jobs.").font(.caption).foregroundStyle(.secondary)
                            let mailStatus=model.heartbeat.mailReviewStatus(model)
                            if !mailStatus.isEmpty {Text(mailStatus).font(.callout)}
                            Text(model.emailSummaries.coverage(model)).font(.caption).foregroundStyle(.secondary)
                            Text("Calendar: "+model.paOrientationHealth.detail).font(.caption)
                            Text("Reminders: "+model.reminderHealth.detail).font(.caption)
                            Text("Recent reminder completions: "+model.completedReminderHealth.detail).font(.caption)
                            Text("Completion evidence covers up to 80 permitted reminders ticked off in the last 30 days. A missing item does not mean it was completed.").font(.caption).foregroundStyle(.secondary)
                            let pending=model.emailSummaries.highlights(model).filter{EmailReplyDraftRules.needsBackgroundDraft($0.1,message:$0.0)}.count
                            Text("\(pending) replies awaiting preparation · \(model.emailSummaries.rejectedCount(model)) emails with rejected assessments").font(.caption)
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(5)
                    }
                    activitySection("Recent reviews") {
                        VStack(alignment:.leading,spacing:12) {
                            if runs.isEmpty {Text("New review activity will be recorded here. Earlier reviews have no detailed history.").foregroundStyle(.secondary)}
                            ForEach(runs) {run in
                                VStack(alignment:.leading,spacing:5) {
                                    HStack {Text(run.started.formatted(date:.abbreviated,time:.shortened)).font(.callout.weight(.semibold));Spacer();Text(run.finished == nil ? (model.heartbeat.reviewInProgress(run,registration:registration) ? "Running" : "Interrupted") : run.phase == "paused" ? "Paused" : run.phase == "waiting" ? "Work waiting" : "Checked").font(.caption)}
                                    Text(run.detail).font(.callout).textSelection(.enabled)
                                    Text("\(run.calls) AI calls · \(run.checkedAccounts) checked Mail accounts · \(run.waitingAccounts) waiting").font(.caption).foregroundStyle(.secondary)
                                    Text("\(run.preparedItems) new proposals · \(run.drafts) new drafts · \(run.handled) new planned/addressed connections").font(.caption).foregroundStyle(.secondary)
                                }
                                Divider()
                            }
                            Text("Last 20 communication reviews for this account. Counts describe saved work, not complete inbox coverage. Source bodies and AI reasoning are not copied into this history.").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(5)
                    }
                    activitySection("Learning from dismissals") {
                        VStack(alignment:.leading,spacing:8) {
                            Text("Dismissal says a review item was unhelpful, not that its task is complete. Repeated similar dismissals guide future assessments; new requests and changed deadlines can still be raised. Undo removes that signal.").font(.caption).foregroundStyle(.secondary)
                            let feedback=model.emailSummaries.dismissalContext(model)
                            if feedback.isEmpty {Text("No recent email dismissal examples.").foregroundStyle(.secondary)}
                            ForEach(Array(feedback.enumerated()),id:\.offset) {_,row in
                                VStack(alignment:.leading,spacing:3) {
                                    Text(row["subject"] ?? "Email").font(.callout)
                                    Text((row["sender"] ?? "")+" · "+(row["similarSenderDismissals"] ?? "1")+" recent dismissals from this sender").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(5)
                    }
                    Text("Opening this page makes no AI request. Sources collect without AI; communication review, morning brief, memory work and explicitly queued work have separate controls. The app must be open and the Mac awake.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(24).frame(width:650,height:650)
    }
    private func activitySection<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:10) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content()
        }.frame(maxWidth:.infinity,alignment:.leading).padding(14)
            .background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
            .accessibilityElement(children:.contain)
    }
}
