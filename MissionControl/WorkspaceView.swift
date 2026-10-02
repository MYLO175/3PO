import SwiftUI
import AppKit

struct WorkspaceView: View {
    @Bindable var model: DashboardModel
    @AppStorage("workspaceSidebar") private var sidebarVisible = true
    @AppStorage("workspaceTheme") private var theme = "warm"
    @AppStorage("workspaceAppearance") private var appearance = "system"
    @AppStorage("workspaceAccent") private var accent = "sage"
    @Environment(\.colorScheme) private var scheme
    @State private var editing = false
    @State private var naming: UUID?
    @State private var name = ""
    @State private var showName = false
    @State private var legacy = false
    private var store: WorkspaceStore { model.workspace }
    private var accentColor: Color { accent == "blue" ? .blue : accent == "rose" ? Color(red:0.69,green:0.36,blue:0.43) : (scheme == .dark ? Color(red:0.60,green:0.76,blue:0.64) : Color(red:0.32,green:0.48,blue:0.38)) }
    private var background: Color { theme == "native" ? Color(nsColor:.windowBackgroundColor) : scheme == .dark ? Color(red:0.12,green:0.13,blue:0.12) : Color(red:0.96,green:0.95,blue:0.92) }
    var body: some View {
        VStack(spacing:0) {
            header
            Divider()
            if let report = model.validationReport { HStack { Text(report).font(.caption).textSelection(.enabled); Spacer(); Button { model.validationReport = nil } label: { Image(systemName:"xmark") }.buttonStyle(.borderless).help("Dismiss validation result") }.padding(10) }
            if let error = store.error { HStack { Label(error,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange); Spacer(); Button("Original dashboard") { legacy = true } }.padding(10) }
            if let error = model.storageError ?? model.writeError { Text(error).font(.caption).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading).padding(10) }
            if model.undoToken != nil {
                HStack { Label("Completed: \(model.undoTitle)",systemImage:"checkmark.circle"); Spacer(); Button("Undo reminder") { model.undo() }.disabled(model.writing) }.font(.callout).padding(10).background(.green.opacity(0.06))
            }
            HStack(spacing:0) {
                if sidebarVisible { sidebar.frame(width:170); Divider() }
                GeometryReader { geometry in
                    let width = max(1040,geometry.size.width-32), rows = max(8,Int((geometry.size.height-32)/76))
                    ScrollView([.horizontal,.vertical]) {
                        if store.selected.widgets.isEmpty {
                            VStack(spacing:14) { Image(systemName:"square.grid.2x2").font(.largeTitle).foregroundStyle(accentColor); Text("Make this dashboard yours").font(.title2.weight(.semibold)); Text("Add a widget, then move and resize it in Edit mode.").foregroundStyle(.secondary); addMenu }.frame(width:width,height:max(400,geometry.size.height-32))
                        } else {
                            ZStack(alignment:.topLeading) {
                                if editing { Canvas { context,size in
                                    let cell = (width-132)/12
                                    for x in 0..<12 { for y in 0..<Int(size.height/76) { context.fill(Path(ellipseIn:CGRect(x:Double(x)*(cell+12),y:Double(y)*76,width:3,height:3)),with:.color(.secondary.opacity(0.2))) } }
                                } }
                                ForEach(store.selected.widgets) { widget in
                                    WorkspaceTile(model:model,store:store,widget:widgetBinding(widget),editing:editing,canvasWidth:width,fillRows:rows)
                                }
                            }.frame(width:width,height:max(geometry.size.height-32,Double(store.selected.widgets.map { $0.rect.y+$0.rect.h }.max() ?? 8)*76-12),alignment:.topLeading)
                                .coordinateSpace(name:"workspaceGrid")
                        }
                    }.padding(16)
                }
            }
            HStack { Text(editing ? "Drag a widget's handle to move it · Drag its corner to resize · Overlap is prevented" : "Apple apps stay the source of truth"); Spacer(); if ProcessInfo.processInfo.arguments.contains("--sample") { Text("Sample data") } }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,18).padding(.vertical,9)
        }.background(background).tint(accentColor).frame(minWidth:780,minHeight:580)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
            .task { model.start() }
            .sheet(isPresented:$showName) { VStack(alignment:.leading,spacing:16) { Text(naming == nil ? "New dashboard" : "Rename dashboard").font(.title2.weight(.semibold)); TextField("Name",text:$name).onSubmit { saveName() }; HStack { Spacer(); Button("Cancel") { showName = false }.keyboardShortcut(.cancelAction); Button("Save") { saveName() }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) } }.padding(24).frame(width:360) }
            .sheet(item:$model.selectedMessage) { DashboardView(model:model).previewSheet($0) }
            .sheet(isPresented:$legacy) { DashboardView(model:model).frame(width:1150,height:750) }
    }
    private var header: some View {
        HStack(spacing:12) {
            Button { sidebarVisible.toggle() } label: { Image(systemName:"sidebar.left") }.buttonStyle(.borderless).help("Show dashboard pages")
            VStack(alignment:.leading,spacing:3) { Text(store.selected.title).font(.system(size:23,weight:.semibold,design:.rounded)); Text(Date.now.formatted(date:.complete,time:.omitted)).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button { model.assistant.openPA(); store.showAssistant() } label: { Label("Assistant",systemImage:"bubble.left.and.bubble.right") }.keyboardShortcut("j",modifiers:.command)
            Button { model.refresh() } label: { Image(systemName:"arrow.clockwise") }.help("Refresh Apple sources (⌘R)").accessibilityLabel("Refresh Apple sources").keyboardShortcut("r",modifiers:.command)
            addMenu
            Toggle("Edit",isOn:$editing).toggleStyle(.button)
            if store.canUndo { Button { store.undo() } label: { Image(systemName:"arrow.uturn.backward") }.help("Undo last workspace change").accessibilityLabel("Undo workspace change") }
            Menu {
                Picker("Style",selection:$theme) { Text("Warm workspace").tag("warm"); Text("Native macOS").tag("native") }
                Picker("Appearance",selection:$appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                Picker("Accent",selection:$accent) { Text("Sage").tag("sage"); Text("Blue").tag("blue"); Text("Rose").tag("rose") }
            } label: { Image(systemName:"paintpalette") }.help("Workspace appearance").accessibilityLabel("Workspace appearance")
            SettingsLink { Image(systemName:"gearshape") }.buttonStyle(.borderless).help("Settings")
        }.padding(.horizontal,20).padding(.vertical,17)
    }
    private var addMenu: some View {
        Menu { ForEach(WidgetKind.allCases,id:\.self) { kind in Button { store.addWidget(kind); editing = true } label: { Label(kind.title,systemImage:kind.icon) } } } label: { Label("Add widget",systemImage:"plus") }
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("MISSION CONTROL").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary).padding(.top,8)
            ScrollView {
                VStack(spacing:5) {
                    ForEach(store.state.pages) { page in
                        Button { store.select(page.id) } label: { HStack(spacing:8) { Image(systemName:page.widgets.count == 1 ? page.widgets[0].kind?.icon ?? "square" : "square.grid.2x2"); Text(page.title).lineLimit(1); Spacer(minLength:0) }.font(.callout).padding(10).frame(maxWidth:.infinity,alignment:.leading).background(page.id == store.selected.id ? accentColor.opacity(0.12) : Color.clear,in:RoundedRectangle(cornerRadius:9)) }.buttonStyle(.plain)
                            .contextMenu { Button("Rename") { naming = page.id; name = page.title; showName = true }; Button("Duplicate") { store.duplicate(page.id) }; Button("Move up") { store.movePage(page.id,offset:-1) }; Button("Move down") { store.movePage(page.id,offset:1) }; Divider(); Button("Remove dashboard") { store.removePage(page.id) }.disabled(store.state.pages.count == 1) }
                    }
                }
            }
            Button { naming = nil; name = "New dashboard"; showName = true } label: { Label("New dashboard",systemImage:"plus") }.buttonStyle(.borderless)
            Text("Each page is yours to arrange.").font(.caption).foregroundStyle(.secondary)
        }.padding(12)
    }
    private func saveName() { if let naming { store.rename(naming,title:name) } else { store.addPage(name) }; showName = false }
    private func widgetBinding(_ original: WidgetPlacement) -> Binding<WidgetPlacement> { Binding(get:{ store.selected.widgets.first { $0.id == original.id } ?? original },set:{ store.update($0) }) }
}
private struct WorkspaceTile: View {
    @Bindable var model: DashboardModel
    @Bindable var store: WorkspaceStore
    @Binding var widget: WidgetPlacement
    var editing: Bool; var canvasWidth: Double; var fillRows: Int
    @State private var proposal: GridRect?
    @State private var readingMode = false
    private var rect: GridRect { proposal ?? widget.rect }
    private var cell: Double { (canvasWidth-132)/12 }
    private var valid: Bool { GridRules.valid(rect,among:store.selected.widgets,excluding:widget.id) }
    private var configuration: Binding<WidgetConfiguration> { Binding(get:{ widget.configuration },set:{ widget.configuration = $0 }) }
    var body: some View {
        VStack(spacing:0) {
            if editing {
                HStack {
                    HStack { Image(systemName:"line.3.horizontal"); Text(widget.kind?.title ?? "Unavailable widget").font(.caption.weight(.semibold)); Spacer() }.contentShape(Rectangle()).gesture(moveGesture)
                    Menu {
                        Button("Fill page") { store.fullPage(widget,rows:fillRows) }
                        Button("Move right") { adjust(x:1) }; Button("Move left") { adjust(x:-1) }; Button("Move down") { adjust(y:1) }; Button("Move up") { adjust(y:-1) }
                        Button("Wider") { adjust(w:1) }; Button("Narrower") { adjust(w:-1) }; Button("Taller") { adjust(h:1) }; Button("Shorter") { adjust(h:-1) }
                        Divider(); Button("Remove widget") { store.removeWidget(widget.id) }
                    } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).frame(width:20).accessibilityLabel("\(widget.kind?.title ?? "Widget") layout actions")
                }.padding(.horizontal,12).frame(height:34).background(Color.accentColor.opacity(0.08))
            }
            content.allowsHitTesting(!editing).frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(width:Double(rect.w)*cell+Double(rect.w-1)*12,height:Double(rect.h)*64+Double(rect.h-1)*12)
            .background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:16))
            .clipShape(RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).stroke(editing ? (valid ? Color.accentColor.opacity(0.6) : .red) : Color.primary.opacity(0.06),lineWidth:editing ? 2 : 1))
            .overlay(alignment:.bottomTrailing) { if editing { Image(systemName:"arrow.down.right.and.arrow.up.left").font(.caption.weight(.bold)).padding(9).background(.regularMaterial,in:RoundedRectangle(cornerRadius:7)).contentShape(Rectangle()).gesture(resizeGesture).accessibilityLabel("Resize \(widget.kind?.title ?? "widget")") } }
            .shadow(color:.black.opacity(0.025),radius:8,y:3)
            .offset(x:Double(rect.x)*(cell+12),y:Double(rect.y)*76)
    }
    @ViewBuilder private var content: some View {
        switch widget.kind {
        case .calendar: CalendarWidgetView(model:model,configuration:configuration)
        case .reminders: DashboardView(model:model,widgetConfiguration:configuration).remindersPanel
        case .mail: DashboardView(model:model,widgetConfiguration:configuration).inboxPanel
        case .conversation: AssistantPanel(model:model,assistant:model.assistant,readingMode:$readingMode,supportsReadingMode:false)
        case .overview:
            VStack(alignment:.leading,spacing:10) { GeneralOverviewView(model:model,briefings:model.briefings); BriefingView(model:model,briefings:model.briefings); DisclosureGroup("Email follow-ups") { EmailOverviewView(model:model,summaries:model.emailSummaries).frame(maxHeight:220) } }.padding(16)
        case nil: ContentUnavailableView("Widget unavailable",systemImage:"square.dashed",description:Text("Its saved placement is preserved for a future app version."))
        }
    }
    private var moveGesture: some Gesture { DragGesture(minimumDistance:3).onChanged { value in var next = widget.rect; next.x = max(0,min(12-next.w,next.x+Int((value.translation.width/(cell+12)).rounded()))); next.y = max(0,next.y+Int((value.translation.height/76).rounded())); proposal = next }.onEnded { _ in commit() } }
    private var resizeGesture: some Gesture { DragGesture(minimumDistance:3).onChanged { value in var next = widget.rect; next.w = max(widget.kind?.minimumColumns ?? 3,min(12-next.x,next.w+Int((value.translation.width/(cell+12)).rounded()))); next.h = max(widget.kind?.minimumRows ?? 4,next.h+Int((value.translation.height/76).rounded())); proposal = next }.onEnded { _ in commit() } }
    private func commit() { if let proposal, valid { var next = widget; next.rect = proposal; store.update(next) }; proposal = nil }
    private func adjust(x: Int = 0,y: Int = 0,w: Int = 0,h: Int = 0) { var next = widget; next.rect.x += x; next.rect.y += y; next.rect.w = max(widget.kind?.minimumColumns ?? 3,next.rect.w+w); next.rect.h = max(widget.kind?.minimumRows ?? 4,next.rect.h+h); store.update(next) }
}
