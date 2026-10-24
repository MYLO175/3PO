import Foundation
import Darwin

@main struct GraphitiProcessChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("graphiti-transport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("fixture.py")
        try #"""
import json, os, signal, sys, time
request = json.loads(sys.stdin.readline())
mode = request['mode']
def emit(value):
    print(json.dumps(value), flush=True)
def result(value):
    emit({'type':'result', 'result':value})
if mode == 'echo':
    result({'value':request['value'], 'pid':os.getpid(), 'secret':os.environ.get('OPENAI_API_KEY'), 'telemetry':os.environ.get('GRAPHITI_TELEMETRY_ENABLED')})
elif mode in ('llm', 'blocked_callback', 'duplicate'):
    for index in range(2 if mode != 'blocked_callback' else 1):
        emit({'type':'llm_request','id':str(index if mode != 'duplicate' else 0),'name':'ExtractEntities','messages':[{'role':'system','content':'Fictional fixture only.'},{'role':'user','content':'Alex studies art.'}],'schema':{'type':'object','properties':{'entities':{'type':'array','items':{'type':'string'}}}}})
        response = json.loads(sys.stdin.readline())
        assert response['type'] == 'llm_response'
        assert response['id'] == str(index)
        assert response['result'] == {'entities':['Alex']}
    result({'ok':True})
elif mode == 'bad_callback':
    emit({'type':'llm_request','id':'bad','name':'ExtractEntities','messages':[{'role':'developer','content':'Fictional'}],'schema':{'type':'object','properties':{}}})
elif mode == 'stderr':
    sys.stderr.write('private fixture stderr' * 100000)
    sys.stderr.flush()
    result({'ok':True})
elif mode == 'bad_json':
    print('not json private fixture', flush=True)
elif mode == 'unknown':
    emit({'type':'unknown','content':'private fixture'})
elif mode == 'error':
    emit({'type':'error','message':'private fixture error'})
elif mode == 'missing_result':
    pass
elif mode == 'oversize':
    print('x' * (2*1024*1024+1), flush=True)
elif mode == 'trailing':
    result({'ok':True})
    print('extra', flush=True)
elif mode == 'partial':
    sys.stdout.write('{"type":"result","result":{}}')
elif mode == 'result_then_fail':
    result({'ok':True})
    sys.exit(3)
elif mode in ('sleep', 'ignore_term'):
    if mode == 'ignore_term': signal.signal(signal.SIGTERM, signal.SIG_IGN)
    with open(request['pid_path'], 'w') as f: f.write(str(os.getpid()))
    time.sleep(30)
"""#.write(to: helper, atomically: true, encoding: .utf8)
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        var callbackCount = 0
        func run(_ mode: String, timeout: TimeInterval = 3, extra: [String: Any] = [:]) async throws -> [String: Any] {
            var request = extra
            request["mode"] = mode
            return try await GraphitiProcess.run(python: python, helper: helper, request: request, timeout: timeout) { message in
                callbackCount += 1
                precondition(message["name"] as? String == "ExtractEntities")
                return ["entities": ["Alex"]]
            }
        }
        setenv("OPENAI_API_KEY", "fictional-test-secret", 1)
        defer { unsetenv("OPENAI_API_KEY") }
        let echo = try await run("echo", extra: ["value": "Fictional fixture only."])
        precondition(echo["value"] as? String == "Fictional fixture only.")
        precondition(echo["secret"] is NSNull)
        precondition(echo["telemetry"] as? String == "false")
        let llmResult = try await run("llm")
        precondition(llmResult["ok"] as? Bool == true)
        precondition(callbackCount == 2)
        let stderrResult = try await run("stderr")
        precondition(stderrResult["ok"] as? Bool == true)
        for mode in ["bad_json", "bad_callback", "unknown", "error", "missing_result", "oversize", "trailing", "partial", "result_then_fail", "duplicate"] {
            do { _ = try await run(mode); fatalError("Expected rejection: \(mode)") }
            catch { precondition(!error.localizedDescription.contains("private fixture")) }
        }
        do {
            _ = try await run("echo", extra: ["value": String(repeating: "x", count: 2 * 1024 * 1024)])
            fatalError("Expected oversized input rejection")
        } catch GraphitiProcess.Failure.invalidRequest {}
        let pidPath = root.appendingPathComponent("pid")
        for mode in ["sleep", "ignore_term"] {
            let start = ProcessInfo.processInfo.systemUptime
            do { _ = try await run(mode, timeout: 0.25, extra: ["pid_path": pidPath.path]); fatalError("Expected timeout") }
            catch GraphitiProcess.Failure.timedOut {} 
            precondition(ProcessInfo.processInfo.systemUptime - start < 4)
            if let pid = Int32(try String(contentsOf: pidPath, encoding: .utf8)) {
                try await Task.sleep(nanoseconds: 100_000_000)
                precondition(kill(pid, 0) == -1 && errno == ESRCH)
            } else { fatalError("Missing helper process identity") }
        }
        let cancelled = Task { @MainActor in try await run("sleep", extra: ["pid_path": pidPath.path]) }
        try await Task.sleep(nanoseconds: 200_000_000)
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Expected cancellation") }
        catch is CancellationError {}
        let pid = Int32(try String(contentsOf: pidPath, encoding: .utf8))!
        precondition(kill(pid, 0) == -1 && errno == ESRCH)
        var inferenceCancelled = false
        do {
            _ = try await GraphitiProcess.run(python: python, helper: helper, request: ["mode": "blocked_callback"], timeout: 0.25) { _ in
                do { try await Task.sleep(nanoseconds: 5_000_000_000) }
                catch { inferenceCancelled = true; throw error }
                return [:]
            }
            fatalError("Expected timeout during inference")
        } catch GraphitiProcess.Failure.timedOut {}
        precondition(inferenceCancelled)
        do {
            _ = try await GraphitiProcess.run(python: python, helper: helper, request: ["mode": "llm"]) { _ in
                throw NSError(domain: "private fixture", code: 1)
            }
            fatalError("Expected inference error")
        } catch GraphitiProcess.Failure.inferenceFailed {}
        let normalized = try GraphitiProcess.normalizeSchema([
            "type": "object", "title": "ExtractEntities", "properties": [
                "entities": ["type": "array", "items": ["$ref": "#/$defs/Entity"], "default": []],
                "summary": ["anyOf": [["type": "string"], ["type": "null"]], "default": NSNull()]
            ],
            "$defs": ["Entity": ["type": "object", "properties": ["name": ["type": "string"], "kind": ["type": "string", "enum": ["person", "project"]]], "required": ["name"]]]
        ])
        precondition(normalized["required"] as? [String] == ["entities", "summary"])
        precondition(normalized["additionalProperties"] as? Bool == false)
        let props = normalized["properties"] as! [String: [String: Any]]
        precondition(props["entities"]?["default"] == nil && props["entities"]?["type"] as? String == "array")
        precondition((props["summary"]?["anyOf"] as? [[String: Any]])?.count == 2)
        let entity = (normalized["$defs"] as! [String: [String: Any]])["Entity"]!
        precondition(entity["required"] as? [String] == ["kind", "name"])
        precondition(entity["additionalProperties"] as? Bool == false)
        for unsupported: [String: Any] in [["type": "object", "additionalProperties": ["type": "string"]], ["type": "array", "items": ["type": "string"]], ["type": "object", "properties": [:], "additionalProperties": true]] {
            do { _ = try GraphitiProcess.normalizeSchema(unsupported); fatalError("Expected schema rejection") }
            catch GraphitiProcess.Failure.invalidRequest {}
        }
        print("Graphiti process checks passed: isolated environment, round trips, inference callbacks, stderr draining, protocol/size errors, child termination, timeout, cancellation and strict schema normalization.")
    }
}
