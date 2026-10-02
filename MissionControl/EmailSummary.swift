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
    static func verbatimEvidence(_ quote: String, body: String, subject: String) -> String? {
        guard !quote.isEmpty else { return nil }
        if body.contains(quote) || subject.contains(quote) { return quote }
        let words = quote.components(separatedBy:.whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let pattern = words.map(NSRegularExpression.escapedPattern(for:)).joined(separator:"\\s+")
        guard let regex = try? NSRegularExpression(pattern:pattern) else { return nil }
        for source in [body,subject] {
            let text = source as NSString
            if let match = regex.firstMatch(in:source,range:NSRange(location:0,length:text.length)) {
                let original = text.substring(with:match.range)
                if original.count <= 500 { return original }
            }
        }
        return nil
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
        let exactEvidence = verbatimEvidence(output.evidence,body:body,subject:message.subject)
        let supported = exactEvidence != nil
        guard output.evidence.isEmpty || supported, !output.attention || supported else { throw SummaryFailure.unsupportedEvidence }
        return .init(id: message.id, registration: registration, fingerprint: fingerprint(message), summary: output.summary, attention: output.attention, reason: output.reason, evidence: exactEvidence ?? "", messageReceived: message.received)
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
        return reason + " It was not saved."
    }
}

struct EmailSummaryRejection: Codable {
    var id: String
    var registration: String
    var fingerprint: String
    var received: Date
    var reason: String
    func matches(_ message: MailMessage, registration: String) -> Bool {
        self.registration == registration && id == message.id && fingerprint == EmailSummary.fingerprint(message)
    }
}
