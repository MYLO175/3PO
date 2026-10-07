import SwiftUI
import UniformTypeIdentifiers

enum LifeProjectPresentation: String, CaseIterable, Identifiable {
    case overview = "Overview", list = "List", board = "Board", outline = "Outline", deadlines = "Deadlines"
    var id: String { rawValue }
    var symbol:String { switch self { case .overview:"rectangle.grid.2x2";case .list:"list.bullet";case .board:"rectangle.split.3x1";case .outline:"list.bullet.indent";case .deadlines:"calendar" } }
}
struct LifeProjectWidget: View {
    @Bindable var model: DashboardModel
    var configuration: Binding<WidgetConfiguration>
    var showsHeader = true
    var topicScope:UUID? = nil
    var previewRegistration: String? = nil
    var focusAreas: [LifeArea] = []
    @Environment(\.workspacePalette) private var palette
    @State private var navigation = LifeProjectNavigation()
    @State private var quickTask = ""
    @State private var notesEditing: LifeItem?
    @State private var search = ""
    @State private var editing: LifeItem?
    @State private var linking: LifeItem?
    @State private var notice: String?
    @State private var moving:LifeItem?
    @State private var deleting:LifeItem?
    @State private var showDeleted=false
    @State private var matching:LifeItem?
    @State private var drag:LifeProjectDrag?
    @State private var dropHover:String?
    @State private var availableWidth:CGFloat=300
    private var registration: String { previewRegistration ?? model.chatGPT.activeID }
    private var store: LifeWorkspaceStore { model.assistant.projects }
    private var items: [LifeItem] {
        let all = store.items(registration,topic:topicScope)
        guard !focusAreas.isEmpty else { return all }
        let matching = all.filter { !Set(LifeWorkspaceRules.navigationAreas($0,in:all)).isDisjoint(with:focusAreas) }
        let included = Set(matching.flatMap { LifeItemQuery.path($0, in:all).map(\.id) })
        return all.filter { included.contains($0.id) }
    }
    private var savedRoot: UUID? { configuration.wrappedValue.projectRoots?[registration].flatMap(UUID.init(uuidString:)) }
    private var currentID: UUID? { navigation.destination(startingAt:savedRoot) }
    private var current: LifeItem? { items.first { $0.id == currentID } }
    private var presentation: LifeProjectPresentation { LifeProjectPresentation(rawValue: configuration.wrappedValue.projectView ?? "") ?? .overview }
    private var unfinished: Bool { configuration.wrappedValue.projectOnlyUnfinished == true }
    private var filtered: [LifeItem] { LifeItemQuery(root: current?.id, query: search, unfinished: unfinished).matching(items).filter { $0.id != current?.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                Label("Projects", systemImage: "folder").font(.title3.weight(.semibold))
            }
            HStack(spacing: 8) {
                breadcrumbs
                    .onDrop(of:[LifeProjectDrag.type],delegate:LifeProjectDrop(target:nil,parent:current?.id,before:nil,drag:$drag,hover:$dropHover,key:"home",store:store,activeRegistration:{model.chatGPT.activeID},report:{notice=$0}))
                Spacer(minLength: 0)
                Menu {
                    Button("Start here") { setRoot(current?.id) }
                    Button("Start at all projects") { setRoot(nil) }
                    Divider()
                    Button("Recently deleted…") { showDeleted=true }
                } label: { Image(systemName:"ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Project navigation options")
            }
            HStack(spacing: 8) {
                HStack(spacing:6) {
                    Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search…", text: $search).textFieldStyle(.plain).font(.callout).accessibilityLabel("Find in this branch")
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                }.padding(8).background(palette[.input], in: RoundedRectangle(cornerRadius: 8))
                Menu {
                    Picker("View", selection: Binding(get: { presentation }, set: setPresentation)) {
                        ForEach(LifeProjectPresentation.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Divider()
                    Toggle("Only unfinished", isOn: Binding(get: { unfinished }, set: { value in var config = configuration.wrappedValue; config.projectOnlyUnfinished = value; configuration.wrappedValue = config }))
                } label: { HStack(spacing:5) { Image(systemName:presentation.symbol);if availableWidth >= 340 { Text(presentation.rawValue) };if unfinished { Image(systemName:"line.3.horizontal.decrease").font(.caption2) } }.font(.callout) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Project view: " + presentation.rawValue)
                Menu {
                    ForEach([LifeItemKind.project,.section,.task,.resource,.course,.milestone,.area],id:\.self) { kind in
                        Button(kind == .resource ? "Note or resource" : kind == .section ? "Folder" : kind.title) { add(kind) }
                    }
                } label: { Image(systemName:"plus") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("New project, folder, task or note").disabled(registration.isEmpty || store.readOnly)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let current { projectPage(current) }
                    else { homeSummary }
                    if !search.isEmpty { Text("Search results · \(filtered.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                    if current?.kind.isWork != true, search.isEmpty, [.overview,.list,.board].contains(presentation) { quickCapture }
                    if filtered.isEmpty, current?.kind.isWork != true {
                        VStack(alignment:.leading,spacing:8) {
                            Text(items.isEmpty ? "A home for your projects" : "Nothing here yet").font(.headline)
                            Text(items.isEmpty ? "Create a project or course, add folders, and keep its notes and work together." : search.isEmpty ? "Add a folder, task or note to this page." : "Try another search or turn off Only unfinished.").foregroundStyle(.secondary).font(.callout)
                            if items.isEmpty { Button("Create your first project") { add(.project) }.disabled(store.readOnly || registration.isEmpty) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
                    } else if !filtered.isEmpty {
                        switch presentation {
                        case .overview: overview
                        case .list: rows(filtered)
                        case .outline: outline
                        case .board: board
                        case .deadlines: deadlines
                        }
                    }
                    if let error = store.error ?? notice { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editing) { item in LifeItemEditor(model: model, item: item) { editing = nil } }
        .sheet(item: $notesEditing) { item in LifeProjectNotesSheet(model:model,item:item,notes:item.notes) { notesEditing=nil } }
        .sheet(item:$matching) { item in LifeIdentitySheet(model:model,item:item) { matching=nil } }
        .sheet(item:$moving) { item in LifeMoveSheet(model:model,item:item) { moving=nil } }
        .sheet(item:$deleting) { item in LifeDeleteSheet(model:model,item:item) { deleting=nil } }
        .sheet(isPresented:$showDeleted) { LifeRecentlyDeleted(model:model,registration:registration) }
        .sheet(item: $linking) { item in LifeItemLinkEditor(model: model, item: item) { linking = nil } }
        .onGeometryChange(for:CGFloat.self) { $0.size.width } action: { availableWidth=$0 }
        .onChange(of: registration) { navigation = .init(); search = ""; quickTask="";notesEditing=nil; editing = nil; linking = nil;moving=nil;deleting=nil;matching=nil;drag=nil;showDeleted=false; notice = nil }
        .onChange(of:store.revision) { navigation.reconcile(items:items) }
        .onChange(of:focusAreas) { navigation.reconcile(items:items);search="";quickTask="" }
        .onChange(of: savedRoot) { navigation = .init(); search = "";quickTask="" }
    }
    private var breadcrumbs:some View {
        HStack(spacing:6) {
            Button { navigateHome() } label: { Image(systemName:"house").frame(width:18) }.buttonStyle(.plain).help("All projects")
            if let current {
                Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary)
                Menu {
                    Button("All projects") { navigateHome() }
                    ForEach(LifeItemQuery.path(current,in:items)) { item in Button(item.title) { open(item) } }
                } label: { Text(current.title).font(.callout.weight(.semibold)).lineLimit(1) }.menuStyle(.borderlessButton)
                Button { navigation.back(startingAt:savedRoot,items:items);resetPage() } label: { Image(systemName:"arrow.up").font(.caption) }.buttonStyle(.plain).help("Open parent")
            } else { Text("All projects").font(.callout.weight(.semibold)).lineLimit(1) }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func setPresentation(_ value:LifeProjectPresentation) { var config=configuration.wrappedValue;config.projectView=value.rawValue;configuration.wrappedValue=config }
    private func resetPage() { search="";quickTask="";notice=nil }
    private func navigateHome() { navigation.home();resetPage() }
    private func setRoot(_ id: UUID?) {
        var config = configuration.wrappedValue
        if config.projectRoots == nil { config.projectRoots = [:] }
        config.projectRoots?[registration] = id?.uuidString ?? ""; configuration.wrappedValue = config
        navigation = .init();resetPage()
    }
    private func open(_ item: LifeItem) { navigation.open(item.id);resetPage() }
    private func add(_ kind:LifeItemKind) {
        editing=LifeItem(registration:registration,conversationID:current?.conversationID ?? topicScope,kind:kind,title:"",parentID:current?.id,areas:current?.areas ?? Array(focusAreas.prefix(3)))
    }
    private var quickCapture:some View {
        HStack(spacing:8) {
            Image(systemName:"circle").foregroundStyle(.secondary)
            TextField("Add project task…",text:$quickTask).textFieldStyle(.plain).onSubmit { saveQuickTask() }
            Button { saveQuickTask() } label:{Image(systemName:"arrow.turn.down.left")}.buttonStyle(.plain).help("Add local task").disabled(quickTask.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.readOnly || registration.isEmpty)
        }.font(.callout).padding(10).background(palette[.input].opacity(0.5),in:RoundedRectangle(cornerRadius:10))
    }
    private func saveQuickTask() {
        let title=quickTask.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.isEmpty,registration == model.chatGPT.activeID else { return }
        do {
            if let current, !store.items(registration,topic:topicScope).contains(where:{$0.id == current.id && $0.revision == current.revision}) { throw LifeWorkspaceFailure.message("This page changed. Reopen it before adding work.") }
            _ = try store.save(.init(registration:registration,conversationID:current?.conversationID ?? topicScope,kind:.task,title:title,parentID:current?.id,areas:current?.areas ?? Array(focusAreas.prefix(3))),expected:nil)
            quickTask="";notice=nil
        } catch { notice=error.localizedDescription }
    }
    private func complete(_ item:LifeItem) {
        guard registration == model.chatGPT.activeID,item.registration == registration else { return }
        var value=item;value.status=item.status == .done ? .planned : .done
        do { _ = try store.save(value,expected:item.revision);notice=nil } catch { notice=error.localizedDescription }
    }
    private var homeSummary:some View {
        VStack(alignment:.leading,spacing:8) {
            Text("Your projects").font(.title2.weight(.semibold))
            Text("Projects, courses, notes and the work inside them.").font(.callout).foregroundStyle(.secondary)
            let projects=items.filter{$0.kind == .project && $0.status != .archived}
            let work=items.filter{$0.kind.isWork && $0.status != .done && $0.status != .archived}
            HStack(spacing:12) { Label("\(projects.count) \(projects.count == 1 ? "project" : "projects")",systemImage:"folder");Label("\(work.count) \(work.count == 1 ? "task" : "tasks") left",systemImage:"checklist") }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private func projectPage(_ item:LifeItem)->some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top,spacing:10) {
                Image(systemName:item.kind.symbol).font(.title2).foregroundStyle(palette[.accent]).padding(.top,3)
                VStack(alignment:.leading,spacing:5) {
                    Text(item.title).font(.title2.weight(.semibold)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                    Text(item.kind.title + (item.status != .planned || item.kind.isWork || item.kind == .project ? " · " + item.status.title : "")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Menu {
                    Button("Edit details…") { editing=item }
                    Button("Edit notes…") { notesEditing=item }
                    Button("Link something…") { linking=item }
                    Button("Match PA understanding…") { matching=item }
                    Button("Move…") { moving=item }
                    Divider();Button("Delete…",role:.destructive) { deleting=item }
                } label: { Image(systemName:"ellipsis.circle") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Page actions")
            }
            if item.kind.isWork { Button { complete(item) } label: { Label(item.status == .done ? "Completed · mark incomplete" : "Mark complete",systemImage:item.status == .done ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain).font(.callout).foregroundStyle(palette[.accent]).disabled(store.readOnly).help("Changes this workspace task only") }
            if item.due != nil || item.estimateMinutes != nil {
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:12) { properties(item) }
                    VStack(alignment:.leading,spacing:4) { properties(item) }
                }.font(.callout).foregroundStyle(.secondary)
            }
            let work=items.filter { LifeWorkspaceRules.descendants(item.id,in:items).contains($0.id) && $0.kind.isWork && $0.status != .archived }
            if !work.isEmpty, presentation == .overview {
                VStack(alignment:.leading,spacing:5) {
                    HStack { Text("Progress");Spacer();Text("\(work.filter{$0.status == .done}.count) of \(work.count) done") }.font(.caption).foregroundStyle(.secondary)
                    ProgressView(value:Double(work.filter{$0.status == .done}.count),total:Double(work.count)).tint(palette[.accent])
                }
            }
            if presentation == .overview {
                notesPanel(item)
                if item.placement?.status == "question" { details(item) }
                else { DisclosureGroup("Connections & PA context") { details(item).padding(.top,6) }.font(.caption).foregroundStyle(.secondary) }
            } else {
                if !work.isEmpty { Text(workSummary(item)).font(.caption).foregroundStyle(.secondary) }
                if item.placement?.status == "question" { details(item) }
                DisclosureGroup("Notes & connections") { notesPanel(item);details(item).padding(.top,6) }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func notesPanel(_ item:LifeItem)->some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text("Notes").font(.callout.weight(.semibold));Spacer();Button(item.notes.isEmpty ? "Add notes" : "Edit") { notesEditing=item }.font(.caption).buttonStyle(.plain).foregroundStyle(palette[.accent]) }
            if !item.notes.isEmpty { Text(item.notes).font(.callout).foregroundStyle(palette[.text]).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
        }.padding(12).background(palette[.input].opacity(0.5),in:RoundedRectangle(cornerRadius:10))
    }
    @ViewBuilder private func properties(_ item:LifeItem)->some View {
        if let due=item.due { Label("Due " + LifeWorkspaceRules.displayDate(due),systemImage:"calendar") }
        if let minutes=item.estimateMinutes { Label("\(minutes) min",systemImage:"clock") }
    }
    private func workSummary(_ item: LifeItem) -> String {
        let children = LifeWorkspaceRules.descendants(item.id, in: items)
        let work = items.filter { children.contains($0.id) && $0.kind.isWork && $0.status != .archived }
        if work.isEmpty { return item.kind.title }
        return "\(work.filter { $0.status == .done }.count) of \(work.count) done"
    }
    private func card(_ item: LifeItem) -> some View {
        HStack(spacing:0) {
            if item.kind.isWork {
                Button { complete(item) } label: {
                    Image(systemName:item.status == .done ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(item.status == .done ? palette[.accent] : palette[.text].opacity(0.5)).padding(.leading,12)
                }.buttonStyle(.plain).accessibilityLabel((item.status == .done ? "Mark incomplete: " : "Complete task: ")+item.title).help("Changes this workspace task only").disabled(store.readOnly)
            }
            Button { open(item) } label: {
                HStack(alignment: .top, spacing: 10) {
                    if !item.kind.isWork { Image(systemName: item.kind.symbol).foregroundStyle(palette[.accent]).frame(width: 20) }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.callout.weight(.semibold)).foregroundStyle(palette[.text]).lineLimit(2)
                        Text(item.kind.isWork ? item.status.title : workSummary(item)).font(.caption).foregroundStyle(.secondary)
                        HStack { if let due = item.due { Text("Due " + LifeWorkspaceRules.displayDate(due)) }; if let minutes = item.estimateMinutes { Text("\(minutes) min") } }.font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.background(palette[.input].opacity(0.6),in:RoundedRectangle(cornerRadius:10))
        .contextMenu { Button("Open") { open(item) };Button("Edit details…") { editing=item };Button("Edit notes…") { notesEditing=item };Button("Move…") { moving=item };Button("Link something…") { linking=item };Button("Match PA understanding…") { matching=item };Divider();Button("Delete…",role:.destructive) { deleting=item } }
        .onDrag { drag = .init(id:item.id,registration:registration,revision:store.revision);let provider=NSItemProvider();provider.registerDataRepresentation(forTypeIdentifier:LifeProjectDrag.type.identifier,visibility:.ownProcess) { complete in complete(Data(item.id.uuidString.utf8),nil);return nil };return provider }
        .onDrop(of:[LifeProjectDrag.type],delegate:LifeProjectDrop(target:item.id,parent:item.kind.isWork ? item.parentID : item.id,before:item.kind.isWork ? item.id : nil,drag:$drag,hover:$dropHover,key:item.id.uuidString,store:store,activeRegistration:{model.chatGPT.activeID},report:{notice=$0}))
        .overlay(RoundedRectangle(cornerRadius:10).stroke(dropHover == item.id.uuidString ? palette[.accent] : .clear,lineWidth:2))
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            let direct = filtered.filter { $0.parentID == current?.id && !$0.kind.isWork }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:min(220,max(80,availableWidth))),alignment:.top)],alignment:.leading,spacing:10) {
                ForEach(search.isEmpty ? direct : filtered) { card($0) }
            }
            let next = filtered.filter { $0.kind.isWork && $0.status != .done && $0.status != .archived }.sorted { ($0.due ?? "9999", $0.created) < ($1.due ?? "9999", $1.created) }
            if !next.isEmpty, search.isEmpty {
                Text("Upcoming work").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                rows(Array(next.prefix(5)))
                if next.count > 5 { Button("View all \(next.count) work items") { setPresentation(.list) }.font(.caption) }
            } else if search.isEmpty {
                let completed=filtered.filter{$0.kind.isWork && $0.status == .done}
                if !completed.isEmpty { Text("Completed work").font(.caption.weight(.semibold)).foregroundStyle(.secondary);rows(Array(completed.prefix(5))) }
            }
        }
    }
    private func rows(_ values: [LifeItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) { ForEach(values) { item in card(item) } }
    }
    private func collapsed(_ id:UUID)->Bool { configuration.wrappedValue.projectCollapsed?[registration]?.contains(id.uuidString) == true }
    private func toggle(_ id:UUID) { var config=configuration.wrappedValue;var values=Set(config.projectCollapsed?[registration] ?? []);if !values.insert(id.uuidString).inserted { values.remove(id.uuidString) };if config.projectCollapsed == nil { config.projectCollapsed=[:] };config.projectCollapsed?[registration]=values.sorted();configuration.wrappedValue=config }
    private var outlineItems:[LifeItem] {
        guard search.isEmpty else { return filtered }
        let ids=Set(filtered.map(\.id));var result:[LifeItem]=[]
        func visit(_ parent:UUID?) { for item in items.filter({$0.parentID == parent && ids.contains($0.id)}) { result.append(item);if !collapsed(item.id) { visit(item.id) } } }
        visit(current?.id);return result
    }
    private var outline:some View {
        LazyVStack(alignment:.leading,spacing:4) {
            ForEach(Array(outlineItems.prefix(120))) { item in
                let depth=max(0,LifeItemQuery.path(item,in:items).count-(current.map{LifeItemQuery.path($0,in:items).count} ?? 0)-1)
                VStack(spacing:0) {
                    if drag != nil { Rectangle().fill(dropHover == "before:"+item.id.uuidString ? palette[.accent] : palette[.border].opacity(0.4)).frame(height:6)
                        .onDrop(of:[LifeProjectDrag.type],delegate:LifeProjectDrop(target:item.id,parent:item.parentID,before:item.id,drag:$drag,hover:$dropHover,key:"before:"+item.id.uuidString,store:store,activeRegistration:{model.chatGPT.activeID},report:{notice=$0})) }
                    HStack(spacing:5) {
                        if items.contains(where:{$0.parentID == item.id}) { Button { toggle(item.id) } label:{Image(systemName:collapsed(item.id) ? "chevron.right" : "chevron.down").frame(width:16)}.buttonStyle(.plain).accessibilityLabel((collapsed(item.id) ? "Expand " : "Collapse ")+item.title) }
                        else { Color.clear.frame(width:16,height:1) }
                        card(item)
                    }
                }.padding(.leading,CGFloat(min(depth,8))*14)
            }
            if outlineItems.count > 120 { Text("Showing 120 items. Search to narrow this branch.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var board: some View {
        // Columns adapt to available widget width rather than forcing dashboard scrolling.
        LazyVGrid(columns: [GridItem(.adaptive(minimum:min(180,max(80,availableWidth))), alignment: .top)], alignment: .leading, spacing: 12) {
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
            Text(item.ownership == "life" ? "PA life context · you can correct its organisation" : "Your workspace · the PA edits it when asked").font(.caption).foregroundStyle(.secondary)
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
            let factIDs=understanding.anchors.first{$0.id == "life:"+item.id.uuidString}?.memoryIDs ?? []
            let facts=understanding.notes.flatMap(\.records).filter{factIDs.contains($0.id)}
            if !facts.isEmpty {
                DisclosureGroup("PA understanding · \(Set(facts.map(\.id)).count) facts") {
                    ForEach(Array(Dictionary(facts.map{($0.id,$0)},uniquingKeysWith:{a,_ in a}).values.sorted{$0.id.uuidString < $1.id.uuidString}.prefix(12))) { fact in
                        VStack(alignment:.leading,spacing:3) { Text(fact.text).font(.callout).textSelection(.enabled);Text(fact.attribution).font(.caption).foregroundStyle(.secondary);PAMemoryEvidenceView(record:fact,sourcePermitted:model.assistant.memory.permittedRecords.contains{$0.id == fact.id}) }.padding(.vertical,4)
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

/// A captured page/revision draft; source links and native notes are never edited here.
struct LifeProjectNotesSheet:View {
    @Bindable var model:DashboardModel
    let item:LifeItem
    @State var notes:String
    var close:()->Void
    @State private var error:String?
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Notes").font(.title2.weight(.semibold))
            Text(item.title).font(.callout).foregroundStyle(.secondary)
            TextEditor(text:$notes).font(.body).padding(6).frame(minHeight:240).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Button("Cancel",action:close).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    guard item.registration == model.chatGPT.activeID else {error="Account changed; your draft has not been saved.";return}
                    var value=item;value.notes=notes
                    do { _ = try model.assistant.projects.save(value,expected:item.revision);close() } catch { self.error=error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(item.registration != model.chatGPT.activeID || model.assistant.projects.readOnly)
            }
        }.padding(24).frame(width:520,height:440)
    }
}

struct LifeItemEditor: View {
    @Bindable var model: DashboardModel
    @State var item: LifeItem
    var close: () -> Void
    var reviewedSuggestion:PADiscovery? = nil
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
            Text((expected == nil ? "New " : "Edit ") + item.kind.title.lowercased()).font(.title2.weight(.semibold))
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
            Text("Workspace tasks track project work. Your linked Apple reminders and calendar keep their own dates and completion state.").font(.caption).foregroundStyle(.secondary)
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
        if [.project,.section,.task,.milestone,.resource].contains(item.kind) { item.ownership="workspace" }
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.due = dueEnabled ? DateRules.localDate(dueDate) : nil; item.estimateMinutes = Int(value)
        if item.kind == .project {
            if expected == nil,autoPlace { item.placement = .init(parentPinned:parentChanged || item.parentID != nil) }
            else if parentChanged { item.placement = .init(status:"placed",reason:"Your chosen home is pinned.",parentPinned:true) }
        }
        do {
            if let proposal=reviewedSuggestion {
                guard expected == nil,model.proactive.visible(proposal,model:model),proposal.registration == model.chatGPT.activeID else { throw LifeWorkspaceFailure.message("The source suggestion changed or is no longer permitted. Your draft is kept.") }
                item.humanEvidence="Accepted a reviewed PA project suggestion."
                let reference:LifeReference
                if proposal.sourceKind == "whatsapp",let chat=proposal.sourceChatID,let message=proposal.sourceMessageID,let identity=proposal.sourceIdentity,let version=proposal.sourceRevision { reference = .init(kind:.whatsapp,id:message,containerID:chat,linkedIdentity:identity,contentRevision:version) }
                else if let message=model.emailSummaries.highlights(model).first(where:{$0.0.id == proposal.mailID})?.0 { reference = .init(kind:.mail,id:message.id,containerID:message.accountID,contentRevision:message.internetMessageID) }
                else { throw LifeWorkspaceFailure.message("The original source is unavailable; no project saved.") }
                _ = try model.assistant.projects.create([item],receipt:.init(id:"project-suggestion:"+proposal.id,registration:item.registration,result:"Created a human-reviewed project.",itemID:item.id),links:[.init(registration:item.registration,conversationID:item.conversationID,from:item.id,relation:.evidence,target:reference)])
            } else { _ = try model.assistant.projects.save(item, expected: expected) }
            model.projectPlacement.check(model);close()
        } catch { self.error = error.localizedDescription }
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
