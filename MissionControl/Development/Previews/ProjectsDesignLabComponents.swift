#if DEBUG
import SwiftUI

struct LabChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.medium)).lineLimit(1).padding(.horizontal,6).padding(.vertical,2)
            .foregroundStyle(color).background(color.opacity(0.13),in:RoundedRectangle(cornerRadius:5))
    }
}
struct LabDueChip: View {
    let due: Date
    var body: some View {
        let label = LabDue.label(due)
        LabChip(text:label.text,color:label.urgency.color).help(due.formatted(date:.complete,time:.omitted))
    }
}
/// Same red/amber/green split as the real header bar; exact counts on hover only.
struct LabProgressBar: View {
    let counts: [Int]
    var height: CGFloat = 10
    private var summary: String { LifeTaskStage.allCases.enumerated().map { "\($0.element.rawValue): \(counts[$0.offset])" }.joined(separator:", ") }
    var body: some View {
        let total = max(1,counts.reduce(0,+))
        GeometryReader { proxy in
            HStack(spacing:0) {
                ForEach(Array(LifeTaskStage.allCases.enumerated()),id:\.element.id) { index,stage in
                    if counts[index] > 0 { stage.color.frame(width:proxy.size.width*CGFloat(counts[index])/CGFloat(total)) }
                }
            }.frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.07)).clipShape(Capsule())
        }.frame(height:height).help(summary).accessibilityElement(children:.ignore).accessibilityLabel("Task progress").accessibilityValue(summary)
    }
}
struct LabStagePill: View {
    let task: LabTask
    let store: LabStore
    var body: some View {
        HStack(spacing:3) {
            Circle().fill(task.stage.color).frame(width:6,height:6)
            Menu { ForEach(LifeTaskStage.allCases) { stage in Button(stage.rawValue) { store.setStage(task.id,stage) } } } label: { Text(task.stage.rawValue).font(.caption2) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }
}
struct LabTaskRow: View {
    let task: LabTask
    let store: LabStore
    var tag: String? = nil
    var showStage = false
    var card = true
    @Environment(\.workspacePalette) private var palette
    private var done: Bool { task.stage == .done }
    private var hasMeta: Bool { (card && task.due != nil && !done) || (task.waiting != nil && !done) || tag != nil }
    var body: some View {
        HStack(alignment:.top,spacing:9) {
            Button { store.toggle(task.id) } label: {
                Image(systemName:done ? "checkmark.circle.fill" : "circle").font(.body)
                    .foregroundStyle(done ? LifeTaskStage.done.color : palette[.text].opacity(0.4))
            }.buttonStyle(.plain).accessibilityLabel((done ? "Mark incomplete: " : "Complete: ")+task.title)
            VStack(alignment:.leading,spacing:5) {
                Text(task.title).font(.callout.weight(.medium)).foregroundStyle(palette[.text].opacity(done ? 0.5 : 1)).fixedSize(horizontal:false,vertical:true)
                if hasMeta { meta }
            }
            Spacer(minLength:6)
            if !card {
                HStack(spacing:8) {
                    if showStage && !done { LabStagePill(task:task,store:store) }
                    if let due = task.due, !done { LabDueChip(due:due) }
                }
            }
        }
        .padding(card ? 10 : 7)
        .background(card ? palette[.input].opacity(0.6) : Color.clear,in:RoundedRectangle(cornerRadius:9))
        .contentShape(Rectangle())
        .contextMenu { ForEach(LifeTaskStage.allCases) { stage in Button(stage.rawValue) { store.setStage(task.id,stage) } } }
    }
    private var meta: some View {
        HStack(spacing:6) {
            if card, let due = task.due, !done { LabDueChip(due:due) }
            if let waiting = task.waiting, !done { LabChip(text:"Waiting on "+waiting,color:.purple) }
            if let tag { Label(tag,systemImage:"folder").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}
/// Inline add: type a task, optionally ending in a date, and press Return. Esc closes.
struct LabQuickAdd: View {
    let add: (String,Date?) -> Void
    let close: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        let parsed = LabDueParser.parse(text)
        HStack(spacing:8) {
            Image(systemName:"circle").foregroundStyle(palette[.text].opacity(0.3))
            TextField("Lab report fri",text:$text).textFieldStyle(.plain).focused($focused)
                .onSubmit(submit).onExitCommand(perform:close)
            if let due = parsed.due { LabDueChip(due:due) }
        }
        .padding(10).background(palette[.input],in:RoundedRectangle(cornerRadius:9))
        .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(palette[.accent].opacity(0.6)))
        .onAppear { focused = true }
        .help("End with a date if you like: today, tomorrow, fri, next week, in 3 days, 14 nov. Return adds, Esc closes.")
    }
    private func submit() {
        let parsed = LabDueParser.parse(text)
        guard !parsed.title.trimmingCharacters(in:.whitespaces).isEmpty else { return }
        add(parsed.title,parsed.due); text = ""; focused = true
    }
}
struct LabSection<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text(title).font(.headline); Spacer(); accessory }
            content
        }
    }
}
extension LabSection where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; accessory = EmptyView(); self.content = content() }
}
/// Breadcrumb plus the short progress bar for the open project.
struct LabHeader: View {
    let store: LabStore
    let current: UUID?
    var homeTitle = "Projects"
    let open: (UUID?) -> Void
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        ViewThatFits(in:.horizontal) {
            HStack(spacing:20) { crumbs; progress(144); Spacer(minLength:0) }
            VStack(alignment:.leading,spacing:10) { crumbs; progress(120) }
        }
    }
    @ViewBuilder private func progress(_ width: CGFloat) -> some View {
        if let current, store.tasks(under:current).count > 0 { LabProgressBar(counts:store.progress(current)).frame(width:width) }
    }
    private var crumbs: some View {
        HStack(spacing:8) {
            Button { open(nil) } label: {
                if current == nil { Label(homeTitle,systemImage:"folder").font(.title3.weight(.semibold)) } else { Image(systemName:"house").font(.callout) }
            }.buttonStyle(.plain).help(homeTitle)
            ForEach(store.path(current)) { item in
                Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary)
                Button(item.title) { open(item.id) }.buttonStyle(.plain).lineLimit(1)
                    .font(item.id == current ? .title3.weight(.semibold) : .callout)
                    .foregroundStyle(item.id == current ? palette[.text] : palette[.text].opacity(0.6))
            }
        }.fixedSize(horizontal:true,vertical:false)
    }
}
/// Notes as they are today: quiet cards below the work, side by side when there is room.
struct LabNotes: View {
    let notes: [LabNote]
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        if !notes.isEmpty {
            VStack(alignment:.leading,spacing:10) {
                Text("Notes").font(.headline)
                LazyVGrid(columns:[GridItem(.adaptive(minimum:220),spacing:12,alignment:.top)],alignment:.leading,spacing:12) {
                    ForEach(notes) { note in
                        VStack(alignment:.leading,spacing:6) {
                            Text(note.title).font(.callout.weight(.semibold))
                            Text(note.body).font(.callout).foregroundStyle(palette[.text].opacity(0.8)).lineLimit(6)
                        }.padding(14).frame(maxWidth:.infinity,minHeight:90,alignment:.topLeading)
                            .background(palette[.input].opacity(0.8),in:RoundedRectangle(cornerRadius:10))
                            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(palette[.border]))
                    }
                }
            }
        }
    }
}
/// Project-only deadlines: late, this week and next week, labelled with where each task lives.
struct LabDueSoonList: View {
    let store: LabStore
    let scope: UUID?
    var limit: Int? = nil
    @State private var showAll = false
    var body: some View {
        let open = store.open(under:scope).filter { $0.due.map { LabDue.days($0) < 14 } ?? false }
        let shown = showAll || limit == nil ? open : Array(open.prefix(limit!))
        VStack(alignment:.leading,spacing:14) {
            if open.isEmpty { Text("Nothing due in the next two weeks.").font(.callout).foregroundStyle(.secondary) }
            ForEach(LabStore.timeGroups(shown,horizon:14),id:\.title) { group in
                VStack(alignment:.leading,spacing:2) {
                    Text(group.title).font(.caption.weight(.semibold)).foregroundStyle(group.title == "Late" ? Color.red : Color.secondary).padding(.bottom,2)
                    ForEach(group.tasks) { task in LabTaskRow(task:task,store:store,tag:store.place(task,from:scope),card:false) }
                }
            }
            if let limit, open.count > limit {
                Button(showAll ? "Show fewer" : "Show \(open.count - limit) more") { showAll.toggle() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
struct LabDueSummary: View {
    let store: LabStore
    let scope: UUID?
    var body: some View {
        let open = store.open(under:scope).compactMap(\.due).map(LabDue.days)
        let late = open.filter { $0 < 0 }.count, week = open.filter { (0...6).contains($0) }.count
        HStack(spacing:10) {
            Text("Due soon").font(.headline)
            if late > 0 { LabChip(text:"\(late) late",color:.red) }
            LabChip(text:"\(week) this week",color:.orange)
        }
    }
}
struct LabProjectCard: View {
    let project: LabProject
    let store: LabStore
    var compact = false
    let open: () -> Void
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        let late = store.lateCount(project.id), subprojects = store.children(of:project.id).count
        Button(action:open) {
            VStack(alignment:.leading,spacing:compact ? 7 : 9) {
                HStack(alignment:.firstTextBaseline,spacing:8) {
                    Image(systemName:project.icon).foregroundStyle(palette[.accent])
                    Text(project.title).font(compact ? .callout.weight(.semibold) : .body.weight(.semibold)).lineLimit(2)
                    Spacer(minLength:4)
                    if late > 0 { Text("\(late) late").font(.caption.weight(.medium)).foregroundStyle(.red) }
                }
                LabProgressBar(counts:store.progress(project.id),height:compact ? 6 : 8)
                if let next = store.nextDue(project.id), let due = next.due {
                    HStack(spacing:6) { LabDueChip(due:due); Text(next.title).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                } else { Text("No deadlines").font(.caption).foregroundStyle(.tertiary) }
                if !compact && subprojects > 0 { Text(subprojects == 1 ? "1 subproject" : "\(subprojects) subprojects").font(.caption2).foregroundStyle(.secondary) }
            }
            .padding(compact ? 11 : 14).frame(maxWidth:.infinity,alignment:.topLeading)
            .background(palette[.input].opacity(0.6),in:RoundedRectangle(cornerRadius:12))
            .contentShape(RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain)
    }
}
struct LabCardGrid: View {
    let projects: [LabProject]
    let store: LabStore
    var minimum: CGFloat = 200
    var compact = false
    let open: (UUID) -> Void
    var body: some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:minimum),spacing:12,alignment:.top)],alignment:.leading,spacing:12) {
            ForEach(projects) { project in LabProjectCard(project:project,store:store,compact:compact) { open(project.id) } }
        }
    }
}
struct LabStageHeader: View {
    let stage: LifeTaskStage
    let count: Int
    let add: () -> Void
    var body: some View {
        HStack(spacing:7) {
            Circle().fill(stage.color).frame(width:7,height:7)
            Text(stage.rawValue).font(.caption.weight(.semibold))
            Text(String(count)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Spacer(minLength:4)
            Button(action:add) { Image(systemName:"plus").font(.system(size:12,weight:.medium)).frame(width:22,height:22).contentShape(Rectangle()) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Add a task to "+stage.rawValue).accessibilityLabel("Add task: "+stage.rawValue)
        }.padding(.horizontal,3)
    }
}
/// To do / In progress / Done, sorted by due date, with inline add and older Done folded away.
struct LabBoard: View {
    let store: LabStore
    let scope: UUID
    var deep = false
    let width: CGFloat
    @State private var adding: LifeTaskStage?
    @State private var allDone = false
    var body: some View {
        let count = width >= 600 ? 3 : width >= 400 ? 2 : 1
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10,alignment:.top),count:count),alignment:.leading,spacing:10) {
            ForEach(LifeTaskStage.allCases) { stage in column(stage) }
        }
    }
    private func column(_ stage: LifeTaskStage) -> some View {
        let all = store.tasks(under:scope,deep:deep).filter { $0.stage == stage }
        let sorted = stage == .done ? all.sorted { ($0.finished ?? .distantPast) > ($1.finished ?? .distantPast) } : all.sorted(by:LabStore.byDue)
        let shown = stage == .done && !allDone ? Array(sorted.prefix(3)) : sorted
        return VStack(alignment:.leading,spacing:8) {
            LabStageHeader(stage:stage,count:all.count) { adding = adding == stage ? nil : stage }
            if adding == stage { LabQuickAdd { title,due in store.add(title,due:due,project:scope,stage:stage) } close: { adding = nil } }
            ForEach(shown) { task in LabTaskRow(task:task,store:store,tag:deep ? store.place(task,from:scope) : nil) }
            if sorted.count > shown.count {
                Button("\(sorted.count - shown.count) earlier") { allDone = true }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(.leading,4)
            } else if stage == .done && allDone && sorted.count > 3 {
                Button("Show fewer") { allDone = false }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(.leading,4)
            }
        }
        .padding(9).frame(maxWidth:.infinity,minHeight:150,alignment:.topLeading)
        .background(stage.color.opacity(0.055),in:RoundedRectangle(cornerRadius:12))
    }
}
#endif
