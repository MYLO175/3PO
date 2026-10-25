import Foundation
import Darwin
import Security

/// One headless Claude Code invocation. Never `--bare`: it ignores the user's own
/// Claude login and would need an API key.
enum ClaudeCodeInvocation {
    enum Failure: Error, Equatable { case invalidModel, invalidEffort }
    /// Personal Claude Code settings, plugins, hooks and commands stay out of 3PO's runs.
    static let isolation = ["--setting-sources", "local", "--disable-slash-commands"]
    private static let modelID = try! NSRegularExpression(pattern: "^claude-[a-z0-9.-]{1,64}$")

    /// The CLI model name for a captured `claude-code:` model.
    static func cliModel(_ model: String) throws -> String {
        guard model.hasPrefix(PAProvider.claudeModelTag) else { throw Failure.invalidModel }
        let id = String(model.dropFirst(PAProvider.claudeModelTag.count))
        guard modelID.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil else { throw Failure.invalidModel }
        return id
    }

    static func arguments(model: String, effort: String, systemFile: URL, mcpConfig: URL?, jsonSchema: [String: Any]?) throws -> [String] {
        guard ["low", "medium", "high"].contains(effort) else { throw Failure.invalidEffort }
        var arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--include-partial-messages", "--verbose",
                         "--tools", "", "--strict-mcp-config", "--permission-mode", "dontAsk", "--permission-prompts", "none",
                         "--no-session-persistence", "--model", try cliModel(model), "--effort", effort,
                         "--system-prompt-file", systemFile.path] + isolation
        if let mcpConfig { arguments += ["--mcp-config", mcpConfig.path, "--allowedTools", ClaudeCodeTranscript.toolPrefix + "*"] }
        if let jsonSchema {
            let data = try JSONSerialization.data(withJSONObject: jsonSchema, options: [.sortedKeys])
            arguments += ["--json-schema", String(decoding: data, as: UTF8.self)]
        }
        return arguments
    }

    /// Deliberate allowlist: API keys, tokens, base URLs and loader variables are never inherited.
    static func environment(_ inherited: [String: String]) -> [String: String] {
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "ENABLE_TOOL_SEARCH": "false", "DISABLE_TELEMETRY": "1",
                           "DISABLE_ERROR_REPORTING": "1", "DISABLE_AUTOUPDATER": "1", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"]
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL"] { if let value = inherited[key] { environment[key] = value } }
        return environment
    }

    static func mcpConfig(node: URL, server: URL, tools: URL) -> [String: Any] {
        ["mcpServers": [ClaudeCodeTranscript.serverName: ["command": node.path, "args": [server.path], "env": ["THREEPO_TOOL_SCHEMA_FILE": tools.path]]]]
    }
}

/// Finds the user's own Claude Code and confirms Anthropic signed it. The Claude
/// desktop app's private copy is never used.
enum ClaudeCodeLocator {
    static func candidates(home: URL, custom: String?) -> [URL] {
        var paths = [home.appendingPathComponent(".local/bin/claude").path, "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        if let custom, !custom.isEmpty { paths.insert(custom, at: 0) }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    static func locate(home: URL = FileManager.default.homeDirectoryForCurrentUser, custom: String? = nil) -> URL? {
        for candidate in candidates(home: home, custom: custom) {
            let resolved = candidate.resolvingSymlinksInPath()
            guard !resolved.path.contains("/Application Support/Claude/"), !resolved.path.contains(".app/Contents/"),
                  FileManager.default.isExecutableFile(atPath: resolved.path) else { continue }
            return resolved
        }
        return nil
    }

    /// The signing certificate's subject when the binary carries a valid Developer ID signature.
    static func signer(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let certificates = (information as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return nil }
        return SecCertificateCopySubjectSummary(leaf) as String?
    }

    static func anthropicSigned(_ subject: String?) -> Bool { subject?.contains("Anthropic PBC") == true }

    struct Auth: Equatable { var loggedIn: Bool; var subscription: Bool; var plan: String? }
    /// Reads only sign-in state from `claude auth status --json`; never credentials.
    static func auth(_ json: [String: Any]) -> Auth {
        let loggedIn = json["loggedIn"] as? Bool ?? json["logged_in"] as? Bool ?? false
        let method = ((json["authMethod"] ?? json["auth_method"] ?? json["method"]) as? String ?? "").lowercased()
        let usesKey = ["api", "console", "key"].contains { method.contains($0) }
        let plan = (json["subscriptionType"] ?? json["subscription_type"]) as? String
        return .init(loggedIn: loggedIn, subscription: loggedIn && !usesKey, plan: plan.map { "Claude " + $0.capitalized })
    }
}

/// Supervises one Claude Code run: writes its single stdin message, streams stdout
/// lines to the caller, and stops the run once the caller reports a completed round.
@MainActor enum ClaudeCodeProcess {
    enum Failure: Error, Equatable { case unavailable, timedOut, limitsExceeded, exited(Int32) }
    struct Outcome { var status: Int32?; var diagnostics: String }

    static func run(executable: URL, arguments: [String], environment: [String: String], directory: URL, input: Data,
                    timeout: TimeInterval = 180, onLine: (String) throws -> Bool) async throws -> Outcome {
        try Task.checkCancellation()
        guard FileManager.default.isExecutableFile(atPath: executable.path), timeout > 0, timeout <= 600 else { throw Failure.unavailable }
        let maxLine = 1_000_000, maxBytes = 16 * 1024 * 1024
        let process = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
        // F_SETNOSIGPIPE keeps an exited CLI from terminating 3PO on write.
        for handle in [stdin.fileHandleForWriting, stdout.fileHandleForReading, stderr.fileHandleForReading] {
            let descriptor = handle.fileDescriptor
            guard fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) != -1 else { throw Failure.unavailable }
            _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        }
        do { try process.run() } catch { throw Failure.unavailable }
        try? stdin.fileHandleForReading.close(); try? stdout.fileHandleForWriting.close(); try? stderr.fileHandleForWriting.close()
        defer { for handle in [stdin.fileHandleForWriting, stdout.fileHandleForReading, stderr.fileHandleForReading] { try? handle.close() } }
        let started = ProcessInfo.processInfo.systemUptime
        var outgoing = input, inputClosed = false, buffered = Data(), stdoutBytes = 0, stderrTail = Data()
        var stdoutEnded = false, stderrEnded = false
        func chunk(_ handle: FileHandle) throws -> Data? {
            var bytes = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
            if count == 0 { return Data() }
            if count < 0 { if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { return nil }; throw Failure.limitsExceeded }
            return Data(bytes.prefix(count))
        }
        func outcome() -> Outcome { .init(status: process.isRunning ? nil : process.terminationStatus, diagnostics: String(decoding: stderrTail, as: UTF8.self)) }
        do {
            while true {
                try Task.checkCancellation()
                if ProcessInfo.processInfo.systemUptime - started >= timeout { throw Failure.timedOut }
                if !outgoing.isEmpty {
                    let count = outgoing.withUnsafeBytes { Darwin.write(stdin.fileHandleForWriting.fileDescriptor, $0.baseAddress!, $0.count) }
                    if count > 0 { outgoing.removeFirst(count) }
                    else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR { outgoing.removeAll() }
                }
                if outgoing.isEmpty && !inputClosed { try? stdin.fileHandleForWriting.close(); inputClosed = true }
                for _ in 0..<16 {
                    guard !stderrEnded, let bytes = try chunk(stderr.fileHandleForReading) else { break }
                    if bytes.isEmpty { stderrEnded = true; break }
                    stderrTail.append(bytes)
                    if stderrTail.count > 4096 { stderrTail = stderrTail.suffix(4096) }
                }
                for _ in 0..<16 {
                    guard !stdoutEnded, let bytes = try chunk(stdout.fileHandleForReading) else { break }
                    if bytes.isEmpty { stdoutEnded = true; break }
                    stdoutBytes += bytes.count
                    guard stdoutBytes <= maxBytes else { throw Failure.limitsExceeded }
                    buffered.append(bytes)
                    while let end = buffered.firstIndex(of: 10) {
                        let line = String(decoding: buffered[..<end], as: UTF8.self)
                        buffered.removeSubrange(...end)
                        guard !line.isEmpty else { continue }
                        if try onLine(line) { await stop(process); return outcome() }
                    }
                    guard buffered.count <= maxLine else { throw Failure.limitsExceeded }
                }
                if !process.isRunning && stdoutEnded {
                    if !buffered.isEmpty, try onLine(String(decoding: buffered, as: UTF8.self)) { return outcome() }
                    return outcome()
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        } catch {
            await stop(process)
            throw error
        }
    }

    /// Bounded graceful stop, then SIGKILL; the advertise-only tool server exits with its parent's pipe.
    private static func stop(_ process: Process) async {
        guard process.isRunning else { return }
        process.terminate()
        let started = ProcessInfo.processInfo.systemUptime
        while process.isRunning && ProcessInfo.processInfo.systemUptime - started < 3 {
            await withCheckedContinuation { continuation in DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) { continuation.resume() } }
        }
        if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
    }

    /// Short, source-free commands such as `--version` and `auth status`.
    static func capture(executable: URL, arguments: [String], environment: [String: String], directory: URL, timeout: TimeInterval = 15) async throws -> (status: Int32?, output: String) {
        var lines: [String] = []
        let outcome = try await run(executable: executable, arguments: arguments, environment: environment, directory: directory, input: Data(), timeout: timeout) { line in
            lines.append(line); guard lines.count <= 200 else { throw Failure.limitsExceeded }; return false
        }
        return (outcome.status, lines.joined(separator: "\n"))
    }
}
