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
        let key=WhatsAppReadRules.accessKey(registration:"connection-a",linkedIdentity:"linked-a")!
        let choices=[key:access]
        assert(WhatsAppReadRules.access(choices,registration:"connection-a",linkedIdentity:"linked-a")==access)
        assert(!WhatsAppReadRules.access(choices,registration:"connection-b",linkedIdentity:"linked-a").enabled)
        assert(!WhatsAppReadRules.access(choices,registration:"connection-a",linkedIdentity:"linked-b").enabled)
        assert(!WhatsAppReadRules.access(choices,registration:"connection-a",linkedIdentity:"").enabled)
        assert(WhatsAppReadRules.accessKey(registration:"",linkedIdentity:"linked-a")==nil)
        let restoredChoices=try JSONDecoder().decode([String:WhatsAppAccess].self,from:JSONEncoder().encode(choices))
        assert(restoredChoices==choices)
        let revision=UUID(), scope=WhatsAppSourceScope(registration:"connection-a",linkedIdentity:"linked-a",revision:revision)
        assert(scope != .init(registration:"connection-b",linkedIdentity:"linked-a",revision:revision))
        assert(scope != .init(registration:"connection-a",linkedIdentity:"linked-b",revision:revision))
        assert(scope != .init(registration:"connection-a",linkedIdentity:"linked-a",revision:UUID()))
        var london=Calendar(identifier:.gregorian);london.timeZone=TimeZone(identifier:"Europe/London")!
        for month in [2,9] {
            let first=london.date(from:DateComponents(year:2026,month:month,day:1))!
            let day90=london.date(byAdding:.day,value:90,to:first)!, day91=london.date(byAdding:.day,value:91,to:first)!
            assert(WhatsAppReadRules.validSearchRange(start:first,end:day90,calendar:london))
            assert(!WhatsAppReadRules.validSearchRange(start:first,end:day91,calendar:london))
            assert(!WhatsAppReadRules.validSearchRange(start:first,end:first,calendar:london))
            assert(!WhatsAppReadRules.validSearchRange(start:first,end:day90.addingTimeInterval(1),calendar:london))
        }
        let revoked=try JSONDecoder().decode(WhatsAppReadEvent.self,from:Data("{\"connected\":false,\"revoked\":true}".utf8))
        assert(revoked.revoked==true)
        let cursor=WhatsAppSearchCursor(messages:messages,allowed:["allowed"],chat:nil,query:"MEETING sender",start:start,end:end,fetched:start)
        let page1=try cursor.page(messages:messages,allowed:["allowed"],chat:nil,query:" meeting   SENDER ",start:start,end:end,offset:30)
        assert(page1.page.map(\.id)==next.page.map(\.id) && cursor.fetched==start)
        func rejected(_ body: () throws -> Void) {
            do { try body(); assertionFailure("Changed WhatsApp search must be rejected") }
            catch { assert(error is WhatsAppSearchFailure) }
        }
        let arrival=WhatsAppReadMessage(id:"new",chat:"allowed",sender:"Fixture sender",text:"meeting notes",sentByMe:false,time:165000)
        for changed in [messages+[arrival],Array(messages.dropLast()),messages.map { item in item.id=="m31" ? WhatsAppReadMessage(id:item.id,chat:item.chat,sender:item.sender,text:"changed meeting notes",sentByMe:item.sentByMe,time:item.time) : item }] {
            rejected { _=try cursor.page(messages:changed,allowed:["allowed"],chat:nil,query:"meeting sender",start:start,end:end,offset:30) }
        }
        rejected { _=try cursor.page(messages:messages,allowed:[],chat:nil,query:"meeting sender",start:start,end:end,offset:30) }
        rejected { _=try cursor.page(messages:messages,allowed:["allowed"],chat:"allowed",query:"meeting sender",start:start,end:end,offset:30) }
        rejected { _=try cursor.page(messages:messages,allowed:["allowed"],chat:nil,query:"different",start:start,end:end,offset:30) }
        let unrelated=WhatsAppReadMessage(id:"unselected",chat:"excluded",sender:"Fixture sender",text:"meeting notes",sentByMe:false,time:165000)
        let unchanged=try cursor.page(messages:messages+[unrelated],allowed:["allowed"],chat:nil,query:"meeting sender",start:start,end:end,offset:30)
        assert(unchanged.page.map(\.id)==page1.page.map(\.id))
        print("WhatsApp scope, date bounds, pagination and defaults checks passed")
    }
}
