#if DEBUG
import SwiftUI

/// Settings opened on its Context page for a fictional account. Pages, projects and
/// memories go to the disposable in-memory store; sources, helpers and AI never start.
struct SettingsContextPreview: View {
    var model: DashboardModel
    @AppStorage("settingsSelectedPage") private var selectedPage = "General"
    @State private var ready = false
    var body: some View {
        Group {
            if ready { SettingsView(model: model) } else { ProgressView() }
        }.task {
            guard !ready else { return }
            model.inference.useChatGPTForFictionalEvaluation()
            model.chatGPT.activeID = "fictional-settings-preview"
            try? MemoryInspectionPreview.seedContextPages(model)
            selectedPage = "Context"
            ready = true
        }
    }
}
#endif
