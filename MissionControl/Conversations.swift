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
    var choices: [String]? = nil
    var profileSessionID: UUID? = nil
    var profileControl: Bool? = nil
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
    /// Each optional context is a distinct ongoing thread. Tagged messages preserve the previous feed without copying or deleting records.
    static func thread(feed: AssistantConversation, topic: AssistantConversation?) -> [AssistantTurn] {
        let turns = feed.turns.filter { $0.contextID == topic?.id } + (topic?.turns ?? [])
        return turns.enumerated().sorted {
            let lhs = $0.element.created ?? .distantPast, rhs = $1.element.created ?? .distantPast
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.map(\.element)
    }
    static func profileThread(feed:AssistantConversation,topic:AssistantConversation?,session:UUID)->[AssistantTurn] {
        thread(feed:feed,topic:topic).filter { $0.profileSessionID == session }
    }
    static func history(feed: AssistantConversation, topic: AssistantConversation?, excludedDeliveries: Set<String> = []) -> [AssistantTurn] {
        Array(thread(feed:feed,topic:topic).filter { $0.completed && $0.profileSessionID == nil && ($0.deliveryID.map { !excludedDeliveries.contains($0) } ?? true) }.suffix(20))
    }
    static let promptByteLimit = 16_000
    static func acceptsPrompt(_ prompt: String) -> Bool {
        guard prompt.utf8.count <= promptByteLimit, let data = try? JSONSerialization.data(withJSONObject:["role":"user","content":prompt]) else { return false }
        return data.count + 2 <= 24_000
    }
    static func utf8Prefix(_ text: String, bytes: Int) -> String {
        var data = Array(text.utf8.prefix(max(0,bytes)))
        while !data.isEmpty {
            if let result = String(bytes:data,encoding:.utf8) { return result }
            data.removeLast()
        }
        return ""
    }
    /// The current human request is intact; only older saved turns may become labelled excerpts.
    static func replay(_ turns: [AssistantTurn], currentUserID: UUID, bytes: Int = 24_000) -> [[String:String]] {
        guard let current = turns.last(where:{ $0.id == currentUserID && $0.role == "user" && $0.completed }) else { return [] }
        let last = ["role":current.role,"content":current.content]
        guard let encoded = try? JSONSerialization.data(withJSONObject:last), encoded.count + 2 <= bytes else { return [] }
        var result = [last], used = encoded.count + 2
        let before = turns.prefix(while:{ $0.id != currentUserID })
        for turn in before.suffix(19).reversed() where turn.completed && ["user","assistant"].contains(turn.role) {
            let content = turn.content.utf8.count > 3000 ? utf8Prefix(turn.content,bytes:3000) + "\n[Earlier message excerpt; remaining text omitted.]" : turn.content
            let value = ["role":turn.role,"content":content]
            guard let data = try? JSONSerialization.data(withJSONObject:value), used + data.count + 1 <= bytes else { break }
            result.insert(value,at:0); used += data.count + 1
        }
        return result
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
