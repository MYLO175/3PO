import SwiftUI
import UniformTypeIdentifiers

enum LifeProjectPresentation: String, CaseIterable, Identifiable {
    // Raw values are saved layout/tool identities; only display names change.
    case overview = "Overview", list = "List", board = "Board", outline = "Outline", deadlines = "Deadlines"
    var id: String { rawValue }
    var title:String { switch self { case .overview:"Folders";case .outline:"Tree";default:rawValue } }
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
    @State private var unfiled=false
    @State private var quickTask = ""
    @State private var notesEditing: LifeItem?
    @State private var editing: LifeItem?
    @State private var linking: LifeItem?
    @State private var inspecting=false
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
    private var atHome:Bool { current == nil && !unfiled }
    private var presentation: LifeProjectPresentation { LifeProjectPresentation(rawValue: configuration.wrappedValue.projectView ?? "") ?? .overview }
    private var unfinished: Bool { configuration.wrappedValue.projectOnlyUnfinished == true }
    private var children:[LifeItem] { LifeFolderContents.children(of:current?.id,in:items,unfinished:unfinished) }
    private var folders:[LifeItem] { children.filter{!$0.kind.isWork} }
    private var work:[LifeItem] { children.filter{$0.kind.isWork && $0.status != .archived} }
    private var looseWork:[LifeItem] { LifeFolderContents.children(of:nil,in:items).filter{$0.kind.isWork} }
    private var filtered:[LifeItem] { unfiled ? children.filter{$0.kind.isWork} : atHome ? folders : children }
    private var viewTitle:String { presentation == .overview && !work.isEmpty && !atHome ? "Board" : presentation.title }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in:.horizontal) {
                HStack(spacing:12) { breadcrumbs;Spacer(minLength:12);controls }
                VStack(alignment:.leading,spacing:10) { breadcrumbs;HStack { Spacer();controls } }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let current { projectPage(current) }
                    if atHome { folderGrid(folders,includeUnfiled:true) }
                    else if current?.kind.isWork != true {
                        if filtered.isEmpty {
                            Text(unfinished ? "No unfinished work here." : "This folder is empty.").font(.callout).foregroundStyle(.secondary).padding(.vertical,12)
                        }
                        switch presentation {
                        case .overview:
                            if !unfiled { folderGrid(folders) }
                            if !work.isEmpty { board }
                        case .board:
                            if !unfiled { folderGrid(folders) }
                            board
                        case .list: rows(filtered)
                        case .outline: outline
                        case .deadlines: deadlines
                        }
                        if !atHome { quickCapture }
                    }
                    if atHome && folders.isEmpty && looseWork.isEmpty {
                        Button { add(.section) } label: { Label("New folder",systemImage:"plus").padding(.vertical,20) }.buttonStyle(.plain).foregroundStyle(palette[.accent]).disabled(store.readOnly || registration.isEmpty)
                    }
                    if let error = store.error ?? notice { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom,8)
            }.id((current?.id.uuidString ?? (unfiled ? "unfiled" : "home"))+":"+presentation.rawValue)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editing) { item in LifeItemEditor(model: model, item: item) { editing = nil } }
        .sheet(item: $notesEditing) { item in LifeProjectNotesSheet(model:model,item:item,notes:item.notes) { notesEditing=nil } }
        .sheet(item:$matching) { item in LifeIdentitySheet(model:model,item:item) { matching=nil } }
        .sheet(item:$moving) { item in LifeMoveSheet(model:model,item:item) { moving=nil } }
        .sheet(item:$deleting) { item in LifeDeleteSheet(model:model,item:item) { deleting=nil } }
        .sheet(isPresented:$showDeleted) { LifeRecentlyDeleted(model:model,registration:registration) }
        .sheet(item: $linking) { item in LifeItemLinkEditor(model: model, item: item) { linking = nil } }
        .sheet(isPresented:$inspecting) {
            VStack(alignment:.leading,spacing:16) {
                HStack { Text("Connections & organisation").font(.title2.weight(.semibold));Spacer();Button("Done") { inspecting=false } }
                if let current { Text(current.title).font(.callout).foregroundStyle(.secondary);ScrollView { details(current) } }
            }.padding(24).frame(width:540,height:460)
        }
        .onGeometryChange(for:CGFloat.self) { $0.size.width } action: { availableWidth=$0 }
        .onChange(of: registration) { navigation = .init(); unfiled=false;quickTask="";notesEditing=nil; editing = nil; linking = nil;moving=nil;deleting=nil;matching=nil;drag=nil;showDeleted=false;inspecting=false; notice = nil }
        .onChange(of:store.revision) { navigation.reconcile(items:items) }
        .onChange(of:focusAreas) { navigation.reconcile(items:items);quickTask="";inspecting=false }
        .onChange(of: savedRoot) { navigation = .init();unfiled=false;quickTask="";inspecting=false }
    }
    private var controls:some View {
        HStack(spacing:14) {
            if !atHome,current?.kind.isWork != true {
                Menu {
                    ForEach([LifeProjectPresentation.overview,.list,.board]) { view in
                        Toggle(view == .overview ? "Folders & tasks" : view.title,isOn:Binding(get:{presentation == view},set:{if $0 { setPresentation(view) }}))
                    }
                    Menu("More views") { Button("Tree") { setPresentation(.outline) };Button("Deadlines") { setPresentation(.deadlines) } }
                    Divider()
                    Toggle("Hide finished tasks", isOn: Binding(get: { unfinished }, set: { value in var config = configuration.wrappedValue; config.projectOnlyUnfinished = value; configuration.wrappedValue = config }))
                } label: { HStack(spacing:5) { Image(systemName:presentation.symbol);if availableWidth >= 420 { Text(viewTitle) };if unfinished { Image(systemName:"line.3.horizontal.decrease").font(.caption2) } }.font(.callout) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Project view: " + viewTitle)
            }
            Menu {
                ForEach([LifeItemKind.section,.project,.course,.area,.resource],id:\.self) { kind in Button(kind == .resource ? "Note" : kind.title) { add(kind) } }
                if !atHome { Divider();Button("Task") { add(.task) };Button("Milestone") { add(.milestone) } }
            } label: { Image(systemName:"plus") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Add to this folder").disabled(registration.isEmpty || store.readOnly)
            Menu {
                if let current {
                    Button("Edit details…") { editing=current };Button("Edit notes…") { notesEditing=current }
                    Button("Connections & organisation…") { inspecting=true }
                    Button("Move…") { moving=current }
                    Divider()
                    Toggle("Open this folder by default",isOn:Binding(get:{savedRoot == current.id},set:{setRoot($0 ? current.id : nil)}))
                    Button("Delete…",role:.destructive) { deleting=current }
                }
                if savedRoot != nil { Button("Open Projects home by default") { setRoot(nil) };Divider() }
                Button("Recently deleted…") { showDeleted=true }
            } label: { Image(systemName:"ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Folder options")
        }.foregroundStyle(palette[.accent])
    }
    private var breadcrumbs:some View {
        let path=current.map{LifeItemQuery.path($0,in:items)} ?? []
        return ViewThatFits(in:.horizontal) {
            breadcrumbPath(path,compact:false)
            breadcrumbPath(path,compact:true)
        }
    }
    private func breadcrumbPath(_ path:[LifeItem],compact:Bool)->some View {
        HStack(spacing:8) {
            Button { navigateHome() } label: {
                if atHome { Label("Projects",systemImage:"folder").font(showsHeader ? .title3.weight(.semibold) : .callout.weight(.semibold)) }
                else { Image(systemName:"house").font(.callout) }
            }.buttonStyle(.plain).help("Projects home").accessibilityLabel("Projects home")
            if compact,path.count > 1 {
                Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary)
                Menu { ForEach(path.dropLast()) { item in Button(item.title) { open(item) } } } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Parent folders")
            }
            ForEach(compact ? Array(path.suffix(1)) : path) { item in
                Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary)
                Button(item.title) { open(item) }.buttonStyle(.plain).font(.callout.weight(item.id == current?.id ? .semibold : .regular)).foregroundStyle(item.id == current?.id ? palette[.text] : palette[.text].opacity(0.65)).lineLimit(1).help(item.title)
            }
            if unfiled { Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary);Text("Unfiled tasks").font(.callout.weight(.semibold)) }
        }.fixedSize(horizontal:!compact,vertical:false)
    }
    private func setPresentation(_ value:LifeProjectPresentation) { var config=configuration.wrappedValue;config.projectView=value.rawValue;configuration.wrappedValue=config }
    private func resetPage() { quickTask="";notice=nil;inspecting=false }
    private func navigateHome() { navigation.home();unfiled=false;resetPage() }
    private func setRoot(_ id: UUID?) {
        var config = configuration.wrappedValue
        if config.projectRoots == nil { config.projectRoots = [:] }
        config.projectRoots?[registration] = id?.uuidString ?? ""; configuration.wrappedValue = config
        navigation = .init();unfiled=false;resetPage()
    }
    private func open(_ item: LifeItem) { navigation.open(item.id);unfiled=false;resetPage() }
    private func add(_ kind:LifeItemKind) {
        editing=LifeItem(registration:registration,conversationID:current?.conversationID ?? topicScope,kind:kind,title:"",parentID:current?.id,areas:current?.areas ?? Array(focusAreas.prefix(3)))
    }
    private var quickCapture:some View {
        HStack(spacing:8) {
            Image(systemName:"plus").foregroundStyle(.secondary)
            TextField("Add a task…",text:$quickTask).textFieldStyle(.plain).onSubmit { saveQuickTask() }
            if !quickTask.isEmpty { Button { saveQuickTask() } label:{Image(systemName:"arrow.turn.down.left")}.buttonStyle(.plain).help("Add local task").disabled(quickTask.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.readOnly || registration.isEmpty) }
        }.font(.callout).padding(.vertical,8)
    }
    private func saveQuickTask() {
        let title=quickTask.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !atHome,!title.isEmpty,registration == model.chatGPT.activeID else { return }
        do {
            if let current, !store.items(registration,topic:topicScope).contains(where:{$0.id == current.id && $0.revision == current.revision}) { throw LifeWorkspaceFailure.message("This page changed. Reopen it before adding work.") }
            _ = try store.save(.init(registration:registration,conversationID:current?.conversationID ?? topicScope,kind:.task,title:title,parentID:current?.id,areas:current?.areas ?? Array(focusAreas.prefix(3))),expected:nil)
            quickTask="";notice=nil
        } catch { notice=error.localizedDescription }
    }
    private func complete(_ item:LifeItem) { setStatus(item,item.status == .done ? .planned : .done) }
    private func setStatus(_ item:LifeItem,_ status:LifeItemStatus) {
        guard registration == model.chatGPT.activeID,item.registration == registration else { return }
        var value=item;value.status=status
        do { _ = try store.save(value,expected:item.revision);notice=nil } catch { notice=error.localizedDescription }
    }
    private func projectPage(_ item:LifeItem)->some View {
        VStack(alignment:.leading,spacing:14) {
            if item.kind.isWork {
                Text(item.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                Picker("Stage",selection:Binding(get:{item.status},set:{setStatus(item,$0)})) {
                    ForEach(LifeTaskStage.allCases) { Text($0.rawValue).tag($0.status) }
                    if item.status == .waiting || item.status == .archived { Text(item.status.title).tag(item.status) }
                }.pickerStyle(.segmented).disabled(store.readOnly)
            }
            if item.due != nil || item.estimateMinutes != nil {
                ViewThatFits(in:.horizontal) { HStack(spacing:12) { properties(item) };VStack(alignment:.leading,spacing:4) { properties(item) } }.font(.caption).foregroundStyle(.secondary)
            }
            let progress=LifeFolderContents.progress(under:item.id,in:items)
            if progress.total > 0 { LifeTaskProgressView(progress:progress,showsLegend:true) }
            notesPanel(item)
        }
    }
    private func notesPanel(_ item:LifeItem)->some View {
        VStack(alignment:.leading,spacing:6) {
            if item.notes.isEmpty {
                Button { notesEditing=item } label:{Label("Add a note…",systemImage:"square.and.pencil")}.buttonStyle(.plain).font(.callout).foregroundStyle(palette[.text].opacity(0.45)).padding(.vertical,6)
            } else {
                HStack(alignment:.top,spacing:10) {
                    Text(item.notes).font(.callout).foregroundStyle(palette[.text].opacity(0.8)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                    Button { notesEditing=item } label:{Image(systemName:"pencil")}.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).accessibilityLabel("Edit folder notes")
                }
            }
        }
    }
    @ViewBuilder private func properties(_ item:LifeItem)->some View {
        if let due=item.due { Label(LifeWorkspaceRules.displayDate(due),systemImage:"calendar") }
        if let minutes=item.estimateMinutes { Label("\(minutes) min",systemImage:"clock") }
    }
    private func folderGrid(_ values:[LifeItem],includeUnfiled:Bool=false)->some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:min(160,max(80,availableWidth))),spacing:16,alignment:.top)],alignment:.leading,spacing:18) {
            ForEach(values) { item in
                interactive(item) {
                    Button { open(item) } label: {
                        VStack(spacing:12) {
                            Image(systemName:item.kind == .resource ? "doc.text.fill" : "folder.fill").font(.system(size:48,weight:.regular)).foregroundStyle(palette[.accent].opacity(0.85))
                                .overlay(alignment:.bottomTrailing) { if ![LifeItemKind.section,.resource,.project].contains(item.kind) { Image(systemName:item.kind.symbol).font(.system(size:13,weight:.semibold)).foregroundStyle(palette[.widget]).padding(4) } }
                            Text(item.title).font(.callout.weight(.medium)).foregroundStyle(palette[.text]).multilineTextAlignment(.center).lineLimit(3).frame(maxWidth:.infinity)
                            let progress=LifeFolderContents.progress(under:item.id,in:items)
                            if progress.total > 0 { LifeTaskProgressView(progress:progress,showsLegend:false).frame(maxWidth:100) }
                            else { let count=LifeFolderContents.children(of:item.id,in:items).count;Text(count == 0 ? "" : "\(count) inside").font(.caption2).foregroundStyle(.secondary) }
                        }.padding(.vertical,16).padding(.horizontal,8).frame(maxWidth:.infinity,minHeight:140,alignment:.top).contentShape(RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(.plain)
                }
            }
            if includeUnfiled,!looseWork.isEmpty {
                Button { navigation.home();unfiled=true;resetPage() } label: {
                    VStack(spacing:12) {
                        Image(systemName:"tray.fill").font(.system(size:42)).foregroundStyle(palette[.text].opacity(0.35)).frame(height:52)
                        Text("Unfiled tasks").font(.callout.weight(.medium)).foregroundStyle(palette[.text])
                        Text("\(looseWork.count)").font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical,16).frame(maxWidth:.infinity,minHeight:140,alignment:.top).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
    private func card(_ item:LifeItem,filing:Bool=true,showStage:Bool=true)->some View {
        interactive(item,filing:filing) {
            HStack(alignment:.top,spacing:9) {
                if item.kind.isWork {
                    Button { complete(item) } label:{Image(systemName:item.status == .done ? "checkmark.circle.fill" : "circle").font(.body).foregroundStyle(item.status == .done ? LifeTaskStage.done.color : palette[.text].opacity(0.4))}.buttonStyle(.plain).accessibilityLabel((item.status == .done ? "Mark incomplete: " : "Complete task: ")+item.title).help("Changes this workspace task only").disabled(store.readOnly).padding(.top,2)
                } else { Image(systemName:item.kind.symbol).foregroundStyle(palette[.accent]).padding(.top,2) }
                Button { open(item) } label: {
                    VStack(alignment:.leading,spacing:5) {
                        Text(item.title).font(.callout.weight(.medium)).foregroundStyle(palette[.text]).fixedSize(horizontal:false,vertical:true)
                        if showStage && item.kind.isWork || item.status == .waiting { Text(item.status.title).font(.caption).foregroundStyle(.secondary) }
                        HStack(spacing:8) { properties(item) }.font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(palette[.input].opacity(0.5),in:RoundedRectangle(cornerRadius:9))
        }
    }
    private func interactive<Content:View>(_ item:LifeItem,filing:Bool=true,@ViewBuilder content:()->Content)->some View {
        content()
            .contextMenu {
                Button("Open") { open(item) }
                if item.kind.isWork { Menu("Stage") { ForEach(LifeTaskStage.allCases) { stage in Button(stage.rawValue) { setStatus(item,stage.status) } } } }
                Button("Edit details…") { editing=item };Button("Edit notes…") { notesEditing=item };Button("Move…") { moving=item };Button("Link something…") { linking=item };Button("Match PA understanding…") { matching=item };Divider();Button("Delete…",role:.destructive) { deleting=item }
            }
            .onDrag { drag = .init(id:item.id,registration:registration,revision:store.revision);let provider=NSItemProvider();provider.registerDataRepresentation(forTypeIdentifier:LifeProjectDrag.type.identifier,visibility:.ownProcess) { complete in complete(Data(item.id.uuidString.utf8),nil);return nil };return provider }
            .onDrop(of:[LifeProjectDrag.type],delegate:LifeProjectDrop(target:item.id,parent:item.kind.isWork ? item.parentID : item.id,before:item.kind.isWork ? item.id : nil,drag:$drag,hover:$dropHover,key:item.id.uuidString,store:store,activeRegistration:{model.chatGPT.activeID},report:{notice=$0},enabled:filing))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(dropHover == item.id.uuidString ? palette[.accent] : .clear,lineWidth:2))
    }
    private func rows(_ values: [LifeItem]) -> some View { LazyVStack(alignment:.leading,spacing:7) { ForEach(values) { card($0) } } }
    private func collapsed(_ id:UUID)->Bool { configuration.wrappedValue.projectCollapsed?[registration]?.contains(id.uuidString) == true }
    private func toggle(_ id:UUID) { var config=configuration.wrappedValue;var values=Set(config.projectCollapsed?[registration] ?? []);if !values.insert(id.uuidString).inserted { values.remove(id.uuidString) };if config.projectCollapsed == nil { config.projectCollapsed=[:] };config.projectCollapsed?[registration]=values.sorted();configuration.wrappedValue=config }
    private var outlineItems:[LifeItem] {
        guard !unfiled else { return work }
        var result:[LifeItem]=[]
        func visit(_ parent:UUID?) { for item in LifeFolderContents.children(of:parent,in:items,unfinished:unfinished) { result.append(item);if !collapsed(item.id) { visit(item.id) } } }
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
            if outlineItems.count > 120 { Text("Showing 120 items. Open a folder to see more.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var board:some View {
        let columns=availableWidth >= 560 ? 3 : availableWidth >= 380 ? 2 : 1
        return LazyVGrid(columns:Array(repeating:GridItem(.flexible(minimum:0),alignment:.top),count:columns),alignment:.leading,spacing:12) {
            ForEach(LifeTaskStage.allCases) { stage in
                let tasks=work.filter{LifeTaskStage.stage(for:$0.status) == stage}
                VStack(alignment:.leading,spacing:9) {
                    HStack(spacing:6) { Circle().fill(stage.color).frame(width:7,height:7);Text(stage.rawValue).font(.caption.weight(.medium));Text(String(tasks.count)).font(.caption).foregroundStyle(.secondary);Spacer(minLength:0) }.padding(.horizontal,3)
                    ForEach(tasks) { card($0,filing:false,showStage:false) }
                    if tasks.isEmpty { Color.clear.frame(height:28) }
                }.padding(9).frame(maxWidth:.infinity,minHeight:90,alignment:.topLeading).background(stage.color.opacity(0.055),in:RoundedRectangle(cornerRadius:12))
                    .overlay(RoundedRectangle(cornerRadius:12).stroke(dropHover == "stage:"+stage.id ? stage.color : .clear,lineWidth:2))
                    .onDrop(of:[LifeProjectDrag.type],delegate:LifeProjectStageDrop(stage:stage,parent:current?.id,drag:$drag,hover:$dropHover,store:store,activeRegistration:{model.chatGPT.activeID},permittedIDs:Set(work.map(\.id)),report:{notice=$0}))
            }
        }
    }
    private var deadlines:some View {
        VStack(alignment:.leading,spacing:10) {
            let dates=Set(filtered.compactMap(\.due)).sorted()
            ForEach(dates,id:\.self) { due in Text(LifeWorkspaceRules.displayDate(due)).font(.caption).foregroundStyle(.secondary);rows(filtered.filter{$0.due == due}) }
            let undated=filtered.filter{$0.due == nil}
            if !undated.isEmpty { Text("No deadline").font(.caption).foregroundStyle(.secondary);rows(undated) }
        }
    }
    @ViewBuilder private func details(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let placement=item.placement {
                Text("Where this belongs").font(.headline)
                if let question=placement.question,placement.status == "question" {
                    Text(question).font(.callout)
                    ForEach(placement.choices) { choice in Button(choice.label) { model.projectPlacement.choose(choice,for:item,model:model) }.controlSize(.small) }
                } else if ["paused","unplaced"].contains(placement.status) {
                    Text("The PA hasn’t finished suggesting a home for this item.").font(.callout).foregroundStyle(.secondary)
                    Button("Suggest a folder") { model.projectPlacement.retry(item,model:model) }.disabled(model.projectPlacement.busy)
                    if !placement.reason.isEmpty { DisclosureGroup("Details") { Text(placement.reason).font(.caption).textSelection(.enabled) } }
                } else if !placement.reason.isEmpty { Text(placement.reason).font(.callout).foregroundStyle(.secondary) }
                if placement.parentPinned { Label("You chose this folder",systemImage:"pin.fill").font(.caption).foregroundStyle(.secondary) }
            }
            HStack { Button("Link something…") { inspecting=false;linking=item };Button("Match PA understanding…") { inspecting=false;matching=item } }.controlSize(.small)
            if let evidence=item.humanEvidence { DisclosureGroup("Created from your PA conversation") { Text(evidence).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }.font(.caption) }
            let understanding=model.assistant.memory.notebook(registration,topic:item.conversationID)
            let factIDs=understanding.anchors.first{$0.id == "life:"+item.id.uuidString}?.memoryIDs ?? []
            let facts=understanding.notes.flatMap(\.records).filter{factIDs.contains($0.id)}
            if !facts.isEmpty {
                let count=Set(facts.map(\.id)).count
                DisclosureGroup("PA understanding · \(count) \(count == 1 ? "fact" : "facts")") {
                    ForEach(Array(Dictionary(facts.map{($0.id,$0)},uniquingKeysWith:{a,_ in a}).values.sorted{$0.id.uuidString < $1.id.uuidString}.prefix(12))) { fact in
                        VStack(alignment:.leading,spacing:3) { Text(fact.text).font(.callout).textSelection(.enabled);Text(fact.attribution).font(.caption).foregroundStyle(.secondary);PAMemoryEvidenceView(record:fact,sourcePermitted:model.assistant.memory.permittedRecords.contains{$0.id == fact.id}) }.padding(.vertical,4)
                    }
                }.font(.caption)
            }
            let links=store.state.links.filter{$0.from == item.id && $0.registration == registration}
            ForEach(links) { link in
                if let target=LifeWorkspaceContext.resolve(link.target,model:model,registration:registration,topic:item.conversationID,includeTopics:false) {
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:3) {
                            Text(link.relation.title).font(.caption).foregroundStyle(.secondary)
                            if link.target.kind == .item,let id=UUID(uuidString:link.target.id),let node=items.first(where:{$0.id == id}) { Button(target.title) { open(node) }.buttonStyle(.plain).font(.callout).lineLimit(3) }
                            else { Text(target.title).font(.callout).lineLimit(3).textSelection(.enabled) }
                            Text(target.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            if link.inferred == true { Text("PA connection"+(link.reason.map{" · "+$0} ?? "")).font(.caption2).foregroundStyle(.secondary).lineLimit(3) }
                        }
                        Spacer()
                        Button { do { try store.unlink(link.id,registration:registration,expectedRevision:store.revision) } catch { notice=error.localizedDescription } } label:{Image(systemName:"link.badge.plus").rotationEffect(.degrees(45))}.buttonStyle(.plain).accessibilityLabel("Remove relationship")
                    }.padding(8).background(palette[.input].opacity(0.5),in:RoundedRectangle(cornerRadius:8))
                } else {
                    HStack { Text(link.relation.title+" · source unavailable").font(.caption).foregroundStyle(.secondary);Spacer();Button("Unlink") { do { try store.unlink(link.id,registration:registration,expectedRevision:store.revision) } catch { notice=error.localizedDescription } }.font(.caption).buttonStyle(.plain) }
                }
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.orange) }
        }
    }
}

extension LifeTaskStage {
    var color:Color { switch self { case .todo:Color(red:0.55,green:0.47,blue:0.76);case .inProgress:Color(red:0.81,green:0.59,blue:0.23);case .done:Color(red:0.32,green:0.65,blue:0.45) } }
}
struct LifeTaskProgressView:View {
    let progress:LifeTaskProgress
    var showsLegend=false
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            GeometryReader { proxy in
                HStack(spacing:0) { ForEach(Array(LifeTaskStage.allCases.enumerated()),id:\.element.id) { index,stage in
                    if progress.counts[index] > 0 { stage.color.frame(width:proxy.size.width*Double(progress.counts[index])/Double(max(1,progress.total))) }
                } }.clipShape(Capsule())
            }.frame(height:showsLegend ? 7 : 4).accessibilityLabel("Overall task progress").accessibilityValue(LifeTaskStage.allCases.enumerated().map{"\($0.element.rawValue) \(progress.percentages[$0.offset]) percent"}.joined(separator:", ")).help("Overall progress across \(progress.total) saved tasks and milestones, including subfolders.")
            if showsLegend {
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:16) { legend }
                    VStack(alignment:.leading,spacing:5) { legend }
                }
            }
        }
    }
    private var legend:some View { ForEach(Array(LifeTaskStage.allCases.enumerated()),id:\.element.id) { index,stage in HStack(spacing:5) { Circle().fill(stage.color).frame(width:6,height:6);Text(stage.rawValue+" \(progress.percentages[index])%").foregroundStyle(.secondary) }.font(.caption2) } }
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
                    Text("Projects home").tag(Optional<UUID>.none)
                    ForEach(parents) { parent in Text(LifeItemQuery.path(parent, in: parents).map(\.title).joined(separator: " / ")).tag(Optional(parent.id)) }
                }
                Picker("Stage", selection: $item.status) {
                    ForEach(LifeTaskStage.allCases) { Text($0.rawValue).tag($0.status) }
                    if item.status == .waiting || item.status == .archived { Text(item.status.title).tag(item.status) }
                }
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
