import Foundation

extension PAProvider {
    var usageURL: URL { URL(string: self == .claudeCode ? "https://claude.ai/settings/usage" : "https://chatgpt.com/settings/usage")! }
    var usageLinkTitle: String { self == .claudeCode ? "See Claude plan usage" : "Manage ChatGPT usage" }
    /// True for the error each provider reports when its plan's usage limit stops a request.
    static func isUsageLimitError(_ text: String) -> Bool {
        text.contains("subscription_sharing_usage_limit_exceeded") || text.contains("usage limit was reached")
    }
}

/// Provider-neutral access controls for views shared by ChatGPT and Claude.
extension DashboardModel {
    var providerAccessMessage: String { inference.provider == .claudeCode ? claude.message : chatGPT.message }
    func checkProviderAccess() {
        switch inference.provider {
        case .chatGPT: chatGPT.testConnection()
        case .claudeCode: Task { await claude.checkAccess() }
        }
    }
}
