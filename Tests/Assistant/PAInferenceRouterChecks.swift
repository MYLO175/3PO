import Foundation

@MainActor private final class FictionalBackend: PAInferenceConnection {
    var activeID: String
    var selectedModel: String
    var busy = false, usagePaused = false, inferenceVerified = true, hasSession = true
    let overridesTypedResult: Bool
    private(set) var calls: [(kind: String, model: String?, effort: String?)] = []
    init(activeID: String, selectedModel: String, overridesTypedResult: Bool = false) {
        self.activeID = activeID; self.selectedModel = selectedModel; self.overridesTypedResult = overridesTypedResult
    }
    func streamResponse(input: [[String: String]], instructions: String, model: String?, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> String {
        calls.append(("stream", model, effort)); return "{}"
    }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        calls.append(("tool", model, nil)); return .init(text: "", output: [], calls: [])
    }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        calls.append(("tool", model, effort)); return .init(text: "", output: [], calls: [])
    }
    func typedResult(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, effort: String, purpose: AIRequestPurpose) async throws -> PAResponse {
        guard overridesTypedResult else {
            return try await toolResponse(input: input, instructions: instructions, tools: tools, model: model, effort: effort, purpose: purpose) { _ in }
        }
        calls.append(("typed", model, effort)); return .init(text: "", output: [], calls: [])
    }
}

/// A backend relying on the protocol's default typedResult.
@MainActor private final class DefaultTypedBackend: PAInferenceConnection {
    let activeID = "fictional-account", selectedModel = "fictional-gpt"
    let busy = false, usagePaused = false, inferenceVerified = true, hasSession = true
    private(set) var toolEfforts: [String] = []
    func streamResponse(input: [[String: String]], instructions: String, model: String?, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> String { "" }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        toolEfforts.append("none"); return .init(text: "", output: [], calls: [])
    }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        toolEfforts.append(effort); return .init(text: "", output: [], calls: [])
    }
}

@main struct Checks {
    @MainActor static func main() async throws {
        let suite = "missioncontrol-router-checks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let claudeModel = PAProvider.claudeModelTag + "claude-sonnet-5-5"

        assert(PAProvider(model: claudeModel) == .claudeCode)
        assert(PAProvider(model: "gpt-6.1-sol") == .chatGPT)
        assert(PAProvider(model: "claude-sonnet-5-5") == .chatGPT, "only the explicit tag routes to Claude")

        // Without a Claude backend, behaviour is exactly the ChatGPT connection's.
        let chatGPT = FictionalBackend(activeID: "fictional-account", selectedModel: "fictional-gpt")
        defaults.set(PAProvider.claudeCode.rawValue, forKey: PAInferenceRouter.Keys.provider)
        let plain = PAInferenceRouter(chatGPT: chatGPT, defaults: defaults)
        assert(plain.provider == .chatGPT, "a stored Claude choice is ignored when no Claude backend exists")
        assert(plain.activeID == "fictional-account" && plain.selectedModel == "fictional-gpt")
        do { try plain.select(.claudeCode); assertionFailure("Claude must be unavailable") }
        catch let error as PAInferenceRouteError { assert(error == .providerUnavailable(.claudeCode)) }
        do { _ = try await plain.toolResponse(input: [], instructions: "", tools: [], model: claudeModel, purpose: .conversation) { _ in }; assertionFailure("Claude model must not reach ChatGPT") }
        catch let error as PAInferenceRouteError { assert(error == .providerUnavailable(.claudeCode)) }
        assert(chatGPT.calls.isEmpty)
        defaults.removeObject(forKey: PAInferenceRouter.Keys.provider)

        // Effort is forwarded rather than dropped; nil model means the current selection.
        _ = try await plain.toolResponse(input: [], instructions: "", tools: [], model: "fictional-gpt", effort: "high", purpose: .conversation) { _ in }
        _ = try await plain.streamResponse(input: [], instructions: "", model: nil, effort: "low", purpose: .intentCheck) { _ in }
        assert(chatGPT.calls.map(\.kind) == ["tool", "stream"] && chatGPT.calls[0].effort == "high" && chatGPT.calls[1].effort == "low")

        // Selecting Claude keeps the workspace registration and persists the choice.
        let claude = FictionalBackend(activeID: "", selectedModel: claudeModel, overridesTypedResult: true)
        let router = PAInferenceRouter(chatGPT: chatGPT, claude: claude, defaults: defaults)
        assert(router.provider == .chatGPT && router.activeID == "fictional-account")
        try router.select(.claudeCode)
        assert(router.provider == .claudeCode && router.activeID == "fictional-account" && router.pinnedRegistration == "fictional-account")
        assert(router.selectedModel == claudeModel)
        let reopened = PAInferenceRouter(chatGPT: chatGPT, claude: claude, defaults: defaults)
        assert(reopened.provider == .claudeCode && reopened.activeID == "fictional-account", "the choice survives reopening")

        // Captured models keep their provider; typed results reach a provider's own implementation.
        _ = try await router.toolResponse(input: [], instructions: "", tools: [], model: "fictional-gpt", purpose: .conversation) { _ in }
        _ = try await router.typedResult(input: [], instructions: "", tools: [], model: claudeModel, effort: "medium", purpose: .brief)
        _ = try await router.streamResponse(input: [], instructions: "", model: nil, effort: "medium", purpose: .intentCheck) { _ in }
        assert(chatGPT.calls.count == 3 && chatGPT.calls[2].model == "fictional-gpt")
        assert(claude.calls.map(\.kind) == ["typed", "stream"])

        // State follows the selected provider; busy covers both backends.
        claude.usagePaused = true
        assert(router.usagePaused && !plain.usagePaused)
        claude.usagePaused = false
        chatGPT.busy = true; assert(router.busy); chatGPT.busy = false
        claude.busy = true; assert(router.busy && !plain.busy); claude.busy = false

        // ChatGPT may not finish captured work under a different account while Claude owns the workspace.
        chatGPT.activeID = "other-fictional-account"
        assert(router.activeID == "fictional-account")
        do { _ = try await router.toolResponse(input: [], instructions: "", tools: [], model: "fictional-gpt", purpose: .conversation) { _ in }; assertionFailure("account mismatch must refuse") }
        catch let error as PAInferenceRouteError { assert(error == .accountMismatch) }
        assert(chatGPT.calls.count == 3, "no request reached ChatGPT")
        try router.select(.chatGPT)
        assert(router.activeID == "other-fictional-account", "switching back follows ChatGPT's account, as today")

        // A Claude-only workspace receives one stable local registration.
        let fresh = FictionalBackend(activeID: "", selectedModel: "fictional-gpt")
        let isolated = UserDefaults(suiteName: suite + "-fresh")!
        defer { isolated.removePersistentDomain(forName: suite + "-fresh") }
        let local = PAInferenceRouter(chatGPT: fresh, claude: claude, defaults: isolated)
        try local.select(.claudeCode)
        let pinned = local.activeID
        assert(pinned.hasPrefix("local-") && pinned.count > 20)
        try local.select(.chatGPT); try local.select(.claudeCode)
        assert(local.activeID == pinned)

        // The protocol default sends a typed result as one effort-carrying tool request.
        let defaulted = DefaultTypedBackend()
        _ = try await defaulted.typedResult(input: [], instructions: "", tools: [], model: "fictional-gpt", effort: "medium", purpose: .learning)
        assert(defaulted.toolEfforts == ["medium"])
        print("PAInferenceRouter checks passed")
    }
}
