import Foundation
import Observation

/// The subscription transport serving a request. Captured model strings carry it,
/// so a job keeps the provider it started with after the human switches.
enum PAProvider: String, CaseIterable, Sendable {
    case chatGPT = "chatgpt"
    case claudeCode = "claude-code"
    static let claudeModelTag = "claude-code:"
    init(model: String) { self = model.hasPrefix(Self.claudeModelTag) ? .claudeCode : .chatGPT }
    var displayName: String { self == .chatGPT ? "ChatGPT" : "Claude" }
}

enum PAInferenceRouteError: LocalizedError, Equatable {
    case providerUnavailable(PAProvider)
    case accountMismatch
    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let provider): "\(provider.displayName) is not available in this build; no request was sent."
        case .accountMismatch: "The selected ChatGPT account differs from the workspace Claude is using; no request was sent."
        }
    }
}

/// Routes each request to the provider of its captured model while reporting one
/// workspace registration. That registration is the data-partition key, so a
/// provider switch never hides or re-partitions saved records.
@MainActor @Observable final class PAInferenceRouter: PAInferenceConnection {
    enum Keys {
        static let provider = "inferenceProvider"
        static let registration = "inferenceWorkspaceRegistration"
    }
    let chatGPT: any PAInferenceConnection
    let claude: (any PAInferenceConnection)?
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var provider: PAProvider
    /// The registration Claude work runs under; ignored while ChatGPT is selected.
    private(set) var pinnedRegistration: String

    init(chatGPT: any PAInferenceConnection, claude: (any PAInferenceConnection)? = nil, defaults: UserDefaults = .standard) {
        self.chatGPT = chatGPT
        self.claude = claude
        self.defaults = defaults
        let stored = defaults.string(forKey: Keys.provider).flatMap(PAProvider.init(rawValue:)) ?? .chatGPT
        let pinned = defaults.string(forKey: Keys.registration) ?? ""
        pinnedRegistration = pinned
        provider = stored == .claudeCode && claude != nil && !pinned.isEmpty ? .claudeCode : .chatGPT
    }

    var activeID: String { provider == .chatGPT ? chatGPT.activeID : pinnedRegistration }
    var selectedModel: String { selected.selectedModel }
    var busy: Bool { chatGPT.busy || claude?.busy == true }
    var usagePaused: Bool { selected.usagePaused }
    var inferenceVerified: Bool { selected.inferenceVerified }
    var hasSession: Bool { selected.hasSession }
    private var selected: any PAInferenceConnection { provider == .claudeCode ? claude ?? chatGPT : chatGPT }

    /// Selecting Claude pins the registration whose data is currently shown; a
    /// Claude-only workspace receives a stable local registration instead.
    func select(_ next: PAProvider) throws {
        guard next != provider else { return }
        if next == .claudeCode {
            guard claude != nil else { throw PAInferenceRouteError.providerUnavailable(.claudeCode) }
            let registration = !chatGPT.activeID.isEmpty ? chatGPT.activeID
                : !pinnedRegistration.isEmpty ? pinnedRegistration : "local-" + UUID().uuidString.lowercased()
            pinnedRegistration = registration
            defaults.set(registration, forKey: Keys.registration)
        }
        provider = next
        defaults.set(next.rawValue, forKey: Keys.provider)
    }

    #if DEBUG
    /// Fictional evaluations simulate accounts through ChatGPT's own state. They own their
    /// process, so this in-memory selection is never saved and never changes the human's choice.
    func useChatGPTForFictionalEvaluation() { provider = .chatGPT }
    #endif

    /// A nil model means the current selection; captured models keep their provider.
    func backend(for model: String?) throws -> any PAInferenceConnection {
        switch model.map(PAProvider.init(model:)) ?? provider {
        case .claudeCode:
            guard let claude else { throw PAInferenceRouteError.providerUnavailable(.claudeCode) }
            return claude
        case .chatGPT:
            // While Claude owns the workspace, ChatGPT may only finish that same account's captured work.
            guard provider == .chatGPT || chatGPT.activeID == pinnedRegistration else { throw PAInferenceRouteError.accountMismatch }
            return chatGPT
        }
    }

    func streamResponse(input: [[String: String]], instructions: String, model: String?, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> String {
        try await backend(for: model).streamResponse(input: input, instructions: instructions, model: model, effort: effort, purpose: purpose, onDelta: onDelta)
    }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        try await backend(for: model).toolResponse(input: input, instructions: instructions, tools: tools, model: model, purpose: purpose, onDelta: onDelta)
    }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        try await backend(for: model).toolResponse(input: input, instructions: instructions, tools: tools, model: model, effort: effort, purpose: purpose, onDelta: onDelta)
    }
    func typedResult(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, effort: String, purpose: AIRequestPurpose) async throws -> PAResponse {
        try await backend(for: model).typedResult(input: input, instructions: instructions, tools: tools, model: model, effort: effort, purpose: purpose)
    }
}
