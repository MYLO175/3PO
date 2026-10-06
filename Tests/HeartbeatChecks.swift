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
        precondition(PAHeartbeatRules.needsAssessment(account,fingerprint:"new",manual:false))
        account.phase="assessing"
        let recovered=PAHeartbeatRules.recovered(account)
        precondition(recovered.phase == "paused" && recovered.checked == account.checked && recovered.fingerprint == "same")
        precondition(!PAHeartbeatRules.needsAssessment(recovered,fingerprint:"new",manual:false))
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
        print("PASS heartbeat: configurable due boundaries, changed/pending assessment, persisted daily request allowance, day rollover, captured account isolation and interrupted inference requiring explicit resume")
    }
}
