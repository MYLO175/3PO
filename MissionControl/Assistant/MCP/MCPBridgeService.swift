import Foundation
import Observation

/// External clients can submit proposals, but only the native UI calls approve.
/// No external request enters the inference/intent-check or background pipeline.
@MainActor @Observable final class MCPBridgeService {
    private weak var model: DashboardModel?
    private(set) var enabled = false
    private(set) var status = "Off"
    private(set) var error: String?
    private(set) var records: [MCPActionRecord] = []
    private var loaded = false
    private var original: Data?
    private var listener: MCPBridgeListener?
    private var generation = UUID()
    private var token = ""
    private struct Session {
        var tools: PAToolSession
        var scope: String
        var lastUsed = Date.now
        var busy = false
        var calls = 0
    }
    private var sessions: [UUID: Session] = [:]
    private let key = "externalMCPActions"
    private let connectionFile: URL
    private let defaults: UserDefaults
    private static var defaultConnectionFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Mission Control/MCP/connection.json")
    }
    init(model: DashboardModel, connectionFile: URL? = nil, defaults: UserDefaults = .standard) {
        self.model = model; self.connectionFile = connectionFile ?? Self.defaultConnectionFile; self.defaults = defaults
    }
    func resume() {
        if defaults.bool(forKey: "externalMCPEnabled") { setEnabled(true) }
    }
    func setEnabled(_ value: Bool) {
        generation = UUID(); listener?.stop(); listener = nil; sessions.removeAll(); enabled = false
        removeConnectionFile()
        defaults.set(false, forKey: "externalMCPEnabled")
        status = "Off"; error = nil
        guard value, let model else { return }
        guard !model.storageOwnershipBlocked, model.container != nil,
              !ProcessInfo.processInfo.arguments.contains("--sample") else { error = "External tools require normal app storage."; return }
        do { try load() } catch { self.error = "External action history is unavailable. The saved data has been kept."; return }
        enabled = true; status = "Starting…"
        token = UUID().uuidString + UUID().uuidString
        let captured = generation
        let server = MCPBridgeListener(token: token) { [weak self] bytes in
            guard let self else { return Data("{}".utf8) }
            return await self.handle(bytes, generation: captured)
        }
        listener = server
        Task {
            do {
                let port = try await server.start()
                guard enabled, generation == captured else { server.stop(); return }
                let file = connectionFile
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.deletingLastPathComponent().path)
                let bytes = try JSONSerialization.data(withJSONObject: ["url": "http://127.0.0.1:\(port)/bridge", "token": token])
                try bytes.write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                defaults.set(true, forKey: "externalMCPEnabled")
                status = "Ready · Calendar and Reminders"
            } catch {
                guard generation == captured else { return }
                setEnabled(false); self.error = "The local MCP bridge could not start. " + error.localizedDescription
            }
        }
    }
    private func removeConnectionFile() {
        guard !token.isEmpty, let data = try? Data(contentsOf: connectionFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String], object["token"] == token else { return }
        try? FileManager.default.removeItem(at: connectionFile)
    }
    private func load() throws {
        guard !loaded, let model, let container = model.container else { return }
        let bytes = try LocalRecordRepository(container: container).read(key)
        let saved = try bytes.map { try JSONDecoder().decode([MCPActionRecord].self, from: $0) } ?? []
        records = saved; original = bytes; loaded = true
    }
    private func replace(_ values: [MCPActionRecord]) throws {
        guard let container = model?.container else { throw ActionFailure.message("External action storage is unavailable.") }
        let bytes = try LocalRecordCoding.preservingUnknown(values, original: original)
        try LocalRecordRepository(container: container).write([key: bytes], expected: [key: LocalRecordVersion(original)])
        original = bytes; records = values
    }
    private func scope(_ model: DashboardModel) -> String {
        [model.chatGPT.activeID, model.reviewStorageIdentity, String(model.assistant.contextEnabled),
         model.assistant.excludedCalendars.sorted().joined(separator: "\n"), model.assistant.excludedLists.sorted().joined(separator: "\n")].joined(separator: "\u{0}")
    }
    private func handle(_ bytes: Data, generation captured: UUID) async -> Data {
        let output: [String: Any]
        do {
            guard enabled, generation == captured, let model, !model.storageOwnershipBlocked else { throw ActionFailure.message("The MCP connection is off. Enable it in 3PO Settings > External assistants.") }
            guard let request = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let method = request["method"] as? String else { throw ActionFailure.message("Invalid bridge request.") }
            if method == "tools/list" { output = ["tools": MCPBridgeContract.definitions] }
            else if method == "tools/call" {
                guard model.assistant.contextEnabled else { throw ActionFailure.message("Enable source context in 3PO Assistant settings before using external tools.") }
                guard let sessionText = request["session"] as? String, let sessionID = UUID(uuidString: sessionText),
                      let name = request["name"] as? String, let args = request["arguments"] as? [String: Any] else { throw ActionFailure.message("Invalid tool call.") }
                let client = String((request["client"] as? String ?? "External assistant").prefix(120))
                let currentScope = scope(model)
                sessions = sessions.filter { $0.value.busy || $0.value.lastUsed.timeIntervalSinceNow > -3600 }
                if sessions[sessionID] == nil {
                    guard sessions.count < 8 else { throw ActionFailure.message("Too many external sessions. Close an old connection.") }
                    sessions[sessionID] = .init(tools: PAToolSession(model: model, human: MCPBridgeContract.approvalEvidence, humanContext: "External MCP session", topicID: nil, turnID: UUID()), scope: currentScope)
                }
                guard let session = sessions[sessionID], session.scope == currentScope else { throw ActionFailure.message("Account or source permissions changed. Restart this MCP connection and read fresh sources.") }
                guard !session.busy else { throw ActionFailure.message("This connection already has a tool call running. Run tool calls sequentially.") }
                guard session.calls < 200 else { throw ActionFailure.message("Restart this MCP connection to begin a fresh bounded session, then read fresh sources. Keep existing action request IDs.") }
                sessions[sessionID]?.busy = true; sessions[sessionID]?.lastUsed = .now
                sessions[sessionID]?.calls += 1
                defer {
                    // A revoked connection can be recreated with the same
                    // adapter ID while an old read is finishing. Do not release
                    // the new session's claim from the old request.
                    if let current = sessions[sessionID], current.tools === session.tools { sessions[sessionID]?.busy = false }
                }
                let valid: NativeWriteValidity = { [weak self, weak model] in
                    guard let self, let model else { return false }
                    return self.enabled && self.generation == captured && !model.storageOwnershipBlocked && self.scope(model) == currentScope
                }
                if name == "action_status" {
                    guard Set(args.keys) == ["requestID"], let id = (args["requestID"] as? String).flatMap(UUID.init(uuidString:)),
                          let record = records.first(where: { $0.id == id && $0.registration == model.chatGPT.activeID }) else { throw ActionFailure.message("That external action is unavailable. Check the original item; do not resubmit an uncertain change.") }
                    output = record.output
                } else {
                    let call = try MCPBridgeContract.call(name: name, arguments: args)
                    if MCPBridgeContract.writes.contains(name) {
                        let id = UUID(uuidString: args["requestID"] as! String)!
                        if let existing = records.first(where: { $0.id == id }) {
                            guard existing.registration == model.chatGPT.activeID, existing.tool == name, existing.arguments == call.arguments else { throw ActionFailure.message("This requestID belongs to a different payload or account. It cannot be reused.") }
                            output = existing.output
                        } else {
                            guard records.count < 1000, records.filter({ $0.phase == .pending }).count < 20 else { throw ActionFailure.message("The external action queue is full. Review pending actions in 3PO.") }
                            let proposal = try await session.tools.prepareMCPApproval(call, requestID: id, valid: valid)
                            guard valid() else { throw CancellationError() }
                            // Another client can finish preparing this ID while
                            // the native destination read yields. Recheck before
                            // claiming, even though each individual session is serial.
                            if let existing = records.first(where: { $0.id == id }) {
                                guard existing.registration == model.chatGPT.activeID, existing.tool == name, existing.arguments == call.arguments else { throw ActionFailure.message("This requestID belongs to a different payload or account.") }
                                output = existing.output
                            } else {
                                guard records.count < 1000, records.filter({ $0.phase == .pending }).count < 20 else { throw ActionFailure.message("The external action queue is full.") }
                                let record = MCPActionRecord(id: id, registration: model.chatGPT.activeID, client: client, tool: name, arguments: call.arguments, proposal: try JSONEncoder().encode(proposal))
                                try replace(records + [record]); output = record.output
                            }
                        }
                    } else {
                        let result = try await session.tools.execute(call, valid: valid)
                        guard valid() else { throw ActionFailure.message("Source access changed during the read. Its result was withheld.") }
                        output = (try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]) ?? ["result": result]
                    }
                }
            } else { throw ActionFailure.message("Unknown bridge method.") }
        } catch { output = ["error": String(error.localizedDescription.prefix(1000))] }
        return (try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
    func proposal(for record: MCPActionRecord) -> AssistantActionProposal? { try? JSONDecoder().decode(AssistantActionProposal.self, from: record.proposal) }
    func dismiss(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id && $0.phase == .pending }) else { return }
        var values = records; values[index].phase = .dismissed; values[index].result = "Declined in 3PO. Nothing was changed."
        do { try replace(values) } catch { self.error = error.localizedDescription }
    }
    func approve(_ id: UUID) async {
        guard enabled, let model, !model.storageOwnershipBlocked, !model.assistant.busy, !model.writing,
              let index = records.firstIndex(where: { $0.id == id && $0.phase == .pending }),
              let proposal = proposal(for: records[index]), records[index].registration == model.chatGPT.activeID else { error = "This action is unavailable or 3PO is busy. No change was attempted."; return }
        error = nil
        let captured = generation, currentScope = scope(model)
        var values = records; values[index].phase = .attempted
        do { try replace(values) } catch { self.error = "Could not save the action claim. Nothing was attempted."; return }
        let valid: NativeWriteValidity = { [weak self, weak model] in
            guard let self, let model else { return false }
            return self.enabled && self.generation == captured && !model.storageOwnershipBlocked && self.scope(model) == currentScope
        }
        do {
            let result = try await PAToolSession.performApproval(proposal, model: model, valid: valid)
            var completed = records; completed[index].phase = .completed; completed[index].result = result
            try replace(completed)
        } catch {
            var failed = records
            // A receipt persistence failure can follow a verified native save.
            // Only the writer's typed pre-save proof establishes no mutation.
            failed[index].phase = error is NativePreSaveFailure ? .failed : .uncertain
            failed[index].result = String(error.localizedDescription.prefix(1000))
            do { try replace(failed) } catch { self.error = "The action outcome could not be saved. Check the original item; do not retry it." }
        }
    }
}
