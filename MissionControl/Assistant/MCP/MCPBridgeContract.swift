import Foundation

/// Only this explicit subset of the in-app tools crosses the external boundary.
enum MCPBridgeContract {
    static let reads: Set<String> = ["read_calendar", "read_reminders", "read_item_details"]
    static let writes: Set<String> = ["change_calendar", "change_reminder"]
    // A provenance sentinel for the existing concrete-approval executor. It is
    // never accepted from a client and never authorises execution by itself.
    static let approvalEvidence = "Approve the concrete external MCP action shown in 3PO."
    static var definitions: [[String: Any]] {
        let native = PAToolProtocol.tools.first?["tools"] as? [[String: Any]] ?? []
        var result = native.compactMap { definition -> [String: Any]? in
            guard let name = definition["name"] as? String, reads.contains(name) || writes.contains(name),
                  var schema = definition["parameters"] as? [String: Any] else { return nil }
            var description = definition["description"] as? String ?? ""
            if writes.contains(name) {
                var properties = schema["properties"] as! [String: [String: Any]]
                properties.removeValue(forKey: "authorization")
                properties["requestID"] = ["type": "string", "description": "A new UUID for this intended action. Reuse it for an identical submission or status check. Never replace an uncertain request with a new UUID to retry it."]
                schema["properties"] = properties
                schema["required"] = properties.keys.sorted()
                description = "Submit a concrete change for human approval in 3PO Settings > External assistants. This does NOT save it. Check action_status with the same requestID after approval; claim success only for status completed. " + description
            }
            return ["name": name, "description": description, "inputSchema": schema,
                    "annotations": ["readOnlyHint": reads.contains(name), "destructiveHint": writes.contains(name), "openWorldHint": false]]
        }
        result.append(["name": "action_status", "description": "Check a previously submitted external action by requestID. Pending needs human approval in 3PO. Attempted or uncertain must never be retried. Only completed confirms a verified save.",
                       "inputSchema": ["type": "object", "properties": ["requestID": ["type": "string"]], "required": ["requestID"], "additionalProperties": false],
                       "annotations": ["readOnlyHint": true, "openWorldHint": false]])
        return result
    }
    static func call(name: String, arguments: [String: Any]) throws -> PAFunctionCall {
        guard reads.contains(name) || writes.contains(name) else { throw ActionFailure.message("This tool is not exposed to external assistants.") }
        var args = arguments
        if writes.contains(name) {
            guard let token = args.removeValue(forKey: "requestID") as? String, UUID(uuidString: token) != nil else { throw ActionFailure.message("Supply a valid requestID UUID for this intended action.") }
            guard args["authorization"] == nil else { throw ActionFailure.message("External callers cannot supply human approval.") }
            args["authorization"] = approvalEvidence
        }
        let data = try JSONSerialization.data(withJSONObject: args, options: [.sortedKeys])
        guard data.count <= 64_000 else { throw ActionFailure.message("The external tool arguments are too large.") }
        let call = PAFunctionCall(id: UUID().uuidString, name: name, namespace: "pa", arguments: String(decoding: data, as: UTF8.self))
        _ = try PAToolProtocol.arguments(call)
        return call
    }
}

struct MCPActionRecord: Codable, Identifiable {
    enum Phase: String, Codable { case pending, attempted, completed, failed, dismissed, uncertain }
    var id: UUID
    var registration: String
    var client: String
    var tool: String
    var arguments: String
    var proposal: Data
    var created = Date.now
    var phase: Phase = .pending
    var result: String?
    var output: [String: Any] {
        ["requestID": id.uuidString, "status": phase.rawValue, "verified": phase == .completed,
         "result": result ?? (phase == .pending ? "Review this action in 3PO Settings > External assistants. No change has been made." : "Check the original item before continuing; do not repeat this operation.")]
    }
}
