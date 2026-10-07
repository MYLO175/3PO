import Foundation

struct PAHeartbeatAccount: Codable {
    var checked: Date?
    var fingerprint: String?
    var phase = "idle"
    var budgetDay:String? = nil
    var calls:Int? = nil
    var assessed:Date? = nil
    var pending:Bool? = nil
    var mailLanes:[String:PAHeartbeatMailLane]? = nil
}
struct PAHeartbeatMailLane:Codable {
    var checked:Date?
    var assessed:Date?
    var fingerprint:String?
    var pending=true
    var issue:String?
}
struct PAHeartbeatState: Codable {
    var accounts: [String:PAHeartbeatAccount] = [:]
}
enum PAHeartbeatRules {
    static let defaultMinutes = 60
    static func due(_ account: PAHeartbeatAccount, now: Date, minutes:Int = defaultMinutes) -> Bool {
        account.checked.map { now.timeIntervalSince($0) >= Double(minutes)*60 } ?? true
    }
    static func needsAssessment(_ account: PAHeartbeatAccount, fingerprint: String, manual: Bool,pendingSources:Bool = false) -> Bool {
        manual || (account.phase != "paused" && account.phase != "assessing" && (account.pending == true || pendingSources || account.fingerprint != fingerprint))
    }
    static func callCount(_ account:PAHeartbeatAccount,day:String)->Int { account.budgetDay == day ? account.calls ?? 0 : 0 }
    static func claim(_ account:PAHeartbeatAccount,day:String,limit:Int) throws -> PAHeartbeatAccount {
        let count=callCount(account,day:day)
        guard count < limit else { throw HeartbeatBudgetExhausted() }
        var value=account;value.budgetDay=day;value.calls=count+1;return value
    }
    static func recovered(_ account: PAHeartbeatAccount) -> PAHeartbeatAccount {
        var value = account
        if value.phase == "assessing" { value.phase = "paused" }
        return value
    }
    static func collectingMail(_ account:PAHeartbeatAccount,enabled:Set<String>,ready:Set<String>,issues:[String:String],now:Date)->PAHeartbeatAccount {
        var value=account,lanes=(account.mailLanes ?? [:]).filter{enabled.contains($0.key)}
        for id in enabled {
            var lane=lanes[id] ?? .init();lane.checked=now;lane.issue=issues[id]
            if !ready.contains(id) {lane.pending=true}
            lanes[id]=lane
        }
        value.mailLanes=lanes;return value
    }
    static func completedMail(_ account:PAHeartbeatAccount,fingerprints:[String:String],pending:Set<String>,now:Date)->PAHeartbeatAccount {
        var value=account,lanes=account.mailLanes ?? [:]
        for (id,fingerprint) in fingerprints {
            var lane=lanes[id] ?? .init();lane.assessed=now;lane.fingerprint=fingerprint;lane.pending=pending.contains(id);lane.issue=nil;lanes[id]=lane
        }
        value.mailLanes=lanes;return value
    }
}

struct HeartbeatBudgetExhausted:LocalizedError { var errorDescription:String? { "Daily communication-review call limit reached. Source collection continues; pending assessment is kept for the next day." } }
