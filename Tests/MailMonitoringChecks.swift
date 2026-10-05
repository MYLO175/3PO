import Foundation

@main struct MailMonitoringChecks {
    static func main() throws {
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"Europe/London")!
        let now = ISO8601DateFormatter().date(from:"2026-10-06T10:00:00Z")!
        let accounts = [MailAccount(id:"a",title:"A"),MailAccount(id:"b",title:"B")]
        var state = try JSONDecoder().decode(MailIndexState.self,from:Data(#"{"windows":[]}"#.utf8))
        state.prepare(accounts:accounts,now:now,calendar:calendar)
        assert(state.monitor("a")!.start == now.addingTimeInterval(-48*3600))
        assert(state.windows.count == 62)
        // Finished historical cache remains intact across frequent refreshes.
        for i in state.windows.indices { state.windows[i].complete = true; state.windows[i].lastSuccess = now }
        let first = state.monitor("a")!
        let empty = MailBatch(messages:[],messageIDs:[],nextOffset:0,complete:true,errors:[])
        var snapshot = MailSnapshot(messages:[],accounts:accounts,errors:[])
        snapshot = state.apply(empty,to:first.id,snapshot:snapshot,now:now)
        state.prepare(accounts:accounts,now:now.addingTimeInterval(60),calendar:calendar)
        assert(state.monitor("a")!.start == now.addingTimeInterval(-600))
        assert(state.windows.allSatisfy(\.complete), "Polling must not reopen the month's history")
        let monitor = state.monitor("a")!
        _ = state.apply(MailBatch(messages:[],messageIDs:[1,2],nextOffset:1,complete:false,errors:[]),to:monitor.id,snapshot:snapshot,now:now)
        state = try JSONDecoder().decode(MailIndexState.self,from:JSONEncoder().encode(state))
        state.prepare(accounts:accounts,now:now.addingTimeInterval(3600),calendar:calendar)
        assert(state.monitor("a")!.end == monitor.end && state.monitor("a")!.offset == 1 && state.monitor("a")!.messageIDs == [1,2], "An interrupted arrival scan keeps its exact range and cursor")
        assert(state.windows.filter { !$0.complete }.count <= 2, "An hourly audit nominates at most one day per account")
        let background = state.background("a",now:now.addingTimeInterval(3600))!
        assert(state.background("a",now:now.addingTimeInterval(3660)) == nil)
        state.failed("a",detail:"timeout",now:now)
        assert(!state.available("a",now:now.addingTimeInterval(30)) && state.available("b",now:now))
        state.failed("a",detail:"timeout",now:now.addingTimeInterval(60))
        assert(!state.available("a",now:now.addingTimeInterval(179)) && state.available("a",now:now.addingTimeInterval(180)))
        state.resume()
        assert(state.available("a",now:now) && state.monitor("a")!.offset == 1)
        state.resetCursor(monitor.id)
        assert(state.monitor("a")!.offset == 0 && state.monitor("a")!.messageIDs == nil)
        assert(state.windows.first(where:{ $0.id == background.id }) != nil)
        state.prepare(accounts:[accounts[1]],now:now.addingTimeInterval(86400),calendar:calendar)
        assert(state.monitors!.allSatisfy { $0.accountID == "b" } && state.windows.allSatisfy { $0.accountID == "b" })
        var offline = MailIndexState()
        offline.prepare(accounts:accounts,now:now,calendar:calendar,lastCheck:now.addingTimeInterval(-40*86400))
        assert(offline.monitor("a")!.start == now.addingTimeInterval(-30*86400), "A known offline gap catches up once within cache retention")
        // Partial scans retain unseen cache rows; complete exact ranges reconcile
        // deletions while leaving older rows and the other account untouched.
        func message(_ id:Int,account:String,received:Date) throws -> MailMessage {
            let json:[String:Any] = ["id":account+":"+String(id),"accountID":account,"account":account,"messageID":id,"internetMessageID":"fixture\(id)@example.invalid","sender":"Fixture","subject":"Test","received":received.ISO8601Format(),"unread":true,"replied":false,"flagged":false]
            return try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:json))
        }
        var reconcile = MailIndexState(); reconcile.prepare(accounts:accounts,now:now,calendar:calendar)
        let kept = try message(1,account:"a",received:now.addingTimeInterval(-60))
        let removed = try message(2,account:"a",received:now.addingTimeInterval(-60))
        let older = try message(3,account:"a",received:now.addingTimeInterval(-3*86400))
        let other = try message(4,account:"b",received:now.addingTimeInterval(-60))
        let original = MailSnapshot(messages:[kept,removed,older,other],accounts:accounts,errors:[])
        let part = reconcile.apply(MailBatch(messages:[kept],messageIDs:[1,2],nextOffset:1,complete:false,errors:[]),to:reconcile.monitor("a")!.id,snapshot:original,now:now)
        assert(part.messages.count == 4)
        reconcile.resetCursor(reconcile.monitor("a")!.id)
        let end = reconcile.apply(MailBatch(messages:[kept],messageIDs:[1],nextOffset:1,complete:true,errors:[]),to:reconcile.monitor("a")!.id,snapshot:part,now:now)
        assert(Set(end.messages.map(\.id)) == ["a:1","a:3","b:4"])
        print("PASS Mail monitoring: legacy migration, overlapping arrival watermark, immutable interrupted cursors, bounded rotating audit/history, per-account retry isolation, offline catch-up, source removal and exact-range reconciliation")
    }
}
