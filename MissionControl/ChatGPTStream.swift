import Foundation

struct ChatGPTStream {
    enum Failure: Error { case invalid, oversized, failed(String), incomplete, interrupted }
    private(set) var text = ""
    private var completed = false
    private var eventData: [String] = []
    private var byteLine = Data()
    private var sawCR = false
    // SSE framing uses ASCII CR/LF, never Unicode separators inside JSON strings.
    mutating func byte(_ value: UInt8) throws -> String? {
        if value == 10 && sawCR { sawCR = false; return nil }
        if value == 10 || value == 13 {
            sawCR = value == 13
            guard let text = String(data:byteLine,encoding:.utf8) else { throw Failure.invalid }
            byteLine.removeAll(keepingCapacity:true)
            return try line(text)
        }
        sawCR = false
        byteLine.append(value)
        guard byteLine.count <= 1_000_000 else { throw Failure.oversized }
        return nil
    }
    mutating func finishBytes() throws -> String {
        if !byteLine.isEmpty {
            guard let text = String(data:byteLine,encoding:.utf8) else { throw Failure.invalid }
            byteLine.removeAll()
            _ = try line(text)
        }
        return try finish()
    }
    mutating func line(_ line: String) throws -> String? {
        if line.isEmpty { return try consume() }
        guard line.hasPrefix("data:") else { return nil }
        eventData.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        let payload = eventData.joined(separator: "\n")
        guard payload.utf8.count <= 1_000_000 else { throw Failure.oversized }
        if payload == "[DONE]" || (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) != nil { return try consume() }
        return nil
    }
    private mutating func consume() throws -> String? {
        guard !eventData.isEmpty else { return nil }
        let payload = eventData.joined(separator: "\n"); eventData = []
        if payload == "[DONE]" { return nil }
        guard let event = (try? JSONSerialization.jsonObject(with:Data(payload.utf8))) as? [String:Any], let type = event["type"] as? String else { throw Failure.invalid }
        switch type {
        case "response.output_text.delta":
            guard !completed, let delta = event["delta"] as? String else { throw Failure.invalid }
            text += delta; return delta
        case "response.completed": completed = true
        case "response.failed", "error":
            let root = event["response"] as? [String:Any] ?? event
            let error = root["error"] as? [String:Any] ?? root
            throw Failure.failed(error["code"] as? String ?? "response_failed")
        case "response.incomplete": throw Failure.incomplete
        default: break
        }
        return nil
    }
    mutating func finish() throws -> String {
        _ = try consume()
        guard completed, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.interrupted }
        return text
    }
}
