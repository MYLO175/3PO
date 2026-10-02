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
    var bodyFingerprint: String? = nil
    var bodyCheckedAt: Date? = nil
    var messageReceived: Date? = nil
    static func fingerprintBody(_ body: String) -> String {
        SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func fingerprint(_ message: MailMessage) -> String {
        let fields = [message.id, message.internetMessageID, message.sender, message.subject, message.received.ISO8601Format()]
        return SHA256.hash(data: Data(fields.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func decode(_ response: String, message: MailMessage, body: String, registration: String) throws -> EmailSummary {
        struct Output: Decodable { let summary: String; let attention: Bool; let reason: String; let evidence: String }
        let output = try JSONDecoder().decode(Output.self, from: Data(response.utf8))
        guard !output.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SummaryFailure.emptySummary }
        guard output.summary.count <= 1200, output.reason.count <= 600, output.evidence.count <= 500 else { throw SummaryFailure.tooLong }
        guard !output.attention || !output.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SummaryFailure.missingReason }
        let supported = !output.evidence.isEmpty && (body.contains(output.evidence) || message.subject.contains(output.evidence))
        guard output.evidence.isEmpty || supported, !output.attention || supported else { throw SummaryFailure.unsupportedEvidence }
        return .init(id: message.id, registration: registration, fingerprint: fingerprint(message), summary: output.summary, attention: output.attention, reason: output.reason, evidence: output.evidence, messageReceived: message.received)
    }
}
enum SummaryFailure: LocalizedError {
    case invalid, emptySummary, tooLong, missingReason, unsupportedEvidence
    var errorDescription: String? {
        let reason: String
        switch self {
        case .invalid: reason = "AI output or storage was invalid."
        case .emptySummary: reason = "The model returned an empty summary."
        case .tooLong: reason = "The model exceeded the summary, reason or quote length limit."
        case .missingReason: reason = "The attention item had no explanation."
        case .unsupportedEvidence: reason = "The model's quote did not exactly match the supplied email."
        }
        return reason + " It was not saved; processing is paused."
    }
}
