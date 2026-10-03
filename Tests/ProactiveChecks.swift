import Foundation
@main struct ProactiveChecks {
    static func main() throws {
        let candidates = [DiscoveryCandidate(alias:"mail_0",mailID:"real-A",evidence:"Please register by 10 October.",followUpEvidence:"10 October")]
        let good = #"{"suggestions":[{"mailID":"mail_0","kind":"reminder","message":"I could not spot a registration reminder. Shall I add one?","evidence":"Please register by 10 October."}]}"#
        let records = try ProactiveRules.decode(good,candidates:candidates,registration:"A",scope:"s",now:.now)
        precondition(records.count == 1 && records[0].mailID == "real-A" && records[0].deliveryID.hasPrefix("discovery:"))
        func rejected(_ text: String) { do { _ = try ProactiveRules.decode(text,candidates:candidates,registration:"A",scope:"s",now:.now); fatalError("Unexpected acceptance") } catch {} }
        rejected(good.replacingOccurrences(of:"mail_0",with:"invented"))
        rejected(good.replacingOccurrences(of:"Please register by 10 October.",with:"Invented deadline"))
        rejected(good.replacingOccurrences(of:"\"reminder\"",with:"\"send_email\""))
        rejected(#"{"suggestions":[{"mailID":"mail_0","kind":"calendar","message":"Hi","evidence":""}]}"#)
        precondition(ProactiveRules.unreported(records,prior:records,budget:3).isEmpty)
        var dismissed = records[0]; dismissed.dismissed = true
        precondition(ProactiveRules.unreported(records,prior:[dismissed],budget:3).isEmpty)
        var anotherAccount = dismissed; anotherAccount.registration = "B"
        precondition(ProactiveRules.unreported(records,prior:[anotherAccount],budget:1).count == 1)
        precondition(ProactiveRules.unreported(records,prior:[],budget:0).isEmpty)
        var progress = ProactiveProgress(); precondition(ProactiveRules.allowed(progress,now:.now))
        progress.paused = true; precondition(!ProactiveRules.allowed(progress,now:.now)); precondition(ProactiveRules.allowed(progress,now:.now,manual:true))
        progress.delivered = 3; precondition(!ProactiveRules.allowed(progress,now:.now,manual:true))
        progress.delivered = 0; progress.paused = false; progress.attempts = 4; precondition(!ProactiveRules.allowed(progress,now:.now))
        progress.attempts = 0; progress.lastAttempt = .now; precondition(!ProactiveRules.allowed(progress,now:.now))
        let state = ProactiveState(accounts:["A":progress],records:[dismissed])
        let restored = try JSONDecoder().decode(ProactiveState.self,from:JSONEncoder().encode(state))
        precondition(restored.records == [dismissed] && restored.accounts["A"]?.lastAttempt != nil)
        let suggestion = AssistantTurn(role:"assistant",content:records[0].message,completed:true,deliveryID:records[0].deliveryID)
        for request in ["yes","Yes, please!","add that","put it in my reminders","Please add a reminder for that","add that pls"] {
            precondition(ProactiveReviewRules.reference(request,turns:[suggestion],records:records)?.id == records[0].id)
        }
        for request in ["don't add that","An email says: yes please", "add that and delete the original", "add that to my calendar", "yes, but only if I accept", "what about that?", ""] {
            precondition(ProactiveReviewRules.reference(request,turns:[suggestion],records:records) == nil)
        }
        precondition(ProactiveReviewRules.reference("yes",turns:[suggestion],records:[]) == nil)
        precondition(ProactiveReviewRules.reference("yes",turns:[suggestion],records:[dismissed]) == nil)
        let unrelated = AssistantTurn(role:"assistant",content:"Your unrelated question is answered.",completed:true)
        precondition(ProactiveReviewRules.reference("yes",turns:[suggestion,unrelated],records:records) == nil)
        let interrupted = AssistantTurn(role:"assistant",content:"Partial answer",completed:false)
        precondition(ProactiveReviewRules.reference("yes",turns:[suggestion,interrupted],records:records) == nil)
        var pa = AssistantConversation(accountID:"A",title:"Your PA",turns:[suggestion]); pa.isPrimary = true
        let study = AssistantConversation(accountID:"A",title:"Study",isTopic:true)
        precondition(ProactiveReviewRules.reference("yes",turns:ConversationRules.thread(feed:pa,topic:study),records:records) == nil)
        precondition(ProactiveReviewRules.reference("yes",turns:ConversationRules.thread(feed:pa,topic:nil),records:records) != nil)
        print("PASS proactive rules: grounded aliases/quotes, prohibited kinds, account dedup/dismissal, daily budget, pause/cooldown/persistence and conservative current-thread latest-suggestion review references.")
    }
}
