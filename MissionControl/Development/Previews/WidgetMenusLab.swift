#if DEBUG
import SwiftUI
import AppKit

/// Widgets without headers, to compare (`--preview-widget-menus`): each widget is only its content and
/// its options move into a right-click menu. Today's headers plus three designs, fictional data, nothing
/// saved. `--snapshot` writes every design to /tmp and quits.
struct WidgetMenusLab: View {
    @State private var lab = WidgetLabState()
    @State private var design = WidgetMenuDesign.bare
    @State private var dark = true
    var body: some View {
        WidgetMenusLabSurface(lab: lab, design: design, dark: dark)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Design", selection: $design) { ForEach(WidgetMenuDesign.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden()
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle(isOn: $lab.editing) { Label("Edit layout", systemImage: "square.grid.2x2") }.help("Edit layout: each widget shows its name while you arrange")
                    Toggle(isOn: $lab.problem) { Label("Source problem", systemImage: "exclamationmark.triangle") }.help("Pretend Calendar and Reminders couldn’t refresh")
                    Toggle(isOn: $lab.tip) { Label("First-run tip", systemImage: "lightbulb") }.help("Show the one-time tip that teaches right-click")
                    Toggle(isOn: $dark) { Label("Dark", systemImage: "moon") }.help("Dark or light")
                    Button { lab = WidgetLabState() } label: { Label("Reset sample", systemImage: "arrow.counterclockwise") }.help("Reset the sample")
                }
            }
            .frame(minWidth: 1240, minHeight: 780)
            .preferredColorScheme(dark ? .dark : .light)
            .task {
                guard ProcessInfo.processInfo.arguments.contains("--snapshot") else { return }
                await Self.render(); NSApp.terminate(nil)
            }
    }
}

enum WidgetMenuDesign: String, CaseIterable, Identifiable {
    case today, bare, hover, inline
    var id: String { rawValue }
    var title: String { switch self { case .today: "Today"; case .bare: "A · Just content"; case .hover: "B · Hover"; case .inline: "C · Inline" } }
    var summary: String {
        switch self {
        case .today: "Today’s headers for comparison: an icon, the name and the controls on every widget, plus a second control row on Calendar and Reminders."
        case .bare: "No header and no control rows. Every option, including New, Today and the view, is in the widget’s right-click menu. A dot appears only when a source has a problem; click it for details."
        case .hover: "Calm at rest, like A. Point at a widget and its one to three everyday buttons fade in at the top right, with ••• for the same menu as right-click."
        case .inline: "No header. The few controls you use daily sit in the content: the date line steers the calendar, New reminder sits under the list, the brief’s update time sits under the greeting and the new-chat button is in the message field. The rest is in right-click."
        }
    }
}

enum LabWidget: String, CaseIterable, Identifiable {
    case calendar, brief, reminders, chat
    var id: String { rawValue }
    var title: String { switch self { case .calendar: "Calendar"; case .brief: "Today’s brief"; case .reminders: "Reminders"; case .chat: "3PO" } }
    var symbol: String { switch self { case .calendar: "calendar"; case .brief: "sun.max"; case .reminders: "checklist"; case .chat: "sparkles" } }
    /// Calendar and Reminders read Apple sources, so they're the ones that can show a source problem.
    var hasSource: Bool { self == .calendar || self == .reminders }
}

/// Everything the lab's widgets and menus change; in memory only.
@Observable final class WidgetLabState {
    var calendarMode = "agenda"
    var date = Date.now
    var choosingDate = false
    var hiddenCalendars: Set<String> = []
    var grouping = "lists"
    var hiddenLists: Set<String> = []
    var collapsedLists: Set<String> = []
    var textSize = 14.0
    var showsWeather = true
    var focus: [LifeArea] = []
    var chat = WidgetLabFixtures.chat
    var draft = ""
    var editing = false
    var problem = false
    var tip = false
    let updated = Date.now.addingTimeInterval(-14 * 60)

    var days: [Date] {
        let calendar = Calendar.current, first = calendar.startOfDay(for: date)
        let count = switch calendarMode { case "day": 1; case "week": 7; case "month": calendar.range(of: .day, in: .month, for: date)?.count ?? 30; default: 7 }
        let start = calendarMode == "week" ? calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? first : calendarMode == "month" ? calendar.dateInterval(of: .month, for: date)?.start ?? first : first
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private var unit: (Calendar.Component, String) {
        switch calendarMode { case "week": (.weekOfYear, "week"); case "month": (.month, "month"); default: (.day, "day") }
    }
    func step(_ direction: Int) { date = Calendar.current.date(byAdding: unit.0, value: direction, to: date) ?? date }
    func stepTitle(_ direction: Int) -> String { (direction < 0 ? "Previous " : "Next ") + unit.1 }
    func expanded(_ list: String) -> Binding<Bool> {
        Binding(get: { !self.collapsedLists.contains(list) }, set: { if $0 { self.collapsedLists.remove(list) } else { self.collapsedLists.insert(list) } })
    }
    func health(_ widget: LabWidget) -> SourceHealth {
        SourceHealth(lastSuccess: updated, error: problem ? "\(widget.title) couldn’t refresh. This is pretend; nothing was asked of Apple." : nil)
    }
    func newChat() { chat = []; draft = "" }
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chat += [LabMessage(mine: true, text: text), LabMessage(mine: false, text: "This is a preview, so nothing is sent and I can’t look anything up.")]
        draft = ""
    }
}

/// The dashboard canvas and the caption under it; the snapshot renders this without the toolbar.
struct WidgetMenusLabSurface: View {
    @Bindable var lab: WidgetLabState
    var design: WidgetMenuDesign
    var dark: Bool
    var forceHover = false
    private var palette: WorkspacePalette {
        var overrides = WorkspaceColorOverrides(); overrides.profiles = WorkspaceColorTheme.threePO.profiles
        return .resolved(raw: overrides.encoded, mode: dark ? "dark" : "light", theme: "custom", accent: "sage")
    }
    var body: some View {
        let palette = palette
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                WorkspaceBackdropView(palette: palette)
                GeometryReader { geometry in
                    HStack(spacing: 14) {
                        tile(.calendar).frame(width: (geometry.size.width - 28) * 0.32)
                        VStack(spacing: 14) {
                            tile(.brief).frame(height: (geometry.size.height - 14) * 0.48)
                            tile(.reminders)
                        }
                        tile(.chat)
                    }
                }.padding(16)
                if lab.tip && design != .today { tip.padding(.bottom, 26).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(design.title).font(.callout.weight(.semibold))
                Text(design.summary).font(.callout).foregroundStyle(palette[.text].opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Text("Fictional data · nothing is saved").font(.caption).foregroundStyle(palette[.text].opacity(0.5))
            }.padding(.horizontal, 18).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).background(palette[.sidebar])
        }
        .environment(\.workspacePalette, palette)
        .foregroundStyle(palette[.text]).tint(palette[.accent])
        .background(palette[.sidebar])
        .toolbarBackground(palette[.sidebar], for: .windowToolbar)
        .animation(.smooth(duration: 0.25), value: lab.tip)
    }
    private func tile(_ widget: LabWidget) -> some View {
        LabTile(widget: widget, design: design, lab: lab, forceHover: forceHover)
    }
    private var tip: some View {
        HStack(spacing: 10) {
            Image(systemName: "cursorarrow.click.2").foregroundStyle(palette[.accent])
            Text("Right-click any widget for its options").font(.callout.weight(.medium))
            Button { lab.tip = false } label: { Image(systemName: "xmark").font(.caption.weight(.semibold)) }.buttonStyle(.borderless).help("Got it")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(palette[.border]))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }
}

/// One widget: its content, the design's controls, the right-click menu and Edit layout's name label.
struct LabTile: View {
    let widget: LabWidget
    let design: WidgetMenuDesign
    @Bindable var lab: WidgetLabState
    var forceHover = false
    @State private var hovering = false
    @Environment(\.workspacePalette) private var palette
    private var motion = MotionPreference()
    init(widget: LabWidget, design: WidgetMenuDesign, lab: WidgetLabState, forceHover: Bool = false) {
        self.widget = widget; self.design = design; self._lab = Bindable(lab); self.forceHover = forceHover
    }
    var body: some View {
        let showsBar = design == .hover && (hovering || forceHover) && !lab.editing
        VStack(alignment: .leading, spacing: 12) {
            if design == .today { LabTodayHeader(widget: widget, lab: lab) }
            LabWidgetContent(widget: widget, design: design, lab: lab)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(.system(size: 13))
        .contentShape(Rectangle())
        .labMenu(design != .today) { LabWidgetMenu(widget: widget, lab: lab) }
        .overlay(alignment: .topTrailing) {
            if showsBar { LabHoverBar(widget: widget, lab: lab).padding(10).transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing))) }
            else if design != .today, widget.hasSource, lab.problem {
                SourceStatusIndicator(title: widget.title, health: lab.health(widget)).padding(8)
            }
        }
        .overlay { if lab.editing { editLabel } }
        .workspaceSurface(palette, highlight: lab.editing ? palette[.accent].opacity(0.55) : nil)
        .onHover { inside in withAnimation(motion.animation(.easeOut(duration: 0.18))) { hovering = inside } }
    }
    /// While arranging, the name the header used to carry identifies the widget.
    private var editLabel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WorkspaceSurfaceModifier.radius, style: .continuous).fill(palette[.canvas].opacity(0.75))
            Label(widget.title, systemImage: widget.symbol).font(.headline)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(palette[.widget], in: Capsule())
                .overlay(Capsule().strokeBorder(palette[.border]))
        }.contentShape(Rectangle())
    }
}

extension View {
    /// The widget's options on right-click; today's design has no widget menu.
    @ViewBuilder func labMenu(_ enabled: Bool, @ViewBuilder items: () -> some View) -> some View {
        if enabled { contextMenu(menuItems: items) } else { self }
    }
}

/// B's floating buttons: the everyday few, then ••• for the full menu.
struct LabHoverBar: View {
    let widget: LabWidget
    @Bindable var lab: WidgetLabState
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        HStack(spacing: 12) {
            if widget.hasSource, lab.problem { SourceStatusIndicator(title: widget.title, health: lab.health(widget)) }
            switch widget {
            case .calendar:
                Button { lab.step(-1) } label: { Image(systemName: "chevron.left") }.help(lab.stepTitle(-1))
                Button("Today") { lab.date = .now }
                Button { lab.step(1) } label: { Image(systemName: "chevron.right") }.help(lab.stepTitle(1))
                Button {} label: { Image(systemName: "plus") }.help("New event")
            case .brief: Button {} label: { Image(systemName: "arrow.clockwise") }.help("Refresh today’s brief")
            case .reminders: Button {} label: { Image(systemName: "plus") }.help("New reminder")
            case .chat: Button { lab.newChat() } label: { Image(systemName: "square.and.pencil") }.help("New chat")
            }
            Menu { LabWidgetMenu(widget: widget, lab: lab) } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("\(widget.title) options")
        }
        .buttonStyle(.borderless).controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(palette[.border]))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

/// Each widget's right-click menu: what today's header and control rows hold, in one place. The menu's
/// first section is headed with the widget's name and when it last updated.
struct LabWidgetMenu: View {
    let widget: LabWidget
    @Bindable var lab: WidgetLabState
    private var time: String { lab.updated.formatted(date: .omitted, time: .shortened) }
    private var heading: String {
        if widget.hasSource, lab.problem { return widget.title + " · couldn’t refresh" }
        return widget.title + (widget == .chat ? " · heartbeat " : " · updated ") + time
    }
    var body: some View {
        switch widget {
        case .calendar:
            Section(heading) {
                Button("New event…", systemImage: "plus") {}
                if lab.problem { Button("Try again", systemImage: "arrow.clockwise") { lab.problem = false } }
            }
            Section {
                Button("Today") { lab.date = .now }
                Button(lab.stepTitle(-1)) { lab.step(-1) }
                Button(lab.stepTitle(1)) { lab.step(1) }
                Button("Go to date…") { lab.choosingDate = true }
            }
            Picker("View", selection: $lab.calendarMode) { Text("Agenda").tag("agenda"); Text("Day").tag("day"); Text("Week").tag("week"); Text("Month").tag("month") }
            Menu("Calendars") { LabCalendarToggles(lab: lab) }
            Divider()
            Button("Edit layout") { lab.editing = true }
        case .brief:
            Section(heading) {
                Button("Refresh brief", systemImage: "arrow.clockwise") {}
            }
            Picker("Text size", selection: $lab.textSize) { Text("Small").tag(12.0); Text("Default").tag(14.0); Text("Large").tag(16.0); Text("Larger").tag(18.0); Text("Largest").tag(21.0) }
            Toggle("Show weather", isOn: $lab.showsWeather)
            Divider()
            Button("Edit brief prompt…") {}
            Divider()
            Button("Edit layout") { lab.editing = true }
        case .reminders:
            Section(heading) {
                Button("New reminder…", systemImage: "plus") {}
                if lab.problem { Button("Try again", systemImage: "arrow.clockwise") { lab.problem = false } }
            }
            Picker("Group by", selection: $lab.grouping) { Text("Lists").tag("lists"); Text("Due date").tag("due") }
            Menu("Lists") { LabListToggles(lab: lab) }
            Divider()
            Button("Edit layout") { lab.editing = true }
        case .chat:
            Section(heading) {
                Button("New chat", systemImage: "square.and.pencil") { lab.newChat() }
                Button("Chat history…", systemImage: "clock.arrow.circlepath") {}
            }
            Menu("Focus: " + LifeFocusRules.label(lab.focus), systemImage: "scope") {
                Button("All areas") { lab.focus = [] }
                Divider()
                ForEach(LifeArea.allCases.filter { $0 != .unsorted }) { area in
                    Toggle(area.title, isOn: Binding(get: { lab.focus.contains(area) }, set: { enabled in
                        lab.focus = LifeFocusRules.normalised((enabled ? lab.focus + [area] : lab.focus.filter { $0 != area }).map(\.rawValue))
                    }))
                }
            }
            Button("Name your PA…") {}
            Button("Context…") {}
            Button("Set up my PA…") {}
            Text("Apple source context enabled")
            Divider()
            Button("Edit layout") { lab.editing = true }
        }
    }
}

/// Today's header and control rows, as the installed widgets draw them.
struct LabTodayHeader: View {
    let widget: LabWidget
    @Bindable var lab: WidgetLabState
    var body: some View {
        let time = lab.updated.formatted(date: .omitted, time: .shortened)
        switch widget {
        case .calendar:
            WidgetHeader(title: "Calendar", symbol: "calendar") {
                SourceStatusIndicator(title: "Calendar", health: lab.health(.calendar))
                Menu { LabCalendarToggles(lab: lab) } label: { Image(systemName: "line.3.horizontal.decrease") }.menuStyle(.borderlessButton).fixedSize().help("Filter calendars")
                Button {} label: { Image(systemName: "plus") }.help("New event")
                Picker("Calendar view", selection: $lab.calendarMode) { Text("Agenda").tag("agenda"); Text("Day").tag("day"); Text("Week").tag("week"); Text("Month").tag("month") }
                    .pickerStyle(.menu).labelsHidden().frame(width: 90)
            }.buttonStyle(.borderless).controlSize(.small)
        case .brief:
            WidgetHeader(title: "Today’s brief", symbol: "sun.max") {
                Text("Updated " + time).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Button {} label: { Image(systemName: "arrow.clockwise") }.help("Refresh today’s brief")
                Menu {
                    Toggle("Show weather", isOn: $lab.showsWeather)
                    Picker("Text size", selection: $lab.textSize) { Text("Small").tag(12.0); Text("Default").tag(14.0); Text("Large").tag(16.0); Text("Larger").tag(18.0); Text("Largest").tag(21.0) }
                    Divider()
                    Button("Edit brief prompt…") {}
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Brief options")
            }.buttonStyle(.borderless).controlSize(.small)
        case .reminders:
            WidgetHeader(title: "Reminders", symbol: "checklist") {
                SourceStatusIndicator(title: "Reminders", health: lab.health(.reminders))
                Button {} label: { Image(systemName: "plus") }.help("New reminder")
            }.buttonStyle(.borderless).controlSize(.small)
        case .chat:
            WidgetHeader(title: "3PO", symbol: "sparkles") {
                Text("Heartbeat " + time).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Button { lab.newChat() } label: { Image(systemName: "square.and.pencil") }.help("New chat")
                Menu {
                    Button("Chat history…", systemImage: "clock.arrow.circlepath") {}
                    Button("Name your PA…") {}
                    Button("Context…") {}
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("PA options")
            }.buttonStyle(.borderless).controlSize(.small)
        }
    }
}

extension WidgetMenusLab {
    /// Every design in both modes, plus B with its buttons showing, Edit layout and a source problem.
    @MainActor static func render() async {
        for design in WidgetMenuDesign.allCases {
            for dark in [true, false] { await shot(design: design, dark: dark, name: "\(design.rawValue)-\(dark ? "dark" : "light")") }
        }
        await shot(design: .hover, dark: true, hover: true, name: "hover-shown-dark")
        await shot(design: .bare, dark: true, configure: { $0.editing = true }, name: "edit-dark")
        await shot(design: .bare, dark: true, configure: { $0.problem = true; $0.tip = true }, name: "problem-tip-dark")
    }
    @MainActor private static func shot(design: WidgetMenuDesign, dark: Bool, hover: Bool = false, configure: (WidgetLabState) -> Void = { _ in }, name: String) async {
        let lab = WidgetLabState(); configure(lab)
        let hosting = NSHostingView(rootView: WidgetMenusLabSurface(lab: lab, design: design, dark: dark, forceHover: hover).frame(width: 1320, height: 820).environment(\.colorScheme, dark ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 820), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = hosting
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(700))
        hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
        if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: EvaluationOutput.url("/tmp/missioncontrol-widget-menus-" + name + ".png"), options: .atomic)
        }
        window.close()
    }
}
#endif
