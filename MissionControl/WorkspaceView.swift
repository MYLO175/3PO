import SwiftUI
import AppKit

struct WorkspaceView: View {
    @Bindable var model: DashboardModel
    @AppStorage("workspaceSidebar") private var sidebarVisible = true
    @AppStorage("workspaceTheme") private var theme = "warm"
    @AppStorage("workspaceAppearance") private var appearance = "system"
    @AppStorage("workspaceAccent") private var accent = "sage"
    @AppStorage("workspaceToolbarHidden") private var toolbarHidden = ""
    @Environment(\.colorScheme) private var scheme
    @State private var editing = false
    @State private var naming: UUID?
    @State private var name = ""
    @State private var showName = false
    @State private var legacy = false
    @State private var focusedWidgetID: UUID?
    private var store: WorkspaceStore { model.workspace }
    private var accentColor: Color { accent == "blue" ? .blue : accent == "rose" ? Color(red:0.69,green:0.36,blue:0.43) : (scheme == .dark ? Color(red:0.60,green:0.76,blue:0.64) : Color(red:0.32,green:0.48,blue:0.38)) }
    private var background: Color { theme == "native" ? Color(nsColor:.windowBackgroundColor) : scheme == .dark ? Color(red:0.12,green:0.13,blue:0.12) : Color(red:0.96,green:0.95,blue:0.92) }
    var body: some View {
        VStack(spacing:0) {
            header
            Divider()
            if let report = model.validationReport { HStack { Text(report).font(.caption).textSelection(.enabled); Spacer(); Button { model.validationReport = nil } label: { Image(systemName:"xmark") }.buttonStyle(.borderless).help("Dismiss validation result") }.padding(10) }
            if let error = store.error { HStack { Label(error,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange); Spacer(); if store.readOnly { Button("Original dashboard") { legacy = true } } else { Button("Dismiss") { store.error = nil } } }.padding(10) }
            if let error = model.storageError ?? model.writeError { Text(error).font(.caption).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading).padding(10) }
            HStack(spacing:0) {
                if sidebarVisible { sidebar.frame(width:170); Divider() }
                GeometryReader { geometry in
                    let width = max(1,geometry.size.width-32), height = max(1,geometry.size.height-32)
                    let rows = GridRules.rows(store.selected)
                    let metrics = WorkspaceGeometry(width:width,height:height,rows:rows)
                    if store.selected.widgets.isEmpty {
                        VStack(spacing:14) { Image(systemName:"square.grid.2x2").font(.largeTitle).foregroundStyle(accentColor); Text("Make this dashboard yours").font(.title2.weight(.semibold)); Text("Add a widget, then move and resize it in Edit mode.").foregroundStyle(.secondary); addMenu }.frame(maxWidth:.infinity,maxHeight:.infinity)
                    } else if width < 900 && !editing && store.selected.widgets.count > 1 {
                        VStack(spacing:10) {
                            HStack {
                                Text("Focused view").font(.caption).foregroundStyle(.secondary)
                                Picker("Widget",selection:Binding(get:{ store.selected.widgets.first(where:{ $0.id == focusedWidgetID })?.id ?? store.selected.widgets.first!.id },set:{ focusedWidgetID = $0 })) {
                                    ForEach(Array(store.selected.widgets.enumerated()),id:\.element.id) { index,widget in Text("\(widget.kind?.title ?? "Widget") \(index+1)").tag(widget.id) }
                                }.labelsHidden()
                                Spacer()
                            }
                            if let widget = store.selected.widgets.first(where:{ $0.id == focusedWidgetID }) ?? store.selected.widgets.first {
                                WorkspaceTile(model:model,store:store,widget:widgetBinding(widget),editing:false,metrics:WorkspaceGeometry(width:width,height:max(1,height-38),rows:rows),focused:true)
                            }
                        }.padding(16)
                    } else {
                        ZStack(alignment:.topLeading) {
                            if editing { Canvas { context,size in
                                for x in 0..<12 { for y in 0..<rows { context.fill(Path(ellipseIn:CGRect(x:Double(x)*metrics.xStep,y:Double(y)*metrics.yStep,width:3,height:3)),with:.color(.secondary.opacity(0.2))) } }
                            }.allowsHitTesting(false) }
                            ForEach(store.selected.widgets) { widget in
                                WorkspaceTile(model:model,store:store,widget:widgetBinding(widget),editing:editing,metrics:metrics)
                            }
                        }.frame(width:width,height:height,alignment:.topLeading).coordinateSpace(name:"workspaceGrid").padding(16)
                    }
                }.clipped()

            }
        }.background(background).tint(accentColor).frame(minWidth:780,minHeight:580)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
            .task { model.start() }
            .onChange(of:store.selected.id) { focusedWidgetID = nil }
            .sheet(isPresented:$showName) { VStack(alignment:.leading,spacing:16) { Text(naming == nil ? "New dashboard" : "Rename dashboard").font(.title2.weight(.semibold)); TextField("Name",text:$name).onSubmit { saveName() }; HStack { Spacer(); Button("Cancel") { showName = false }.keyboardShortcut(.cancelAction); Button("Save") { saveName() }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) } }.padding(24).frame(width:360) }
            .sheet(item:$model.selectedMessage) { DashboardView(model:model).previewSheet($0) }
            .sheet(item:$model.editTarget) { NativeItemEditor(model:model,target:$0) }
            .sheet(isPresented:$legacy) { DashboardView(model:model).frame(width:1150,height:750) }
    }
    private var header: some View {
        HStack(spacing:8) {
            Button { sidebarVisible.toggle() } label: { Image(systemName:"sidebar.left") }.buttonStyle(.borderless).help("Show dashboard pages")
            Text(store.selected.title).font(.system(size:17,weight:.semibold,design:.rounded)).lineLimit(1).frame(maxWidth:170,alignment:.leading)
            if visible(.date) { TimelineView(.periodic(from:.now,by:60)) { context in Text(context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }
            Spacer(minLength:4)
            TimelineView(.periodic(from:.now,by:1)) { context in
                if let notice = model.nativeWriteNotice, let date = model.feedbackDate, context.date.timeIntervalSince(date) < 8 {
                    Label(notice,systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(.green).lineLimit(1).frame(maxWidth:210).help(notice).padding(.horizontal,8).padding(.vertical,5).background(.green.opacity(0.07),in:Capsule())
                }
            }.layoutPriority(-1)
            ViewThatFits(in:.horizontal) {
                HStack(spacing:6) { toolbarActions(labels:true) }
                HStack(spacing:5) { toolbarActions(labels:false) }
            }
            Menu {
                Section("Show in toolbar") { ForEach(WorkspaceTool.allCases,id:\.self) { tool in Toggle(tool.title,isOn:Binding(get:{ visible(tool) },set:{ toolbarHidden = ToolbarRules.setting(tool,visible:$0,hidden:toolbarHidden) })) }; Button("Reset toolbar") { toolbarHidden = "" } }
                Section("Actions") {
                    Button("Assistant") { model.assistant.openPA(); store.showAssistant() }.keyboardShortcut("j",modifiers:.command)
                    Button("Refresh") { model.refresh() }.keyboardShortcut("r",modifiers:.command)
                    Menu("Add widget") { widgetChoices }
                    Toggle("Edit layout",isOn:$editing)
                    Button(model.undoLabel) { model.undoLatest() }.disabled(model.latestUndo == nil || model.writing || model.assistant.busy)
                }
            } label: { Image(systemName:"slider.horizontal.3") }.help("Customise toolbar").accessibilityLabel("Customise toolbar")
            SettingsLink { Image(systemName:"gearshape") }.buttonStyle(.borderless).help("Settings")
        }.controlSize(.small).padding(.horizontal,16).frame(height:44)
    }
    private func visible(_ tool: WorkspaceTool) -> Bool { ToolbarRules.visible(tool,hidden:toolbarHidden) }
    @ViewBuilder private func toolbarActions(labels: Bool) -> some View {
        if visible(.assistant) { Button { model.assistant.openPA(); store.showAssistant() } label: { if labels { Label("Assistant",systemImage:"bubble.left.and.bubble.right") } else { Image(systemName:"bubble.left.and.bubble.right") } }.help("Assistant (⌘J)").accessibilityLabel("Assistant") }
        if visible(.refresh) { Button { model.refresh() } label: { Image(systemName:"arrow.clockwise") }.help("Refresh Apple sources (⌘R)").accessibilityLabel("Refresh Apple sources") }
        if visible(.addWidget) { Menu { widgetChoices } label: { if labels { Label("Add widget",systemImage:"plus") } else { Image(systemName:"plus") } }.accessibilityLabel("Add widget") }
        if visible(.edit) { Button { editing.toggle() } label: { if labels { Text(editing ? "Done" : "Edit") } else { Image(systemName:editing ? "checkmark" : "slider.horizontal.3") } }.help("Arrange widgets · Drag handle/corner, release to snap").accessibilityLabel(editing ? "Finish arranging widgets" : "Edit layout").tint(editing ? .accentColor : nil) }
        if visible(.undo) { Button { model.undoLatest() } label: { Image(systemName:"arrow.uturn.backward") }.disabled(model.latestUndo == nil || model.writing || model.assistant.busy).help(model.undoLabel).accessibilityLabel(model.undoLabel) }
        if visible(.appearance) { Menu {
                Picker("Style",selection:$theme) { Text("Warm workspace").tag("warm"); Text("Native macOS").tag("native") }
                Picker("Appearance",selection:$appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                Picker("Accent",selection:$accent) { Text("Sage").tag("sage"); Text("Blue").tag("blue"); Text("Rose").tag("rose") }
            } label: { Image(systemName:"paintpalette") }.help("Workspace appearance").accessibilityLabel("Workspace appearance") }
    }
    private var widgetChoices: some View { ForEach(WidgetKind.allCases,id:\.self) { kind in Button { store.addWidget(kind); editing = true } label: { Label(kind.title,systemImage:kind.icon) } } }
    private var addMenu: some View {
        Menu { widgetChoices } label: { Label("Add widget",systemImage:"plus") }
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
    var editing: Bool
    var metrics: WorkspaceGeometry
    var focused = false
    @State private var interaction: Interaction?
    @State private var readingMode = false
    private struct Interaction { var origin: GridRect; var translation: CGSize; var resizing: Bool }
    private var baseRect: GridRect { focused ? GridRect(x:0,y:0,w:12,h:metrics.rows) : widget.rect }
    private var baseFrame: CGRect { metrics.frame(baseRect) }
    private var target: GridRect {
        guard let interaction else { return baseRect }
        return metrics.target(origin:interaction.origin,dx:interaction.translation.width,dy:interaction.translation.height,resizing:interaction.resizing,minimumColumns:widget.kind?.minimumColumns ?? 3,minimumRows:widget.kind?.minimumRows ?? 4)
    }
    private var visual: CGRect {
        guard let interaction else { return baseFrame }
        return metrics.preview(origin:interaction.origin,dx:interaction.translation.width,dy:interaction.translation.height,resizing:interaction.resizing,minimumColumns:widget.kind?.minimumColumns ?? 3,minimumRows:widget.kind?.minimumRows ?? 4)
    }
    private var valid: Bool { GridRules.valid(target,among:store.selected.widgets,excluding:widget.id,rowLimit:metrics.rows) }
    private var configuration: Binding<WidgetConfiguration> { Binding(get:{ widget.configuration },set:{ widget.configuration = $0 }) }
    var body: some View {
        ZStack(alignment:.topLeading) {
            if interaction != nil {
                let destination = metrics.frame(target)
                RoundedRectangle(cornerRadius:16).fill((valid ? Color.accentColor : .red).opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius:16).stroke(valid ? Color.accentColor : .red,style:StrokeStyle(lineWidth:2,dash:[6,4])))
                    .frame(width:destination.width,height:destination.height).offset(x:destination.minX,y:destination.minY).allowsHitTesting(false)
            }
            VStack(spacing:0) {
                if editing {
                    HStack {
                        HStack { Image(systemName:"line.3.horizontal"); Text(widget.kind?.title ?? "Unavailable widget").font(.caption.weight(.semibold)); Spacer() }.contentShape(Rectangle()).gesture(gesture(resizing:false))
                        Menu {
                            Button("Fill page") { store.fullPage(widget) }
                            Button("Move right") { adjust(x:1) }; Button("Move left") { adjust(x:-1) }; Button("Move down") { adjust(y:1) }; Button("Move up") { adjust(y:-1) }
                            Button("Wider") { adjust(w:1) }; Button("Narrower") { adjust(w:-1) }; Button("Taller") { adjust(h:1) }; Button("Shorter") { adjust(h:-1) }
                            Divider(); Button("Remove widget") { store.removeWidget(widget.id) }
                        } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).frame(width:20).accessibilityLabel("\(widget.kind?.title ?? "Widget") layout actions")
                    }.padding(.horizontal,12).frame(height:34).background(Color.accentColor.opacity(0.08))
                }
                content.allowsHitTesting(!editing).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
            // Keep content at its committed size during the gesture; only the preview shell follows the pointer.
            .frame(width:baseFrame.width,height:baseFrame.height,alignment:.topLeading)
            .frame(width:visual.width,height:visual.height,alignment:.topLeading)
            .background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:16))
            .clipShape(RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).stroke(editing ? (valid ? Color.accentColor.opacity(0.6) : .red) : Color.primary.opacity(0.06),lineWidth:editing ? 2 : 1))
            .overlay(alignment:.bottomTrailing) { if editing { Image(systemName:"arrow.down.right.and.arrow.up.left").font(.caption.weight(.bold)).padding(9).background(.regularMaterial,in:RoundedRectangle(cornerRadius:7)).contentShape(Rectangle()).gesture(gesture(resizing:true)).accessibilityLabel("Resize \(widget.kind?.title ?? "widget")") } }
            .shadow(color:.black.opacity(interaction == nil ? 0.025 : 0.12),radius:interaction == nil ? 8 : 14,y:3)
            .offset(x:visual.minX,y:visual.minY)
        }.frame(width:metrics.width,height:metrics.height,alignment:.topLeading).zIndex(interaction == nil ? 0 : 1)
            .onChange(of:editing) { interaction = nil }
            .onChange(of:metrics.width) { interaction = nil }
            .onChange(of:metrics.height) { interaction = nil }
    }
    @ViewBuilder private var content: some View {
        switch widget.kind {
        case .calendar: CalendarWidgetView(model:model,configuration:configuration)
        case .reminders: DashboardView(model:model,widgetConfiguration:configuration).remindersPanel
        case .mail: DashboardView(model:model,widgetConfiguration:configuration).inboxPanel
        case .conversation: AssistantPanel(model:model,assistant:model.assistant,readingMode:$readingMode,supportsReadingMode:false,widgetID:widget.id,configuration:configuration)
        case .overview:
            TodayBriefView(model:model,briefings:model.briefings).padding(16)
        case .emailSummary: EmailOverviewView(model:model,summaries:model.emailSummaries,configuration:configuration).padding(16)
        case .clock: DateClockWidget(configuration:configuration)
        case nil: ContentUnavailableView("Widget unavailable",systemImage:"square.dashed",description:Text("Its saved placement is preserved for a future app version."))
        }
    }
    private func gesture(resizing: Bool) -> some Gesture {
        DragGesture(minimumDistance:3,coordinateSpace:.named("workspaceGrid"))
            .onChanged { value in
                if interaction == nil { interaction = Interaction(origin:widget.rect,translation:.zero,resizing:resizing) }
                interaction?.translation = value.translation
            }
            .onEnded { _ in
                let destination = target
                withAnimation(.snappy(duration:0.18)) {
                    if valid && destination != widget.rect { var next = widget; next.rect = destination; store.update(next) }
                    interaction = nil
                }
            }
    }
    private func adjust(x: Int = 0,y: Int = 0,w: Int = 0,h: Int = 0) { var next = widget; next.rect.x += x; next.rect.y += y; next.rect.w = max(widget.kind?.minimumColumns ?? 3,next.rect.w+w); next.rect.h = max(widget.kind?.minimumRows ?? 4,next.rect.h+h); store.update(next) }
}
