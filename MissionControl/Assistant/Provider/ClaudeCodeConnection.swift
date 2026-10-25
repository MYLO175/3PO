import Foundation
import Observation

struct ClaudeCodeModel: Identifiable, Equatable { var id: String; var name: String }

enum ClaudeCodeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Runs inference on the user's own Claude plan through their installed, signed-in
/// Claude Code. 3PO never reads, stores or relays Claude credentials and uses no API key.
@MainActor @Observable final class ClaudeCodeConnection: PAInferenceConnection {
    enum Keys {
        static let model = "claudeModel", verifiedModel = "claudeVerifiedModel", paused = "claudeUsagePaused"
        static let customPath = "claudeCodePath", consent = "claudeContextConsentDate"
        static let resolvedPath = "claudeCodeResolvedPath", signedIn = "claudeCodeSignedIn"
    }
    static let models: [ClaudeCodeModel] = [
        .init(id: PAProvider.claudeModelTag + "claude-sonnet-5-5", name: "Claude Sonnet 5.5"),
        .init(id: PAProvider.claudeModelTag + "claude-opus-5-5", name: "Claude Opus 5.5"),
        .init(id: PAProvider.claudeModelTag + "claude-haiku-5-5", name: "Claude Haiku 5.5"),
        .init(id: PAProvider.claudeModelTag + "claude-fable-5-1", name: "Claude Fable 5.1"),
    ]

    /// The last verified installation and sign-in state, so background work is ready after
    /// relaunch without starting a helper during construction. The first request re-verifies both.
    private(set) var binary: URL? = UserDefaults.standard.string(forKey: Keys.resolvedPath).map(URL.init(fileURLWithPath:)).flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil } {
        didSet { UserDefaults.standard.set(binary?.path, forKey: Keys.resolvedPath) }
    }
    private(set) var version: String?
    private(set) var signedIn = UserDefaults.standard.bool(forKey: Keys.signedIn) { didSet { UserDefaults.standard.set(signedIn, forKey: Keys.signedIn) } }
    private(set) var plan: String?
    private(set) var checked = false
    var selectedModel = UserDefaults.standard.string(forKey: Keys.model) ?? models[0].id { didSet { UserDefaults.standard.set(selectedModel, forKey: Keys.model) } }
    private(set) var verifiedModel = UserDefaults.standard.string(forKey: Keys.verifiedModel)
    private(set) var usagePaused = UserDefaults.standard.bool(forKey: Keys.paused) { didSet { UserDefaults.standard.set(usagePaused, forKey: Keys.paused) } }
    var busy = false
    var message = "Choose Claude to use your Claude plan."
    @ObservationIgnored weak var usageStore: AIUsageStore?
    /// Where the bundled Node runtime and tool-schema server live; the app bundle by default.
    @ObservationIgnored let resources: URL?

    init(resources: URL? = Bundle.main.resourceURL) { self.resources = resources }

    var installed: Bool { binary != nil }
    var hasSession: Bool { installed && signedIn }
    /// Like ChatGPT, one completed check verifies the plan; a model the plan lacks fails at request time.
    var inferenceVerified: Bool { hasSession && verifiedModel != nil }
    /// The workspace registration the router pinned for Claude work.
    var activeID: String { UserDefaults.standard.string(forKey: PAInferenceRouter.Keys.registration) ?? "" }

    private var runtime: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mission Control/ClaudeRuntime", isDirectory: true)
    }
    private var environment: [String: String] { ClaudeCodeInvocation.environment(ProcessInfo.processInfo.environment) }

    /// Finds the CLI, confirms Anthropic signed it and reads sign-in state. No AI request.
    func refresh() async {
        defer { checked = true }
        do {
            let workspace = try directory("workspace")
            guard let found = ClaudeCodeLocator.locate(custom: UserDefaults.standard.string(forKey: Keys.customPath)) else {
                binary = nil; signedIn = false; message = "Claude Code isn't installed on this Mac yet."; return
            }
            guard ClaudeCodeLocator.anthropicSigned(found) else {
                binary = nil; signedIn = false; message = "The claude program found on this Mac isn't Anthropic's signed Claude Code, so 3PO won't use it."; return
            }
            binary = found
            version = try await ClaudeCodeProcess.capture(executable: found, arguments: ["--version"], environment: environment, directory: workspace).output
                .components(separatedBy: " ").first
            let status = try await ClaudeCodeProcess.capture(executable: found, arguments: ["auth", "status", "--json"], environment: environment, directory: workspace)
            let json = (try? JSONSerialization.jsonObject(with: Data(status.output.utf8))) as? [String: Any] ?? [:]
            let auth = ClaudeCodeLocator.auth(json)
            signedIn = auth.loggedIn && auth.subscription
            plan = auth.plan
            message = !auth.loggedIn ? "Claude Code is installed. Sign in with your Claude plan to continue."
                : !auth.subscription ? "Claude Code is signed in with an API key or Console account. 3PO only uses a Claude plan, so sign in with Claude instead."
                : inferenceVerified ? "Ready to use \(plan ?? "your Claude plan")." : "Signed in. Run the access check to start using Claude."
        } catch {
            binary = nil; signedIn = false; message = "3PO couldn't check Claude Code. Try again."
        }
    }

    /// One short, source-free request that confirms the selected model works on this plan.
    func checkAccess() async {
        let model = selectedModel
        message = "Checking Claude access with \(Self.models.first { $0.id == model }?.name ?? model)…"
        do {
            let reply = try await perform(input: [["role": "user", "content": "Reply with exactly: 3PO connection works."]], instructions: "", tools: [],
                                          model: model, effort: "low", purpose: .connectionCheck, mode: .text, onDelta: { _ in }).text
            guard reply.contains("connection works"), selectedModel == model else { throw ClaudeCodeError.message("The access check didn't complete. Try again.") }
            verifiedModel = model; UserDefaults.standard.set(model, forKey: Keys.verifiedModel)
            usagePaused = false
            message = "Claude is ready. Personal sources were not sent."
        } catch { message = error.localizedDescription }
    }

    func streamResponse(input: [[String: String]], instructions: String, model: String?, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> String {
        let note = "When these instructions ask for JSON, reply with the raw JSON value only: no code fences or commentary."
        let text = try await perform(input: input.map { $0 as [String: Any] }, instructions: instructions.isEmpty ? note : instructions + "\n\n" + note, tools: [],
                                     model: model ?? selectedModel, effort: effort, purpose: purpose, mode: .text, onDelta: onDelta).text
        return ClaudeCodeTranscript.unfenced(text)
    }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        try await toolResponse(input: input, instructions: instructions, tools: tools, model: model, effort: "medium", purpose: purpose, onDelta: onDelta)
    }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        try await perform(input: input, instructions: instructions, tools: tools, model: model, effort: effort, purpose: purpose, mode: tools.isEmpty ? .text : .tools, onDelta: onDelta)
    }
    /// Claude Code can't force a tool choice, so a typed result uses its JSON-schema mode.
    func typedResult(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, effort: String, purpose: AIRequestPurpose) async throws -> PAResponse {
        let note = "Return your result as the requested structured JSON output; there is no tool to call."
        return try await perform(input: input, instructions: instructions.isEmpty ? note : instructions + "\n\n" + note, tools: tools, model: model, effort: effort, purpose: purpose, mode: .typed, onDelta: { _ in })
    }

    private enum Mode { case text, tools, typed }

    private func perform(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, effort: String,
                         purpose: AIRequestPurpose, mode: Mode, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        guard !busy else { throw ClaudeCodeError.message("Another Claude request is in progress.") }
        guard purpose == .connectionCheck || (!usagePaused && hasSession && inferenceVerified) else {
            throw ClaudeCodeError.message(usagePaused ? "Claude requests are paused after a usage limit. Run Check access in Settings once your limit resets."
                                                      : "Finish setting up Claude in Settings first.")
        }
        busy = true; defer { busy = false }
        if !checked { await refresh() }
        guard let binary, signedIn else { throw ClaudeCodeError.message(message) }
        let registration = activeID
        let typed = mode == .typed ? try ClaudeCodeTranscript.typedTool(tools) : nil
        let request = try ClaudeCodeTranscript.request(input: input, instructions: instructions, tools: mode == .tools ? tools : [])
        let run = try directory("run-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: run) }
        let system = run.appendingPathComponent("system.txt")
        try write(Data(request.system.utf8), to: system)
        var mcp: URL?
        if !request.tools.isEmpty {
            guard let resources else { throw ClaudeCodeError.message("3PO's tool helper is missing from this build.") }
            let schema = run.appendingPathComponent("tools.json"), config = run.appendingPathComponent("mcp.json")
            try write(try JSONSerialization.data(withJSONObject: request.tools, options: [.sortedKeys]), to: schema)
            let node = resources.appendingPathComponent("WhatsAppBridge/Runtime/node"), server = resources.appendingPathComponent("MCPBridge/tool-schema-server.mjs")
            try write(try JSONSerialization.data(withJSONObject: ClaudeCodeInvocation.mcpConfig(node: node, server: server, tools: schema)), to: config)
            mcp = config
        }
        let arguments = try ClaudeCodeInvocation.arguments(model: model, effort: effort, systemFile: system, mcpConfig: mcp, jsonSchema: typed?.schema)
        var stream = typed != nil ? ClaudeCodeStream(expectedTools: [ClaudeCodeStream.structuredOutputTool], endsAtToolUse: false)
            : ClaudeCodeStream(expectedTools: Set(request.tools.compactMap { ($0["name"] as? String).map { ClaudeCodeTranscript.toolPrefix + $0 } }))
        let usage = usageStore?.begin(registration: registration, model: model, purpose: purpose)
        do {
            let line = try JSONSerialization.data(withJSONObject: request.message) + Data([10])
            let outcome = try await ClaudeCodeProcess.run(executable: binary, arguments: arguments, environment: environment, directory: try directory("workspace"), input: line) { raw in
                if let delta = try stream.line(raw) { onDelta(delta) }
                return stream.finished
            }
            if !stream.finished, outcome.status != 0 { throw ClaudeCodeStream.classify(outcome.diagnostics) }
            try stream.completed()
            let response: PAResponse
            if let typed {
                let structured = stream.structuredOutput as? [String: Any]
                    ?? (try? JSONSerialization.jsonObject(with: Data(ClaudeCodeTranscript.unfenced(stream.text).utf8))) as? [String: Any]
                guard let structured else { throw ClaudeCodeStream.Failure.invalid }
                let call = try ClaudeCodeTranscript.call(id: "claude_" + UUID().uuidString.lowercased(), name: ClaudeCodeTranscript.toolPrefix + typed.name,
                                                         input: structured, tools: [["name": typed.name, "inputSchema": typed.schema]])
                response = .init(text: "", output: ClaudeCodeTranscript.output(text: "", calls: [call]), calls: [call])
            } else {
                let calls = try stream.toolUses.map { try ClaudeCodeTranscript.call(id: $0.id, name: $0.name, input: $0.input, tools: request.tools) }
                response = .init(text: stream.text, output: ClaudeCodeTranscript.output(text: stream.text, calls: calls), calls: calls)
            }
            usageStore?.finish(usage, outcome: .completed, tokens: stream.reportedTokens)
            return response
        } catch {
            usageStore?.finish(usage, outcome: Task.isCancelled ? .interrupted : .failed, tokens: stream.reportedTokens)
            throw describe(error)
        }
    }

    /// Only the category of a failure reaches the person; CLI output is never shown verbatim.
    private func describe(_ error: Error) -> Error {
        if error is CancellationError { return error }
        switch error {
        case ClaudeCodeStream.Failure.usageLimit:
            usagePaused = true
            return ClaudeCodeError.message("Your Claude plan's usage limit was reached, so new AI requests are paused. Run Check access in Settings once it resets.")
        case ClaudeCodeStream.Failure.overloaded: return ClaudeCodeError.message("Claude is temporarily overloaded. Nothing was changed; try again shortly.")
        case ClaudeCodeStream.Failure.signedOut:
            signedIn = false
            return ClaudeCodeError.message("Claude Code is signed out. Sign in with Claude in Settings.")
        case ClaudeCodeStream.Failure.apiKeyAuthentication:
            return ClaudeCodeError.message("Claude Code is set to use an API key, which 3PO never uses. Sign in with your Claude plan instead.")
        case ClaudeCodeStream.Failure.unexpectedEnvironment:
            return ClaudeCodeError.message("Claude Code started with tools or plugins 3PO didn't ask for, so the request was stopped before anything ran.")
        case ClaudeCodeStream.Failure.refused: return ClaudeCodeError.message("Claude declined this request.")
        case ClaudeCodeStream.Failure.truncated: return ClaudeCodeError.message("Claude's reply was cut off before it finished.")
        case ClaudeCodeProcess.Failure.timedOut: return ClaudeCodeError.message("Claude didn't finish within three minutes. Nothing further was run.")
        case ClaudeCodeProcess.Failure.unavailable: return ClaudeCodeError.message("Claude Code couldn't be started. Check it in Settings.")
        case is ClaudeCodeError: return error
        default: return ClaudeCodeError.message("Claude couldn't complete this request. Nothing further was run.")
        }
    }

    private func directory(_ name: String) throws -> URL {
        let url = runtime.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtime.path)
        return url
    }
    private func write(_ data: Data, to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw ClaudeCodeError.message("3PO couldn't prepare the Claude request.") }
    }

    /// A Terminal script for Anthropic's own installer or sign-in; 3PO never sees the result.
    func terminalScript(_ name: String, _ command: String) throws -> URL {
        let url = try directory("terminal").appendingPathComponent(name + ".command")
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: Data(("#!/bin/zsh\n" + command + "\necho\necho 'Done. Return to 3PO and choose Check again.'\n").utf8),
                                             attributes: [.posixPermissions: 0o700]) else { throw ClaudeCodeError.message("3PO couldn't open Terminal.") }
        return url
    }
    func signInScript() throws -> URL {
        guard let binary else { throw ClaudeCodeError.message("Install Claude Code first.") }
        return try terminalScript("sign-in-to-claude", "'" + binary.path.replacingOccurrences(of: "'", with: "'\\''") + "' auth login --claudeai")
    }
    func installScript() throws -> URL { try terminalScript("install-claude-code", "curl -fsSL https://claude.ai/install.sh | bash") }
}
