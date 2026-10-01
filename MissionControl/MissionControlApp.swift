import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main struct MissionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = DashboardModel()
    var body: some Scene {
        Window("Mission Control", id: "dashboard") {
            DashboardView(model: model)
        }.defaultSize(width: 1200, height: 780)
        MenuBarExtra("Mission Control", systemImage: "square.grid.2x2") {
            MenuContent(model: model)
        }
        Settings { SettingsView() }
    }
}
struct MenuContent: View {
    var model: DashboardModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Button("Open dashboard") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "dashboard") }
        Button("Refresh") { model.refresh() }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Mission Control") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
