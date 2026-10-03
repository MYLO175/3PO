import Foundation

struct MailLookupPlan: Codable {
    var message: String
    var terms: [String]?
    var start: String?
    var end: String?
}
enum MailLookupRules {
    static func roles(_ request: String) -> Set<MailFolderRole> {
        let value = request.lowercased()
        var roles: Set<MailFolderRole> = []
        if value.range(of:#"\b(?:sent (?:mail|emails?|messages?|folder|mailbox)|(?:i|we) (?:have )?(?:sent|emailed))\b"#,options:.regularExpression) != nil { roles.insert(.sent) }
        if value.range(of:#"\barchiv(?:e|es|ed)\b"#,options:.regularExpression) != nil { roles.insert(.archive) }
        if value.range(of:#"\binbox\b"#,options:.regularExpression) != nil { roles.insert(.inbox) }
        return roles.isEmpty ? [.inbox,.sent,.archive] : roles
    }
    static func answerRequest(original: String) -> String {
        "Answer this original mail question using the newly retrieved search evidence: \(original). The app has already performed this bounded search. Explain the findings and remaining coverage; do not treat this as a request to operate Mail yourself."
    }
    static func requested(_ request: String) -> Bool {
        let value = request.lowercased()
        let mail = value.range(of:#"\b(?:email|emails|mail|inbox)\b"#,options:.regularExpression) != nil || value.range(of:#"\b(?:i|we) (?:have )?(?:sent|emailed)\b"#,options:.regularExpression) != nil
        return mail && value.range(of:#"\b(?:find|search|old|earlier|last|when|what|look|continue)\b"#,options:.regularExpression) != nil
    }
    static func terms(_ plan: MailLookupPlan, request: String) throws -> [String] {
        guard let terms = plan.terms, !terms.isEmpty, terms.count <= 5, terms.allSatisfy({ !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.count >= 2 && $0.count <= 80 && !["email","emails","mail","inbox","find","search","old","earlier","last","the","from","to","sent","archive","archived"].contains($0.lowercased()) && request.localizedCaseInsensitiveContains($0) }) else { throw ActionFailure.message("Please name a sender or subject keyword for the email search.") }
        return terms
    }
    static func matches(_ message: MailMessage, terms: [String]) -> Bool {
        terms.contains { term in message.subject.localizedCaseInsensitiveContains(term) || message.sender.localizedCaseInsensitiveContains(term) || (message.mailboxRole == .sent && (message.recipients ?? []).contains(where:{ $0.localizedCaseInsensitiveContains(term) })) }
    }
}
