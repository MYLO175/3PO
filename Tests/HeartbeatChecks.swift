import Foundation
@main struct HeartbeatChecks {
    static func main() throws {
        let now=Date(timeIntervalSince1970:1_791_280_000)
        var account=PAHeartbeatAccount()
        precondition(PAHeartbeatRules.due(account,now:now))
        account.checked=now
        precondition(!PAHeartbeatRules.due(account,now:now.addingTimeInterval(1799)))
        precondition(PAHeartbeatRules.due(account,now:now.addingTimeInterval(1800)))
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
        print("PASS heartbeat: 30-minute due boundary, changed-only assessment, captured account isolation, persistence and interrupted inference requiring explicit resume")
    }
}
