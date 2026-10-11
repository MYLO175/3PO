import SwiftUI
struct EmailOverviewView: View {
    @Bindable var model: DashboardModel
    @Bindable var summaries: EmailSummaryService
    var configuration: Binding<WidgetConfiguration>? = nil
    @State private var filter = "All"
    @State private var limit = 6
    @State private var showRelevance=false
    private var available: [(MailMessage,EmailSummary)] {
        summaries.highlights(model).filter { message,summary in
            !(configuration?.wrappedValue.sourceExclusions.contains(message.accountID) ?? false) && (filter == "All" || (filter == "Needs action" ? EmailHighlightRules.needsAction(summary,replied:message.replied) : filter == "Worth reading" ? summary.worthReading == true && !EmailHighlightRules.needsAction(summary,replied:message.replied) : summary.followUpDate != nil))
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label("Email summary",systemImage:"envelope.badge").font(.title3.weight(.semibold)); Spacer()
                Button {showRelevance=true} label:{Image(systemName:"slider.horizontal.3")}.help("What matters to me").accessibilityLabel("What matters to me")
                Button { summaries.process(model,resume:true) } label: { Image(systemName:"arrow.clockwise") }.help("Check incoming mail").accessibilityLabel("Check incoming mail").disabled(!summaries.enabled || summaries.busy || model.chatGPT.busy || model.assistant.busy || model.chatGPT.usagePaused || !model.chatGPT.inferenceVerified)
                if summaries.busy { ProgressView().controlSize(.small); Button("Stop") { summaries.cancel() } }
            }
            HStack {
                Picker("Show",selection:$filter) { ForEach(["All","Needs action","Worth reading","Future dates"],id:\.self) { Text($0).tag($0) } }.labelsHidden().frame(maxWidth:160)
                if let configuration {
                    Menu("Accounts") {
                        ForEach(model.mailData.accounts) { account in
                            Toggle(account.title,isOn:Binding(get:{ !configuration.wrappedValue.sourceExclusions.contains(account.id) },set:{ on in var value = configuration.wrappedValue; if on { value.sourceExclusions.remove(account.id) } else { value.sourceExclusions.insert(account.id) }; configuration.wrappedValue = value }))
                        }
                    }
                }
                Spacer(minLength:0)
            }
            if summaries.canUndoDismiss { HStack { Text("Suggestion dismissed").font(.caption).foregroundStyle(.secondary); Button("Undo") { summaries.undoDismiss(model) }.controlSize(.small); Spacer() } }
            ScrollView {
                LazyVStack(alignment:.leading,spacing:10) {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:250),spacing:12,alignment:.top)],alignment:.leading,spacing:12) {
                    ForEach(Array(available.prefix(limit)),id:\.0.id) { message,summary in
                        VStack(alignment:.leading,spacing:8) {
                            HStack(alignment:.top) {
                                Text(EmailHighlightRules.category(summary,replied:message.replied)).font(.caption.weight(.semibold)).foregroundStyle(summary.attention ? Color.accentColor : Color.secondary)
                                Spacer()
                                ReviewFeedbackButton(model:model,topic:message.subject,isCurrent:{model.emailSummaries.feedbackSourceCurrent(message,summary:summary,model:model)})
                                Button { summaries.dismiss(message.id,model:model,expectedRegistration:summary.registration,expectedVersion:ReviewAcknowledgementRules.emailVersion(message,summary)) } label: { Image(systemName:"xmark") }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).help("Dismiss suggestion").accessibilityLabel("Dismiss email suggestion")
                            }
                            Text(message.subject).font(.callout.weight(.semibold)).lineLimit(2)
                            Text(summary.summary).font(.callout).lineSpacing(3).lineLimit(4).textSelection(.enabled)
                            if let date = summary.followUpDate { Label(date,systemImage:"calendar").font(.caption).foregroundStyle(.secondary) }
                            if let relevance=summary.personalRelevance {Label(relevance.reason,systemImage:"person.crop.circle.badge.checkmark").font(.caption).foregroundStyle(.secondary)}
                            DisclosureGroup("Why this matters") {
                                VStack(alignment:.leading,spacing:6) { Text(summary.summary).textSelection(.enabled); if !summary.reason.isEmpty { Text(summary.reason) }; if !summary.evidence.isEmpty { Text("“" + summary.evidence + "”").foregroundStyle(.secondary).textSelection(.enabled) } }.font(.caption)
                            }.font(.caption)
                            HStack { Text(message.account + " · " + message.received.formatted(date:.abbreviated,time:.omitted)).font(.caption2).foregroundStyle(.secondary); Spacer(); Button("Read original") { model.select(message) }.buttonStyle(.link).font(.caption) }
                        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
                    }
                    }
                    if available.count > limit { Button("Show more (\(available.count-limit))") { limit += 6 }.controlSize(.small) }
                    if available.isEmpty { ContentUnavailableView("Nothing highlighted here",systemImage:"envelope.open",description:Text(!summaries.enabled ? "Enable incoming email monitoring in Settings. It reads relevant new mail without summarising the historical inbox." : "No saved suggestions match this view. Coverage is partial while new mail is being checked.")) }
                    DisclosureGroup("Coverage and controls") {
                        VStack(alignment:.leading,spacing:8) {
                            Text(summaries.coverage(model)).font(.caption).foregroundStyle(.secondary)
                            Text("AI suggestions can be mistaken. Reply flags are hints; email is read-only here. Dismiss hides a suggestion without changing Mail.").font(.caption).foregroundStyle(.secondary)
                            if summaries.rejectedCount(model) > 0 { Button("Retry skipped assessments") { summaries.retryRejected(model) }.disabled(summaries.busy || model.chatGPT.busy || model.chatGPT.usagePaused) }
                        }.padding(.top,6)
                    }.font(.caption)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            if summaries.paused || model.chatGPT.usagePaused { Text(model.chatGPT.usagePaused ? "Subscription processing paused; saved suggestions are available." : "Monitoring paused. Check incoming mail to resume one bounded batch.").font(.caption).foregroundStyle(.orange) }
            if let error = summaries.error { DisclosureGroup("Monitoring details") { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }.font(.caption) }
        }.sheet(isPresented:$showRelevance) {ReviewRelevancePreferencesView(model:model)}.onChange(of:model.chatGPT.activeID) {showRelevance=false}.onChange(of:filter) { limit = 6 }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
}
struct EmailSummarySettings: View {
    @Bindable var model: DashboardModel
    @Bindable var summaries: EmailSummaryService
    var body: some View {
        Section("Incoming email assessment") {
            Picker("Email summary model", selection: $summaries.modelID) {
                Text("Use assistant model").tag("")
                ForEach(model.chatGPT.models) { Text($0.name).tag($0.id) }
            }.disabled(summaries.busy)
            Picker("Email reasoning", selection: $summaries.effort) {
                Text("Low").tag("low"); Text("Medium").tag("medium"); Text("High").tag("high")
            }.disabled(summaries.busy)
            Text("Heartbeats analyse collected permitted mail and prepare relevant reply drafts through your ChatGPT plan. Mail refreshes separately every five minutes. Completed assessments are reused; collection issues are shown without discarding collected data. A failed AI check tries again at the next heartbeat. Nothing is sent.").font(.caption)
            Text("Choose permitted mail accounts in Settings → Assistant → Assistant source scope. Mailbox filters change only the source view.").font(.caption).foregroundStyle(.secondary)
        }
    }
}


struct ReviewPreferenceDraft:Identifiable {
    var id=UUID()
    var value:ReviewRelevancePreference
    var expected:ReviewRelevancePreference?
    var isCurrent:()->Bool={true}
    var onSaved:()->Void={}
}
struct ReviewFeedbackButton:View {
    @Bindable var model:DashboardModel
    var topic:String
    var isCurrent:()->Bool
    @State private var showingFeedback=false
    @State private var saved=false
    var body:some View {
        HStack(spacing:8) {
            Button("Feedback") {showingFeedback=true}.controlSize(.small).help("Explain what matters; save your words in PA memory")
            if saved {Text("Saved in PA memory").font(.caption).foregroundStyle(.secondary)}
        }
        .sheet(isPresented:$showingFeedback) {ReviewFeedbackEditor(model:model,topic:topic,isCurrent:isCurrent,onSaved:{saved=true})}
        .onChange(of:model.chatGPT.activeID) {showingFeedback=false;saved=false}
    }
}
struct ReviewFeedbackEditor:View {
    @Bindable var model:DashboardModel
    var topic:String=""
    var expected:PAMemory? = nil
    var isCurrent:()->Bool={true}
    var onSaved:()->Void={}
    private let registration:String
    @Environment(\.dismiss) private var dismiss
    @State private var words:String
    @State private var about:String
    @State private var error:String?
    init(model:DashboardModel,topic:String="",expected:PAMemory?=nil,isCurrent:@escaping ()->Bool={true},onSaved:@escaping ()->Void={}) {
        self.model=model;self.topic=topic;self.expected=expected;self.isCurrent=isCurrent;self.onSaved=onSaved;registration=model.chatGPT.activeID;_words=State(initialValue:expected?.text ?? "");_about=State(initialValue:expected?.reviewContext ?? String(topic.prefix(300)))
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text(expected == nil ? "Feedback" : "Edit review preference").font(.title2.weight(.semibold))
            LabeledContent("About") {TextField("Optional topic",text:$about).textFieldStyle(.roundedBorder).accessibilityLabel("Feedback topic")}
            Text("The topic helps your PA understand feedback such as ‘these can stay quiet’. You can make it broader or more specific.").font(.caption).foregroundStyle(.secondary)
            Text("What should your PA learn about what is worth reviewing?").font(.headline)
            TextEditor(text:$words).frame(height:140).font(.body).border(Color.secondary.opacity(0.25))
            Text("For example: Assessment submission confirmations can stay quiet. Invitations to complete an assessment, new stages and results are important to me.").font(.caption).foregroundStyle(.secondary)
            Text("Your exact words will be saved as a preference in PA memory. You can edit or disable it in Review preferences or Memory. Dismiss only means acknowledged.").font(.caption).foregroundStyle(.secondary)
            if !model.assistant.memory.enabled {Text("Memory use is paused. The preference will be saved and used when you turn it back on.").font(.caption).foregroundStyle(.secondary)}
            if let error {Text(error).font(.caption).foregroundStyle(.orange)}
            HStack {
                Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save to memory") {
                    guard registration == model.chatGPT.activeID,isCurrent() else {error="The item or account changed. Reopen Feedback before saving.";return}
                    guard model.assistant.memory.saveReviewPreference(words,registration:registration,expected:expected,about:about) else {error=model.assistant.memory.error;return}
                    onSaved();dismiss()
                }.keyboardShortcut(.defaultAction).disabled(words.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || words.count > 2000 || about.count > 300)
            }
        }.padding(24).frame(width:540).onChange(of:model.chatGPT.activeID) {dismiss()}
    }
}
struct ReviewRelevanceEditor:View {
    @Bindable var model:DashboardModel
    let draft:ReviewPreferenceDraft
    @Environment(\.dismiss) private var dismiss
    @State private var topic:String
    @State private var direction:String
    @State private var error:String?
    init(model:DashboardModel,draft:ReviewPreferenceDraft) {
        self.model=model;self.draft=draft;_topic=State(initialValue:draft.value.topic);_direction=State(initialValue:draft.value.direction)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Review preferences").font(.title2.weight(.semibold))
            Text("Choose the kind of information this applies to. Future reviews and briefs will use your preference.").font(.callout)
            TextField("Topic or kind of request",text:$topic).textFieldStyle(.roundedBorder).accessibilityLabel("Relevance topic")
            Picker("Attention",selection:$direction) {Text("Less attention").tag("less");Text("Prioritise").tag("more")}.pickerStyle(.segmented)
            Text("For example: society treasurer budget requests, or updates about my current engineering project. Other requests from the same sender can still matter.").font(.caption).foregroundStyle(.secondary)
            if let error {Text(error).foregroundStyle(.orange).font(.caption)}
            HStack {Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction);Spacer();Button("Save preference") {
                do {
                    guard draft.isCurrent(),draft.value.registration == model.chatGPT.activeID else {throw ActionFailure.message("The item or account changed. Reopen its feedback before saving.")}
                    var value=draft.value;value.topic=topic;value.direction=direction
                    try model.emailSummaries.savePreference(value,expected:draft.expected,model:model)
                    if direction == "less" {draft.onSaved()}
                    dismiss()
                } catch {self.error=error.localizedDescription}
            }.keyboardShortcut(.defaultAction).disabled(topic.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || topic.count > 300)}
        }.padding(24).frame(width:520)
    }
}
struct ReviewRelevancePreferencesView:View {
    @Bindable var model:DashboardModel
    private let registration:String
    @Environment(\.dismiss) private var dismiss
    @State private var editing:ReviewPreferenceDraft?
    @State private var editingMemory:PAMemory?
    @State private var addingMemory=false
    @State private var error:String?
    init(model:DashboardModel) {self.model=model;registration=model.chatGPT.activeID}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {Text("Review preferences").font(.title2.weight(.semibold));Spacer();Button("Done") {dismiss()}}
            Text("Your feedback is part of PA memory. Each preference keeps your words and edit history. Dismiss simply clears the item; it does not teach a preference.").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(model.assistant.memory.reviewPreferences(registration,includeRetired:true)) {value in
                        HStack(alignment:.top) {
                            VStack(alignment:.leading,spacing:5) {if let about=value.reviewContext {Text(about).font(.callout.weight(.semibold))};Text(value.text).textSelection(.enabled);Text(value.retiredAt == nil ? "Saved in PA memory" : "Disabled").font(.caption).foregroundStyle(.secondary)}
                            Spacer()
                            Menu {Button("Edit") {editingMemory=value};Button(value.retiredAt == nil ? "Disable" : "Restore") {
                                guard model.assistant.memory.retire(value.id,retired:value.retiredAt == nil,expectedRevision:model.assistant.memory.revision) else {error=model.assistant.memory.error;return}
                            }} label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).fixedSize()
                        }.padding(12).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
                    }
                    if model.assistant.memory.reviewPreferences(registration,includeRetired:true).isEmpty {Text("Use Feedback on an item to explain what matters to you, or add a preference below.").foregroundStyle(.secondary).padding(.vertical)}
                    let legacy=model.emailSummaries.relevancePreferences.filter{$0.registration == registration}
                    if !legacy.isEmpty {
                        DisclosureGroup("Earlier topic preferences (\(legacy.count))") {
                            ForEach(legacy) {value in
                                HStack {VStack(alignment:.leading) {Text(value.topic);Text(value.inactive ? "Inactive" : value.direction == "more" ? "Prioritise" : "Less attention").font(.caption).foregroundStyle(.secondary)};Spacer();Button("Edit") {editing = .init(value:value,expected:value)}}.padding(.vertical,6)
                            }
                        }
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            if let error=error ?? model.emailSummaries.relevanceError {Text(error).font(.caption).foregroundStyle(.orange)}
            HStack {
                Button("Add preference…") {addingMemory=true}
                if model.emailSummaries.canUndoPreference(registration) {Button("Undo last change") {do {try model.emailSummaries.undoPreference(model)} catch {self.error=error.localizedDescription}}}
                Spacer()
            }
        }.padding(24).frame(width:620,height:430).sheet(item:$editing) {ReviewRelevanceEditor(model:model,draft:$0)}.sheet(item:$editingMemory) {ReviewFeedbackEditor(model:model,expected:$0)}.sheet(isPresented:$addingMemory) {ReviewFeedbackEditor(model:model)}.onChange(of:model.chatGPT.activeID) {dismiss()}
    }
}
