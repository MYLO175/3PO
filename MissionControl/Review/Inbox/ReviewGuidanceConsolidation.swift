import Foundation

extension EmailSummaryService {
    /// One owned synthesis after conversation learning. Until it succeeds, all current rules
    /// remain together in the effective guide; failure never drops new feedback.
    func consolidateReviewGuidance(_ model: DashboardModel, request: HeartbeatChildRequest,
                                  infer: ((String) async throws -> PAResponse)? = nil) async throws -> HeartbeatLearningResult {
        try request.validate()
        let registration = request.registration
        let memory = model.assistant.memory
        guard memory.enabled, memory.learningEnabled, !model.assistant.hasDraft, !model.assistant.busy, !busy else {
            return .init(detail: "Review guidance is waiting for idle permitted memory.", skipped: true)
        }
        guard reviewPolicies.writable else {
            return .init(failure: reviewPolicies.error ?? "Review guidance storage is unavailable.", detail: "Saved guidance is preserved.", skipped: false)
        }
        let preferences = guidancePreferences(registration)
        guard reviewPolicies.needsConsolidation(registration, preferences: preferences) else {
            return .init(detail: "Review guidance is current.", skipped: true)
        }
        let captured = policy(registration)
        guard ReviewPolicyRules.validText(captured.text) else {
            return .init(failure: "Review guidance exceeds the supported document size. Edit it before the next assessment; no preferences were discarded.", detail: "Review guidance is retained.", skipped: false)
        }
        let selectedModel = model.inference.selectedModel
        let permission = memory.useRevision, controls = memory.controlsRevision
        busy = true
        defer { busy = false }
        do {
            try request.validate(); try request.claim()
            let input = String(decoding: try JSONSerialization.data(withJSONObject: ["guidance": captured.text], options: .sortedKeys), as: UTF8.self)
            let result: PAResponse
            if let infer { result = try await infer(input) }
            else {
                result = try await model.inference.typedResult(input: [["role": "user", "content": input]], instructions: ReviewGuidanceRules.instructions,
                    tools: ReviewGuidanceRules.tools, model: selectedModel, effort: "medium", purpose: .learning)
            }
            try Task.checkCancellation(); try request.validate()
            guard registration == model.inference.activeID, memory.enabled, memory.learningEnabled,
                  permission == memory.useRevision, controls == memory.controlsRevision,
                  selectedModel == model.inference.selectedModel, !model.assistant.busy, !model.assistant.hasDraft,
                  policyAvailable(captured), result.calls.count == 1, let call = result.calls.first,
                  (call.namespace == "pa" && call.name == ReviewGuidanceRules.toolName) ||
                  (call.namespace == nil && call.name == "pa." + ReviewGuidanceRules.toolName) else { throw SummaryFailure.invalid }
            let text = try ReviewGuidanceRules.decode(call.arguments)
            guard reviewPolicies.save(text, registration: registration, expected: captured, preferences: preferences, consolidate: true),
                  policy(registration).text == text else { throw SummaryFailure.invalid }
            return .init(detail: "Review guidance consolidated into one document.", skipped: false)
        } catch is CancellationError { throw CancellationError() }
        catch is HeartbeatBudgetExhausted { throw HeartbeatBudgetExhausted() }
        catch {
            return .init(failure: "Review guidance could not be consolidated. Existing guidance and all new learned rules remain available for the next heartbeat.", detail: "Review guidance is retained.", skipped: false)
        }
    }
}
