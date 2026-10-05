import SwiftUI

enum LifeProjectPresentation: String, CaseIterable, Identifiable {
    case overview = "Overview", list = "List", board = "Board", outline = "Outline", deadlines = "Deadlines"
    var id: String { rawValue }
}
struct LifeProjectWidget: View {
    @Bindable var model: DashboardModel
    var configuration: Binding<WidgetConfiguration>
    var showsHeader = true
    var previewRegistration: String? = nil
    var focusAreas: [LifeArea] = []
    @Environment(\.workspacePalette) private var palette
    @State private var path: [UUID] = []
    @State private var search = ""
    @State private var editing: LifeItem?
    @State private var linking: LifeItem?
    @State private var notice: String?
    private var registration: String { previewRegistration ?? model.chatGPT.activeID }
    private var store: LifeWorkspaceStore { model.assistant.projects }
    private var items: [LifeItem] {
        let all = store.items(registration)
        guard !focusAreas.isEmpty else { return all }
        let matching = all.filter { !Set(LifeItemQuery.path($0, in:all).flatMap(\.areas)).isDisjoint(with:focusAreas) }
        let included = Set(matching.flatMap { LifeItemQuery.path($0, in:all).map(\.id) })
        return all.filter { included.contains($0.id) }
    }
    private var savedRoot: UUID? { configuration.wrappedValue.projectRoots?[registration].flatMap(UUID.init(uuidString:)) }
    private var currentID: UUID? { path.last ?? savedRoot }
    private var current: LifeItem? { items.first { $0.id == currentID } }
    private var presentation: LifeProjectPresentation { LifeProjectPresentation(rawValue: configuration.wrappedValue.projectView ?? "") ?? .overview }
    private var unfinished: Bool { configuration.wrappedValue.projectOnlyUnfinished == true }
    private var filtered: [LifeItem] { LifeItemQuery(root: current?.id, query: search, unfinished: unfinished).matching(items).filter { $0.id != current?.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                HStack {
                    Label("Projects", systemImage: "folder").font(.title3.weight(.semibold))
                    Spacer(minLength: 4)
                    Menu {
                        Picker("View", selection: Binding(get: { presentation }, set: { value in var config = configuration.wrappedValue; config.projectView = value.rawValue; configuration.wrappedValue = config })) {
                            ForEach(LifeProjectPresentation.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Toggle("Only unfinished", isOn: Binding(get: { unfinished }, set: { value in var config = configuration.wrappedValue; config.projectOnlyUnfinished = value; configuration.wrappedValue = config }))
                        Divider()
                        Button("Start here") { setRoot(current?.id) }
                        Button("Start at all projects") { setRoot(nil) }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Project view options")
                }
            }
            HStack(spacing: 8) {
                if current != nil {
                    Button { if !path.isEmpty { path.removeLast() } else { setRoot(current?.parentID) }; search = "" } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).accessibilityLabel("Back to parent")
                }
                Text(current?.title ?? "Your projects").font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                if let current {
                    Menu {
                        Button("Edit details") { editing = current }
                        Button("Link something") { linking = current }
                    } label: { Image(systemName: "pencil") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Edit project or links")
                }
                Button { editing = LifeItem(registration: registration, kind: current == nil ? .project : .task, title: "", parentID: current?.id, areas: current?.areas ?? []) } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).accessibilityLabel("Add project item").disabled(registration.isEmpty || store.readOnly)
            }
            HStack {
                TextField("Find in this branch", text: $search).textFieldStyle(.plain).font(.callout)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
            }.padding(8).background(palette[.input], in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let current { details(current) }
                    if filtered.isEmpty, current?.kind.isWork != true {
                        Text(items.isEmpty ? "Give your projects a home. Add a course, project or area here, or ask your PA to set one up." : "No matching items in this branch.")
                            .foregroundStyle(.secondary).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
                    } else if !filtered.isEmpty {
                        switch presentation {
                        case .overview: overview
                        case .list: rows(filtered)
                        case .outline: outline
                        case .board: board
                        case .deadlines: deadlines
                        }
                    }
                    if let error = store.error ?? notice { Text(error).font(.caption).foregroundStyle(.orange) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editing) { item in LifeItemEditor(model: model, item: item) { editing = nil } }
        .sheet(item: $linking) { item in LifeItemLinkEditor(model: model, item: item) { linking = nil } }
        .onChange(of: registration) { path = []; search = ""; editing = nil; linking = nil; notice = nil }
        .onChange(of: savedRoot) { path = []; search = "" }
    }
    private func setRoot(_ id: UUID?) {
        var config = configuration.wrappedValue
        if config.projectRoots == nil { config.projectRoots = [:] }
        config.projectRoots?[registration] = id?.uuidString ?? ""; configuration.wrappedValue = config
        path = []; search = ""
    }
    private func open(_ item: LifeItem) { path.append(item.id); search = ""; notice = nil }
    private func workSummary(_ item: LifeItem) -> String {
        let children = LifeWorkspaceRules.descendants(item.id, in: items)
        let work = items.filter { children.contains($0.id) && $0.kind.isWork && $0.status != .archived }
        if work.isEmpty { return item.kind.title }
        return "\(work.filter { $0.status == .done }.count) of \(work.count) work items done"
    }
    private func card(_ item: LifeItem) -> some View {
        Button { open(item) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.kind.symbol).foregroundStyle(palette[.accent]).frame(width: 20)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.callout.weight(.semibold)).foregroundStyle(palette[.text]).lineLimit(2)
                    Text(item.kind.isWork ? item.status.title : workSummary(item)).font(.caption).foregroundStyle(.secondary)
                    HStack { if let due = item.due { Text("Due " + LifeWorkspaceRules.displayDate(due)) }; if let minutes = item.estimateMinutes { Text("\(minutes) min") } }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(palette[.input].opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            let direct = filtered.filter { $0.parentID == current?.id && !$0.kind.isWork }
            ForEach(search.isEmpty ? direct : filtered) { card($0) }
            let next = filtered.filter { $0.kind.isWork && $0.status != .done && $0.status != .archived }.sorted { ($0.due ?? "9999", $0.created) < ($1.due ?? "9999", $1.created) }
            if !next.isEmpty, search.isEmpty {
                Text("Upcoming work").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                rows(Array(next.prefix(5)))
                if next.count > 5 { Button("View all \(next.count) work items") { var config = configuration.wrappedValue; config.projectView = "List"; configuration.wrappedValue = config }.font(.caption) }
            }
        }
    }
    private func rows(_ values: [LifeItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) { ForEach(values) { item in card(item) } }
    }
    private var outline: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(filtered.sorted { a, b in
                LifeItemQuery.path(a, in: items).map { $0.created }.lexicographicallyPrecedes(LifeItemQuery.path(b, in: items).map { $0.created })
            }) { item in
                let depth = max(0, LifeItemQuery.path(item, in: items).count - (current.map { LifeItemQuery.path($0, in: items).count } ?? 0) - 1)
                card(item).padding(.leading, CGFloat(min(depth, 6)) * 12)
            }
        }
    }
    private var board: some View {
        // Columns adapt to available widget width rather than forcing dashboard scrolling.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .top)], alignment: .leading, spacing: 12) {
            ForEach(LifeItemStatus.allCases.filter { $0 != .archived }) { status in
                let work = filtered.filter { $0.kind.isWork && $0.status == status }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(status.title).font(.caption.weight(.semibold)); Spacer(); Text(String(work.count)).font(.caption).foregroundStyle(.secondary) }
                    rows(work)
                    if work.isEmpty { Text("No work items").font(.caption).foregroundStyle(.secondary).padding(.vertical, 8) }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
    private var deadlines: some View {
        VStack(alignment: .leading, spacing: 8) {
            let dates = Set(filtered.compactMap(\.due)).sorted()
            ForEach(dates, id: \.self) { due in
                Text(LifeWorkspaceRules.displayDate(due)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                rows(filtered.filter { $0.due == due })
            }
            let undated = filtered.filter { $0.due == nil && $0.kind.isWork }
            if !undated.isEmpty { Text("No deadline").font(.caption.weight(.semibold)).foregroundStyle(.secondary); rows(undated) }
        }
    }
    @ViewBuilder private func details(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { if item.status != .planned || item.kind.isWork || item.kind == .project || item.kind == .goal { Text(item.status.title) }; if let due = item.due { Text(LifeWorkspaceRules.displayDate(due)) }; if let minutes = item.estimateMinutes { Text("\(minutes) min") } }.font(.caption).foregroundStyle(.secondary)
            if !item.notes.isEmpty { Text(item.notes).font(.callout).textSelection(.enabled) }
            if let placement=item.placement {
                if let question=placement.question,placement.status == "question" {
                    Text(question).font(.callout.weight(.medium))
                    ForEach(placement.choices) { choice in Button(choice.label) { model.projectPlacement.choose(choice,for:item,model:model) }.controlSize(.small) }
                } else {
                    HStack(alignment:.top) {
                        Text(placement.reason.isEmpty ? "Waiting for PA placement…" : placement.reason).font(.caption).foregroundStyle(.secondary)
                        if ["paused","unplaced"].contains(placement.status) { Button("Continue placement") { model.projectPlacement.retry(item,model:model) }.font(.caption).disabled(model.projectPlacement.busy) }
                    }
                }
                if placement.parentPinned { Label("Your chosen home",systemImage:"pin.fill").font(.caption2).foregroundStyle(.secondary) }
            }
            if let evidence = item.humanEvidence {
                DisclosureGroup("Created from your PA conversation") { Text(evidence).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }.font(.caption)
            }
            let understanding=model.assistant.memory.notebook(registration,topic:item.conversationID)
            let factIDs=understanding.entities.first{$0.id == "life:"+item.id.uuidString}?.memoryIDs ?? []
            let facts=understanding.notes.flatMap(\.records).filter{factIDs.contains($0.id)}
            if !facts.isEmpty {
                DisclosureGroup("PA understanding · \(Set(facts.map(\.id)).count) facts") {
                    ForEach(Array(Dictionary(facts.map{($0.id,$0)},uniquingKeysWith:{a,_ in a}).values.sorted{$0.id.uuidString < $1.id.uuidString}.prefix(12))) { fact in
                        VStack(alignment:.leading,spacing:3) { Text(fact.text).font(.callout).textSelection(.enabled);Text(fact.attribution).font(.caption).foregroundStyle(.secondary) }.padding(.vertical,4)
                    }
                }.font(.caption)
            }
            let links = store.state.links.filter { $0.from == item.id && $0.registration == registration }
            ForEach(links) { link in
                if let target = LifeWorkspaceContext.resolve(link.target, model: model, registration: registration, topic: item.conversationID, includeTopics: false) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(link.relation.title).font(.caption).foregroundStyle(.secondary)
                            if link.target.kind == .item, let id = UUID(uuidString:link.target.id), let node = items.first(where: { $0.id == id }) {
                                Button(target.title) { open(node) }.buttonStyle(.plain).font(.callout).lineLimit(3)
                            } else { Text(target.title).font(.callout).lineLimit(3).textSelection(.enabled) }
                            Text(target.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            if link.inferred == true { Text("PA connection" + (link.reason.map { " · " + $0 } ?? "")).font(.caption2).foregroundStyle(.secondary).lineLimit(3) }
                        }
                        Spacer()
                        Button { do { try store.unlink(link.id, registration: registration, expectedRevision: store.revision) } catch { notice = error.localizedDescription } } label: { Image(systemName: "link.badge.plus").rotationEffect(.degrees(45)) }.buttonStyle(.plain).accessibilityLabel("Remove relationship")
                    }.padding(8).background(palette[.input].opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            let unavailable = links.filter { LifeWorkspaceContext.resolve($0.target, model: model, registration: registration, topic: item.conversationID, includeTopics: false) == nil }
            ForEach(unavailable) { link in
                HStack {
                    Text(link.relation.title + " · source unavailable").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Unlink") { do { try store.unlink(link.id, registration:registration, expectedRevision:store.revision) } catch { notice = error.localizedDescription } }.font(.caption).buttonStyle(.plain)
                }
            }
        }
    }
}

struct LifeItemEditor: View {
    @Bindable var model: DashboardModel
    @State var item: LifeItem
    var close: () -> Void
    @State private var error: String?
    @State private var dueEnabled = false
    @State private var dueDate = Date.now
    @State private var estimate = ""
    @State private var parentChanged=false
    @State private var autoPlace=true
    private var original: LifeItem? { model.assistant.projects.state.items.first { $0.id == item.id } }
    @State private var expected: UUID?
    private var parents: [LifeItem] {
        let all = model.assistant.projects.items(item.registration, topic: item.conversationID)
        let forbidden = LifeWorkspaceRules.descendants(item.id, in: all).union([item.id])
        return all.filter { !forbidden.contains($0.id) && $0.conversationID == item.conversationID }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(expected == nil ? "New item" : "Edit item").font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $item.title)
                Picker("Type", selection: $item.kind) { ForEach(LifeItemKind.allCases) { Text($0.title).tag($0) } }
                Picker("Inside", selection: $item.parentID) {
                    Text("Your projects").tag(Optional<UUID>.none)
                    ForEach(parents) { parent in Text(LifeItemQuery.path(parent, in: parents).map(\.title).joined(separator: " / ")).tag(Optional(parent.id)) }
                }
                Picker("Status", selection: $item.status) { ForEach(LifeItemStatus.allCases) { Text($0.title).tag($0) } }
                if item.kind == .project,expected == nil { Toggle("Let PA find its place in my Life map",isOn:$autoPlace) }
                Toggle("Deadline", isOn: $dueEnabled)
                if dueEnabled { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
                TextField("Estimate (minutes, optional)", text: $estimate)
                Menu {
                    ForEach(LifeArea.allCases.filter { $0 != .unsorted }) { area in
                        Toggle(area.title, isOn: Binding(get: { item.areas.contains(area) }, set: { selected in
                            if selected, item.areas.count < 3 { item.areas.append(area) } else { item.areas.removeAll { $0 == area } }
                        }))
                    }
                } label: { LabeledContent("Life areas", value: item.areas.isEmpty ? "None" : item.areas.map(\.title).joined(separator: ", ")) }
                TextField("Notes", text: $item.notes, axis: .vertical).lineLimit(4...8)
            }.formStyle(.grouped)
            Text("This tracks local work. Linked calendars and reminders keep their own dates and completion state.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange).font(.callout) }
            HStack { Button("Cancel", action: close).keyboardShortcut(.cancelAction); Spacer(); Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.registration != model.chatGPT.activeID) }
        }.padding(24).frame(width: 500).frame(maxHeight: 720)
        .onChange(of:item.parentID) { parentChanged=true }
        .onAppear {
            expected = original == nil ? nil : item.revision
            dueEnabled = item.due != nil
            if let due = item.due { let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; if let parsed = formatter.date(from: due) { dueDate = parsed } }
            estimate = item.estimateMinutes.map(String.init) ?? ""
        }
    }
    private func save() {
        guard item.registration == model.chatGPT.activeID else { error = "Account changed; your draft has not been saved."; return }
        let value = estimate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, Int(value).map({ (1...100000).contains($0) }) != true { error = "Enter a positive estimate in minutes, or leave it empty."; return }
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.due = dueEnabled ? DateRules.localDate(dueDate) : nil; item.estimateMinutes = Int(value)
        if item.kind == .project {
            if expected == nil,autoPlace { item.placement = .init(parentPinned:parentChanged || item.parentID != nil) }
            else if parentChanged { item.placement = .init(status:"placed",reason:"Your chosen home is pinned.",parentPinned:true) }
        }
        do { _ = try model.assistant.projects.save(item, expected: expected); model.projectPlacement.check(model); close() } catch { self.error = error.localizedDescription }
    }
}

struct LifeItemLinkEditor: View {
    @Bindable var model: DashboardModel
    let item: LifeItem
    var close: () -> Void
    @State private var search = ""
    @State private var kind: LifeReferenceKind = .item
    @State private var relation: LifeRelation = .related
    @State private var selected: LifeReference?
    @State private var error: String?
    private var options: [LifeLinkOption] {
        LifeWorkspaceContext.options(model, registration: item.registration, topic: item.conversationID, includeTopics: false).filter {
            $0.reference.kind == kind && $0.reference.id != item.id.uuidString && (search.isEmpty || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link to " + item.title).font(.title2.weight(.semibold)).lineLimit(2)
            Picker("Relationship", selection: $relation) { ForEach(LifeRelation.allCases.filter{$0 != .identifies}) { Text($0.title).tag($0) } }
            Picker("Look in", selection: $kind) { ForEach(LifeReferenceKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
            TextField("Find an item", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(options.prefix(100)) { option in
                        Button { selected = option.reference } label: {
                            HStack(alignment: .top) {
                                Image(systemName: selected == option.reference ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 4) { Text(option.title).lineLimit(3); Text(option.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                Spacer()
                            }.padding(8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if options.isEmpty { Text("No matching items in current access and cached coverage.").foregroundStyle(.secondary) }
                }
            }.frame(maxWidth: .infinity, minHeight: 180, maxHeight: 340)
            Text("Creates a relationship here. The linked source stays unchanged.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            HStack {
                Button("Cancel", action: close).keyboardShortcut(.cancelAction); Spacer()
                Button("Link") {
                    guard item.registration == model.chatGPT.activeID, let selected, LifeWorkspaceContext.resolve(selected, model: model, registration: item.registration, topic: item.conversationID, includeTopics: false) != nil else { error = "The account, source or item changed. Choose a current item."; return }
                    do { _ = try model.assistant.projects.link(.init(registration: item.registration, conversationID: item.conversationID, from: item.id, relation: relation, target: selected), expected: item.revision); close() } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(selected == nil || item.registration != model.chatGPT.activeID)
            }
        }.padding(24).frame(width: 500)
        .onChange(of: kind) { selected = nil }
    }
}
