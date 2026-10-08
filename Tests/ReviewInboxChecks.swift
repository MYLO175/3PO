import Foundation
@main struct ReviewInboxChecks {
    static func main() throws {
        let now=Date.now,quote="The Orion prototype report deadline has moved to 20 October 2026."
        let targetTask=TaskItem(id:"exact-orion",listID:"studies",title:"Submit Orion prototype report",due:Calendar.current.date(from:DateComponents(year:2026,month:10,day:16)),hasTime:false,sourceLabel:"Studies",writable:true,recurring:false,modified:now)
        let target=DiscoveryNativeTarget.reminder(targetTask)
        let candidate=DiscoveryCandidate(alias:"wa_0",mailID:"opaque-message",evidence:"",followUpEvidence:"",sourceKind:"whatsapp",sourceChatID:"studies",sourceMessageID:"message",sourceIdentity:"linked",sourceRevision:"rev1",sourceLabel:"Orion project",sourceText:quote)
        let json=#"{"suggestions":[{"mailID":"wa_0","kind":"change","targetID":"reminder_0","newDate":"2026-10-20","hasTime":false,"connection":"The same distinctive Orion report is named in the message and reminder.","message":"The Orion message moves the deadline from 16 to 20 October. Review the reminder date?","evidence":"The Orion prototype report deadline has moved to 20 October 2026."}]}"#
        func decode(_ text:String,_ targets:[String:DiscoveryNativeTarget] = ["reminder_0":target]) throws->[PADiscovery] {try ProactiveRules.decode(text,candidates:[candidate],registration:"account",scope:"scope",now:now,targets:targets)}
        let record=try decode(json)[0],change=record.proposedChange!
        precondition(change.target.itemID == targetTask.id && change.target.sourceID == "studies" && DateRules.localDate(change.date()!) == "2026-10-20")
        precondition(change.target.matches(events:[],reminders:[targetTask],excludedCalendars:[],excludedLists:[]))
        var moved=targetTask;moved.due=change.date()
        precondition(!change.target.matches(events:[],reminders:[moved],excludedCalendars:[],excludedLists:[]))
        moved=targetTask;moved.modified=now.addingTimeInterval(1)
        precondition(!change.target.matches(events:[],reminders:[moved],excludedCalendars:[],excludedLists:[]))
        precondition(!change.target.matches(events:[],reminders:[targetTask],excludedCalendars:[],excludedLists:["studies"]))
        func reject(_ text:String,_ targets:[String:DiscoveryNativeTarget] = ["reminder_0":target]) {do {_=try decode(text,targets);fatalError("Unexpected proposal accepted")}catch{}}
        reject(json.replacingOccurrences(of:"reminder_0",with:"invented"))
        reject(json.replacingOccurrences(of:"2026-10-20",with:"2026-02-30"))
        reject(json.replacingOccurrences(of:quote,with:"invented evidence"))
        reject(json.replacingOccurrences(of:"\"change\"",with:"\"delete\""))
        var readOnly=target;readOnly.writable=false;reject(json,["reminder_0":readOnly])
        reject(json.replacingOccurrences(of:"2026-10-20",with:"2026-10-16"))
        var changed=record;changed.proposedChange?.newDate="2026-10-21"
        precondition(ProactiveRules.unreported([record],prior:[record]).isEmpty)
        precondition(ProactiveRules.unreported([changed],prior:[record]).count == 1)
        var previousUpdate=record;previousUpdate.kind="update";previousUpdate.proposedChange=nil
        precondition(ProactiveRules.unreported([record],prior:[previousUpdate]).count == 1)
        var otherZone=record;otherZone.proposedChange?.timeZoneID="Pacific/Honolulu"
        precondition(ProactiveRules.unreported([record],prior:[otherZone]).count == 1)
        precondition(otherZone.proposedChange?.date() == nil)
        var many=ProactiveProgress();many.delivered=10000
        precondition(ProactiveRules.allowed(many,now:now,manual:true))
        precondition(ProactiveRules.allowed(many,now:now,heartbeat:true,comparisonLimit:96))
        var stopped=many;stopped.paused=true;stopped.lastAttempt=now;stopped.attempts=1
        precondition(!ProactiveRules.allowed(stopped,now:now,heartbeat:true,comparisonLimit:96,cooldown:3600))
        precondition(ProactiveRules.allowed(stopped,now:now.addingTimeInterval(3600),heartbeat:true,comparisonLimit:96,cooldown:3600),"A fresh due heartbeat can recover a failed comparison")
        precondition(!ProactiveRules.allowed(stopped,now:now.addingTimeInterval(3600)),"Independent discovery retains explicit retry policy")
        stopped.attempts=96
        precondition(!ProactiveRules.allowed(stopped,now:now.addingTimeInterval(3600),heartbeat:true,comparisonLimit:96,cooldown:3600),"Recovery cannot bypass comparison allowance")
        let versions=Dictionary(uniqueKeysWithValues:(0..<8).map{(ProactiveRules.sourceKey("whatsapp",String($0)),"v1")})
        let firstKeys=Set((0..<3).map{ProactiveRules.sourceKey("whatsapp",String($0))})
        let limited=ProactiveRules.completing(many,versions:versions,context:"epoch",limited:true,reportedKeys:firstKeys)
        precondition(limited.assessedSourceVersions?.count == 3)
        precondition(!ProactiveRules.assessed(limited,kind:"whatsapp",id:"7",revision:"v1",context:"epoch"))
        let quiet=ProactiveRules.completing(limited,versions:versions,context:"epoch",limited:false,reportedKeys:[])
        precondition(quiet.assessedSourceVersions?.count == 8)
        precondition(ProactiveRules.assessed(quiet,kind:"whatsapp",id:"7",revision:"v1",context:"epoch"))
        precondition(!ProactiveRules.assessed(quiet,kind:"whatsapp",id:"7",revision:"v2",context:"epoch"))
        precondition(!ProactiveRules.assessed(quiet,kind:"whatsapp",id:"7",revision:"v1",context:"changed-native-context"))
        let restored=try JSONDecoder().decode(ProactiveState.self,from:JSONEncoder().encode(ProactiveState(accounts:["account":quiet],records:[record])))
        precondition(restored.records == [record] && restored.accounts["account"]?.assessedSourceVersions == quiet.assessedSourceVersions)
        var legacy=record;legacy.proposedChange=nil;legacy.reviewState=nil;legacy.reviewedAt=nil
        let legacyRoundtrip=try JSONDecoder().decode(PADiscovery.self,from:JSONEncoder().encode(legacy));precondition(legacyRoundtrip.proposedChange == nil)
        let timed=DiscoveryDateChange(target:target,newDate:"2026-10-20T17:00:00+01:00",hasTime:true,connection:"Exact quoted time",timeZoneID:TimeZone.current.identifier)
        precondition(timed.date() == ISO8601DateFormatter().date(from:"2026-10-20T16:00:00Z"))
        let weekQuote="The form deadline has moved to Wednesday of week one."
        var weekCandidate=candidate;weekCandidate.sourceText=weekQuote
        let weekJSON=json.replacingOccurrences(of:quote,with:weekQuote)
        let grounded=try ProactiveRules.decode(weekJSON,candidates:[weekCandidate],registration:"account",scope:"scope",now:now,targets:["reminder_0":target])[0]
        precondition(grounded.kind == "update" && grounded.proposedChange == nil && grounded.message.contains("Date needs clarification"))
        precondition(grounded.evidence == weekQuote && grounded.sourceRevision == candidate.sourceRevision)
        var oldWeek=record;oldWeek.evidence=weekQuote
        let projected=ProactiveRules.reviewProjection(oldWeek)
        precondition(projected.id == oldWeek.id && projected.kind == "update" && projected.proposedChange == nil && oldWeek.proposedChange != nil)
        precondition(projected.sourceAssessmentRevision == oldWeek.sourceAssessmentRevision && projected.evidence == oldWeek.evidence)
        oldWeek.reviewState="pending";precondition(ProactiveRules.reviewProjection(oldWeek) == oldWeek,"An uncertain save receipt must remain inspectable")
        oldWeek.reviewState="approved";precondition(ProactiveRules.reviewProjection(oldWeek) == oldWeek,"An approved receipt must never be rewritten")
        precondition(ProactiveRules.reviewProjection(record) == record,"An explicitly dated source remains reviewable")
        // A source stays pending across capped responses, exhausted allowance and
        // restart. Simulated responses use the real decoder and persisted receipts.
        var review=PAHeartbeatAccount(),timeline=ProactiveState(accounts:["fixture":.init()])
        let mailVersions=Dictionary(uniqueKeysWithValues:(0..<8).map{(ProactiveRules.sourceKey("mail","fixture-\($0)"),"v1")})
        var issued=0
        func round(_ time:Date)throws {
            let day=BriefingRules.day(time)
            guard PAHeartbeatRules.due(review,now:time,day:day,allowance:2) else {return}
            let progress=timeline.accounts["fixture"]!
            let waiting=(0..<8).filter{!ProactiveRules.assessed(progress,kind:"mail",id:"fixture-\($0)",revision:"v1",context:"stable")}
            review.checked=time
            guard !waiting.isEmpty else {
                review=PAHeartbeatRules.quiet(review,fingerprint:"stable",ready:[],pending:false);return
            }
            do {review=try PAHeartbeatRules.claim(review,day:day,limit:2)} catch is HeartbeatBudgetExhausted {
                review=PAHeartbeatRules.deferred(review,now:time,reason:.allowance);return
            }
            issued += 1
            let batch=Array(waiting.prefix(3)),candidates=batch.map{DiscoveryCandidate(alias:"mail_\($0)",mailID:"fixture-\($0)",evidence:"Submit fictional report \($0) by 20 October 2026.",followUpEvidence:"",sourceRevision:"v1")}
            let payload:[String:Any]=["suggestions":candidates.map{["mailID":$0.alias,"kind":"reminder","message":"Review this fictional report submission?","evidence":$0.evidence]}]
            let rows=try ProactiveRules.decode(String(decoding:try JSONSerialization.data(withJSONObject:payload),as:UTF8.self),candidates:candidates,registration:"fixture",scope:"fixture",now:time)
            timeline.records += ProactiveRules.unreported(rows,prior:timeline.records)
            timeline.accounts["fixture"]=ProactiveRules.completing(progress,versions:mailVersions,context:"stable",limited:batch.count == 3,reportedKeys:Set(batch.map{ProactiveRules.sourceKey("mail","fixture-\($0)")}))
            review.phase="idle";review.assessed=time;review.pending=timeline.accounts["fixture"]!.assessedSourceVersions?.count != 8
            review=PAHeartbeatRules.clearWait(review)
            timeline=try JSONDecoder().decode(ProactiveState.self,from:JSONEncoder().encode(timeline))
            review=PAHeartbeatRules.recovered(try JSONDecoder().decode(PAHeartbeatAccount.self,from:JSONEncoder().encode(review)),now:time)
        }
        let start=ISO8601DateFormatter().date(from:"2026-10-07T08:00:00Z")!
        try round(start);precondition(timeline.records.count == 3 && review.pending == true)
        try round(start.addingTimeInterval(3600));precondition(timeline.records.count == 6 && review.calls == 2 && review.pending == true)
        try round(start.addingTimeInterval(7200));precondition(issued == 2 && review.retryReason == "allowance" && review.pending == true)
        let nextDay=Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:start))!
        try round(nextDay);precondition(issued == 3 && timeline.records.count == 8 && review.calls == 1 && review.pending == false)
        for hour in 1...48 {try round(nextDay.addingTimeInterval(Double(hour)*3600))}
        precondition(issued == 3 && timeline.records.count == 8 && Set(timeline.records.map(\.mailID)).count == 8 && review.pending == false,"Quiet multi-day checks must neither repeat requests nor lose capped sources")
        print("PASS review inbox: exact issued target/evidence, date semantics, stale native/scope/timezone rejection, distinct proposed vs confirmed links, duplicate suppression, no daily output cap, persisted quiet/limited-batch progress and legacy decode. No native writes or AI.")
    }
}
