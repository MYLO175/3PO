import Foundation

struct AssistantTurn: Codable, Identifiable {
    var id = UUID()
    var role: String
    var content: String
    var completed: Bool
    var deliveryID: String?
    var created: Date? = .now
}
struct AssistantConversation: Codable, Identifiable {
    var id = UUID()
    var accountID: String
    var title: String
    var created = Date.now
    var turns: [AssistantTurn] = []
    var isPrimary: Bool?
    var focus: String?
}

enum ConversationRules {
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
