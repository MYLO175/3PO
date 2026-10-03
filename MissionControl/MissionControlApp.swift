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
        .windowToolbarStyle(.unifiedCompact(showsTitle:false))
        .commands {
            WorkspaceCommands(model:model)
            #if DEBUG
            CommandGroup(after: .help) {
                Button("Run disposable Calendar check") { model.validateCalendarIntegration() }
                Button("Invalidate today's test briefing") { model.briefings.invalidateToday(model) }
                Button("Check proactive suggestions (fictional)") { model.validateProactivePrompt() }.keyboardShortcut("p",modifiers:[.command,.option,.shift])
                Button("Check Mail search folders") { model.validateMailFolders() }.keyboardShortcut("m",modifiers:[.command,.option,.shift])
                Button("Run disposable editor check") { let current = model; Task { guard !current.writing else { return }; current.writing = true; defer { current.writing = false; current.refresh(retryMail:false) }; do { current.validationReport = try await current.eventKit.validateNativeEditors() } catch { current.validationReport = error.localizedDescription } } }
                Button("Run disposable action check") { let current = model; Task { guard !current.writing else { return }; current.writing = true; defer { current.writing = false }; do { current.validationReport = try await current.eventKit.validateDisposableActions() } catch { current.validationReport = error.localizedDescription } } }
                Button("Check memory learning (fictional)") { model.validateMemoryLearning() }
                Button("Preview compact dashboard") { if let window = NSApp.windows.first(where:{ $0.isVisible && !$0.isFloatingPanel }) { window.setContentSize(NSSize(width:820,height:640)); window.center() } }
                Button("Restore dashboard window size") { if let window = NSApp.windows.first(where:{ $0.isVisible && !$0.isFloatingPanel }) { window.setContentSize(NSSize(width:1200,height:780)); window.center() } }
                Button("Check email triage (fictional)") { let current = model; Task { do { current.validationReport = try await current.emailSummaries.validateTriage(current) } catch { current.validationReport = error.localizedDescription } } }
                Button("Clean assistant action fixtures") { let current = model; Task { do { current.validationReport = try await current.assistantActions.cleanupFixtures(current) } catch { current.validationReport = error.localizedDescription } } }
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
