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
}

enum ConversationRules {
    static func morningKey(registration: String, day: String) -> String { registration + ":morning:" + day }
    static func hasDelivery(_ conversations: [AssistantConversation], registration: String, key: String) -> Bool {
        conversations.contains { $0.accountID == registration && $0.turns.contains { $0.deliveryID == key } }
    }
}
