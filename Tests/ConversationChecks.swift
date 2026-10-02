import Foundation
@main struct Checks {
    static func main() throws {
        let legacy = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"accountID\":\"one\",\"title\":\"Old topic\",\"created\":0,\"turns\":[{\"id\":\"00000000-0000-0000-0000-000000000002\",\"role\":\"user\",\"content\":\"Hello\",\"completed\":true}]}".utf8)
        var chat = try JSONDecoder().decode(AssistantConversation.self,from:legacy)
        precondition(chat.isPrimary == nil && chat.turns[0].deliveryID == nil)
        let key = ConversationRules.morningKey(registration:"one",day:"2026-10-02")
        precondition(!ConversationRules.hasDelivery([chat],registration:"one",key:key))
        chat.turns.append(AssistantTurn(role:"assistant",content:"Briefing",completed:true,deliveryID:key)); chat.isPrimary = true
        let saved = try JSONDecoder().decode(AssistantConversation.self,from:JSONEncoder().encode(chat))
        precondition(ConversationRules.hasDelivery([saved],registration:"one",key:key))
        precondition(!ConversationRules.hasDelivery([saved],registration:"two",key:key))
        precondition(!ConversationRules.hasDelivery([saved],registration:"one",key:ConversationRules.morningKey(registration:"one",day:"2026-10-03")))
        precondition(saved.isPrimary == true && saved.turns.count == 2)
        print("PASS: legacy transcript migration, primary marker, persisted daily deduplication and registration/day separation")
    }
}
