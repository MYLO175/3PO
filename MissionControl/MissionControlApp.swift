import SwiftUI
import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--small-window") || arguments.contains("--dark-window") else { return }
        // SwiftUI may restore a fullscreen window after didFinishLaunching.
        // Retry after restoration and identify the dashboard without relying on
        // its title (which can be empty while fullscreen).
        for attempt in 1...4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt)) {
                guard let window = NSApp.windows.first(where: { $0.isVisible && !$0.isFloatingPanel }) else { return }
                if arguments.contains("--dark-window") { window.appearance = NSAppearance(named: .darkAqua) }
                if arguments.contains("--small-window") {
                    if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
                    else { window.setContentSize(NSSize(width: 820, height: 640)); window.center() }
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
            WorkspaceView(model: model)
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark-window") ? .dark : nil)
        }.defaultSize(width: ProcessInfo.processInfo.arguments.contains("--small-window") ? 820 : 1200, height: ProcessInfo.processInfo.arguments.contains("--small-window") ? 640 : 780)
        .commands {
            #if DEBUG
            CommandGroup(after: .help) {
                Button("Run disposable Calendar check") { model.validateCalendarIntegration() }
                Button("Invalidate today's test briefing") { model.briefings.invalidateToday(model) }
                Button("Run disposable action check") { Task { guard !model.writing else { return }; model.writing = true; defer { model.writing = false }; do { model.validationReport = try await model.eventKit.validateDisposableActions() } catch { model.validationReport = error.localizedDescription } } }
                Button("Check memory learning (fictional)") { model.validateMemoryLearning() }
                Button("Check email triage (fictional)") { Task { do { model.validationReport = try await model.emailSummaries.validateTriage(model) } catch { model.validationReport = error.localizedDescription } } }
                Button("Clean assistant action fixtures") { Task { do { model.validationReport = try await model.assistantActions.cleanupFixtures(model) } catch { model.validationReport = error.localizedDescription } } }
            }
            #endif
        }
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("Mission Control")
        }
        Settings { SettingsView(model: model) }
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
