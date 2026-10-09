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
    var reviews:[PAReviewRun]? = nil
    var retryAfter:Date? = nil
    var retryReason:String? = nil
}
struct PAReviewRun:Codable,Identifiable {
    var id:String
    var started:Date
    var finished:Date?
    var manual:Bool
    var phase:String
    var detail:String
    var calls:Int = 0
    var checkedAccounts:Int = 0
    var waitingAccounts:Int = 0
    var preparedItems:Int = 0
    var drafts:Int = 0
    var handled:Int = 0
    var briefUpdated:Bool? = nil
    var questions:Int? = nil
    var steps:[PAHeartbeatStep]? = nil
    var failure:String? = nil
    var mailCollectionIndependent:Bool? = nil

    func outcome(running:Bool = false)->String {
        if finished == nil {return running ? "Running" : "Interrupted"}
        if phase == "suspended" { return "Paused for sleep" }
        if briefUpdated == true {return ["paused","failed","interrupted"].contains(phase) ? "Partly completed" : "Completed"}
        return phase == "failed" ? "Failed" : phase == "interrupted" ? "Interrupted" : phase == "paused" ? "Stopped" : phase == "waiting" ? "Waiting" : "Checked"
    }
    var summary:String {
        var parts=[briefUpdated == nil ? "Earlier review saved" : briefUpdated == true ? "Brief updated" : "Brief not updated"]
        if preparedItems > 0 {parts.append("\(preparedItems) suggestion\(preparedItems == 1 ? "" : "s")")}
        if drafts > 0 {parts.append("\(drafts) draft\(drafts == 1 ? "" : "s")")}
        if let questions,questions > 0 {parts.append("\(questions) question\(questions == 1 ? "" : "s")")}
        if waitingAccounts > 0 {parts.append(mailCollectionIndependent == true ? "\(waitingAccounts) Mail collection issue\(waitingAccounts == 1 ? "" : "s")" : "\(waitingAccounts) Mail account\(waitingAccounts == 1 ? "" : "s") waiting")}
        return parts.joined(separator:" · ")
    }
}
struct PAHeartbeatStep:Codable,Identifiable {
    var id:String
    var title:String
    var status:String = "pending"
    var detail:String? = nil
    var label:String {
        switch status {case "done":return "Done";case "running":return "Running";case "failed":return "Stopped";case "skipped":return "Off";case "waiting":return "Waiting";default:return "Not run"}
    }
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
    static func stages()->[PAHeartbeatStep] {
        [.init(id:"sources",title:"Context"),.init(id:"email",title:"Email review"),.init(id:"suggestions",title:"Suggestions & drafts"),.init(id:"brief",title:"Today’s brief")]
    }
    // Cache arrivals between completed stages are fresh input to the next stage.
    // Each inference job still validates the exact context it actually supplied.
    static func canContinue(owner:String,currentOwner:String,controls:UUID,currentControls:UUID,scope:String,currentScope:String,day:String,currentDay:String,model:String,currentModel:String)->Bool {
        owner == currentOwner && controls == currentControls && scope == currentScope && day == currentDay && model == currentModel
    }
    static func canPrepareSources(settings:String,currentSettings:String,choices:UUID,currentChoices:UUID,identity:String,currentIdentity:String)->Bool {
        settings == currentSettings && choices == currentChoices && (identity.isEmpty || identity == currentIdentity)
    }
    static let defaultMinutes = 60
    static func nextReview(_ account:PAHeartbeatAccount,now:Date,minutes:Int = defaultMinutes,day:String? = nil,allowance:Int? = nil)->Date {
        if account.phase != "paused",let retry=account.retryAfter {
            if account.retryReason == "failure",let checked=account.checked {return checked.addingTimeInterval(Double(minutes)*60)}
            if account.retryReason == "allowance",let day,account.budgetDay != day {return now}
            if account.retryReason == "allowance",let day,let allowance,callCount(account,day:day) < allowance {return now}
            return retry
        }
        return account.checked?.addingTimeInterval(Double(minutes)*60) ?? now
    }
    static func due(_ account: PAHeartbeatAccount, now: Date, minutes:Int = defaultMinutes,day:String? = nil,allowance:Int? = nil) -> Bool {
        account.phase != "paused" && nextReview(account,now:now,minutes:minutes,day:day,allowance:allowance) <= now
    }
    enum WaitReason:String {case foreground,sources,allowance}
    static func deferred(_ account:PAHeartbeatAccount,now:Date,reason:WaitReason,calendar:Calendar = .current)->PAHeartbeatAccount {
        var value=account;value.pending=true
        guard value.phase != "paused" else {value.retryAfter=nil;value.retryReason=nil;return value}
        value.phase="idle";value.retryReason=reason.rawValue
        value.retryAfter=reason == .allowance ? calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:now)) : now.addingTimeInterval(reason == .foreground ? 60 : 300)
        return value
    }
    static func clearWait(_ account:PAHeartbeatAccount)->PAHeartbeatAccount {
        var value=account;value.retryAfter=nil;value.retryReason=nil;return value
    }
    static func quiet(_ account:PAHeartbeatAccount,fingerprint:String,ready:Set<String>,pending:Bool)->PAHeartbeatAccount {
        var value=clearWait(account)
        guard value.phase != "paused" else {value.pending=true;return value}
        value.phase="idle";value.pending=pending;value.fingerprint=fingerprint
        for id in ready where value.mailLanes?[id] != nil {value.mailLanes?[id]?.pending=false}
        return value
    }
    static func failed(_ account:PAHeartbeatAccount,now:Date,minutes:Int = defaultMinutes)->PAHeartbeatAccount {
        var value=account;value.phase="idle";value.pending=true;value.checked=now
        value.retryReason="failure";value.retryAfter=now.addingTimeInterval(Double(minutes)*60)
        return value
    }
    static func suspended(_ account:PAHeartbeatAccount,prior:PAHeartbeatAccount)->PAHeartbeatAccount {
        // Keep completed work/call claims, but a lid/sleep interruption does not
        // consume the due interval or postpone the fresh wake catch-up.
        var value=account;value.phase="idle";value.pending=true
        value.checked=prior.checked;value.retryAfter=prior.retryAfter;value.retryReason=prior.retryReason
        return value
    }
    static func interrupted(_ account:PAHeartbeatAccount,now:Date,foreground:Bool,minutes:Int = defaultMinutes)->PAHeartbeatAccount {
        if account.phase == "assessing" || account.phase == "paused" {
            return failed(account,now:now,minutes:minutes)
        }
        return deferred(account,now:now,reason:foreground ? .foreground : .sources)
    }
    static func needsAssessment(_ account: PAHeartbeatAccount, fingerprint: String, manual: Bool,pendingSources:Bool = false) -> Bool {
        manual || (account.phase != "paused" && account.phase != "assessing")
    }
    static func callCount(_ account:PAHeartbeatAccount,day:String)->Int { account.budgetDay == day ? account.calls ?? 0 : 0 }
    static func claim(_ account:PAHeartbeatAccount,day:String,limit:Int) throws -> PAHeartbeatAccount {
        let count=callCount(account,day:day)
        guard count < limit else { throw HeartbeatBudgetExhausted() }
        var value=account;value.budgetDay=day;value.calls=count+1;return value
    }
    static func recovered(_ account: PAHeartbeatAccount,now:Date = .now,minutes:Int = defaultMinutes) -> PAHeartbeatAccount {
        // Recovery starts a new run, never replays an interrupted request. Keep
        // its original timing so repeated launches cannot postpone the next check.
        if account.phase == "assessing" || account.phase == "paused" {return failed(account,now:account.checked ?? now,minutes:minutes)}
        if account.phase == "refreshing" {return deferred(account,now:now,reason:.sources)}
        return account
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
    static func completedMail(_ account:PAHeartbeatAccount,fingerprints:[String:String],pending:Set<String>,now:Date,issues:[String:String] = [:])->PAHeartbeatAccount {
        var value=account,lanes=account.mailLanes ?? [:]
        for (id,fingerprint) in fingerprints {
            var lane=lanes[id] ?? .init();lane.assessed=now;lane.fingerprint=fingerprint;lane.pending=pending.contains(id) || issues[id] != nil;lane.issue=issues[id];lanes[id]=lane
        }
        value.mailLanes=lanes;return value
    }
}

struct HeartbeatBudgetExhausted:LocalizedError { var errorDescription:String? { "Daily communication-review call limit reached. Source collection continues; pending assessment is kept for the next day." } }
