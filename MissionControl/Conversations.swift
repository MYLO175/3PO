import Foundation

struct AssistantTurn: Codable, Identifiable {
    var id = UUID()
    var role: String
    var content: String
    var completed: Bool
    var deliveryID: String?
    var created: Date? = .now
    /// Context captured when sent; changing a widget's topic never retargets a reply.
    var contextID: UUID?
}
struct AssistantConversation: Codable, Identifiable {
    var id = UUID()
    var accountID: String
    var title: String
    var created = Date.now
    var turns: [AssistantTurn] = []
    var isPrimary: Bool?
    var focus: String?
    var isTopic: Bool?
}

enum ConversationRules {
    static func topics(in conversations: [AssistantConversation], registration: String) -> [AssistantConversation] {
        conversations.filter { $0.accountID == registration && $0.isPrimary != true && ($0.isTopic == true || $0.focus != nil) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    /// Empty stored value means explicitly no topic. Legacy chats become modes only if configured.
    static func topicSelection(_ stored: String?, legacy: UUID?, in conversations: [AssistantConversation], registration: String) -> UUID? {
        let candidate: UUID?
        if let stored { candidate = UUID(uuidString:stored) } else { candidate = legacy }
        return topics(in:conversations,registration:registration).first { $0.id == candidate }?.id
    }
    static func history(feed: AssistantConversation, topic: AssistantConversation?) -> [AssistantTurn] {
        // Old topic transcripts remain local context, without presenting a history browser.
        let turns = feed.turns.filter { $0.completed && ($0.contextID == nil || $0.contextID == topic?.id) } + (topic?.turns.filter(\.completed) ?? [])
        return turns.enumerated().sorted {
            let lhs = $0.element.created ?? .distantPast, rhs = $1.element.created ?? .distantPast
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.suffix(20).map(\.element)
    }
    static func context(for turn: AssistantTurn, in conversation: AssistantConversation) -> UUID? {
        conversation.isPrimary == true ? turn.contextID : conversation.id
    }
    static func selection(_ preferred: UUID?, in conversations: [AssistantConversation], registration: String) -> UUID? {
        let available = conversations.filter { $0.accountID == registration }
        if let preferred, available.contains(where:{ $0.id == preferred }) { return preferred }
        return available.first(where:{ $0.isPrimary == true })?.id ?? available.sorted { $0.created > $1.created }.first?.id
    }
    static func morningKey(registration: String, day: String) -> String { registration + ":morning:" + day }
    static func hasDelivery(_ conversations: [AssistantConversation], registration: String, key: String) -> Bool {
        conversations.contains { $0.accountID == registration && $0.turns.contains { $0.deliveryID == key } }
    }
}

struct ChatDraftState: Codable {
    var version = 1
    var values: [String:String] = [:]
}
enum ChatDraftRules {
    static func key(registration: String, widget: UUID, conversation: UUID?) -> String { registration + ":" + widget.uuidString + ":" + (conversation?.uuidString ?? "unselected") }
    static func hasDraft(_ state: ChatDraftState, registration: String) -> Bool { state.values.contains { $0.key.hasPrefix(registration+":") && !$0.value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty } }
}
