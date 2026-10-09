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
        let referenced = #"{"suggestions":[{"mailID":"mail_0","kind":"reminder","message":"Review registration","evidenceID":"mail_0:primary"}]}"#
        let referencedRecords=try ProactiveRules.decode(referenced,candidates:candidates,registration:"A",scope:"s",now:.now)
        precondition(referencedRecords.first?.evidence == candidates[0].evidence,"Issued evidence reference attaches the exact original quote")
        let followup=try ProactiveRules.decode(referenced.replacingOccurrences(of:"mail_0:primary",with:"mail_0:followup"),candidates:candidates,registration:"A",scope:"s",now:.now)
        precondition(followup.first?.evidence == candidates[0].followUpEvidence)
        rejected(referenced.replacingOccurrences(of:"mail_0:primary",with:"mail_1:primary"))
        rejected(referenced.replacingOccurrences(of:"mail_0:primary",with:"invented"))
        rejected(#"{"suggestions":[{"mailID":"mail_0","kind":"reminder","message":"Review registration","evidenceID":"mail_0:primary","evidence":"invented quote"}]}"#)
        precondition(ProactiveRules.unreported(records,prior:records,budget:3).isEmpty)
        var dismissed = records[0]; dismissed.dismissed = true
        precondition(ProactiveRules.unreported(records,prior:[dismissed],budget:3).isEmpty)
        var anotherAccount = dismissed; anotherAccount.registration = "B"
        precondition(ProactiveRules.unreported(records,prior:[anotherAccount],budget:1).count == 1)
        precondition(ProactiveRules.unreported(records,prior:[],budget:0).isEmpty)
        var progress = ProactiveProgress(); precondition(ProactiveRules.allowed(progress,now:.now))
        progress.paused = true; precondition(!ProactiveRules.allowed(progress,now:.now)); precondition(ProactiveRules.allowed(progress,now:.now,manual:true))
        progress.delivered = 300; precondition(ProactiveRules.allowed(progress,now:.now,manual:true))
        progress.delivered = 0; progress.paused = false; progress.attempts = 4; precondition(!ProactiveRules.allowed(progress,now:.now))
        progress.attempts = 0; progress.lastAttempt = .now; precondition(!ProactiveRules.allowed(progress,now:.now))
        var heartbeat=ProactiveProgress();heartbeat.attempts=4
        precondition(ProactiveRules.allowed(heartbeat,now:.now,heartbeat:true))
        heartbeat.attempts=8;precondition(!ProactiveRules.allowed(heartbeat,now:.now,heartbeat:true))
        let update=try ProactiveRules.decode(good.replacingOccurrences(of:"\"reminder\"",with:"\"update\""),candidates:candidates,registration:"A",scope:"s",now:.now)[0]
        let updateTurn=AssistantTurn(role:"assistant",content:update.message,completed:true,deliveryID:update.deliveryID)
        precondition(ProactiveReviewRules.reference("yes",turns:[updateTurn],records:[update]) == nil, "Informational updates do not offer or implicitly create native items")
        var claimed=update;claimed.notificationClaimed=true
        let restoredClaim=try JSONDecoder().decode(PADiscovery.self,from:JSONEncoder().encode(claimed))
        precondition(restoredClaim.notificationClaimed == true)
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
        let message=WhatsAppReadMessage(id:"same-id",chat:"family",sender:"person",text:"Alex, please book the train for Friday.",sentByMe:false,time:Date.now.timeIntervalSince1970*1000)
        let candidate=DiscoveryCandidate(alias:"wa_0",mailID:"issued-wa",evidence:"",followUpEvidence:"",sourceKind:"whatsapp",sourceChatID:message.chat,sourceMessageID:message.id,sourceIdentity:"linked",sourceRevision:SourceContextRules.revision(message),sourceLabel:"Family",sourceText:message.text)
        let response=#"{"suggestions":[{"mailID":"wa_0","kind":"reminder","title":"Book the train","message":"Your family asked you to book the train. Shall I add a reminder?","evidence":"please book the train for Friday."}]}"#
        let wa=try ProactiveRules.decode(response,candidates:[candidate],registration:"A",scope:"s",now:.now)[0]
        var access=WhatsAppAccess(enabled:true,chats:["family"])
        precondition(ProactiveRules.permittedWhatsApp(wa,access:access,identity:"linked",messages:[message]))
        precondition(!ProactiveRules.permittedWhatsApp(wa,access:access,identity:"other",messages:[message]))
        precondition(!ProactiveRules.permittedWhatsApp(wa,access:access,identity:"linked",messages:[]))
        let edited=WhatsAppReadMessage(id:message.id,chat:message.chat,sender:message.sender,text:"Already booked, thanks",sentByMe:false,time:message.time)
        precondition(!ProactiveRules.permittedWhatsApp(wa,access:access,identity:"linked",messages:[edited]))
        access.chats=[];precondition(!ProactiveRules.permittedWhatsApp(wa,access:access,identity:"linked",messages:[message]))
        var changed=wa;changed.sourceRevision="changed"
        precondition(ProactiveRules.unreported([changed],prior:[wa],budget:1).count == 1)
        do { _=try ProactiveRules.decode(response.replacingOccurrences(of:"please book the train for Friday.",with:"invented evidence"),candidates:[candidate],registration:"A",scope:"s",now:.now);fatalError("Invented WhatsApp evidence accepted") } catch {}
        let waReference = #"{"suggestions":[{"mailID":"wa_0","kind":"reminder","message":"Review booking","evidenceID":"wa_0:primary"}]}"#
        do { _=try ProactiveRules.decode(waReference,candidates:[candidate],registration:"A",scope:"s",now:.now);fatalError("Mail evidence reference accepted for WhatsApp") } catch {}
        let reply=try EmailReplyDraftRules.decode(#"{"draft":"Thanks for the invitation. [Confirm availability]"}"#);precondition(reply.contains("[Confirm availability]"))
        let hbNow=Date.now
        precondition(!ProactiveRules.heartbeatMailEligible(received:hbNow.addingTimeInterval(-49*3600),now:hbNow))
        precondition(ProactiveRules.heartbeatMailEligible(received:hbNow.addingTimeInterval(-48*3600),now:hbNow))
        precondition(!ProactiveRules.heartbeatMailEligible(received:hbNow.addingTimeInterval(-48*3600-1),now:hbNow))
        precondition(ProactiveRules.heartbeatMailEligible(received:hbNow.addingTimeInterval(-7200),now:hbNow))
        let replyCandidate=DiscoveryCandidate(alias:"wa_reply",mailID:"reply-source",evidence:"",followUpEvidence:"",sourceKind:"whatsapp",sourceChatID:"selected",sourceMessageID:"reply-source",sourceIdentity:"link",sourceRevision:"v1",sourceText:"Could you confirm whether you can join our project meeting?")
        let replyPayload = #"{"suggestions":[{"mailID":"wa_reply","kind":"reply","message":"A project reply would help.","evidence":"Could you confirm whether you can join our project meeting?","draft":"Thanks. [Confirm whether you can attend]."}]}"#
        let localReplies=try ProactiveRules.decode(replyPayload,candidates:[replyCandidate],registration:"account",scope:"scope",now:.now)
        precondition(localReplies[0].replyDraft?.contains("[Confirm") == true && localReplies[0].proposedChange == nil)
        precondition(ProactiveRules.unreported(localReplies,prior:localReplies).isEmpty)
        let savedReply=try JSONDecoder().decode(PADiscovery.self,from:JSONEncoder().encode(localReplies[0]))
        precondition(savedReply == localReplies[0])
        do {_ = try ProactiveRules.decode(replyPayload.replacingOccurrences(of:"Could you confirm whether you can join our project meeting?",with:"invented quote"),candidates:[replyCandidate],registration:"account",scope:"scope",now:.now);preconditionFailure("Ungrounded reply accepted")} catch {}
        // Exact source chronology and persistent replacement chains; no native mutation.
        let target=DiscoveryNativeTarget(kind:"reminder",itemID:"orion",sourceID:"studies",title:"Orion",hasTime:false,writable:true,recurring:false,fingerprint:"native-v1")
        let initialDate=Date(timeIntervalSince1970:1791000000)
        var old=records[0];old.kind="change";old.sourceDate=initialDate;old.proposedChange = .init(target:target,newDate:"2026-10-20",hasTime:false,connection:"Same report",timeZoneID:TimeZone.current.identifier)
        let newSource=DiscoveryCandidate(alias:"wa_new",mailID:"new-revision",evidence:"",followUpEvidence:"",sourceKind:"whatsapp",sourceIdentity:"link",sourceRevision:"v2",sourceText:"Your Orion report deadline is now 22 October 2026.",sourceDate:initialDate.addingTimeInterval(3600))
        let correction = #"{"suggestions":[{"mailID":"wa_new","kind":"change","message":"Your deadline moved to 22 October.","evidence":"Your Orion report deadline is now 22 October 2026.","targetID":"reminder_0","newDate":"2026-10-22","hasTime":false,"connection":"Same Orion report.","replaces":["review_0"],"replacementReason":"A later correction replaces the earlier deadline for the same report."}]}"#
        func parse(_ payload:String,_ prior:PADiscovery=old,_ source:DiscoveryCandidate=newSource)throws->[PADiscovery] {try ProactiveRules.decode(payload,candidates:[source],registration:"A",scope:"s",now:initialDate.addingTimeInterval(7200),targets:["reminder_0":target],earlier:["review_0":prior])}
        func replacementRejected(_ body:()throws->Void) {do {try body();preconditionFailure("Unsafe replacement accepted")} catch {}}
        let corrected=try parse(correction)[0]
        let chain=try ProactiveRules.reconciled([corrected],prior:[old],issued:["review_0":old],now:corrected.created)
        precondition(chain[0].supersededBy == corrected.id && chain[1].replaces == [old.id] && chain[0].proposedChange?.newDate == "2026-10-20")
        let restoredChain=try JSONDecoder().decode([PADiscovery].self,from:JSONEncoder().encode(chain));precondition(restoredChain == chain)
        replacementRejected {_ = try parse(correction.replacingOccurrences(of:"review_0",with:"made-up"))}
        var foreign=old;foreign.registration="B";replacementRejected {_ = try parse(correction,foreign)}
        var pending=old;pending.reviewState="pending";replacementRejected {_ = try parse(correction,pending)}
        var approved=old;approved.reviewState="approved";replacementRejected {_ = try parse(correction,approved)}
        var superseded=old;superseded.supersededBy="newer";replacementRejected {_ = try parse(correction,superseded)}
        var otherPlan=old;otherPlan.proposedChange?.target.itemID="vega";replacementRejected {_ = try parse(correction,otherPlan)}
        var olderSource=newSource;olderSource.sourceDate=initialDate.addingTimeInterval(-1);replacementRejected {_ = try parse(correction,old,olderSource)}
        var raced=old;raced.dismissed=true;replacementRejected {_ = try ProactiveRules.reconciled([corrected],prior:[raced],issued:["review_0":old],now:.now)}
        replacementRejected {_ = try ProactiveRules.reconciled([corrected],prior:[old],issued:["review_0":old],now:.now,permittedEarlier:[])}
        replacementRejected {_ = try ProactiveRules.reconciled([],prior:[raced],issued:["review_0":old],now:.now,permittedEarlier:[old.id])}
        var dependent=corrected;dependent.comparisonSourceIDs=[old.id]
        precondition(ProactiveRules.comparisonEvidenceAvailable(dependent,records:[old],available:{_ in true}))
        precondition(!ProactiveRules.comparisonEvidenceAvailable(dependent,records:[old],available:{_ in false}))
        precondition(!ProactiveRules.comparisonEvidenceAvailable(dependent,records:[],available:{_ in true}))
        precondition(!ProactiveRules.comparisonEvidenceAvailable(dependent,records:[foreign],available:{_ in true}))
        var cancellationSource=newSource;cancellationSource.mailID="cancellation";cancellationSource.sourceText="Your Orion report submission is cancelled.";cancellationSource.sourceDate=corrected.created.addingTimeInterval(3600)
        let cancellation = #"{"suggestions":[{"mailID":"wa_new","kind":"update","message":"Your Orion submission is cancelled; check the existing reminder when convenient.","evidence":"Your Orion report submission is cancelled.","replaces":["review_0"],"replacementReason":"The tutor cancelled the same Orion submission."}]}"#
        let cancelled=try parse(cancellation,corrected,cancellationSource)[0]
        var cancelledChain=try ProactiveRules.reconciled([cancelled],prior:chain,issued:["review_0":corrected],now:cancelled.created)
        precondition(cancelledChain.last?.proposedChange == nil && cancelledChain.filter{$0.supersededBy == nil}.map(\.id) == [cancelled.id])
        cancelledChain[2].dismissed=true
        precondition(cancelledChain[0].supersededBy != nil && cancelledChain[1].supersededBy != nil,"Dismissing the cancellation cannot revive obsolete advice")
        let staleTurn=AssistantTurn(role:"assistant",content:old.message,completed:true,deliveryID:old.deliveryID)
        precondition(ProactiveReviewRules.reference("yes",turns:[staleTurn],records:cancelledChain) == nil)
        var legacyAck=dismissed;legacyAck.id="legacy-ack";legacyAck.sourceKind=nil
        var sameSource=legacyAck;sameSource.id="sibling-ack"
        var otherOwner=legacyAck;otherOwner.registration="other"
        var retired=legacyAck;retired.supersededBy="replacement"
        var notDismissed=legacyAck;notDismissed.dismissed=false
        var waAck=legacyAck;waAck.id="wa-first";waAck.sourceKind="whatsapp";waAck.sourceChatID="a:b";waAck.sourceMessageID="c"
        var anotherChat=waAck;anotherChat.id="wa-second";anotherChat.sourceChatID="a";anotherChat.sourceMessageID="b:c"
        let unrelatedAcknowledgements=(0..<2000).map {n -> PADiscovery in var value=legacyAck;value.id="unrelated-\(n)";value.mailID="unrelated-mail-\(n)";return value}
        let index=ReviewAcknowledgementIndex(unrelatedAcknowledgements+[legacyAck,sameSource,sameSource,otherOwner,retired,notDismissed,waAck,anotherChat],registration:legacyAck.registration)
        precondition(index.mail[legacyAck.mailID]?.map(\.id) == [legacyAck.id,sameSource.id,sameSource.id],"Exact-source lookup preserves legacy mail, sibling order and duplicates while excluding retired/other-owner/undismissed records")
        precondition(index.whatsapp[.init(chat:"a:b",message:"c")]?.map(\.id) == [waAck.id] && index.whatsapp[.init(chat:"a",message:"b:c")]?.map(\.id) == [anotherChat.id],"Chat and message identity must remain separate typed keys")
        precondition(index.mail["missing"] == nil && index.whatsapp[.init(chat:"other",message:"c")] == nil)
        print("PASS proactive rules: grounded aliases/quotes, prohibited kinds, account dedup/dismissal, daily budget, pause/cooldown/persistence and conservative current-thread latest-suggestion review references.")
    }
}
