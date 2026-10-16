import Foundation

@main struct ReviewInferenceGuardChecks {
    static func main() throws {
        var count=0
        func check(_ value:Bool,_ text:String) {precondition(value,text);count += 1}
        let now=Date(timeIntervalSince1970:1_792_150_000)
        let source=SourceOption(id:"calendar",title:"Fictional",account:"Example",writable:true)
        let event=AgendaEvent(id:"event@1",calendarID:source.id,title:"Orion prototype",start:now,end:now.addingTimeInterval(3600),allDay:false,location:"Lab",sourceLabel:source.label,modified:now)
        let task=TaskItem(id:"task",listID:"list",title:"Prepare Orion",due:now,hasTime:true,sourceLabel:"Example",writable:true,recurring:false,modified:now)
        let done=CompletedReminder(item:task,completedAt:now)
        let emptyReminders=ReminderSnapshot(sources:[],reminders:[])
        func rows(_ events:[AgendaEvent]=[event],_ tasks:[TaskItem]=[task],_ completed:[CompletedReminder]=[done],writable:Bool=true)->[String:String] {
            var selected=source;selected.writable=writable
            return ReviewInferenceGuard.nativeRows(calendar:.init(sources:[selected],events:events),reminders:.init(sources:[],reminders:tasks),completed:completed,excludedCalendars:[],excludedLists:[])
        }
        let captured=rows()
        var another=event;another.id="other";another.title="Garden watering"
        check(ReviewInferenceGuard.available(captured,current:rows([another,event])),"An unrelated newly collected event cannot invalidate supplied records")
        check(ReviewInferenceGuard.available(captured,current:rows([event,another],[task],[done])),"Collection ordering is irrelevant")
        for field in ["title","start","end","occurrence","source","modified"] {
            var changed=event
            switch field {case "title":changed.title="Changed";case "start":changed.start += 900;case "end":changed.end += 900;case "occurrence":changed.id="event@2";case "source":changed.calendarID="another";default:changed.modified=now.addingTimeInterval(1)}
            check(!ReviewInferenceGuard.available(captured,current:rows([changed])),"Changed exact \(field) invalidates supplied native evidence")
        }
        check(!ReviewInferenceGuard.available(captured,current:rows([],[],[])),"Missing exact supplied records are not an empty successful result")
        check(!ReviewInferenceGuard.available(captured,current:rows(writable:false)),"Source writability remains captured")
        check(!ReviewInferenceGuard.nativeAvailable(captured,current:rows([event,another])),"A newly admitted native item changes duplicate/absence context")
        check(ReviewInferenceGuard.nativeAvailable(captured,current:rows()),"Unchanged admitted native records survive collection refresh")
        var completed=done;completed.completedAt += 1
        check(!ReviewInferenceGuard.available(captured,current:rows([event],[task],[completed])),"Exact completion date is supporting evidence")
        check(!ReviewInferenceGuard.available(captured,current:rows([event],[task],[])),"Undoing a supplied completion invalidates its receipt")
        check(ReviewInferenceGuard.available([:],current:rows()),"An empty supplied set never adopts new rows")
        let withdrawn=ReviewInferenceGuard.nativeRows(calendar:.init(sources:[source],events:[event]),reminders:emptyReminders,completed:[],excludedCalendars:[source.id],excludedLists:[])
        check(!ReviewInferenceGuard.available(["event:"+event.id:captured["event:"+event.id]!],current:withdrawn),"Exact source withdrawal excludes its evidence")
        let base:[String:Any]=["id":"mail","accountID":"account","account":"Example","messageID":1,"internetMessageID":"mail@example.invalid","sender":"Fictional sender","subject":"Orion prototype","received":now.ISO8601Format(),"unread":true,"replied":false,"flagged":false]
        func mail(_ changes:[String:Any]=[:])throws->MailMessage {try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:base.merging(changes,uniquingKeysWith:{$1})))}
        let receipt=ReviewInferenceGuard.mailSource(try mail())
        for changes:[String:Any] in [["unread":false],["flagged":true],["mailboxName":"Archive","mailboxRole":"archive"],["account":"Renamed display label"]] {
            check(ReviewInferenceGuard.mailSource(try mail(changes)) == receipt,"Mail bookkeeping cannot change fetched source ownership")
        }
        for changes:[String:Any] in [["id":"different"],["accountID":"other"],["messageID":2],["internetMessageID":"other@example.invalid"],["sender":"Different sender"],["subject":"Different subject"],["replied":true],["received":now.addingTimeInterval(1).ISO8601Format()]] {
            check(ReviewInferenceGuard.mailSource(try mail(changes)) != receipt,"Mail identity, supplied headers and meaningful reply state remain exact")
        }
        check(ReviewInferenceGuard.available(["project:A":"version-1"],current:["project:A":"version-1","project:B":"new"]),"An unrelated project revision is irrelevant")
        check(!ReviewInferenceGuard.available(["project:A":"version-1"],current:["project:A":"version-2"]),"Supplied project payload remains guarded")
        check(!ReviewInferenceGuard.available(["proposal:A":"version-1"],current:[:]),"A supplied pending proposal must remain the same captured record")
        print("PASS Review inference receipts: \(count) checks; exact native/source/occurrence/completion and supplied rows, irrelevant additions/bookkeeping, no AI or native access.")
    }
}
