import Foundation

/// Parses one headless Claude Code run's stream-json output. A round ends at the
/// first completed assistant message that stops for tool use, or at the result;
/// tool calls count only once their content block is complete.
struct ClaudeCodeStream {
    enum Failure: Error, Equatable {
        case invalid, oversized, apiKeyAuthentication, unexpectedEnvironment
        case usageLimit, overloaded, signedOut, refused, truncated, failed, interrupted
    }
    struct ToolUse { var id: String; var name: String; var input: [String: Any] }

    /// Full MCP names (mcp__pa__…) this round advertised; empty disables tools.
    let expectedTools: Set<String>
    private(set) var streamedText = ""
    private(set) var finished = false
    private(set) var reportedTokens: AIReportedTokens?
    private(set) var structuredOutput: Any?
    private(set) var model: String?
    private(set) var toolUses: [ToolUse] = []
    private var initialised = false
    private var stopReason: String?
    private var messageText: [String] = []
    private var resultText: String?
    private var partial: [Int: (id: String, name: String, json: String)] = [:]
    private var streamUsage: (input: Int, cacheRead: Int, cacheWrite: Int, output: Int)?

    init(expectedTools: Set<String>) { self.expectedTools = expectedTools }

    /// The completed reply text: assistant message content is authoritative over deltas.
    var text: String {
        let completed = messageText.joined()
        return !completed.isEmpty ? completed : !streamedText.isEmpty ? streamedText : resultText ?? ""
    }

    /// Returns a text delta to show, if the line carried one.
    mutating func line(_ raw: String) throws -> String? {
        guard raw.utf8.count <= 1_000_000 else { throw Failure.oversized }
        guard !finished else { return nil }
        guard let event = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any], let type = event["type"] as? String else { throw Failure.invalid }
        if let error = event["error"] as? String { throw Self.classify(error) }
        switch type {
        case "system":
            guard event["subtype"] as? String == "init" else { return nil }
            try verify(event)
        case "stream_event":
            guard initialised, let inner = event["event"] as? [String: Any] else { throw Failure.invalid }
            return try stream(inner)
        case "assistant":
            guard initialised, let message = event["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] else { throw Failure.invalid }
            for block in content {
                switch block["type"] as? String {
                case "text": messageText.append(block["text"] as? String ?? "")
                case "tool_use":
                    guard let id = block["id"] as? String, let name = block["name"] as? String, let input = block["input"] as? [String: Any] else { throw Failure.invalid }
                    try record(.init(id: id, name: name, input: input))
                default: break
                }
            }
            if let reason = message["stop_reason"] as? String { try stop(reason) }
            if stopReason == "tool_use", partial.isEmpty, !toolUses.isEmpty { finish() }
        case "result":
            guard initialised else { throw Failure.invalid }
            if let usage = event["usage"] { reportedTokens = Self.tokens(usage) ?? reportedTokens }
            if event["is_error"] as? Bool == true {
                // Holding a tool call open can end a run at its turn limit; that is a completed round.
                guard event["subtype"] as? String == "error_max_turns", !toolUses.isEmpty else {
                    throw Self.classify(event["result"] as? String ?? event["subtype"] as? String ?? "")
                }
            }
            resultText = event["result"] as? String
            structuredOutput = event["structured_output"]
            finished = true
        default: break
        }
        return nil
    }

    /// The CLI's own report of its environment must match what 3PO asked for.
    private mutating func verify(_ event: [String: Any]) throws {
        guard !initialised else { throw Failure.invalid }
        if let source = event["apiKeySource"] as? String, source != "none" { throw Failure.apiKeyAuthentication }
        guard let tools = event["tools"] as? [String], Set(tools) == expectedTools, tools.count == expectedTools.count else { throw Failure.unexpectedEnvironment }
        let servers = (event["mcp_servers"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        guard servers == (expectedTools.isEmpty ? [] : [ClaudeCodeTranscript.serverName]) else { throw Failure.unexpectedEnvironment }
        if let plugins = event["plugins"] as? [Any], !plugins.isEmpty { throw Failure.unexpectedEnvironment }
        model = event["model"] as? String
        initialised = true
    }

    private mutating func stream(_ inner: [String: Any]) throws -> String? {
        switch inner["type"] as? String {
        case "message_start":
            if let usage = (inner["message"] as? [String: Any])?["usage"] as? [String: Any] {
                streamUsage = (Self.int(usage["input_tokens"]), Self.int(usage["cache_read_input_tokens"]), Self.int(usage["cache_creation_input_tokens"]), Self.int(usage["output_tokens"]))
            }
        case "content_block_start":
            if let index = inner["index"] as? Int, let block = inner["content_block"] as? [String: Any], block["type"] as? String == "tool_use",
               let id = block["id"] as? String, let name = block["name"] as? String { partial[index] = (id, name, "") }
        case "content_block_delta":
            guard let delta = inner["delta"] as? [String: Any] else { throw Failure.invalid }
            if delta["type"] as? String == "text_delta", let text = delta["text"] as? String { streamedText += text; return text }
            if delta["type"] as? String == "input_json_delta", let index = inner["index"] as? Int, let json = delta["partial_json"] as? String, partial[index] != nil {
                partial[index]!.json += json
                guard partial[index]!.json.utf8.count <= 32_000 else { throw Failure.oversized }
            }
        case "content_block_stop":
            if let index = inner["index"] as? Int, let block = partial.removeValue(forKey: index), !toolUses.contains(where: { $0.id == block.id }) {
                let json = block.json.isEmpty ? "{}" : block.json
                guard let input = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { throw Failure.invalid }
                try record(.init(id: block.id, name: block.name, input: input))
            }
        case "message_delta":
            if let usage = inner["usage"] as? [String: Any], var current = streamUsage { current.output = Self.int(usage["output_tokens"]); streamUsage = current }
            if let reason = (inner["delta"] as? [String: Any])?["stop_reason"] as? String { try stop(reason) }
        case "message_stop":
            if stopReason == "tool_use", partial.isEmpty, !toolUses.isEmpty { finish() }
        default: break
        }
        return nil
    }

    private mutating func record(_ use: ToolUse) throws {
        if let index = toolUses.firstIndex(where: { $0.id == use.id }) { toolUses[index] = use; return }
        guard !use.id.isEmpty, !use.name.isEmpty, toolUses.count < 12,
              let data = try? JSONSerialization.data(withJSONObject: use.input), data.count <= 32_000 else { throw Failure.invalid }
        toolUses.append(use)
    }

    private mutating func stop(_ reason: String) throws {
        stopReason = reason
        switch reason {
        case "max_tokens": throw Failure.truncated
        case "refusal": throw Failure.refused
        default: break
        }
    }

    private mutating func finish() {
        finished = true
        if reportedTokens == nil, let usage = streamUsage {
            let input = usage.input + usage.cacheRead + usage.cacheWrite
            reportedTokens = .init(input: input, output: usage.output, total: input + usage.output, cachedInput: usage.cacheRead, cacheWriteInput: usage.cacheWrite)
        }
    }

    /// A run that stopped before its round completed is never accepted.
    func completed() throws {
        guard finished else { throw Failure.interrupted }
    }

    static func tokens(_ value: Any?) -> AIReportedTokens? {
        guard let usage = value as? [String: Any], usage["input_tokens"] != nil, usage["output_tokens"] != nil else { return nil }
        let read = int(usage["cache_read_input_tokens"]), write = int(usage["cache_creation_input_tokens"])
        let input = int(usage["input_tokens"]) + read + write, output = int(usage["output_tokens"])
        let tokens = AIReportedTokens(input: input, output: output, total: input + output, cachedInput: read, cacheWriteInput: write)
        return tokens.valid ? tokens : nil
    }

    private static func int(_ value: Any?) -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue >= 0, number.doubleValue <= 1_000_000_000 else { return 0 }
        return number.intValue
    }

    /// Error text never becomes a user message verbatim; only its category does.
    static func classify(_ text: String) -> Failure {
        let value = text.lowercased()
        if value.contains("rate_limit") || value.contains("usage limit") || (value.contains("limit") && (value.contains("reached") || value.contains("resets"))) { return .usageLimit }
        if value.contains("overloaded") || value.contains("529") || value.contains("server_error") { return .overloaded }
        if value.contains("authentication") || value.contains("login") || value.contains("log in") || value.contains("oauth") || value.contains("401") || value.contains("billing") { return .signedOut }
        return .failed
    }
}
