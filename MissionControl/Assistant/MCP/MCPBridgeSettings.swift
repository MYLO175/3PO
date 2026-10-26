import SwiftUI
import AppKit

struct MCPBridgeSettings: View {
    @Bindable var bridge: MCPBridgeService
    private var script: String { Bundle.main.resourceURL!.appendingPathComponent("MCPBridge/run.sh").path }
    private var configuration: String {
        let value: [String: Any] = ["mcpServers": ["3po": ["command": "/bin/zsh", "args": [script]]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }
    private var command: String { "/bin/zsh '" + script.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
    var body: some View {
        Section("External assistants") {
            Toggle("Enable 3PO workspace tools", isOn: Binding(get: { bridge.enabled }, set: { bridge.setEnabled($0) }))
            Text(bridge.status).font(.callout).foregroundStyle(.secondary)
            Text("Connected assistants can use Calendar, Reminders, Projects, Review inbox, context, memory and instructions. Email and selected WhatsApp chats are read-only. Source choices in Assistant settings still apply. Permission is managed where you are chatting, using that assistant’s tool approval controls. 3PO verifies saves and keeps action receipts. The Mac and 3PO must be running.").font(.callout)
            if let error = bridge.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
        }
        Section("Claude Desktop") {
            Text("Add this server to Claude Desktop’s developer configuration, merging it with any existing mcpServers. Restart Claude Desktop after saving.").font(.callout)
            Button("Copy Claude configuration") { copy(configuration) }
        }
        Section("ChatGPT desktop") {
            Text("In ChatGPT Settings > MCP servers, add a STDIO server named 3po. Use /bin/zsh as the command and the installed adapter path as its argument. The local desktop connection uses the same server as Claude Desktop.").font(.callout)
            Button("Copy local server command") { copy(command) }
            Link("ChatGPT desktop MCP setup", destination: URL(string: "https://learn.chatgpt.com/docs/extend/mcp")!)
        }
        Section("ChatGPT on the web") {
            Text("Create a Secure MCP Tunnel in your OpenAI Platform workspace and run tunnel-client on this Mac using the same local server command. Add the tunnel as a custom MCP plugin in ChatGPT. Tunnel access depends on your account and workspace permissions.").font(.callout)
            Button("Copy tunnel server command") { copy(command) }
            Link("ChatGPT tunnel setup", destination: URL(string: "https://developers.openai.com/api/docs/guides/secure-mcp-tunnels")!)
        }
        if !bridge.records.isEmpty {
            Section("External actions") {
                ForEach(bridge.records.reversed().prefix(20)) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(record.client).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(record.phase.rawValue.capitalized).font(.caption)
                        }
                        if let proposal = bridge.proposal(for: record) {
                            ForEach(Array(proposal.outline.enumerated()), id: \.offset) { _, text in Text(text).fontWeight(.medium) }
                            ForEach(Array(proposal.details.enumerated()), id: \.offset) { _, text in Text(text).font(.callout).foregroundStyle(.secondary) }
                        }
                        if record.proposal.isEmpty { Text(record.tool.replacingOccurrences(of: "_", with: " ")).fontWeight(.medium) }
                        if record.permission == "mcp-host" { Text("Permission managed by the connected assistant").font(.caption).foregroundStyle(.secondary) }
                        Text(record.result ?? "The outcome is unconfirmed. Check the original item before continuing; do not retry.").font(.callout).textSelection(.enabled)
                    }.padding(.vertical, 6)
                }
            }
        }
    }
}
