#if DEBUG
import Foundation

/// Two bounded subscription requests over invented rules and emails, with a private policy store.
@MainActor enum ReviewGuidanceModelEvaluation {
    static func run(_ model: DashboardModel) async throws -> [String: Any] {
        let owner = model.inference.activeID, selected = model.inference.selectedModel
        guard !owner.isEmpty, model.inference.inferenceVerified, !model.inference.usagePaused else { throw SummaryFailure.invalid }
        func validate() throws {
            try Task.checkCancellation()
            guard owner == model.inference.activeID, selected == model.inference.selectedModel else { throw SummaryFailure.invalid }
        }
        var data: Data?
        let store = ReviewPolicyStore(load: { data }, persist: { next, expected in
            guard expected == data else { throw SummaryFailure.invalid }; data = next
        })
        let base = ReviewPolicyRules.defaultText + "\n\n" + String(repeating: "Preserve each preference's specific scope and all conditions when considering new information. ", count: 45)
        guard store.save(base, registration: owner, expected: store.policy(owner)) else { throw SummaryFailure.invalid }
        let rules = [
            "Keep routine Oakwash laundry booking confirmations quiet. Significant new obligations or booking problems still matter.",
            "Routine ShopCo new-device login notices can stay quiet. Suspicious or unauthorised activity warnings still matter.",
            "Oakwash routine reservation confirmations do not need my attention.",
            "Coding assessment results are important to me even when no action or reply is requested."
        ].map { text -> ReviewGuidancePreference in
            let id = UUID().uuidString
            return .init(dependency: .init(id: id, fingerprint: MemoryDependencyRules.fingerprint(["id": id, "text": text])), text: text)
        }
        let pending = store.policy(owner, preferences: rules)
        let input = String(decoding: try JSONSerialization.data(withJSONObject: ["guidance": pending.text], options: .sortedKeys), as: UTF8.self)
        let result = try await model.inference.toolResponse(input: [["role": "user", "content": input]], instructions: ReviewGuidanceRules.instructions,
            tools: ReviewGuidanceRules.tools, model: selected, purpose: .diagnostic) { _ in }
        try validate()
        guard result.calls.count == 1, let call = result.calls.first,
              (call.namespace == "pa" && call.name == ReviewGuidanceRules.toolName) || (call.namespace == nil && call.name == "pa." + ReviewGuidanceRules.toolName) else { throw SummaryFailure.invalid }
        let text = try ReviewGuidanceRules.decode(call.arguments)
        try Data(call.arguments.utf8).write(to: EvaluationOutput.url("/tmp/3po-review-guidance-fictional-synthesis.json"), options: .atomic)
        guard store.save(text, registration: owner, expected: pending, preferences: rules, consolidate: true) else { throw SummaryFailure.invalid }
        let guide = store.policy(owner, preferences: rules)
        let cases = [
            ("routine", "Oakwash <bookings@example.invalid>", "Laundry reservation confirmed", "Your routine Oakwash laundry booking is confirmed. No action is required."),
            ("suspicious", "ShopCo <security@example.invalid>", "Suspicious sign-in blocked", "We detected suspicious unauthorised activity. Please secure your ShopCo account now by reviewing your security settings."),
            ("results", "Assessment portal <results@example.invalid>", "Your coding assessment results", "Your coding assessment results are ready to read. No action or reply is requested.")
        ]
        let decisionInput: [String: Any] = ["reviewPolicy": guide.input, "timezone": "Europe/London", "emails": cases.map {
            ["id": $0.0, "sender": $0.1, "subject": $0.2, "body": $0.3, "received": Date.now.ISO8601Format(), "replied": false] as [String: Any]
        }]
        var messages: [String: MailMessage] = [:]
        for entry in cases {
            let fields: [String: Any] = ["id": entry.0, "accountID": "fictional-mail", "account": "Fictional", "messageID": 1, "internetMessageID": entry.0 + "@example.invalid", "sender": entry.1, "subject": entry.2, "received": Date.now.ISO8601Format(), "unread": true, "replied": false, "flagged": false]
            messages[entry.0] = try JSONDecoder().decode(MailMessage.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        let response = try await model.inference.streamResponse(input: [["role": "user", "content": String(decoding: JSONSerialization.data(withJSONObject: decisionInput, options: .sortedKeys), as: UTF8.self)]],
            instructions: EmailSummary.assessmentInstructions + " " + EmailRelevanceRules.instructions + " " + ReviewPolicyRules.instructions + " Assess each invented email independently using the one complete guide. No other personal facts are supplied. Return ONLY {assessments:[{id:exact supplied ID,assessment:the normal assessment object}]}, one row for each email.",
            model: selected, purpose: .diagnostic) { _ in }
        try validate()
        try Data(response.utf8).write(to: EvaluationOutput.url("/tmp/3po-review-guidance-fictional-decisions.json"), options: .atomic)
        guard let object = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any],
              let rows = object["assessments"] as? [[String: Any]], rows.count == cases.count else { throw SummaryFailure.invalid }
        var decisions: [String: EmailSummary] = [:]
        for row in rows {
            guard let id = row["id"] as? String, let entry = cases.first(where: { $0.0 == id }), let assessment = row["assessment"], decisions[id] == nil else { throw SummaryFailure.invalid }
            guard let message = messages[id] else { throw SummaryFailure.invalid }
            decisions[id] = try EmailSummary.decode(String(decoding: JSONSerialization.data(withJSONObject: assessment), as: UTF8.self), message: message, body: entry.3, registration: owner, reviewPolicy: guide)
        }
        let checks = [
            "synthesis consumes the full guide beyond character 4000": pending.text.count > 4000 && input.contains(rules.last!.text),
            "one typed synthesis produces one current persisted guide": guide.text == text && !store.needsConsolidation(owner, preferences: rules),
            "routine laundry stays quiet": decisions["routine"]?.attention == false && decisions["routine"]?.worthReading == false,
            "security exception remains actionable": decisions["suspicious"]?.attention == true,
            "positive results preference supports exact policy relevance": decisions["results"]?.worthReading == true && decisions["results"]?.attention == false && decisions["results"]?.policyRelevance != nil,
            "decisions require no parallel feedback or interpretation": decisionInput["reviewFeedback"] == nil && decisionInput["sharedMemory"] == nil && decisionInput["learnedGuidance"] == nil
        ]
        return ["completed": Date.now.ISO8601Format(), "model": selected, "requests": 2, "passed": checks.values.filter { $0 }.count, "total": checks.count, "checks": checks,
                "boundary": "Production consolidation prompt/decoder and email decision contracts, two configured requests, invented rules/emails, private policy bytes. No personal source reads, app policy writes, native actions or retry."]
    }
}
#endif
