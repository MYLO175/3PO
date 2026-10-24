import Foundation
import Darwin

/// A private JSONL bridge. Source text and helper diagnostics never become error messages.
@MainActor enum GraphitiProcess {
    enum Failure: LocalizedError {
        case unavailable, invalidRequest, invalidResponse, limitsExceeded, helperFailed, inferenceFailed, timedOut
        var errorDescription: String? {
            switch self {
            case .unavailable: return "The Graphiti runtime is unavailable. Complete its local setup first."
            case .invalidRequest: return "The Graphiti request could not be encoded."
            case .invalidResponse: return "The Graphiti helper returned an invalid response."
            case .limitsExceeded: return "The Graphiti operation exceeded its bounded transport allowance."
            case .helperFailed: return "The Graphiti helper could not complete this operation."
            case .inferenceFailed: return "Graphiti could not complete its memory inference request."
            case .timedOut: return "The Graphiti operation timed out."
            }
        }
    }

    /// Pydantic's defaults make fields omittable. Strict function results must supply
    /// all fields, but we preserve their types: adding null to a defaulted array would
    /// produce a value that Pydantic cannot validate. Existing nullable unions remain.
    static func normalizeSchema(_ schema: [String: Any]) throws -> [String: Any] {
        var nodes = 0
        func normalize(_ value: [String: Any], depth: Int) throws -> [String: Any] {
            nodes += 1
            guard depth <= 32, nodes <= 2_000 else { throw Failure.limitsExceeded }
            var output = value
            output.removeValue(forKey: "default")
            output.removeValue(forKey: "title")
            output.removeValue(forKey: "examples")
            guard value["patternProperties"] == nil, value["unevaluatedProperties"] == nil else { throw Failure.invalidRequest }
            if let definitions = value["$defs"] as? [String: [String: Any]] {
                output["$defs"] = try definitions.mapValues { try normalize($0, depth: depth + 1) }
            }
            for key in ["anyOf", "oneOf", "allOf"] {
                if let choices = value[key] as? [[String: Any]] {
                    guard !choices.isEmpty else { throw Failure.invalidRequest }
                    output[key] = try choices.map { try normalize($0, depth: depth + 1) }
                }
            }
            if let items = value["items"] as? [String: Any] { output["items"] = try normalize(items, depth: depth + 1) }
            if value["type"] as? String == "object" || value["properties"] != nil {
                guard let properties = value["properties"] as? [String: [String: Any]] else { throw Failure.invalidRequest }
                if let additional = value["additionalProperties"], !(additional is Bool && (additional as? Bool) == false) {
                    throw Failure.invalidRequest
                }
                output["properties"] = try properties.mapValues { try normalize($0, depth: depth + 1) }
                output["required"] = properties.keys.sorted()
                output["additionalProperties"] = false
            }
            return output
        }
        guard schema["type"] as? String == "object", schema["properties"] != nil,
              JSONSerialization.isValidJSONObject(schema),
              let data = try? JSONSerialization.data(withJSONObject: schema), data.count <= 256 * 1024 else { throw Failure.invalidRequest }
        return try normalize(schema, depth: 0)
    }

    private final class Callback {
        var result: Result<[String: Any], Error>?
        var task: Task<Void, Never>?
        let id: String
        init(id: String) { self.id = id }
    }

    /// Polls nonblocking pipes so cancellation and the absolute deadline also apply while
    /// the helper is silent, filling stderr, or awaiting an inference callback.
    static func run(python: URL, helper: URL, request: [String: Any], timeout: TimeInterval = 600,
                    onLLM: @escaping @MainActor ([String: Any]) async throws -> [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard timeout.isFinite, timeout > 0, timeout <= 600 else { throw Failure.invalidRequest }
        guard python.isFileURL, helper.isFileURL,
              FileManager.default.isExecutableFile(atPath: python.path),
              FileManager.default.fileExists(atPath: helper.path) else { throw Failure.unavailable }
        let maxLine = 2 * 1024 * 1024, maxBytes = 16 * 1024 * 1024
        func encode(_ object: [String: Any]) throws -> Data {
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                  data.count <= maxLine else { throw Failure.invalidRequest }
            return data + Data([10])
        }
        var outgoing = try encode(request)
        let process = Process(), input = Pipe(), output = Pipe(), diagnostics = Pipe()
        process.executableURL = python
        process.arguments = ["-u", helper.path]
        // Deliberate allowlist: never inherit API keys or provider credentials.
        let inherited = ProcessInfo.processInfo.environment
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "PYTHONUNBUFFERED": "1",
                           "PYTHONNOUSERSITE": "1", "GRAPHITI_TELEMETRY_ENABLED": "false",
                           "DO_NOT_TRACK": "1", "ANONYMIZED_TELEMETRY": "false"]
        for key in ["HOME", "TMPDIR", "LANG", "LC_ALL"] {
            if let value = inherited[key] { environment[key] = value }
        }
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = diagnostics
        // F_SETNOSIGPIPE prevents an exited helper from terminating the app on write.
        for handle in [input.fileHandleForWriting, output.fileHandleForReading, diagnostics.fileHandleForReading] {
            let descriptor = handle.fileDescriptor
            guard fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) != -1 else { throw Failure.unavailable }
            _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        }
        do { try process.run() } catch { throw Failure.unavailable }
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? diagnostics.fileHandleForWriting.close()
        var callback: Callback?
        defer {
            callback?.task?.cancel()
            for handle in [input.fileHandleForWriting, output.fileHandleForReading, diagnostics.fileHandleForReading] { try? handle.close() }
        }
        let started = ProcessInfo.processInfo.systemUptime
        var buffered = Data(), stdoutBytes = 0, stderrBytes = 0, writtenBytes = 0, lines = 0
        var stdoutEnded = false, stderrEnded = false, result: [String: Any]?
        var callbackIDs = Set<String>()
        func readChunk(_ handle: FileHandle) throws -> Data? {
            var bytes = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
            if count == 0 { return Data() }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { return nil }
                throw Failure.invalidResponse
            }
            return Data(bytes.prefix(count))
        }
        do {
            while true {
                try Task.checkCancellation()
                if ProcessInfo.processInfo.systemUptime - started >= timeout { throw Failure.timedOut }
                if let active = callback, let response = active.result {
                    switch response {
                    case .success(let object): outgoing.append(try encode(["type": "llm_response", "id": active.id, "result": object]))
                    case .failure(let error):
                        if error is CancellationError { throw CancellationError() }
                        throw Failure.inferenceFailed
                    }
                    callback = nil
                }
                if !outgoing.isEmpty {
                    let count = outgoing.withUnsafeBytes { bytes in Darwin.write(input.fileHandleForWriting.fileDescriptor, bytes.baseAddress!, bytes.count) }
                    if count > 0 {
                        outgoing.removeFirst(count)
                        writtenBytes += count
                        if writtenBytes > maxBytes { throw Failure.limitsExceeded }
                    } else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR { throw Failure.helperFailed }
                }
                // Bounded work per iteration prevents a noisy child starving cancellation.
                for _ in 0..<16 {
                    guard !stderrEnded, let bytes = try readChunk(diagnostics.fileHandleForReading) else { break }
                    if bytes.isEmpty { stderrEnded = true; break }
                    stderrBytes += bytes.count
                    if stderrBytes > maxBytes { throw Failure.limitsExceeded }
                }
                for _ in 0..<16 {
                    guard !stdoutEnded, let bytes = try readChunk(output.fileHandleForReading) else { break }
                    if bytes.isEmpty { stdoutEnded = true; break }
                    stdoutBytes += bytes.count
                    if stdoutBytes > maxBytes { throw Failure.limitsExceeded }
                    buffered.append(bytes)
                    while let end = buffered.firstIndex(of: 10) {
                        let line = Data(buffered[..<end])
                        buffered.removeSubrange(...end)
                        lines += 1
                        guard line.count <= maxLine, lines <= 512 else { throw Failure.limitsExceeded }
                        guard !line.isEmpty, result == nil,
                              let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                              let type = message["type"] as? String else { throw Failure.invalidResponse }
                        switch type {
                        case "llm_request":
                            guard callback == nil, outgoing.isEmpty,
                                  let id = message["id"] as? String, !id.isEmpty, id.utf8.count <= 128,
                                  callbackIDs.insert(id).inserted, callbackIDs.count <= 96,
                                  let messages = message["messages"] as? [[String: Any]], !messages.isEmpty,
                                  messages.count <= 64,
                                  messages.allSatisfy({ item in
                                      guard let role = item["role"] as? String, ["system", "user", "assistant"].contains(role) else { return false }
                                      return item["content"] is String
                                  }), message["schema"] is [String: Any],
                                  let name = message["name"] as? String, !name.isEmpty, name.utf8.count <= 128 else { throw Failure.invalidResponse }
                            let active = Callback(id: id)
                            callback = active
                            active.task = Task { @MainActor in
                                do { active.result = .success(try await onLLM(message)) }
                                catch { active.result = .failure(error) }
                            }
                        case "result":
                            guard callback == nil, let value = message["result"] as? [String: Any] else { throw Failure.invalidResponse }
                            result = value
                        case "error": throw Failure.helperFailed
                        default: throw Failure.invalidResponse
                        }
                    }
                    if buffered.count > maxLine { throw Failure.limitsExceeded }
                }
                if !process.isRunning && stdoutEnded {
                    guard process.terminationStatus == 0, buffered.isEmpty, callback == nil, let result else { throw Failure.helperFailed }
                    return result
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        } catch {
            callback?.task?.cancel()
            // Graceful helper termination closes its database; escalation is bounded.
            if process.isRunning {
                process.terminate()
                let stopStarted = ProcessInfo.processInfo.systemUptime
                while process.isRunning && ProcessInfo.processInfo.systemUptime - stopStarted < 3 {
                    // A cancelled parent still gives the helper a short cleanup opportunity.
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) { continuation.resume() }
                    }
                }
                if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
            }
            throw error
        }
    }
}
