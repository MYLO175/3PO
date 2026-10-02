import Foundation
@main struct Checks {
    static func main() throws {
        let legacy = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"accountID\":\"one\",\"title\":\"Old topic\",\"created\":0,\"turns\":[{\"id\":\"00000000-0000-0000-0000-000000000002\",\"role\":\"user\",\"content\":\"Hello\",\"completed\":true}]}".utf8)
        var chat = try JSONDecoder().decode(AssistantConversation.self,from:legacy)
        precondition(chat.isPrimary == nil && chat.turns[0].deliveryID == nil && chat.turns[0].created == nil)
        let key = ConversationRules.morningKey(registration:"one",day:"2026-10-02")
        precondition(!ConversationRules.hasDelivery([chat],registration:"one",key:key))
        chat.turns.append(AssistantTurn(role:"assistant",content:"Briefing",completed:true,deliveryID:key)); chat.isPrimary = true
        let saved = try JSONDecoder().decode(AssistantConversation.self,from:JSONEncoder().encode(chat))
        precondition(ConversationRules.hasDelivery([saved],registration:"one",key:key))
        precondition(!ConversationRules.hasDelivery([saved],registration:"two",key:key))
        precondition(!ConversationRules.hasDelivery([saved],registration:"one",key:ConversationRules.morningKey(registration:"one",day:"2026-10-03")))
        precondition(saved.isPrimary == true && saved.turns.count == 2)
        precondition(saved.turns[0].created == nil && saved.turns[1].created != nil)
        var topic = AssistantConversation(accountID:"one",title:"Topic")
        topic.created = saved.created.addingTimeInterval(20)
        var other = AssistantConversation(accountID:"two",title:"Other account"); other.isPrimary = true
        precondition(ConversationRules.selection(topic.id,in:[saved,topic,other],registration:"one") == topic.id)
        precondition(ConversationRules.selection(other.id,in:[saved,topic,other],registration:"one") == saved.id)
        precondition(ConversationRules.selection(nil,in:[saved,topic,other],registration:"one") == saved.id)
        precondition(ConversationRules.selection(nil,in:[saved,topic,other],registration:"unknown") == nil)
        let widget = UUID(), otherWidget = UUID()
        let keys = [ChatDraftRules.key(registration:"one",widget:widget,conversation:saved.id),ChatDraftRules.key(registration:"one",widget:otherWidget,conversation:saved.id),ChatDraftRules.key(registration:"one",widget:widget,conversation:topic.id),ChatDraftRules.key(registration:"two",widget:widget,conversation:saved.id)]
        precondition(Set(keys).count == 4)
        var drafts = ChatDraftState(); drafts.values[keys[0]] = "Draft"; drafts.values[keys[3]] = "   "
        precondition(ChatDraftRules.hasDraft(drafts,registration:"one") && !ChatDraftRules.hasDraft(drafts,registration:"two"))
        let restored = try JSONDecoder().decode(ChatDraftState.self,from:JSONEncoder().encode(drafts))
        precondition(restored.values == drafts.values)
        print("PASS: legacy transcript migration with unknown dates, new message dates, primary marker, persisted daily deduplication and registration/day separation")
    }
}
