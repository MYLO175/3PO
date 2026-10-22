import Foundation
import SwiftData

// Fictional ports around the actual MCP service, listener and durable repository.
// No production DashboardModel, provider or EventKit service is instantiated.
@MainActor final class DashboardModel {
    let container: ModelContainer?
    var storageOwnershipBlocked = false
    var chatGPT = Connection()
    var assistant = Assistant()
    var reviewStorageIdentity = "disposable-mcp-store"
    var writing = false
    init(_ container: ModelContainer) { self.container = container }
    struct Connection { var activeID = "fictional-registration" }
    struct Assistant {
        var contextEnabled = true
        var busy = false
        var excludedCalendars: Set<String> = []
        var excludedLists: Set<String> = []
    }
}
struct AssistantActionProposal: Codable {
    var id: UUID
    var toolName: String
    var arguments: String
    var snapshot: Data
    var outline: [String]
    var details: [String]
}
@MainActor final class PAToolSession {
    static var nativeWrites = 0
    static var failAfterSave = false
    init(model: DashboardModel, human: String, humanContext: String, topicID: UUID?, turnID: UUID) {}
    func execute(_ call: PAFunctionCall, valid: @escaping NativeWriteValidity) async throws -> String {
        precondition(valid())
        return "{\"events\":[{\"id\":\"fictional-event\",\"title\":\"Fictional review\"}]}"
    }
    func prepareMCPApproval(_ call: PAFunctionCall, requestID: UUID, valid: @escaping NativeWriteValidity) async throws -> AssistantActionProposal {
        // Make two clients contend at the real asynchronous preparation boundary.
        try await Task.sleep(for: .milliseconds(30))
        guard valid() else { throw CancellationError() }
        return .init(id: requestID, toolName: call.name, arguments: call.arguments, snapshot: Data(), outline: ["Fictional change"], details: ["No personal sources"])
    }
    static func performApproval(_ proposal: AssistantActionProposal, model: DashboardModel, valid: @escaping NativeWriteValidity) async throws -> String {
        precondition(valid())
        let bytes = try LocalRecordRepository(container: model.container!).read("externalMCPActions")!
        let records = try JSONDecoder().decode([MCPActionRecord].self, from: bytes)
        precondition(records.first(where: { $0.id == proposal.id })?.phase == .attempted, "A durable claim must precede the native writer")
        nativeWrites += 1
        if failAfterSave { throw PANativeActionUncertainty(operationKey: proposal.id.uuidString, message: "Fictional lost readback. Do not retry.") }
        return "Updated fictional event; readback verified."
    }
}

@main struct MCPBridgeServiceChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-service-" + UUID().uuidString)
        let file = directory.appendingPathComponent("connection.json")
        let preferences = "mcp-fixture-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: preferences)!
        defer { defaults.removePersistentDomain(forName: preferences); try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = DashboardModel(container)
        var bridge = MCPBridgeService(model: model, connectionFile: file, defaults: defaults)
        let network = URLSession(configuration: .ephemeral)
        defer { network.invalidateAndCancel() }
        func ready() async throws {
            for _ in 0..<100 {
                if bridge.status.hasPrefix("Ready") { return }
                if let error = bridge.error { preconditionFailure(error) }
                try await Task.sleep(for: .milliseconds(10))
            }
            preconditionFailure("Bridge did not start")
        }
        @Sendable func rpc(_ name: String, _ args: [String: Any], session: UUID = UUID(), origin: String? = nil, wrongToken: Bool = false) async throws -> (Int, [String: Any]) {
            let configuration = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: String]
            var request = URLRequest(url: URL(string: configuration["url"]!)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer " + (wrongToken ? "wrong" : configuration["token"]!), forHTTPHeaderField: "Authorization")
            if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["method": "tools/call", "session": session.uuidString, "client": "Fictional MCP host", "name": name, "arguments": args])
            let (bytes, response) = try await network.data(for: request)
            return ((response as! HTTPURLResponse).statusCode, try JSONSerialization.jsonObject(with: bytes) as! [String: Any])
        }
        func draft(_ id: UUID, title: String = "Fictional review") -> [String: Any] {
            ["requestID": id.uuidString, "operation": "create", "target": NSNull(), "destination": NSNull(), "title": title, "notes": NSNull(), "location": NSNull(), "start": "2026-10-23T15:00:00+01:00", "end": "2026-10-23T15:30:00+01:00", "allDay": false, "scope": NSNull(), "options": NSNull()]
        }
        bridge.setEnabled(true); try await ready()
        let info = try FileManager.default.attributesOfItem(atPath: file.path)
        precondition((info[.posixPermissions] as! NSNumber).intValue == 0o600)
        let unauthorized = try await rpc("read_reminders", [:], wrongToken: true)
        precondition(unauthorized.0 == 403)
        let browser = try await rpc("read_reminders", [:], origin: "https://untrusted.example")
        precondition(browser.0 == 400)
        let read = try await rpc("read_calendar", ["start": "2026-10-22", "end": "2026-10-23"])
        precondition(read.1["events"] != nil)
        let id = UUID(), args = draft(id)
        async let first = rpc("change_calendar", args)
        async let second = rpc("change_calendar", args)
        let results = try await [first, second]
        precondition(results.allSatisfy { $0.1["status"] as? String == "pending" })
        precondition(bridge.records.count == 1, "Contending clients must share one durable request")
        precondition(PAToolSession.nativeWrites == 0, "External tool calls can only prepare")
        let conflict = try await rpc("change_calendar", draft(id, title: "Different payload"))
        precondition(conflict.1["error"] != nil)
        let escalation = try await rpc("approve", ["requestID": id.uuidString])
        precondition(escalation.1["error"] != nil && PAToolSession.nativeWrites == 0)
        await bridge.approve(id)
        precondition(PAToolSession.nativeWrites == 1)
        let saved = try await rpc("action_status", ["requestID": id.uuidString])
        precondition(saved.1["status"] as? String == "completed" && saved.1["verified"] as? Bool == true)
        await bridge.approve(id)
        precondition(PAToolSession.nativeWrites == 1, "An applied action cannot be approved again")
        // Start a new connection to stay below the deliberately bounded session pool.
        bridge.setEnabled(false); bridge.setEnabled(true); try await ready()
        let uncertainID = UUID(), session = UUID()
        let pending = try await rpc("change_calendar", draft(uncertainID), session: session)
        precondition(pending.1["status"] as? String == "pending")
        PAToolSession.failAfterSave = true
        await bridge.approve(uncertainID)
        precondition(PAToolSession.nativeWrites == 2 && bridge.records.last?.phase == .uncertain)
        await bridge.approve(uncertainID)
        precondition(PAToolSession.nativeWrites == 2)
        bridge.setEnabled(false)
        precondition(!FileManager.default.fileExists(atPath: file.path), "Disabling revokes discovery")
        bridge = MCPBridgeService(model: model, connectionFile: file, defaults: defaults)
        bridge.setEnabled(true); try await ready()
        precondition(bridge.records.count == 2 && bridge.records.last?.phase == .uncertain)
        await bridge.approve(uncertainID)
        precondition(PAToolSession.nativeWrites == 2, "Restarting must not replay an uncertain save")
        bridge.setEnabled(false)
        let corrupt = Data("broken fictional history".utf8)
        try LocalRecordRepository(container: container).write(["externalMCPActions": corrupt])
        bridge = MCPBridgeService(model: model, connectionFile: file, defaults: defaults)
        bridge.setEnabled(true)
        precondition(!bridge.enabled && bridge.error != nil)
        let retained = try LocalRecordRepository(container: container).read("externalMCPActions")
        precondition(retained == corrupt, "Unreadable history must never be overwritten")
        print("MCP service, real loopback transport, durable claims, concurrency and recovery checks passed")
    }
}
