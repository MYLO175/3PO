import SwiftUI
import EventKit

/// Local inspection and explicit human edits only. Opening this view starts no source or AI work.
struct ContextPagesView: View {
    @Bindable var model: DashboardModel
    private let registration: String
    private let storage: ObjectIdentifier?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: ContextPageDestination?
    @State private var editor: ContextPageEditRequest?
    @State private var history: ContextPageHistoryRequest?
    @State private var instructions: ContextPageInstructionRequest?
    @State private var choosingProject = false
    @State private var nextEditor: ContextPageEditRequest?
    @State private var forgetting: ContextPage?
    @State private var error: String?

    init(model: DashboardModel) {
        self.model = model
        registration = model.chatGPT.activeID
        storage = model.container.map(ObjectIdentifier.init)
        let first = model.contextPages.pages(registration: model.chatGPT.activeID).first { $0.kind == .overview }
        _selection = State(initialValue: first.map { .page($0.id) })
    }
    private var owned: Bool { ContextPagesAccess.owned(model, registration: registration, storage: storage) }
    private var projects: [LifeItem] {
        model.assistant.projects.items(registration, includeTopics: true).filter { !$0.kind.isWork }
    }
    var body: some View {
        let records = model.contextKnowledge(registration: registration)
        let pages = model.contextPages.pages(registration: registration)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Context pages").font(.title2.weight(.semibold))
                Spacer()
                Menu("Add context") {
                    Button("Everyday overview…") { openOverview() }
                    Button("Note…") { editor = .note(registration: registration) }
                    Button("Project purpose…") { choosingProject = true }.disabled(projects.isEmpty)
                }.disabled(!owned || registration.isEmpty || !model.contextPages.canSave)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Readable context for your PA. Pages maintained by 3PO keep their supporting records; your notes and instructions remain yours.")
                .font(.callout).foregroundStyle(.secondary)
            if owned && !registration.isEmpty {
                HSplitView {
                    pageList(pages: pages, records: records)
                        .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
                    ScrollView {
                        detail(pages: pages, records: records)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    }.frame(minWidth: 450)
                }
                if model.contextPages.isReadable {
                    let pending = ContextPagesAccess.pendingCount(model, registration: registration, records: records)
                    HStack {
                        if let checkpoint = model.contextPages.checkpoint(registration: registration) {
                            Text("Last consolidation \(checkpoint.updated.formatted(date: .abbreviated, time: .shortened))")
                        } else { Text("Awaiting first consolidation") }
                        Spacer()
                        Text(pending == 0 ? "No working changes pending" : "\(pending) working change\(pending == 1 ? "" : "s") pending")
                    }.font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Connect your account", systemImage: "person.crop.circle", description: Text("Context pages stay with the account that owns them. Reopen this view after connecting your account."))
            }
            if let message = error ?? model.contextPages.error {
                Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
        }.padding(22).frame(width: 980, height: 700)
            .sheet(item: $editor) { ContextPageHumanEditor(model: model, request: $0) }
            .sheet(item: $history) { ContextPageHistoryView(model: model, request: $0) }
            .sheet(item: $instructions) { request in
                if request.registration == model.chatGPT.activeID {
                    if let capture = request.brief { BriefPromptEditor(model: model, briefings: model.briefings, capture: capture) }
                    else { ReviewPolicyView(model: model) }
                } else { Text("The account changed. Reopen the instructions.").padding(24) }
            }
            .sheet(isPresented: $choosingProject, onDismiss: {
                if let nextEditor { editor = nextEditor; self.nextEditor = nil }
            }) {
                ContextProjectPurposePicker(model: model, registration: registration) { item in
                    nextEditor = try ContextPageEditRequest.project(item, model: model, registration: registration)
                    choosingProject = false
                }
            }
            .alert("Forget this context page?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } })) {
                Button("Cancel", role: .cancel) { forgetting = nil }
                Button("Forget page", role: .destructive) { forget() }
            } message: { Text("This removes the human page and its saved history. Its project, source records and other memories stay saved.") }
            .onChange(of: model.chatGPT.activeID) { editor = nil; history = nil; instructions = nil; choosingProject = false; nextEditor = nil; forgetting = nil; dismiss() }
    }

    private func pageList(pages: [ContextPage], records: [ContextKnowledgeRecord]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search context pages", text: $query).textFieldStyle(.roundedBorder)
            List(selection: $selection) {
                ForEach([ContextPage.Kind.overview, .topic], id: \.rawValue) { kind in
                    let rows = pages.filter { $0.kind == kind && matches($0, records: records) }
                    if !rows.isEmpty {
                        Section(kind == .overview ? "Everyday" : "Topics") {
                            ForEach(rows) { page in pageRow(page, records: records).tag(ContextPageDestination.page(page.id)) }
                        }
                    }
                }
                let folders = projects.filter { matches(ContextPagesAccess.projectLabel($0, all: projects)) }
                if !folders.isEmpty {
                    Section("Projects") {
                        ForEach(folders) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Label(ContextPagesAccess.projectLabel(item, all: projects), systemImage: "folder")
                                let id = ContextPage.stableID(registration: registration, kind: .project, key: item.id.uuidString)
                                Text(pages.contains { $0.id == id } ? "Maintained page" : "Awaiting first page").font(.caption2).foregroundStyle(.secondary)
                            }.padding(.vertical, 3).tag(ContextPageDestination.project(item.id))
                        }
                    }
                }
                let notes = pages.filter { $0.kind == .note && matches($0, records: records) }
                if !notes.isEmpty {
                    Section("Your notes") { ForEach(notes) { page in pageRow(page, records: records).tag(ContextPageDestination.page(page.id)) } }
                }
                Section("Instructions") {
                    if matches("Brief instructions") { Label("Brief instructions", systemImage: "sun.max").tag(ContextPageDestination.brief) }
                    if matches("Review guidance") { Label("Review guidance", systemImage: "tray").tag(ContextPageDestination.review) }
                    if matches("Calendar guide") { Label("Calendar guide", systemImage: "calendar").tag(ContextPageDestination.calendars) }
                }
            }.listStyle(.sidebar)
        }
    }
    private func pageRow(_ page: ContextPage, records: [ContextKnowledgeRecord]) -> some View {
        let available = ContextPagesAccess.eligible(page, model: model, registration: registration, records: records)
        return VStack(alignment: .leading, spacing: 3) {
            Label(available ? page.title : ContextPagesAccess.kindTitle(page.kind), systemImage: page.owner == .human ? "doc.text" : "sparkles")
            Text(available ? (page.owner == .human ? "Written by you" : "Maintained by 3PO") : "Supporting context unavailable")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical, 3)
    }
    private func matches(_ text: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.localizedStandardContains(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    private func matches(_ page: ContextPage, records: [ContextKnowledgeRecord]) -> Bool {
        guard ContextPagesAccess.eligible(page, model: model, registration: registration, records: records) else { return matches(ContextPagesAccess.kindTitle(page.kind)) }
        return matches(page.title + " " + page.synopsis + " " + page.markdown)
    }
    @ViewBuilder private func detail(pages: [ContextPage], records: [ContextKnowledgeRecord]) -> some View {
        switch selection {
        case .page(let id):
            if let page = pages.first(where: { $0.id == id }) { pageDetail(page, records: records) }
            else { ContentUnavailableView("Page unavailable", systemImage: "doc.text", description: Text("The page may have changed or been forgotten.")) }
        case .project(let id):
            if let item = projects.first(where: { $0.id == id }) {
                let pageID = ContextPage.stableID(registration: registration, kind: .project, key: item.id.uuidString)
                if let page = pages.first(where: { $0.id == pageID }) { pageDetail(page, records: records) }
                else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(item.title).font(.title2.weight(.semibold))
                        Label("Awaiting first maintained page", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                        Text("A heartbeat can gather relevant context for this existing project. Opening this page does not start analysis.").foregroundStyle(.secondary)
                        if !item.searchableNotes.isEmpty { Text("Project notes").font(.headline); ContextMarkdownBody(markdown: item.searchableNotes) }
                    }
                }
                projectContext(item, pages: pages, records: records)
            } else { ContentUnavailableView("Project unavailable", systemImage: "folder", description: Text("This folder is no longer available in the current account.")) }
        case .brief:
            VStack(alignment: .leading, spacing: 16) {
                Text("Brief instructions").font(.title2.weight(.semibold))
                Text("Choose the focus and style of future briefs. Current-time, evidence and approval rules stay built in.").foregroundStyle(.secondary)
                Button("Edit brief instructions…") { instructions = .init(registration: registration, brief: model.briefings.writingPrompt(registration)) }
                ContextMarkdownBody(markdown: model.briefings.writingPrompt(registration).text)
            }
        case .review:
            VStack(alignment: .leading, spacing: 16) {
                Text("Review guidance").font(.title2.weight(.semibold))
                Text("Your Review policy and feedback guide what deserves attention. They keep their existing controls and history.").foregroundStyle(.secondary)
                Button("Open Review guidance…") { instructions = .init(registration: registration) }
                ContextMarkdownBody(markdown: model.emailSummaries.policy(registration).text)
            }
        case .calendars: calendarGuide
        case nil:
            ContentUnavailableView("Your context, in readable pages", systemImage: "doc.text.magnifyingglass", description: Text("Select a page, describe a project, or add your everyday context. Relevant working changes remain available between heartbeats."))
        }
    }
    private func pageDetail(_ page: ContextPage, records: [ContextKnowledgeRecord]) -> some View {
        let available = ContextPagesAccess.eligible(page, model: model, registration: registration, records: records)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text(available ? page.title : ContextPagesAccess.kindTitle(page.kind)).font(.title2.weight(.semibold))
                Spacer()
                Button("History…") { history = .init(page: page) }
            }
            Text((page.owner == .human ? "Written by you" : "Maintained by 3PO") + " · Updated " + page.updated.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
            if available {
                if !page.synopsis.isEmpty { Text(page.synopsis).font(.callout).foregroundStyle(.secondary) }
                ContextMarkdownBody(markdown: page.markdown)
                ContextPageSupportingContext(page: page, records: records).id(page.id)
            } else {
                Label("This saved text is withheld because its supporting context changed, memory use is paused, or access is no longer available. A later heartbeat can maintain the page using current permitted records.", systemImage: "lock.doc")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if page.owner == .human {
                    Button("Edit your page…") { editor = .existing(page) }.disabled(!available || !model.contextPages.canSave)
                    Button("Forget…", role: .destructive) { forgetting = page }.disabled(!model.contextPages.canSave)
                } else {
                    Button("Add context…") { editor = .note(registration: registration) }.disabled(!model.contextPages.canSave)
                }
            }
            if page.owner == .generated { Text("This is an automatically maintained summary. Add your own context in a separate note; your words will remain distinct from source interpretations.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func projectContext(_ item: LifeItem, pages: [ContextPage], records: [ContextKnowledgeRecord]) -> some View {
        let key = "project-purpose:" + item.id.uuidString
        let note = pages.first { $0.kind == .note && $0.key == key && $0.owner == .human }
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Your project context").font(.headline)
                    Spacer()
                    Button(note == nil ? "Describe this project…" : "Edit your context…") {
                        do { editor = try .project(item, model: model, registration: registration) }
                        catch { self.error = error.localizedDescription }
                    }.disabled(!model.contextPages.canSave || (note.map { !ContextPagesAccess.eligible($0, model: model, registration: registration, records: records) } ?? false))
                }
                if let note, ContextPagesAccess.eligible(note, model: model, registration: registration, records: records) { ContextMarkdownBody(markdown: note.markdown) }
                else { Text(note == nil ? "Explain what this folder is for and what matters about it. Only what you type becomes your context." : "The saved note's project identity is unavailable. Its text remains saved.").font(.callout).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.top, 20)
    }
    private var calendarGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calendar guide").font(.title2.weight(.semibold))
            Text("Describe what belongs in each calendar. Your words help choose a destination for a requested event; they do not create events or grant source access.").foregroundStyle(.secondary)
            if !ContextPagesAccess.calendarAccess(model) {
                Label("Calendar source context or Calendar access is off. Saved purpose notes stay preserved.", systemImage: "lock").foregroundStyle(.secondary)
            } else if model.calendarData.sources.isEmpty {
                Text("No calendar identities are cached yet. Refresh sources from the dashboard, then return here. Opening this guide does not read Calendar.").foregroundStyle(.secondary)
            } else {
                let sources = ContextPagesAccess.calendars(model)
                if sources.isEmpty { Text("No calendars are selected for assistant context.").foregroundStyle(.secondary) }
                ForEach(sources) { source in
                    let id = ContextPage.stableID(registration: registration, kind: .calendarPurpose, key: model.calendarPageKey(source))
                    let page = model.contextPages.page(id: id, registration: registration)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.label).font(.headline)
                                    if !source.writable { Text("Read-only calendar").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Button(page == nil ? "Describe…" : "Edit purpose…") { editor = .calendar(source, page: page, model: model, registration: registration) }
                                    .disabled(!model.contextPages.canSave || page.map { $0.owner != .human } == true)
                                if let page { Button("History…") { history = .init(page: page) } }
                            }
                            if let page, page.owner == .human, ContextPagesAccess.eligible(page, model: model, registration: registration, records: []) {
                                ContextMarkdownBody(markdown: page.markdown)
                                HStack {
                                    Text("Written by you · Updated " + page.updated.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Forget purpose…", role: .destructive) { forgetting = page }.controlSize(.small).disabled(!model.contextPages.canSave)
                                }
                            } else { Text("Not described. 3PO will not infer a purpose from the calendar's name.").font(.callout).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
    private func openOverview() {
        let id = ContextPage.stableID(registration: registration, kind: .overview, key: "everyday")
        if let page = model.contextPages.page(id: id, registration: registration) {
            guard page.owner == .human, ContextPagesAccess.eligible(page, model: model, registration: registration, records: model.contextKnowledge(registration: registration)) else { error = "The existing overview cannot be edited as a human page. Add a separate context note."; return }
            editor = .existing(page)
        } else { editor = .overview(registration: registration) }
    }
    private func forget() {
        guard let page = forgetting else { return }
        defer { forgetting = nil }
        guard owned, page.registration == registration, page.owner == .human else { error = "The account or page owner changed. Reopen the page before forgetting it."; return }
        if page.kind == .calendarPurpose && !ContextPagesAccess.eligible(page, model: model, registration: registration, records: []) { error = "This calendar's current identity or access changed. Its note remains saved."; return }
        do {
            try model.contextPages.forget(id: page.id, registration: registration, expectedRevision: page.revision)
            if selection == .page(page.id) { selection = nil }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private enum ContextPageDestination: Hashable { case page(String), project(UUID), brief, review, calendars }
private struct ContextPageInstructionRequest: Identifiable {
    let id = UUID()
    var registration: String
    var brief: BriefWritingPrompt? = nil
}
private struct ContextPageHistoryRequest: Identifiable { let id = UUID(); var page: ContextPage }

private struct ContextPageEditRequest: Identifiable {
    let id = UUID()
    var registration: String
    var kind: ContextPage.Kind
    var key: String
    var title: String
    var expected: ContextPage? = nil
    var calendar: SourceOption? = nil
    var projectReference: ContextPageReference? = nil
    static func note(registration: String) -> Self { .init(registration: registration, kind: .note, key: UUID().uuidString, title: "") }
    static func overview(registration: String) -> Self { .init(registration: registration, kind: .overview, key: "everyday", title: "Everyday context") }
    static func existing(_ page: ContextPage) -> Self {
        .init(registration: page.registration, kind: page.kind, key: page.key, title: page.title, expected: page,
              projectReference: page.references.first { $0.kind == "projectIdentity" })
    }
    @MainActor static func calendar(_ source: SourceOption, page: ContextPage?, model: DashboardModel, registration: String) -> Self {
        .init(registration: registration, kind: .calendarPurpose, key: model.calendarPageKey(source), title: "Calendar purpose", expected: page, calendar: source)
    }
    @MainActor static func project(_ item: LifeItem, model: DashboardModel, registration: String) throws -> Self {
        guard item.registration == registration, !item.kind.isWork,
              let current = model.assistant.projects.items(registration, includeTopics: true).first(where: { $0.id == item.id && !$0.kind.isWork }),
              let reference = model.contextKnowledge(registration: registration).first(where: { $0.reference.kind == "projectIdentity" && $0.reference.key == current.id.uuidString })?.reference else { throw ContextPageFailure.invalid("project identity") }
        let key = "project-purpose:" + current.id.uuidString
        let id = ContextPage.stableID(registration: registration, kind: .note, key: key)
        let page = model.contextPages.page(id: id, registration: registration)
        guard page?.owner == nil || page?.owner == .human else { throw ContextPageFailure.unsupportedPage }
        if let page {
            guard ContextPagesAccess.eligible(page, model: model, registration: registration, records: model.contextKnowledge(registration: registration)) else { throw ContextPageFailure.stalePage }
        }
        return .init(registration: registration, kind: .note, key: key, title: "About " + current.title, expected: page, projectReference: reference)
    }
}

@MainActor private enum ContextPagesAccess {
    static func owned(_ model: DashboardModel, registration: String, storage: ObjectIdentifier?) -> Bool {
        registration == model.chatGPT.activeID && storage == model.container.map(ObjectIdentifier.init)
    }
    static func calendarAccess(_ model: DashboardModel) -> Bool {
        model.assistant.contextEnabled && EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }
    static func calendars(_ model: DashboardModel) -> [SourceOption] {
        guard calendarAccess(model) else { return [] }
        return model.calendarData.sources.filter { !model.assistant.excludedCalendars.contains($0.id) }.sorted { ($0.label, $0.id) < ($1.label, $1.id) }
    }
    static func eligible(_ page: ContextPage, model: DashboardModel, registration: String, records: [ContextKnowledgeRecord]) -> Bool {
        guard page.registration == registration, registration == model.chatGPT.activeID else { return false }
        if page.kind == .calendarPurpose {
            return page.owner == .human && calendars(model).contains { model.calendarPageKey($0) == page.key }
        }
        return model.contextPageEligible(page, records: records)
    }
    static func pendingCount(_ model: DashboardModel, registration: String, records: [ContextKnowledgeRecord]) -> Int {
        let before = Dictionary((model.contextPages.checkpoint(registration: registration)?.references ?? []).map { ($0.contextKey, $0.revision) }, uniquingKeysWith: { first, _ in first })
        let now = Dictionary(records.map { ($0.reference.contextKey, $0.reference.revision) }, uniquingKeysWith: { first, _ in first })
        return now.filter { before[$0.key] != $0.value }.count + before.keys.filter { now[$0] == nil }.count
    }
    static func kindTitle(_ kind: ContextPage.Kind) -> String {
        switch kind { case .overview: "Everyday context"; case .project: "Project context"; case .topic: "Topic context"; case .calendarPurpose: "Calendar purpose"; default: "Your context note" }
    }
    static func projectLabel(_ item: LifeItem, all: [LifeItem]) -> String {
        var names = [item.title], parent = item.parentID, seen: Set<UUID> = [item.id]
        while let id = parent, seen.insert(id).inserted, let value = all.first(where: { $0.id == id }) {
            names.insert(value.title, at: 0); parent = value.parentID
        }
        return names.joined(separator: " › ")
    }
}

private struct ContextPageHumanEditor: View {
    @Bindable var model: DashboardModel
    let request: ContextPageEditRequest
    private let storage: ObjectIdentifier?
    private let storeIdentity: ObjectIdentifier
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var markdown: String
    @State private var error: String?
    init(model: DashboardModel, request: ContextPageEditRequest) {
        self.model = model; self.request = request
        storage = model.container.map(ObjectIdentifier.init); storeIdentity = ObjectIdentifier(model.contextPages)
        _title = State(initialValue: request.title)
        _markdown = State(initialValue: request.expected?.owner == .human ? request.expected!.markdown : "")
    }
    private var owned: Bool { ContextPagesAccess.owned(model, registration: request.registration, storage: storage) && storeIdentity == ObjectIdentifier(model.contextPages) }
    private var bindingCurrent: Bool {
        guard owned else { return false }
        if let source = request.calendar {
            return ContextPagesAccess.calendars(model).contains { $0.id == source.id && model.calendarPageKey($0) == request.key }
        }
        if let reference = request.projectReference {
            guard model.assistant.projects.items(request.registration, includeTopics: true).contains(where: { !$0.kind.isWork && $0.id.uuidString == reference.key }) else { return false }
            return model.contextKnowledge(registration: request.registration).contains { $0.reference == reference }
        }
        return true
    }
    private var readable: Bool {
        guard bindingCurrent else { return false }
        guard let page = request.expected else { return true }
        return page.owner == .human && ContextPagesAccess.eligible(page, model: model, registration: request.registration, records: model.contextKnowledge(registration: request.registration))
    }
    private var validText: Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanTitle.isEmpty && cleanTitle.utf8.count <= ContextPageLimits.maximumTitleBytes && !title.contains("\0") &&
            !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && markdown.utf8.count <= ContextPageLimits.maximumMarkdownBytes && !markdown.contains("\0")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.calendar == nil ? "Your context" : "Calendar purpose").font(.title2.weight(.semibold))
            Text(request.calendar == nil ? "Write only what you want 3PO to know. Your words stay separate from automatically maintained pages." : "Explain what belongs in this calendar. Saving changes only this local guide.").font(.callout).foregroundStyle(.secondary)
            if readable {
                if let source = request.calendar { Text(source.label).font(.headline) }
                else { TextField("Page title", text: $title).textFieldStyle(.roundedBorder) }
                TextEditor(text: $markdown).font(.body).padding(8).frame(minHeight: 280).border(Color.secondary.opacity(0.25)).accessibilityLabel("Your context Markdown")
                Text("Plain text or Markdown. Saving creates a new version; earlier versions remain in History.").font(.caption).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("Context changed", systemImage: "lock.doc", description: Text("The account, project identity or source access changed. Your draft remains here; reopen the page after resolving the change."))
            }
            if title.utf8.count > ContextPageLimits.maximumTitleBytes { Text("Use a shorter page title.").font(.caption).foregroundStyle(.orange) }
            if markdown.utf8.count > ContextPageLimits.maximumMarkdownBytes { Text("Shorten this page before saving.").font(.caption).foregroundStyle(.orange) }
            if let error = error ?? model.contextPages.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(!readable || !validText || !model.contextPages.canSave)
            }
        }.padding(24).frame(width: 680, height: 620)
            .onChange(of: model.chatGPT.activeID) { dismiss() }
    }
    private func save() {
        guard owned, bindingCurrent, readable, validText, request.expected?.owner == nil || request.expected?.owner == .human else { error = "The account, page or supporting identity changed. Reopen the editor before saving."; return }
        let pageID = ContextPage.stableID(registration: request.registration, kind: request.kind, key: request.key)
        let current = model.contextPages.page(id: pageID, registration: request.registration)
        guard current?.revision == request.expected?.revision else { error = ContextPageFailure.stalePage.localizedDescription; return }
        var page = request.expected ?? ContextPage(registration: request.registration, kind: request.kind, key: request.key, owner: .human, title: title, markdown: "")
        page.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        page.markdown = markdown
        page.synopsis = ""
        if request.expected == nil, let reference = request.projectReference { page.references = [reference] }
        do { try model.contextPages.save(page, expectedRevision: request.expected?.revision); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private struct ContextPageHistoryView: View {
    @Bindable var model: DashboardModel
    let request: ContextPageHistoryRequest
    private let storage: ObjectIdentifier?
    private let storeIdentity: ObjectIdentifier
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var error: String?
    init(model: DashboardModel, request: ContextPageHistoryRequest) {
        self.model = model; self.request = request
        storage = model.container.map(ObjectIdentifier.init); storeIdentity = ObjectIdentifier(model.contextPages)
        _selected = State(initialValue: request.page.revision)
    }
    private var owned: Bool { ContextPagesAccess.owned(model, registration: request.page.registration, storage: storage) && storeIdentity == ObjectIdentifier(model.contextPages) }
    var body: some View {
        let versions = owned ? Array(model.contextPages.history(id: request.page.id, registration: request.page.registration).reversed()) : []
        let records = model.contextKnowledge(registration: request.page.registration)
        let current = model.contextPages.page(id: request.page.id, registration: request.page.registration)
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Page history").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Saved versions are immutable. Restoring appends a new version and keeps the current one in history.").font(.callout).foregroundStyle(.secondary)
            Picker("Version", selection: $selected) {
                ForEach(Array(versions)) { version in
                    Text(version.page.updated.formatted(date: .abbreviated, time: .shortened) + (version.id == current?.revision ? " · Current" : ""))
                        .tag(Optional(version.id))
                }
            }
            ScrollView {
                if let version = versions.first(where: { $0.id == selected }) {
                    if ContextPagesAccess.eligible(version.page, model: model, registration: request.page.registration, records: records) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(version.page.title).font(.title3.weight(.semibold))
                            Text(version.page.owner == .human ? "Written by you" : "Maintained by 3PO").font(.caption).foregroundStyle(.secondary)
                            ContextMarkdownBody(markdown: version.page.markdown)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else { Text("This version's text is withheld because its supporting context or current access is unavailable. It cannot be restored now.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
            if current?.revision != request.page.revision { Text("The page changed while history was open. Reopen History before restoring a version.").font(.caption).foregroundStyle(.orange) }
            if let error = error ?? model.contextPages.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Restore this version") { restore() }
                    .disabled(!owned || !model.contextPages.canSave || current?.revision != request.page.revision || selected == current?.revision || !versions.contains { $0.id == selected && ContextPagesAccess.eligible($0.page, model: model, registration: request.page.registration, records: records) })
            }
        }.padding(24).frame(width: 700, height: 620)
            .onChange(of: model.chatGPT.activeID) { dismiss() }
    }
    private func restore() {
        guard owned, let selected,
              let version = model.contextPages.history(id: request.page.id, registration: request.page.registration).first(where: { $0.id == selected }),
              ContextPagesAccess.eligible(version.page, model: model, registration: request.page.registration, records: model.contextKnowledge(registration: request.page.registration)) else { error = "The account, source access or this version's supporting context changed. No version was restored."; return }
        do {
            try model.contextPages.restore(id: request.page.id, registration: request.page.registration, revision: selected, expectedRevision: request.page.revision)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ContextProjectPurposePicker: View {
    @Bindable var model: DashboardModel
    let registration: String
    var choose: (LifeItem) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var error: String?
    var body: some View {
        let items = model.assistant.projects.items(registration, includeTopics: true).filter { !$0.kind.isWork }
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Describe a project").font(.title2.weight(.semibold)); Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Choose the existing folder this context belongs to. This creates no project or task.").font(.callout).foregroundStyle(.secondary)
            TextField("Find a project folder", text: $query).textFieldStyle(.roundedBorder)
            List(items.filter { query.isEmpty || ContextPagesAccess.projectLabel($0, all: items).localizedStandardContains(query) }) { item in
                Button {
                    do { try choose(item) }
                    catch { self.error = error.localizedDescription }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(ContextPagesAccess.projectLabel(item, all: items), systemImage: "folder")
                        Text("Created " + item.created.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.vertical, 4)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(24).frame(width: 580, height: 470)
            .onChange(of: model.chatGPT.activeID) { dismiss() }
    }
}

/// The caller has validated the entire current page; individual quotes also need an exact supplied record.
private struct ContextPageSupportingContext: View {
    var page: ContextPage
    var records: [ContextKnowledgeRecord]
    private var supported: [(quote: ContextPageQuote, record: ContextKnowledgeRecord)] {
        guard page.owner == .generated else { return [] }
        return (page.evidenceQuotes ?? []).compactMap { quote in
            guard let record = records.first(where: { $0.reference.id == quote.referenceID && page.references.contains($0.reference) }) else { return nil }
            return (quote, record)
        }
    }
    var body: some View {
        let rows = supported
        if !rows.isEmpty {
            DisclosureGroup("Supporting context") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rows.indices, id: \.self) { index in
                        let row = rows[index]
                        VStack(alignment: .leading, spacing: 5) {
                            Text(label(row.record)).font(.caption.weight(.semibold))
                            Text(row.quote.quote).font(.callout).textSelection(.enabled)
                            Text(row.record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.top, 8)
            }.font(.caption)
        }
    }
    private func label(_ record: ContextKnowledgeRecord) -> String {
        switch record.reference.kind {
        case "human": "Your conversation"
        case "action": "Verified app action"
        case "project", "projectIdentity": "Project: " + record.title
        case "page": "Your context: " + record.title
        case "memory": "Saved memory"
        default: "Supporting record"
        }
    }
}

/// Render local Markdown without loading remote images or executing embedded content.
private struct ContextMarkdownBody: View {
    var markdown: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks.indices, id: \.self) { index in
                let block = blocks[index]
                if block.hasPrefix("### ") { inline(String(block.dropFirst(4))).font(.headline) }
                else if block.hasPrefix("## ") { inline(String(block.dropFirst(3))).font(.title3.weight(.semibold)) }
                else if block.hasPrefix("# ") { inline(String(block.dropFirst(2))).font(.title2.weight(.semibold)) }
                else { inline(block).font(.body) }
            }
        }.lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var blocks: [String] {
        markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private func inline(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
    }
}
