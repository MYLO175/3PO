import Foundation
import CryptoKit

struct EmailSummary: Codable, Identifiable {
    var id: String
    var registration: String
    var fingerprint: String
    var summary: String
    var attention: Bool
    var reason: String
    var evidence: String
    var created = Date.now
    static func fingerprint(_ message: MailMessage) -> String {
        let fields = [message.id, message.internetMessageID, message.sender, message.subject, message.received.ISO8601Format()]
        return SHA256.hash(data: Data(fields.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func decode(_ response: String, message: MailMessage, body: String, registration: String) throws -> EmailSummary {
        struct Output: Decodable { let summary: String; let attention: Bool; let reason: String; let evidence: String }
        let output = try JSONDecoder().decode(Output.self, from: Data(response.utf8))
        guard !output.summary.isEmpty, output.summary.count <= 1200, output.reason.count <= 600, output.evidence.count <= 500 else { throw SummaryFailure.invalid }
        let supported = !output.evidence.isEmpty && (body.contains(output.evidence) || message.subject.contains(output.evidence))
        guard output.evidence.isEmpty || supported, !output.attention || supported else { throw SummaryFailure.invalid }
        return .init(id: message.id, registration: registration, fingerprint: fingerprint(message), summary: output.summary, attention: output.attention, reason: output.reason, evidence: output.evidence)
    }
}
enum SummaryFailure: LocalizedError {
    case invalid
    var errorDescription: String? { "Summary output lacked valid source evidence. It was not saved; processing is paused." }
}
