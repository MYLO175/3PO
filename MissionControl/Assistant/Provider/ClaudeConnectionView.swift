import SwiftUI
import AppKit

/// One provider at a time: requests go to ChatGPT or Claude, each on its own plan.
struct AIProviderSettings: View {
    let model: DashboardModel
    @State private var confirmClaude = false
    @State private var error: String?
    var body: some View {
        Section("AI provider") {
            Picker("Use", selection: Binding(get: { model.inference.provider }, set: choose)) {
                ForEach(PAProvider.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }.pickerStyle(.segmented)
            Text("3PO's requests go to the provider you choose, using that account's plan. Your saved data and permissions stay the same when you switch.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .alert("Use Claude for 3PO?", isPresented: $confirmClaude) {
            Button("Use Claude") { select(.claudeCode, confirmed: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The personal context you've allowed 3PO to use will be sent to Anthropic instead of OpenAI. Your saved data, memory and source permissions stay as they are.")
        }
        if model.inference.provider == .claudeCode { ClaudeConnectionView(connection: model.claude) }
        else { ChatGPTConnectionView(connection: model.chatGPT) }
    }
    private func choose(_ next: PAProvider) {
        if next == .claudeCode, UserDefaults.standard.object(forKey: ClaudeCodeConnection.Keys.consent) == nil { confirmClaude = true; return }
        select(next, confirmed: false)
    }
    private func select(_ next: PAProvider, confirmed: Bool) {
        do {
            try model.inference.select(next)
            if confirmed { UserDefaults.standard.set(Date(), forKey: ClaudeCodeConnection.Keys.consent) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct ClaudeConnectionView: View {
    @Bindable var connection: ClaudeCodeConnection
    var body: some View {
        Section("Claude") {
            Text(connection.message).font(.callout).textSelection(.enabled).id(connection.message)
            if !connection.checked { ProgressView().controlSize(.small) }
            else if !connection.installed {
                Text("3PO reaches your Claude plan through Claude Code, Anthropic's free app. Install it once and 3PO does the rest.").font(.caption)
                HStack {
                    Button("Install Claude Code…") { open(connection.installScript) }
                    Button("Check again") { refresh() }
                }
                Text("Opens Terminal and runs Anthropic's official installer.").font(.caption).foregroundStyle(.secondary)
                Link("Installation help", destination: URL(string: "https://code.claude.com/docs/en/setup")!)
            } else if !connection.signedIn {
                HStack {
                    Button("Sign in with Claude…") { open(connection.signInScript) }
                    Button("Check again") { refresh() }
                }
                Text("Terminal opens Anthropic's own sign-in in your browser. 3PO never sees your Claude login. Claude Code needs a Pro or Max plan.").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Model", selection: $connection.selectedModel) {
                    ForEach(ClaudeCodeConnection.models) { Text($0.name).tag($0.id) }
                }.disabled(connection.busy)
                HStack {
                    Button("Check access · 1 request") { Task { await connection.checkAccess() } }.disabled(connection.busy)
                    Button("Check again") { refresh() }.disabled(connection.busy)
                    if connection.busy { ProgressView().controlSize(.small) }
                }
                if let plan = connection.plan { Text("Signed in · " + plan).font(.caption).foregroundStyle(.secondary) }
            }
            if connection.usagePaused { Text("Your Claude plan's usage limit was reached, so background AI is paused. Check access makes one source-free request.").font(.caption).foregroundStyle(.orange) }
            Link("See your Claude plan usage", destination: URL(string: "https://claude.ai/settings/usage")!)
            Text("Requests use your Claude plan's usage, with no API key or separate billing. Each request runs privately with no saved Claude Code session history.").font(.caption).foregroundStyle(.secondary)
        }
        .task { if !connection.checked { await connection.refresh() } }
    }
    private func refresh() { Task { await connection.refresh() } }
    private func open(_ make: () throws -> URL) {
        do { NSWorkspace.shared.open(try make()) } catch { connection.message = error.localizedDescription }
    }
}
