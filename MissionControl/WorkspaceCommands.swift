import SwiftUI
import AppKit

// The active dashboard supplies its UI bindings; Settings/other windows cannot
// accidentally arrange a hidden page or present a form in the wrong window.
struct WorkspaceMenuActions {
    var sidebar: Binding<Bool>
    var editing: Binding<Bool>
    var newDashboard: () -> Void
    var addWidget: (WidgetKind) -> Void
    var customiseToolbar: () -> Void
    var customiseColors: () -> Void
}
private struct WorkspaceMenuKey: FocusedValueKey {
    typealias Value = WorkspaceMenuActions
}
extension FocusedValues {
    var workspaceMenu: WorkspaceMenuActions? {
        get { self[WorkspaceMenuKey.self] }
        set { self[WorkspaceMenuKey.self] = newValue }
    }
}
struct WorkspaceCommands: Commands {
    var model: DashboardModel
    @FocusedValue(\.workspaceMenu) private var workspace
    @Environment(\.openWindow) private var openWindow
    @AppStorage("workspaceTheme") private var theme = "warm"
    @AppStorage("workspaceAppearance") private var appearance = "system"
    @AppStorage("workspaceAccent") private var accent = "sage"
    var body: some Commands {
        CommandMenu("Dashboard") {
            Button("Open dashboard") { NSApp.activate(ignoringOtherApps:true); openWindow(id:"dashboard") }
            Button("New dashboard…") { workspace?.newDashboard() }.keyboardShortcut("n",modifiers:.command).disabled(workspace == nil)
            Menu("Add widget") {
                ForEach(WidgetKind.allCases,id:\.self) { kind in
                    Button(kind.title) { workspace?.addWidget(kind) }
                }
            }.disabled(workspace == nil || model.workspace.readOnly)
            Toggle("Edit layout",isOn:editing).disabled(workspace == nil || model.workspace.readOnly)
            Divider()
            Button("Refresh Apple sources") { model.refresh() }.keyboardShortcut("r",modifiers:.command)
        }
        CommandGroup(after:.undoRedo) {
            Button(model.undoLabel) { model.undoLatest() }
                .keyboardShortcut("z",modifiers:[.command,.option])
                .disabled(workspace == nil || model.latestUndo == nil || model.writing || model.assistant.busy)
        }
        CommandGroup(after:.sidebar) {
            Toggle("Show dashboard sidebar",isOn:sidebar).disabled(workspace == nil)
            Button("Show assistant") {
                model.assistant.openPA(); model.workspace.showAssistant()
                NSApp.activate(ignoringOtherApps:true); openWindow(id:"dashboard")
            }.keyboardShortcut("j",modifiers:.command)
        }
        CommandGroup(after:.toolbar) {
            Button("Customise dashboard toolbar…") { workspace?.customiseToolbar() }.disabled(workspace == nil)
            Menu("Dashboard appearance") {
                Picker("Style",selection:$theme) { Text("Warm workspace").tag("warm"); Text("Native macOS").tag("native") }
                Picker("Appearance",selection:$appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                Picker("Accent",selection:$accent) { Text("Sage").tag("sage"); Text("Blue").tag("blue"); Text("Rose").tag("rose") }
                Divider()
                Button("Customise colours…") { workspace?.customiseColors() }.disabled(workspace == nil)
            }
        }
    }
    private var sidebar: Binding<Bool> { workspace?.sidebar ?? .constant(false) }
    private var editing: Binding<Bool> { workspace?.editing ?? .constant(false) }
}
