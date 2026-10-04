import Foundation
@main struct Checks {
    static func main() throws {
        let start=Date(timeIntervalSince1970:100),end=Date(timeIntervalSince1970:200)
        let messages=(0..<65).map { i in WhatsAppReadMessage(id:"m\(i)",chat:i==0 ? "excluded" : "allowed",sender:"Fixture sender",text:"meeting notes",sentByMe:false,time:Double(100+i)*1000) }
        let found=WhatsAppReadRules.search(messages,allowed:["allowed"],chat:nil,query:"MEETING sender",start:start,end:end,offset:0)
        assert(found.total==64 && found.page.count==30 && found.page.first?.id=="m64")
        let next=WhatsAppReadRules.search(messages,allowed:["allowed"],chat:nil,query:"",start:start,end:end,offset:30)
        assert(Set(found.page.map(\.id)).isDisjoint(with:Set(next.page.map(\.id))))
        assert(WhatsAppReadRules.search(messages,allowed:["allowed"],chat:"excluded",query:"",start:start,end:end,offset:0).total==0)
        assert(WhatsAppReadRules.search(messages,allowed:[],chat:nil,query:"",start:start,end:end,offset:0).total==0)
        assert(WhatsAppReadRules.search(messages,allowed:["allowed"],chat:nil,query:"",start:Date(timeIntervalSince1970:164),end:Date(timeIntervalSince1970:165),offset:0).page.map(\.id)==["m64"])
        let legacy=try JSONDecoder().decode(WhatsAppAccess.self,from:JSONEncoder().encode(WhatsAppAccess()))
        assert(!legacy.enabled && legacy.chats.isEmpty)
        let oldJSON=Data("{\"enabled\":true,\"chats\":[\"allowed\"]}".utf8)
        var access=try JSONDecoder().decode(WhatsAppAccess.self,from:oldJSON)
        assert(!access.briefEnabled)
        access.includeInBrief=true
        let recent=WhatsAppReadRules.brief(messages,access:access,now:end)
        assert(recent.total==64 && recent.messages.count==40 && recent.messages.first?.id=="m64")
        assert(!recent.messages.contains { $0.chat == "excluded" })
        access.enabled=false
        assert(WhatsAppReadRules.brief(messages,access:access,now:end).messages.isEmpty)
        access.enabled=true; access.chats=[]
        assert(!access.briefEnabled)
        access.chats=["allowed"]
        let boundary=[WhatsAppReadMessage(id:"old",chat:"allowed",sender:"Fixture",text:"text",sentByMe:false,time:-172701000),WhatsAppReadMessage(id:"future",chat:"allowed",sender:"Fixture",text:"text",sentByMe:false,time:201000)]
        assert(WhatsAppReadRules.brief(boundary,access:access,now:end).total==0)
        print("WhatsApp scope, date bounds, pagination and defaults checks passed")
    }
}
