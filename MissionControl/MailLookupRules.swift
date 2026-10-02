import Foundation

struct MailLookupPlan: Codable {
    var message: String
    var terms: [String]?
    var start: String?
    var end: String?
}
enum MailLookupRules {
    static func answerRequest(original: String) -> String {
        "Answer this original mail question using the newly retrieved search evidence: \(original). The app has already performed this bounded search. Explain the findings and remaining coverage; do not treat this as a request to operate Mail yourself."
    }
    static func requested(_ request: String) -> Bool {
        let value = request.lowercased()
        return value.range(of:#"\b(?:email|emails|mail|inbox)\b"#,options:.regularExpression) != nil && value.range(of:#"\b(?:find|search|old|earlier|last|when|what|look|continue)\b"#,options:.regularExpression) != nil
    }
    static func terms(_ plan: MailLookupPlan, request: String) throws -> [String] {
        guard let terms = plan.terms, !terms.isEmpty, terms.count <= 5, terms.allSatisfy({ !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.count >= 2 && $0.count <= 80 && !["email","emails","mail","inbox","find","search","old","earlier","last","the","from","to"].contains($0.lowercased()) && request.localizedCaseInsensitiveContains($0) }) else { throw ActionFailure.message("Please name a sender or subject keyword for the email search.") }
        return terms
    }
    static func matches(_ message: MailMessage, terms: [String]) -> Bool {
        terms.contains { message.subject.localizedCaseInsensitiveContains($0) || message.sender.localizedCaseInsensitiveContains($0) }
    }
}
