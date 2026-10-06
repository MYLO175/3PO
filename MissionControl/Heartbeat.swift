import Foundation

struct PAHeartbeatAccount: Codable {
    var checked: Date?
    var fingerprint: String?
    var phase = "idle"
    var budgetDay:String? = nil
    var calls:Int? = nil
    var assessed:Date? = nil
    var pending:Bool? = nil
}
struct PAHeartbeatState: Codable {
    var accounts: [String:PAHeartbeatAccount] = [:]
}
enum PAHeartbeatRules {
    static let defaultMinutes = 60
    static func due(_ account: PAHeartbeatAccount, now: Date, minutes:Int = defaultMinutes) -> Bool {
        account.checked.map { now.timeIntervalSince($0) >= Double(minutes)*60 } ?? true
    }
    static func needsAssessment(_ account: PAHeartbeatAccount, fingerprint: String, manual: Bool) -> Bool {
        manual || (account.phase != "paused" && account.phase != "assessing" && (account.pending == true || account.fingerprint != fingerprint))
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
}

struct HeartbeatBudgetExhausted:LocalizedError { var errorDescription:String? { "Daily heartbeat inference allowance reached. Source collection continues; pending assessment is kept for the next day." } }
