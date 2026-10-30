#if DEBUG
import SwiftUI

/// Four fictional Projects layouts to compare side by side (`--preview-projects-lab`).
/// Edits are shared between the designs and live only in memory; Reset restores the sample.
struct ProjectsDesignLab: View {
    @State private var store = LabStore.sample()
    @State private var design = LabDesign.sidebar
    @State private var narrow = false
    @State private var theme = WorkspaceColorTheme.sage
    @State private var dark = false
    private var palette: WorkspacePalette {
        var overrides = WorkspaceColorOverrides(); overrides.profiles = theme.profiles
        return .resolved(raw:overrides.encoded,mode:dark ? "dark" : "light",theme:"custom",accent:"sage")
    }
    var body: some View {
        let palette = palette
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:16) {
                Picker("Design",selection:$design) { ForEach(LabDesign.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(maxWidth:480)
                Picker("Width",selection:$narrow) { Text("Wide").tag(false); Text("Narrow").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width:130)
                Picker("Colours",selection:$theme) { ForEach(WorkspaceColorTheme.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width:130)
                Toggle("Dark",isOn:$dark)
                Spacer()
                Button("Reset sample") { store = .sample() }
            }
            HStack(alignment:.firstTextBaseline) {
                Text(design.summary).font(.callout).foregroundStyle(palette[.text].opacity(0.75)).fixedSize(horizontal:false,vertical:true)
                Spacer()
                Text("Fictional data · nothing is saved").font(.caption).foregroundStyle(palette[.text].opacity(0.5))
            }
            Group {
                switch design {
                case .cards: LabCardsDesign(store:store)
                case .timeline: LabTimelineDesign(store:store)
                case .outline: LabOutlineDesign(store:store)
                case .sidebar: LabSidebarDesign(store:store)
                }
            }
            .padding(20).frame(maxWidth:narrow ? 470 : .infinity,maxHeight:.infinity,alignment:.topLeading)
            .background(palette[.widget],in:RoundedRectangle(cornerRadius:20))
            .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(palette[.border]))
        }
        .padding(16).frame(minWidth:760,minHeight:560)
        .foregroundStyle(palette[.text]).tint(palette[.accent]).background(palette[.canvas])
        .environment(\.workspacePalette,palette).preferredColorScheme(dark ? .dark : .light)
    }
}
enum LabDesign: String, CaseIterable, Identifiable {
    case cards, timeline, outline, sidebar
    var id: String { rawValue }
    var title: String { switch self { case .cards: "A · Cards"; case .timeline: "B · Timeline"; case .outline: "C · Outline"; case .sidebar: "D · Sidebar" } }
    var summary: String {
        switch self {
        case .cards: "Home opens on Due soon, then project cards with progress and the next deadline. Inside a project, subprojects are cards above the board, and the board can include their tasks."
        case .timeline: "Deadlines first. A strip of the next few weeks, then every task grouped Late, This week, Next week and Later. Projects and subprojects are tiles you open."
        case .outline: "One page per project, read top to bottom. Subprojects are folding sections with their own progress; tasks read like a checklist with stage and date on the right."
        case .sidebar: "A sidebar holds the project tree. Home lays out every project as a card with Due soon below; a project shows its subprojects, board and notes."
        }
    }
}

// MARK: A · Cards

struct LabCardsDesign: View {
    let store: LabStore
    @State private var current: UUID?
    @State private var deep = false
    @State private var width: CGFloat = 800
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:26) {
                LabHeader(store:store,current:current) { current = $0 }
                if let current { page(current) } else { home }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.bottom,8)
        }
        .onGeometryChange(for:CGFloat.self) { $0.size.width } action: { width = $0 }
    }
    private var home: some View {
        VStack(alignment:.leading,spacing:26) {
            LabSection(title:"Due soon") { LabDueSoonList(store:store,scope:nil,limit:5) }
            LabSection(title:"Projects") { LabCardGrid(projects:store.children(of:nil),store:store) { current = $0 } }
        }
    }
    @ViewBuilder private func page(_ id: UUID) -> some View {
        let subprojects = store.children(of:id)
        if !subprojects.isEmpty {
            LabSection(title:"Subprojects") { LabCardGrid(projects:subprojects,store:store,minimum:180,compact:true) { current = $0 } }
        }
        LabSection(title:"Tasks",accessory:{
            if !subprojects.isEmpty { Toggle("Include subprojects",isOn:$deep).toggleStyle(.checkbox).font(.caption) }
        }) { LabBoard(store:store,scope:id,deep:deep,width:width) }
        LabNotes(notes:store.notes[id] ?? [])
    }
}

// MARK: B · Timeline

struct LabTimelineDesign: View {
    let store: LabStore
    @State private var current: UUID?
    @State private var adding = false
    @State private var target: UUID?
    @State private var showDone = false
    @State private var width: CGFloat = 800
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                LabHeader(store:store,current:current) { current = $0; adding = false; target = nil }
                LabDayStrip(store:store,scope:current,days:width >= 640 ? 21 : 14)
                tiles
                tasks
                if let current { LabNotes(notes:store.notes[current] ?? []) }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.bottom,8)
        }
        .onGeometryChange(for:CGFloat.self) { $0.size.width } action: { width = $0 }
    }
    @ViewBuilder private var tiles: some View {
        let children = store.children(of:current)
        if !children.isEmpty {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:190),spacing:8,alignment:.top)],alignment:.leading,spacing:8) {
                ForEach(children) { project in LabProjectTile(project:project,store:store) { current = project.id; adding = false; target = nil } }
            }
        }
    }
    private var tasks: some View {
        let all = store.tasks(under:current)
        let groups = LabStore.timeGroups(all.filter { $0.stage != .done }.sorted(by:LabStore.byDue))
        let done = all.filter { $0.stage == .done }.sorted { ($0.finished ?? .distantPast) > ($1.finished ?? .distantPast) }
        return VStack(alignment:.leading,spacing:16) {
            HStack {
                Text(current == nil ? "Everything" : "All tasks here").font(.headline)
                Spacer()
                Button { adding.toggle() } label: { Label("Add task",systemImage:"plus") }.buttonStyle(.borderless)
            }
            if adding { addRow }
            ForEach(groups,id:\.title) { group in
                VStack(alignment:.leading,spacing:0) {
                    Text(group.title).font(.caption.weight(.semibold)).foregroundStyle(group.title == "Late" ? Color.red : Color.secondary).padding(.bottom,4)
                    ForEach(group.tasks) { task in
                        LabTaskRow(task:task,store:store,tag:store.place(task,from:current),showStage:true,card:false)
                        Divider().opacity(0.5)
                    }
                }
            }
            if !done.isEmpty {
                Button { showDone.toggle() } label: {
                    Label(showDone ? "Hide finished" : "\(done.count) finished",systemImage:showDone ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold))
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                if showDone { ForEach(done) { task in LabTaskRow(task:task,store:store,tag:store.place(task,from:current),card:false) } }
            }
        }
    }
    private var addRow: some View {
        let options = store.flattened(under:current)
        let chosen = target.flatMap { id in options.contains { $0.id == id } ? id : nil } ?? current ?? options.first?.id
        return VStack(alignment:.leading,spacing:6) {
            LabQuickAdd { title,due in if let chosen { store.add(title,due:due,project:chosen) } } close: { adding = false }
            if let chosen, options.count > 1 {
                Picker("Add to",selection:Binding(get:{ chosen },set:{ target = $0 })) {
                    ForEach(options) { option in Text(store.path(option.id).map(\.title).joined(separator:" › ")).tag(option.id) }
                }.fixedSize().font(.caption)
            }
        }
    }
}
/// Next few weeks at a glance: a dot for each unfinished deadline, late work counted on the left.
struct LabDayStrip: View {
    let store: LabStore
    let scope: UUID?
    let days: Int
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        let open = store.open(under:scope).filter { $0.due != nil }
        let late = open.filter { LabDue.days($0.due!) < 0 }
        HStack(spacing:6) {
            if !late.isEmpty {
                VStack(spacing:2) { Text("\(late.count)").font(.callout.weight(.semibold)); Text("late").font(.caption2) }
                    .foregroundStyle(.red).frame(width:46).padding(.vertical,7).background(Color.red.opacity(0.1),in:RoundedRectangle(cornerRadius:8))
                    .help(late.map(\.title).joined(separator:"\n"))
            }
            HStack(spacing:2) { ForEach(0..<days,id:\.self) { offset in cell(offset,tasks:open.filter { LabDue.days($0.due!) == offset }) } }
        }
    }
    private func cell(_ offset: Int, tasks: [LabTask]) -> some View {
        let date = LabDue.day(offset)
        let weekend = Calendar.current.isDateInWeekend(date)
        return VStack(spacing:3) {
            Text(date.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
            Text(date.formatted(.dateTime.day())).font(.caption.weight(offset == 0 ? .bold : .regular))
            HStack(spacing:2) {
                ForEach(Array(tasks.prefix(3))) { task in
                    let urgency = LabDue.label(task.due!).urgency
                    Circle().fill(urgency == .later ? palette[.accent] : urgency.color).frame(width:6,height:6)
                }
            }.frame(height:6)
        }
        .frame(maxWidth:.infinity).padding(.vertical,6)
        .background(offset == 0 ? palette[.accent].opacity(0.16) : weekend ? palette[.text].opacity(0.035) : Color.clear,in:RoundedRectangle(cornerRadius:7))
        .help(tasks.isEmpty ? date.formatted(date:.abbreviated,time:.omitted) : tasks.map(\.title).joined(separator:"\n"))
    }
}
struct LabProjectTile: View {
    let project: LabProject
    let store: LabStore
    let open: () -> Void
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        let late = store.lateCount(project.id)
        Button(action:open) {
            HStack(spacing:10) {
                Image(systemName:project.icon).foregroundStyle(palette[.accent]).frame(width:18)
                VStack(alignment:.leading,spacing:5) {
                    Text(project.title).font(.callout.weight(.medium)).lineLimit(1)
                    LabProgressBar(counts:store.progress(project.id),height:5)
                }
                if late > 0 { Text("\(late)").font(.caption2.weight(.bold)).foregroundStyle(.white).frame(minWidth:16,minHeight:16).background(Circle().fill(.red)).help("\(late) late") }
                Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(10).frame(maxWidth:.infinity,alignment:.leading)
            .background(palette[.input].opacity(0.6),in:RoundedRectangle(cornerRadius:10)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// MARK: C · Outline

struct LabOutlineDesign: View {
    let store: LabStore
    @State private var current: UUID?
    @State private var collapsed: Set<UUID> = []
    @State private var adding: UUID?
    @State private var dueSoonOpen = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                LabHeader(store:store,current:current) { current = $0; adding = nil }
                if let current { page(current) } else { home }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.bottom,8)
        }
    }
    private var home: some View {
        VStack(alignment:.leading,spacing:18) {
            DisclosureGroup(isExpanded:$dueSoonOpen) { LabDueSoonList(store:store,scope:nil).padding(.top,8) } label: { LabDueSummary(store:store,scope:nil) }
            VStack(spacing:0) {
                ForEach(store.children(of:nil)) { project in
                    LabProjectRow(project:project,store:store) { current = project.id }
                    Divider().opacity(0.6)
                }
            }
        }
    }
    private func page(_ id: UUID) -> some View {
        VStack(alignment:.leading,spacing:8) {
            LabOutlineTasks(store:store,project:id,adding:$adding)
            ForEach(store.children(of:id)) { child in
                LabOutlineSection(store:store,project:child,depth:0,collapsed:$collapsed,adding:$adding) { current = $0; adding = nil }
            }
            LabNotes(notes:store.notes[id] ?? []).padding(.top,16)
        }
    }
}
struct LabProjectRow: View {
    let project: LabProject
    let store: LabStore
    let open: () -> Void
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        let late = store.lateCount(project.id), subprojects = store.children(of:project.id).count
        Button(action:open) {
            HStack(spacing:12) {
                Image(systemName:project.icon).font(.title3).foregroundStyle(palette[.accent]).frame(width:26)
                VStack(alignment:.leading,spacing:4) {
                    Text(project.title).font(.body.weight(.medium))
                    HStack(spacing:6) {
                        if let next = store.nextDue(project.id), let due = next.due { LabDueChip(due:due); Text(next.title).lineLimit(1) } else { Text("No deadlines") }
                        if subprojects > 0 { Text("· \(subprojects) inside") }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:10)
                if late > 0 { Text("\(late) late").font(.caption.weight(.medium)).foregroundStyle(.red) }
                LabProgressBar(counts:store.progress(project.id),height:7).frame(width:110)
                Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical,11).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
/// Tasks directly in one project, as a checklist with inline add and finished work folded.
struct LabOutlineTasks: View {
    let store: LabStore
    let project: UUID
    @Binding var adding: UUID?
    @State private var showDone = false
    var body: some View {
        let all = store.tasks(under:project,deep:false)
        let open = all.filter { $0.stage != .done }.sorted(by:LabStore.byDue), done = all.filter { $0.stage == .done }
        VStack(alignment:.leading,spacing:0) {
            ForEach(open) { task in LabTaskRow(task:task,store:store,showStage:true,card:false) }
            if adding == project {
                LabQuickAdd { title,due in store.add(title,due:due,project:project) } close: { adding = nil }.padding(.vertical,4)
            } else {
                Button { adding = project } label: { Label("Add task",systemImage:"plus").font(.callout) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).padding(.vertical,6).padding(.leading,6)
            }
            if !done.isEmpty {
                Button(showDone ? "Hide finished" : "\(done.count) finished") { showDone.toggle() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(.leading,6).padding(.bottom,4)
                if showDone { ForEach(done) { task in LabTaskRow(task:task,store:store,card:false) } }
            }
        }
    }
}
struct LabOutlineSection: View {
    let store: LabStore
    let project: LabProject
    let depth: Int
    @Binding var collapsed: Set<UUID>
    @Binding var adding: UUID?
    let open: (UUID) -> Void
    @Environment(\.workspacePalette) private var palette
    private var isCollapsed: Bool { collapsed.contains(project.id) }
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            header
            if !isCollapsed {
                VStack(alignment:.leading,spacing:4) {
                    LabOutlineTasks(store:store,project:project.id,adding:$adding)
                    ForEach(store.children(of:project.id)) { child in
                        LabOutlineSection(store:store,project:child,depth:depth+1,collapsed:$collapsed,adding:$adding,open:open)
                    }
                }.padding(.leading,24)
            }
        }.padding(.top,depth == 0 ? 12 : 4)
    }
    private var header: some View {
        HStack(spacing:8) {
            Button { if isCollapsed { collapsed.remove(project.id) } else { collapsed.insert(project.id) } } label: {
                Image(systemName:"chevron.right").font(.caption.weight(.semibold)).rotationEffect(.degrees(isCollapsed ? 0 : 90)).frame(width:16,height:16).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel((isCollapsed ? "Expand " : "Collapse ")+project.title)
            Image(systemName:project.icon).foregroundStyle(palette[.accent])
            Text(project.title).font(depth == 0 ? .headline : .subheadline.weight(.semibold)).lineLimit(1)
            LabProgressBar(counts:store.progress(project.id),height:6).frame(width:80)
            if isCollapsed, let next = store.nextDue(project.id), let due = next.due { LabDueChip(due:due) }
            Spacer(minLength:6)
            Button { open(project.id) } label: { Image(systemName:"arrow.up.right") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Open as its own page")
        }
        .padding(.vertical,5).padding(.horizontal,6)
        .background(palette[.text].opacity(depth == 0 ? 0.04 : 0.025),in:RoundedRectangle(cornerRadius:8))
    }
}

// MARK: D · Sidebar

enum LabSidebarItem: Hashable { case home, project(UUID) }
struct LabSidebarDesign: View {
    let store: LabStore
    @State private var selection = LabSidebarItem.home
    @State private var expanded: Set<UUID> = []
    @State private var deep = true
    @State private var width: CGFloat = 900
    private var wide: Bool { width >= 640 }
    var body: some View {
        ZStack(alignment:.topLeading) {
            if wide {
                HStack(alignment:.top,spacing:0) {
                    ScrollView { sidebar.padding(.trailing,10) }.frame(width:260)
                    Divider().padding(.trailing,20)
                    ScrollView { detail.frame(maxWidth:.infinity,alignment:.leading).padding(.bottom,8) }
                }
            } else {
                VStack(alignment:.leading,spacing:16) { compactPicker; ScrollView { detail.frame(maxWidth:.infinity,alignment:.leading) } }
            }
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .onGeometryChange(for:CGFloat.self) { $0.size.width } action: { width = $0 }
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:2) {
            LabSidebarRow(icon:"square.grid.2x2",title:"All projects",depth:0,selected:selection == .home,late:store.lateCount(nil)) { selection = .home }
            Text("Projects").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top,14).padding(.leading,8).padding(.bottom,4)
            ForEach(store.children(of:nil)) { project in LabTreeRow(store:store,project:project,depth:0,selection:$selection,expanded:$expanded) }
        }
    }
    private var compactPicker: some View {
        Menu {
            Button("All projects") { selection = .home }
            Divider()
            ForEach(store.flattened(under:nil)) { project in
                Button(String(repeating:"    ",count:max(0,store.path(project.id).count-1))+project.title) { selection = .project(project.id) }
            }
        } label: { Label(selectionTitle,systemImage:"sidebar.left") }.fixedSize()
    }
    private var selectionTitle: String {
        if case .project(let id) = selection, let project = store.project(id) { return project.title }
        return "All projects"
    }
    @ViewBuilder private var detail: some View {
        switch selection {
        case .home:
            VStack(alignment:.leading,spacing:26) {
                LabHeader(store:store,current:nil) { selection = $0.map(LabSidebarItem.project) ?? .home }
                LabCardGrid(projects:store.children(of:nil),store:store,minimum:200,compact:true) { id in
                    expanded.formUnion(store.path(id).map(\.id)); selection = .project(id)
                }
                LabSection(title:"Due soon") { LabDueSoonList(store:store,scope:nil,limit:8) }
            }
        case .project(let id):
            let subprojects = store.children(of:id)
            VStack(alignment:.leading,spacing:22) {
                LabHeader(store:store,current:id) { selection = $0.map(LabSidebarItem.project) ?? .home }
                if !subprojects.isEmpty {
                    LabCardGrid(projects:subprojects,store:store,minimum:170,compact:true) { child in
                        expanded.formUnion(store.path(child).map(\.id)); selection = .project(child)
                    }
                }
                LabSection(title:"Tasks",accessory:{
                    if !subprojects.isEmpty { Toggle("Include subprojects",isOn:$deep).toggleStyle(.checkbox).font(.caption) }
                }) { LabBoard(store:store,scope:id,deep:deep,width:wide ? width-290 : width) }
                LabNotes(notes:store.notes[id] ?? [])
            }
        }
    }
}
struct LabSidebarRow: View {
    let icon: String
    let title: String
    let depth: Int
    let selected: Bool
    var late = 0
    var counts: [Int]? = nil
    let select: () -> Void
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        Button(action:select) {
            HStack(spacing:7) {
                Image(systemName:icon).foregroundStyle(palette[.accent]).frame(width:16)
                Text(title).font(.callout).lineLimit(1)
                Spacer(minLength:4)
                if late > 0 { Text("\(late)").font(.caption2.weight(.bold)).foregroundStyle(.white).frame(minWidth:16,minHeight:16).background(Circle().fill(.red)).help("\(late) late") }
                if let counts, counts.reduce(0,+) > 0 { LabProgressBar(counts:counts,height:5).frame(width:28) }
            }
            .padding(.vertical,6).padding(.horizontal,8).padding(.leading,CGFloat(depth)*14)
            .background(selected ? palette[.accent].opacity(0.16) : Color.clear,in:RoundedRectangle(cornerRadius:7)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
struct LabTreeRow: View {
    let store: LabStore
    let project: LabProject
    let depth: Int
    @Binding var selection: LabSidebarItem
    @Binding var expanded: Set<UUID>
    var body: some View {
        let children = store.children(of:project.id), open = expanded.contains(project.id)
        VStack(alignment:.leading,spacing:2) {
            HStack(spacing:0) {
                if children.isEmpty { Color.clear.frame(width:14,height:1) } else {
                    Button { if open { expanded.remove(project.id) } else { expanded.insert(project.id) } } label: {
                        Image(systemName:"chevron.right").font(.caption2.weight(.semibold)).rotationEffect(.degrees(open ? 90 : 0)).frame(width:14,height:20).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.leading,CGFloat(depth)*14)
                }
                LabSidebarRow(icon:project.icon,title:project.title,depth:children.isEmpty ? depth : 0,selected:selection == .project(project.id),late:store.lateCount(project.id),counts:store.progress(project.id)) {
                    selection = .project(project.id); if !children.isEmpty { expanded.insert(project.id) }
                }
            }
            if open { ForEach(children) { child in LabTreeRow(store:store,project:child,depth:depth+1,selection:$selection,expanded:$expanded) } }
        }
    }
}
#endif
