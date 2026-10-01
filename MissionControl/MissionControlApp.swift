import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--small-window") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let window = NSApp.windows.first(where: { $0.title == "Mission Control" }) else { return }
                if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    window.setContentSize(NSSize(width: 820, height: 640))
                }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main struct MissionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = DashboardModel()
    var body: some Scene {
        Window("Mission Control", id: "dashboard") {
            DashboardView(model: model)
        }.defaultSize(width: ProcessInfo.processInfo.arguments.contains("--small-window") ? 820 : 1200, height: ProcessInfo.processInfo.arguments.contains("--small-window") ? 640 : 780)
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
