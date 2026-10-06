import Foundation

struct PAHeartbeatAccount: Codable {
    var checked: Date?
    var fingerprint: String?
    var phase = "idle"
}
struct PAHeartbeatState: Codable {
    var accounts: [String:PAHeartbeatAccount] = [:]
}
enum PAHeartbeatRules {
    static let interval: TimeInterval = 1800
    static func due(_ account: PAHeartbeatAccount, now: Date) -> Bool {
        account.checked.map { now.timeIntervalSince($0) >= interval } ?? true
    }
    static func needsAssessment(_ account: PAHeartbeatAccount, fingerprint: String, manual: Bool) -> Bool {
        manual || (account.phase != "paused" && account.phase != "assessing" && account.fingerprint != fingerprint)
    }
    static func recovered(_ account: PAHeartbeatAccount) -> PAHeartbeatAccount {
        var value = account
        if value.phase == "assessing" { value.phase = "paused" }
        return value
    }
}
