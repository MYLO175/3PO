#if DEBUG
import SwiftUI
import AppKit

/// Settings opened on its Context page for a fictional account. Pages, projects and
/// memories go to the disposable in-memory store; sources, helpers and AI never start.
struct SettingsContextPreview: View {
    var model: DashboardModel
    @State private var ready = false
    var body: some View {
        Group {
            if ready { SettingsView(model: model) } else { ProgressView() }
        }.task {
            guard !ready else { return }
            Self.prepare(model)
            ready = true
        }
    }
    @MainActor private static var prepared = false
    @MainActor private static func prepare(_ model: DashboardModel) {
        guard !prepared else { return }; prepared = true
        model.inference.useChatGPTForFictionalEvaluation()
        model.chatGPT.activeID = "fictional-settings-preview"
        try? MemoryInspectionPreview.seedContextPages(model)
        UserDefaults.standard.set("Context", forKey: "settingsSelectedPage")
    }
    /// `--snapshot`: draws Settings at two sizes into PNGs in an offscreen window, as
    /// LifeProjectPreview does, so it works without the preview window mounting.
    @MainActor static func render(_ model: DashboardModel) async {
        prepare(model)
        var report: [String] = []
        for (name, size, page) in [("regular", NSSize(width: 900, height: 700), "Context"), ("minimum", NSSize(width: 760, height: 620), "Context"), ("learning", NSSize(width: 900, height: 700), "Memory")] {
            UserDefaults.standard.set(page, forKey: "settingsSelectedPage")
            let hosting = NSHostingView(rootView: SettingsView(model: model).background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = hosting
            window.appearance = NSAppearance(named: .darkAqua)
            window.orderFront(nil)
            try? await Task.sleep(for: .milliseconds(800))
            hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
            report.append("\(name): requested \(size), window content \(window.contentLayoutRect.size), content minimum \(window.contentMinSize), fitting \(hosting.fittingSize)")
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: EvaluationOutput.url("/tmp/missioncontrol-settings-context-" + name + ".png"), options: .atomic)
            }
            window.close()
        }
        try? report.joined(separator: "\n").write(to: EvaluationOutput.url("/tmp/missioncontrol-settings-context.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
