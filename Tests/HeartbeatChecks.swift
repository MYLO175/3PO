import Foundation
@main struct HeartbeatChecks {
    static func main() throws {
        let now=Date(timeIntervalSince1970:1_791_280_000)
        var account=PAHeartbeatAccount()
        precondition(PAHeartbeatRules.due(account,now:now))
        account.checked=now
        precondition(!PAHeartbeatRules.due(account,now:now.addingTimeInterval(1799),minutes:30))
        precondition(PAHeartbeatRules.due(account,now:now.addingTimeInterval(1800),minutes:30))
        account.fingerprint="same"
        precondition(!PAHeartbeatRules.needsAssessment(account,fingerprint:"same",manual:false))
        precondition(PAHeartbeatRules.needsAssessment(account,fingerprint:"same",manual:false,pendingSources:true))
        precondition(PAHeartbeatRules.needsAssessment(account,fingerprint:"new",manual:false))
        account.phase="assessing"
        let recovered=PAHeartbeatRules.recovered(account)
        precondition(recovered.phase == "paused" && recovered.checked == account.checked && recovered.fingerprint == "same")
        precondition(!PAHeartbeatRules.needsAssessment(recovered,fingerprint:"new",manual:false))
        precondition(!PAHeartbeatRules.needsAssessment(recovered,fingerprint:"same",manual:false,pendingSources:true))
        precondition(PAHeartbeatRules.needsAssessment(recovered,fingerprint:"same",manual:true,pendingSources:true))
        precondition(PAHeartbeatRules.needsAssessment(recovered,fingerprint:"new",manual:true))
        var state=PAHeartbeatState(accounts:["a":recovered,"b":PAHeartbeatAccount()])
        state=try JSONDecoder().decode(PAHeartbeatState.self,from:JSONEncoder().encode(state))
        precondition(state.accounts["a"]?.phase == "paused" && PAHeartbeatRules.due(state.accounts["b"]!,now:now))
        precondition(!PAHeartbeatRules.due(account,now:now.addingTimeInterval(3599),minutes:60))
        precondition(PAHeartbeatRules.due(account,now:now.addingTimeInterval(3600),minutes:60))
        precondition(PAHeartbeatRules.due(account,now:now.addingTimeInterval(900),minutes:15))
        var budget=PAHeartbeatAccount()
        budget=try PAHeartbeatRules.claim(budget,day:"2026-10-06",limit:2)
        budget=try PAHeartbeatRules.claim(budget,day:"2026-10-06",limit:2)
        do { _ = try PAHeartbeatRules.claim(budget,day:"2026-10-06",limit:2);preconditionFailure("Allowance exceeded") } catch is HeartbeatBudgetExhausted {}
        precondition(PAHeartbeatRules.callCount(budget,day:"2026-10-06") == 2)
        budget.pending=true
        precondition(PAHeartbeatRules.needsAssessment(budget,fingerprint:budget.fingerprint ?? "",manual:false))
        budget.phase="paused"
        precondition(!PAHeartbeatRules.needsAssessment(budget,fingerprint:"new",manual:false))
        budget.phase="idle"
        let next=try PAHeartbeatRules.claim(budget,day:"2026-10-07",limit:2)
        precondition(next.calls == 1 && next.budgetDay == "2026-10-07")
        let savedBudget=try JSONDecoder().decode(PAHeartbeatAccount.self,from:JSONEncoder().encode(budget))
        precondition(savedBudget.calls == 2 && savedBudget.phase == "idle")
        var lanes=PAHeartbeatRules.collectingMail(budget,enabled:["healthy","failed"],ready:["healthy"],issues:["failed":"timeout"],now:now)
        lanes=PAHeartbeatRules.completedMail(lanes,fingerprints:["healthy":"opaque-v1"],pending:[],now:now)
        precondition(lanes.mailLanes?["healthy"]?.assessed == now && lanes.mailLanes?["healthy"]?.pending == false)
        precondition(lanes.mailLanes?["failed"]?.assessed == nil && lanes.mailLanes?["failed"]?.issue == "timeout" && lanes.mailLanes?["failed"]?.pending == true)
        let reopened=try JSONDecoder().decode(PAHeartbeatAccount.self,from:JSONEncoder().encode(lanes))
        precondition(reopened.mailLanes?["healthy"]?.fingerprint == "opaque-v1" && reopened.mailLanes?["failed"]?.issue == "timeout")
        lanes=PAHeartbeatRules.collectingMail(reopened,enabled:["healthy","failed"],ready:["healthy","failed"],issues:[:],now:now.addingTimeInterval(3600))
        precondition(lanes.mailLanes?["failed"]?.pending == true && lanes.mailLanes?["failed"]?.assessed == nil,"Collection alone never marks failed account assessed")
        lanes=PAHeartbeatRules.completedMail(lanes,fingerprints:["failed":"opaque-recovered"],pending:["failed"],now:now.addingTimeInterval(3600))
        precondition(lanes.mailLanes?["failed"]?.assessed == now.addingTimeInterval(3600) && lanes.mailLanes?["healthy"]?.assessed == now)
        let stopped=PAHeartbeatRules.recovered(PAHeartbeatAccount(phase:"assessing",mailLanes:lanes.mailLanes))
        precondition(stopped.phase == "paused" && stopped.mailLanes?["failed"]?.fingerprint == "opaque-recovered")
        let narrowed=PAHeartbeatRules.collectingMail(lanes,enabled:["healthy"],ready:["healthy"],issues:[:],now:now)
        precondition(narrowed.mailLanes?.count == 1 && narrowed.calls == lanes.calls)
        let legacy=try JSONDecoder().decode(PAHeartbeatAccount.self,from:Data(#"{"phase":"idle"}"#.utf8))
        precondition(legacy.mailLanes == nil)
        print("PASS heartbeat: configurable due boundaries, changed/pending assessment, persisted daily request allowance, day rollover, captured account isolation and interrupted inference requiring explicit resume")
    }
}
