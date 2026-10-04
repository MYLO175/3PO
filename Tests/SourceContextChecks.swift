import Foundation
@main struct Checks {
    static func main() throws {
        let now=Date(timeIntervalSince1970:2_000_000_000)
        let message=WhatsAppReadMessage(id:"one",chat:"family",sender:"participant",text:"Alex is starting a robotics project next week.",sentByMe:false,time:now.timeIntervalSince1970*1000)
        let other=WhatsAppReadMessage(id:"one",chat:"excluded",sender:"participant",text:"Secret unrelated text",sentByMe:false,time:message.time)
        let chats=[WhatsAppChat(id:"family",name:"The Nest",group:true)]
        let recent=SourceContextRules.recent([message,other],chats:chats,allowed:["family"],now:now)
        precondition(recent.count == 1 && recent[0].itemID == "one")
        let both=SourceContextRules.recent([message,other],chats:chats,allowed:["family","excluded"],now:now)
        precondition(Set(both.map(\.id)).count == 2,"Identical message IDs in different chats stay separate")
        let output:[String:Any]=["facts":[["messageID":recent[0].id,"text":"A message mentions Alex starting a robotics project.","quote":message.text,"kind":"context","areas":["projects"]]]]
        func json(_ value:[String:Any])->String { String(data:try! JSONSerialization.data(withJSONObject:value),encoding:.utf8)! }
        let facts=SourceContextRules.decode(json(output),messages:recent,registration:"owner",linkedIdentity:"linked",now:now)!
        precondition(facts.count == 1 && !facts[0].explicit && facts[0].certainty == .inferred && facts[0].durability == .situational && facts[0].sourceTurnID == nil)
        precondition(facts[0].source?.identity.itemID == "one" && facts[0].source?.identity.linkedIdentity == "linked")
        precondition(facts[0].organisation?.areas == [.projects])
        var wrong=output
        wrong["facts"]=[["messageID":"invented","text":"Unknown","quote":message.text,"kind":"context","areas":["projects"]]]
        precondition(SourceContextRules.decode(json(wrong),messages:recent,registration:"owner",linkedIdentity:"linked",now:now) == nil)
        wrong["facts"]=[["messageID":recent[0].id,"text":"Unsupported","quote":"Fabricated quotation","kind":"context","areas":["projects"]]]
        precondition(SourceContextRules.decode(json(wrong),messages:recent,registration:"owner",linkedIdentity:"linked",now:now) == nil)
        wrong["facts"]=[["messageID":recent[0].id,"text":"Unsupported preference","quote":message.text,"kind":"preference","areas":["about"]]]
        precondition(SourceContextRules.decode(json(wrong),messages:recent,registration:"owner",linkedIdentity:"linked",now:now) == nil)
        precondition(SourceContextRules.decode(json(output),messages:recent,registration:"owner",linkedIdentity:"",now:now) == nil)
        let access=WhatsAppAccess(enabled:true,chats:["family"],learnContext:true)
        precondition(SourceContextRules.permitted(facts[0],access:access,linkedIdentity:"linked",messages:[message]))
        precondition(!SourceContextRules.permitted(facts[0],access:.init(enabled:true,chats:["family"]),linkedIdentity:"linked",messages:[message]))
        precondition(!SourceContextRules.permitted(facts[0],access:access,linkedIdentity:"other-linked",messages:[message]))
        precondition(!SourceContextRules.permitted(facts[0],access:access,linkedIdentity:"linked",messages:[]))
        let progress=SourceContextProgress(seen:[recent[0].id:recent[0].revision])
        precondition(SourceContextRules.batch(recent,progress:progress).isEmpty)
        let edited=WhatsAppReadMessage(id:message.id,chat:message.chat,sender:message.sender,text:message.text+" Changed",sentByMe:false,time:message.time)
        precondition(SourceContextRules.revision(edited) != SourceContextRules.revision(message))
        precondition(SourceContextRules.recent([edited],chats:chats,allowed:["family"],now:now)[0].id == recent[0].id)
        precondition(SourceContextRules.batch(SourceContextRules.recent([edited],chats:chats,allowed:["family"],now:now),progress:progress).count == 1)
        let expired=WhatsAppReadMessage(id:"old",chat:"family",sender:"participant",text:message.text,sentByMe:false,time:now.addingTimeInterval(-49*3600).timeIntervalSince1970*1000)
        precondition(SourceContextRules.recent([expired],chats:chats,allowed:["family"],now:now).isEmpty)
        let input=try SourceContextRules.input(recent,existing:Array(repeating:["text":String(repeating:"界",count:5000)],count:12))
        precondition(input.utf8.count <= 24000)
        var long=recent[0];long.text=String(repeating:"界",count:1200)
        precondition(SourceContextRules.batch(Array(repeating:long,count:8),progress:.init()).count <= 3)
        var old=facts[0];old.reviewed=now.addingTimeInterval(-91*86400)
        precondition(!MemoryRules.usable(old,registration:"owner",now:now),"Source-derived beliefs age out even if incorrectly marked stable")
        old.durability = .stable;old.certainty = .stated
        precondition(!MemoryRules.usable(old,registration:"owner",now:now))
        let day=BriefingRules.day(now)
        precondition(!LearningBudgetRules.allowed(.init(day:day,attempts:4,lastAttempt:now.addingTimeInterval(-3600)),now:now))
        precondition(!LearningBudgetRules.allowed(.init(day:day,attempts:1,lastAttempt:now),now:now))
        precondition(LearningBudgetRules.allowed(.init(day:"old",attempts:4,lastAttempt:now.addingTimeInterval(-3600)),now:now))
        print("PASS: selected chats, linked identity, scoped revisions, bounded deltas/input, provisional attribution, invalid evidence, expiry and shared quota")
    }
}
