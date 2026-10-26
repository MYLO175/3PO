import Foundation

@main struct AIActivityChecks {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label); checks += 1
        }
        enum FixtureFailure: Error { case unavailable }
        check(!AIActivityStatus.succeeded.isFailure && !AIActivityStatus.stopped.isFailure && !AIActivityStatus.needsAnswer.isFailure,"Success, targeted Stop and questions do not raise failure alerts")
        check(AIActivityStatus.failed.isFailure && AIActivityStatus.partial.isFailure && AIActivityStatus.uncertain.isFailure,"Failed and unconfirmed action outcomes raise failure alerts")
        check(!AIActivityWork.includes([]),"Conversation-only replies never become activity")
        check(!AIActivityWork.includes(["read_memory","read_life_notebook","ask_clarification"]),"Context lookup and ordinary clarification do not turn conversation into work")
        check(!AIActivityWork.includes(["unknown_tool"]),"Unknown tool names cannot invent work")
        check(AIActivityWork.includes(["change_calendar"]),"An attempted Calendar change stays visible even before a save succeeds")
        check(!AIActivityWork.includes(["search_mail","read_calendar","read_life_items"]),"Context reads do not become action outcomes")
        check(AIActivityWork.includes(["execute_review_actions"]),"Prepared actions executed through Review are action work")
        check(AIActivityWork.includes([],confirmed:3) && AIActivityWork.includes([],unconfirmed:1),"Verified or uncertain operation receipts keep actual actions visible")
        check(AIActivityWork.running(["read_memory","change_reminder"]) == "Updating Reminders…","Live activity describes the typed operation")
        check(AIActivityWork.completed(["change_calendar"],receipts:["Added the reviewed event"],confirmed:1) == "Added the reviewed event","Completed activity uses verified receipts instead of chat prose")
        check(AIActivityWork.completed(["read_calendar"],receipts:[],confirmed:0) == "Checked Calendar","Read-only work does not claim a saved change")
        check(AIActivityWork.completed(["change_calendar"],receipts:[],confirmed:0) == "No new changes were confirmed.","A mutation tool name alone cannot claim completion")
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        func record(_ id: String, registration: String = "account-a", state: AIActivityStatus = .queued,
                    kind: AIActivityKind = .review, offset: Double = 0,
                    destination: AIActivityDestination? = .review(targetID: "review-exact")) -> AIActivityRecord {
            .init(id: id, registration: registration, kind: kind, state: state, title: "IIB project dates",
                  message: "Ready to add the reviewed dates", created: date.addingTimeInterval(offset),
                  finished: state.isTerminal ? date.addingTimeInterval(offset + 10) : nil, destination: destination)
        }
        do {
            let success=record("success",state:.succeeded,offset:50)
            let heartbeat=record("heartbeat",state:.succeeded,kind:.heartbeat,offset:90)
            let question=record("question",state:.needsAnswer,offset:30)
            let failure=record("failure",state:.failed,offset:40)
            let running=record("running",state:.running,offset:100)
            func pill(_ records:[AIActivityRecord],_ current:AIActivityRecord?=nil)->AIActivityRecord? {AIActivityPillRules.displayed(records,current:current,registration:"account-a",now:date.addingTimeInterval(60))}
            check(pill([success,heartbeat])?.id == success.id,"Idle pill shows completed action instead of Ready and excludes heartbeat completion")
            check(pill([success,question])?.id == question.id,"An unanswered question takes priority over success")
            check(pill([success,question,failure])?.id == failure.id,"The newest unresolved attention outcome is shown")
            check(pill([failure,question],running)?.id == running.id,"A live task takes priority while running")
            var replied=question;replied.state = .replied
            check(pill([success,replied])?.id == success.id && !replied.needsAttention,"A replied question stops competing with the current success")
            var acknowledged=success;acknowledged.acknowledged=true
            check(pill([acknowledged,record("older",state:.succeeded)]) == nil,"Acknowledging the latest success returns to Ready without resurrecting older successes")
            var acknowledgedFailure=failure;acknowledgedFailure.acknowledged=true
            check(pill([success,acknowledgedFailure])?.id == success.id,"Acknowledged failures do not hide a later success")
            check(pill([record("other",registration:"account-b",state:.needsAnswer),success])?.id == success.id,"Pill selection stays account scoped")
            check(pill([heartbeat,record("ghost",state:.running)]) == nil,"Historical heartbeat and stale running rows never appear as current work")
            check(pill([failure],record("live-heartbeat",state:.running,kind:.heartbeat))?.kind == .heartbeat,"The live heartbeat remains visible while its completion stays out of history")
            check(pill([record("stopped",state:.stopped,offset:100),success]) == nil,"A stopped latest request does not revive an earlier green success")
            check(AIActivityPillRules.displayed([success],current:nil,registration:"account-a",now:date.addingTimeInterval(65))?.id == success.id,"Green success lasts six seconds")
            check(AIActivityPillRules.displayed([success],current:nil,registration:"account-a",now:date.addingTimeInterval(66)) == nil,"Success expires at its exact deadline without acknowledgement")
            check(AIActivityPillRules.displayed([success],current:nil,registration:"account-a",now:date.addingTimeInterval(600)) == nil,"Reopening does not flash an old success")
            check(AIActivityPillRules.displayed([failure],current:nil,registration:"account-a",now:date.addingTimeInterval(600))?.id == failure.id,"Failure attention is retained after the success timeout")
            let history=(0..<9).map{record("task-\($0)",state:.succeeded,offset:Double($0))}
            let recent=AIActivitySummary.recent(history+[heartbeat,replied],current:nil,registration:"account-a",now:date.addingTimeInterval(120))
            check(recent.count == 5 && recent.first?.id == "task-8" && history.count == 9,"Five recent tasks exclude heartbeat and resolved prompts without deleting history")
            check(AIActivitySummary.recent(history,current:running,registration:"account-a",now:date.addingTimeInterval(120)).first?.id == running.id,"Live work leads the five recent tasks")
            check(AIActivitySummary.recent([running],current:running,registration:"account-a",now:date.addingTimeInterval(120)).count == 1,"A current task is shown once")
            check(AIActivitySummary.text("Created reminder: Ask Dad") == "Reminder created: Ask Dad","Canonical Reminder receipt uses natural language")
            check(AIActivitySummary.text("Reminder created: Ask Dad",compact:true) == "Reminder created","Pill omits the title and extra detail")
            check(AIActivitySummary.text("Completed: Created **“Ask Dad”** in To do, without a due date.",hint:"Reminder") == "Reminder created: Ask Dad","Older verified Review outcomes lose Markdown and unnecessary detail")
            check(AIActivitySummary.text("Created event: Random event",compact:true) == "Calendar event created","Calendar success has a concise pill label")
            check(AIActivitySummary.text("No new changes were confirmed.",hint:"Reminder",compact:true) == "No new changes were confirmed.","A kind hint cannot invent creation")
            var readOnly=success;readOnly.message="Checked Reminders"
            check(AIActivitySummary.recent([readOnly],current:nil,registration:"account-a",now:date.addingTimeInterval(120)).isEmpty,"Historical context-only results do not occupy task history")
            check(AIActivitySummary.recent([record("waiting",state:.queued)],current:nil,registration:"account-a",now:date.addingTimeInterval(120)).isEmpty,"Never-started feedback remains saved without crowding completed task history")
            check(AIActivitySummary.text("Recreated London visit (tentative) as an all-day event for Saturday.",hint:"Calendar event") == "Calendar event created: London visit (tentative)","Older verified Calendar outcomes omit scheduling prose")
            check(AIActivitySummary.text("Space created: Orion follow-up",compact:true) == "Space created","Prepared space success uses a short label")
            check(AIActivitySummary.recent([record("ghost",state:.running)],current:nil,registration:"account-a",now:date.addingTimeInterval(120)).isEmpty,"Saved running rows need an exact live owner")
            check(AIActivitySummary.recent([record("other",registration:"account-b",state:.succeeded)],current:nil,registration:"account-a",now:date.addingTimeInterval(120)).isEmpty,"Recent activity stays account scoped")
            let failedHeartbeat=record("failed-heartbeat",state:.failed,kind:.heartbeat,offset:95)
            let partialHeartbeat=record("partial-heartbeat",state:.partial,kind:.heartbeat,offset:94)
            let heartbeatHistory=AIActivityStatus.allCases.map{record("heartbeat-"+$0.rawValue,state:$0,kind:.heartbeat)}
            check(Set(AIActivitySummary.recent(heartbeatHistory,current:nil,registration:"account-a",now:date.addingTimeInterval(120)).map(\.state)) == [.failed,.partial],"Only failed/partial heartbeat analysis enters Activity; success, sleep, Stop, waiting and stale running outcomes stay hidden")
            check(AIActivitySummary.recent([failedHeartbeat,partialHeartbeat,heartbeat],current:nil,registration:"account-a",now:date.addingTimeInterval(120)).map(\.id) == [failedHeartbeat.id,partialHeartbeat.id],"Newer successful heartbeat stays hidden without erasing earlier failure history")
            check(AIActivitySummary.recent([failedHeartbeat,partialHeartbeat],current:nil,registration:"account-b",now:date.addingTimeInterval(120)).isEmpty,"Heartbeat failures remain account scoped")
            check(AIActivitySummary.recent(history+[failedHeartbeat,partialHeartbeat,heartbeat],current:nil,registration:"account-a",now:date.addingTimeInterval(120)).count == 5,"Heartbeat failures share the existing five-outcome Activity bound")
            check(pill([failedHeartbeat,partialHeartbeat])?.id == failedHeartbeat.id,"The newest actual heartbeat failure appears as a dismissible pill alert")
            check(pill([failedHeartbeat,partialHeartbeat],running)?.id == running.id,"Live work keeps priority over failed and partial heartbeat alerts")
            check(pill(heartbeatHistory)?.kind == .heartbeat && [.failed,.partial].contains(pill(heartbeatHistory)!.state),"Only failed/partial heartbeat analysis can supply closed-pill attention")
            var dismissedHeartbeat=failedHeartbeat;dismissedHeartbeat.acknowledged=true
            var dismissedPartial=partialHeartbeat;dismissedPartial.acknowledged=true
            check(pill([dismissedHeartbeat,partialHeartbeat])?.id == partialHeartbeat.id,"Dismissing one heartbeat leaves the other exact unresolved alert visible")
            check(pill([dismissedHeartbeat,dismissedPartial,heartbeat]) == nil,"Dismissing all heartbeat alerts returns the pill to Ready")
            check(AIActivitySummary.recent([dismissedHeartbeat,dismissedPartial],current:nil,registration:"account-a",now:date.addingTimeInterval(120)).isEmpty,"Dismissed heartbeat failures leave the pill dropdown")
            let feedback=AIActivityFeedback(registration:"account-a",message:"Completed: Claim my refund",date:date.addingTimeInterval(61))
            func confirmation(_ displayed:AIActivityRecord?=nil,_ offset:Double=62,_ registration:String="account-a")->AIActivityFeedback? {
                AIActivityPillRules.feedback(feedback,displayed:displayed,registration:registration,now:date.addingTimeInterval(offset))
            }
            check(confirmation()?.message == feedback.message,"Direct UI completion appears in the idle pill")
            check(confirmation(success) != nil,"A newer direct UI confirmation supersedes an older AI success")
            check(confirmation(record("newer",state:.succeeded,offset:55)) == nil,"Newer AI completion supersedes earlier direct feedback")
            check(confirmation(running) == nil && confirmation(record("live-heartbeat",state:.running,kind:.heartbeat)) == nil,"Direct feedback never hides live work or heartbeat")
            check(confirmation(failure) == nil && confirmation(question) == nil,"Direct feedback never hides unresolved failure or question attention")
            check(confirmation(nil,66.999) != nil && confirmation(nil,67) == nil,"Direct completion expires after exactly six seconds")
            check(confirmation(nil,60) == nil && confirmation(nil,600) == nil,"Future or expired feedback never flashes on reopening")
            check(confirmation(nil,62,"account-b") == nil,"A direct completion cannot leak into another account")
        }
        do {
            var dismissalBytes:Data?
            let alerts=AIActivityStore(persist:{dismissalBytes=$0})
            let heartbeat=record("heartbeat:failed-run",state:.failed,kind:.heartbeat,destination:.heartbeat(targetID:"failed-run"))
            let question=record("new-question",state:.needsAnswer,offset:20)
            let other=record(heartbeat.id,registration:"account-b",state:.failed,kind:.heartbeat)
            check(alerts.upsert(heartbeat) && alerts.upsert(other),"Independent heartbeat alerts are saved before local dismissal")
            check(!alerts.dismiss(heartbeat,registration:"account-b"),"A captured alert cannot be dismissed in another account")
            check(!alerts.dismiss(record("unsaved",state:.failed),registration:"account-a"),"An unsaved alert cannot acknowledge another outcome")
            var changed=heartbeat;changed.message="The heartbeat saved a brief but memory analysis failed";changed.state = .partial
            check(alerts.upsert(changed),"The saved alert may receive a more precise outcome before dismissal")
            let beforeDismissal=alerts.state
            check(!alerts.dismiss(heartbeat,registration:"account-a") && alerts.state == beforeDismissal,"A stale alert control cannot dismiss a changed outcome")
            check(alerts.dismiss(changed,registration:"account-a"),"The exact displayed heartbeat alert can be dismissed")
            var expected=changed;expected.acknowledged=true
            check(alerts.records("account-a") == [expected] && alerts.records("account-b") == [other],"Dismissal changes only the exact alert acknowledgement and retains all outcomes")
            check(!alerts.dismiss(changed,registration:"account-a"),"Repeated dismissal cannot create a second acknowledgement")
            let reloaded=AIActivityStore(load:{dismissalBytes},persist:{_ in preconditionFailure("Dismissed alerts must not trigger recovery or replay")})
            check(reloaded.records("account-a") == [expected],"Heartbeat dismissal survives reopening without changing its failure or destination")
            check(AIActivitySummary.recent(reloaded.records("account-a"),current:nil,registration:"account-a",now:date.addingTimeInterval(120)).isEmpty,"A dismissed heartbeat stays out of the dropdown after reopening while its saved outcome remains")
            check(AIActivityPillRules.displayed(reloaded.records("account-a"),current:nil,registration:"account-a",now:date.addingTimeInterval(120)) == nil,"A dismissed heartbeat does not reappear in the pill after reopening")
            check(alerts.upsert(changed) && alerts.records("account-a") == [expected],"Reprojecting the same failed heartbeat preserves dismissal")
            check(alerts.upsert(question) && AIActivityPillRules.displayed(alerts.records("account-a"),current:nil,registration:"account-a",now:date.addingTimeInterval(120))?.id == question.id,"A later question still surfaces after heartbeat dismissal")
            check(alerts.dismiss(question,registration:"account-a"),"An unanswered action question can be dismissed without answering or executing it")
            let next=record("heartbeat:next-run",state:.failed,kind:.heartbeat,offset:40)
            check(alerts.upsert(next) && AIActivityPillRules.displayed(alerts.records("account-a"),current:nil,registration:"account-a",now:date.addingTimeInterval(120))?.id == next.id,"A new failed heartbeat has its own unresolved alert")
            let running=record("live",state:.running)
            let live=AIActivityStore()
            check(live.upsert(running) && !live.dismiss(running,registration:"account-a") && live.latest("account-a") == running,"Dismissal cannot stop or change running work")
            let success=record("success-only",state:.succeeded)
            check(live.upsert(success) && !live.dismiss(success,registration:"account-a"),"Dismiss controls apply to alerts rather than successful outcomes")
        }
        do {
            let day:TimeInterval = 24 * 60 * 60
            let alert=record("expiring",state:.failed,kind:.heartbeat)
            let deadline=alert.date.addingTimeInterval(day)
            for state in [AIActivityStatus.failed,.partial,.interrupted,.needsAnswer,.uncertain,.stopped,.succeeded] {
                var outcome=alert;outcome.kind = .action;outcome.state=state
                check(AIActivitySummary.recent([outcome],current:nil,registration:"account-a",now:deadline.addingTimeInterval(-0.001)).count == 1,"\(state) remains in the dropdown until its 24-hour deadline")
                check(AIActivitySummary.recent([outcome],current:nil,registration:"account-a",now:deadline).isEmpty,"\(state) disappears from the dropdown at exactly 24 hours")
            }
            check(AIActivityPillRules.displayed([alert],current:nil,registration:"account-a",now:deadline.addingTimeInterval(-0.001))?.id == alert.id,"A failed heartbeat remains in the closed pill just before 24 hours")
            check(AIActivityPillRules.displayed([alert],current:nil,registration:"account-a",now:deadline) == nil,"The closed pill returns to Ready at exactly 24 hours")
            check(AIActivitySummary.nextExpiry([alert],registration:"account-a",now:deadline.addingTimeInterval(-1)) == deadline,"The UI schedules the notification deadline without polling")
            check(AIActivitySummary.nextExpiry([alert],registration:"account-a",now:deadline) == nil,"Expired notifications do not schedule repeated wakeups")
            check(AIActivitySummary.nextExpiry([alert],registration:"account-b",now:deadline.addingTimeInterval(-1)) == nil,"Expiry scheduling stays account scoped")
            let new=record("new-alert",state:.needsAnswer,offset:day)
            check(AIActivitySummary.recent([alert,new],current:nil,registration:"account-a",now:deadline).map(\.id) == [new.id],"An expired failure does not crowd a genuinely new notification")
            let running=record("long-running",state:.running,offset:-day)
            check(AIActivityPillRules.displayed([alert],current:running,registration:"account-a",now:deadline)?.id == running.id,"A live owned job remains visible even when it started over a day ago")
            check(AIActivitySummary.recent([alert],current:running,registration:"account-a",now:deadline).map(\.id) == [running.id],"Notification expiry does not hide or stop live owned work")
            var persisted:Data?;var writes=0
            let store=AIActivityStore(persist:{persisted=$0;writes+=1})
            check(store.upsert(alert),"An expiring notification retains its original saved outcome")
            let reloaded=AIActivityStore(load:{persisted},persist:{_ in preconditionFailure("Expiry cannot write or replay activity")})
            check(AIActivitySummary.recent(reloaded.records("account-a"),current:nil,registration:"account-a",now:deadline).isEmpty && reloaded.latest("account-a") == alert && writes == 1,"Reopening after expiry hides the notification without deleting, acknowledging or replaying history")
            check(store.dismiss(alert,registration:"account-a") && AIActivitySummary.nextExpiry(store.records("account-a"),registration:"account-a",now:deadline.addingTimeInterval(-1)) == nil,"Explicit dismissal removes the notification and its pending expiry wakeup")
            check(store.undoAcknowledgement("account-a") && AIActivitySummary.recent(store.records("account-a"),current:nil,registration:"account-a",now:deadline).isEmpty,"Undo cannot revive an already expired notification")
            var delayed=record("delayed-feedback",state:.queued,kind:.feedback)
            check(store.upsert(delayed),"Feedback can wait for a later heartbeat")
            delayed.state = .failed
            check(store.upsert(delayed,now:deadline) && store.latest("account-a")?.finished == deadline,"A delayed outcome starts its notification lifetime when it finishes")
            check(store.upsert(delayed,now:deadline.addingTimeInterval(day)) && store.latest("account-a")?.finished == deadline,"Reprojection does not renew the captured outcome time")
            check(AIActivitySummary.recent(store.records("account-a"),current:nil,registration:"account-a",now:deadline.addingTimeInterval(day)).isEmpty,"Delayed feedback expires once without being revived by reprojection")
        }
        var bytes: Data?
        var writes = 0
        var rejectSave = false
        let store = AIActivityStore(load: { bytes }, persist: { data in
            if rejectSave { throw FixtureFailure.unavailable }
            bytes = data; writes += 1
        })
        check(store.readable && store.records("account-a").isEmpty && writes == 0, "Empty storage requires no writes or job startup")
        var review = record("review-request")
        check(store.upsert(review), "Queue output can be saved before execution")
        check(store.records("account-a").count == 1 && store.latest("account-b") == nil, "Saved output is scoped to its account")
        let queuedBytes = bytes
        let queuedWrites = writes
        check(store.upsert(review) && writes == queuedWrites, "Identical updates keep one event without repeated storage")
        let queuedReload = AIActivityStore(load: { queuedBytes })
        check(queuedReload.latest("account-a")?.state == .queued, "Reopening retains unstarted queued metadata")
        check(queuedReload.readable, "A queued job does not require recovery or start itself")
        check(!store.acknowledge(review.id, registration: "account-a"), "A queued job cannot be acknowledged as an outcome")
        check(!store.acknowledge(review.id, registration: "account-b"), "Another account cannot acknowledge the job")
        review.state = .running; review.progress = 0.4; review.message = "Adding the approved Calendar entries"
        check(store.upsert(review), "Running progress updates the original identity")
        check(store.records("account-a").count == 1 && store.latest("account-a")?.progress == 0.4, "Progress never duplicates a job")
        let runningBytes = bytes
        var recoveredBytes: Data?
        let recovered = AIActivityStore(load: { runningBytes }, persist: { recoveredBytes = $0 })
        check(recovered.latest("account-a")?.state == .interrupted, "A saved running job reopens as interrupted")
        check(recovered.latest("account-a")?.progress == nil && recovered.latest("account-a")?.finished != nil, "Recovery does not claim completed progress")
        check(recovered.latest("account-a")?.id == review.id && recovered.latest("account-a")?.destination == review.destination, "Recovery preserves operation identity and exact navigation")
        check(recovered.latest("account-a")?.message == review.message, "Recovery preserves the last real message while labelling its interrupted outcome")
        check(recoveredBytes != nil && recovered.readable, "Interruption is durable without replaying work")
        let recoveredAgain = AIActivityStore(load: { recoveredBytes }, persist: { _ in preconditionFailure("Recovery must be stable") })
        check(recoveredAgain.latest("account-a")?.state == .interrupted, "Recovered records are not automatically retried on a second reopen")
        let recoveryFailure = AIActivityStore(load: { runningBytes }, persist: { _ in throw FixtureFailure.unavailable })
        check(recoveryFailure.readOnly && recoveryFailure.latest("account-a")?.state == .interrupted && recoveryFailure.error != nil, "Failed recovery preserves original storage and shows interruption read-only")

        review.state = .partial; review.progress = 0.8; review.finished = date.addingTimeInterval(20)
        review.message = "Four project tasks saved; one Calendar save is unconfirmed"
        check(store.upsert(review), "A partial outcome remains a partial outcome")
        check(store.latest("account-a")?.needsAttention == true, "Unacknowledged partial work needs attention")
        check(store.acknowledge(review.id, registration: "account-a"), "The human can acknowledge a terminal AI outcome")
        check(store.latest("account-a")?.acknowledged == true && store.latest("account-a")?.needsAttention == false, "Acknowledgement clears attention without changing the result")
        check(store.latest("account-a")?.state == .partial && store.latest("account-a")?.message == review.message, "Acknowledgement is distinct from underlying action completion")
        check(store.undoDate("account-a") != nil && store.undoLabel("account-a") != nil && store.undoDate("account-b") == nil, "Acknowledgement Undo is account-scoped")
        review.message = "The original Calendar save was verified"
        review.state = .succeeded; review.progress = 1; review.finished = date.addingTimeInterval(25)
        check(store.upsert(review) && store.latest("account-a")?.acknowledged == true, "Progress and outcome updates preserve the human acknowledgement")
        check(store.undoAcknowledgement("account-a"), "Acknowledgement Undo survives progress updates")
        check(store.latest("account-a")?.state == .succeeded && store.latest("account-a")?.message == review.message && store.latest("account-a")?.acknowledged == false, "Undo changes only acknowledgement, never restores stale job output")
        check(store.undoDate("account-a") == nil && !store.undoAcknowledgement("account-a"), "Acknowledgement has one-level Undo and no Redo")
        check(store.acknowledge(review.id, registration: "account-a") && !store.acknowledge(review.id, registration: "account-a"), "Repeated acknowledgement is a no-op")
        review.state = .running; review.finished = nil; review.progress = 0.2
        check(store.upsert(review) && store.latest("account-a")?.acknowledged == true, "The same event preserves acknowledgement even during a later live update")
        review.state = .succeeded; review.finished = date.addingTimeInterval(30)
        check(store.upsert(review), "A verified result remains attached to the original event")
        let successBytes = bytes
        let reloaded = AIActivityStore(load: { successBytes })
        check(reloaded.latest("account-a")?.acknowledged == true, "Acknowledgement persists across reopening")
        check(reloaded.undoDate("account-a") == nil, "Undo is a session receipt rather than persisted execution authority")
        let action=record("action-from-chat",state:.succeeded,kind:.action,destination:.assistant(targetID:"chat-exact"))
        check(AIActivityStore().upsert(action),"Actions started from chat have a distinct work kind")
        check(try! JSONDecoder().decode(AIActivityRecord.self,from:JSONEncoder().encode(action)).kind == .action,"The work kind survives storage")

        let other = record(review.id, registration: "account-b", state: .failed, offset: 35)
        check(store.upsert(other), "Independent accounts may retain the same upstream request id")
        check(store.records("account-a").count == 1 && store.records("account-b").count == 1, "Account-scoped identities cannot overwrite each other")
        check(store.latest("account-b")?.needsAttention == true && store.latest("account-a")?.state == .succeeded, "Failure state is exact to its account")
        check(store.acknowledge(other.id, registration: "account-b"), "Other-account acknowledgement has its own Undo")
        check(store.undoAcknowledgement("account-a") && store.latest("account-b")?.acknowledged == true, "Undo in one account preserves the other's acknowledgement")
        check(store.undoAcknowledgement("account-b") && store.latest("account-b")?.needsAttention == true, "Undo restores a failure's attention marker")
        let beforeFailure = store.state
        let beforeFailureBytes = bytes
        rejectSave = true
        check(!store.acknowledge(review.id, registration: "account-a") && store.state == beforeFailure && bytes == beforeFailureBytes, "Failed acknowledgement rolls back without losing history")
        check(store.error != nil && store.readable, "A save failure is visible and can be resolved without discarding history")
        check(!store.upsert(record("new-unsaved")) && store.records("account-a").count == 1, "An unsaved event never replaces the durable history")
        rejectSave = false
        check(store.upsert(record("second", state: .failed, offset: 50)), "A later successful save recovers local storage")
        check(store.error == nil && store.latest("account-a")?.id == "second", "Latest output is chosen by captured event time")
        check(store.acknowledge("second", registration: "account-a"), "A later event can be acknowledged")
        rejectSave = true
        check(!store.undoAcknowledgement("account-a") && store.latest("account-a")?.acknowledged == true && store.undoDate("account-a") != nil, "Failed Undo retains both acknowledgement and its receipt")
        rejectSave = false
        check(store.undoAcknowledgement("account-a"), "The same Undo can complete after storage becomes writable")

        let previous = store.state
        var retarget = review; retarget.created = date.addingTimeInterval(999)
        check(!store.upsert(retarget) && store.state == previous, "An existing event cannot change its captured creation identity")
        retarget = review; retarget.kind = .heartbeat
        check(!store.upsert(retarget) && store.state == previous, "An existing Review event cannot become a heartbeat")
        var invalid = record("invalid"); invalid.progress = .nan
        check(!store.upsert(invalid), "Invalid progress cannot be persisted")
        invalid.progress = 1.01
        check(!store.upsert(invalid), "Out-of-range progress cannot imply completion")
        invalid.progress = nil; invalid.finished = date.addingTimeInterval(-1)
        check(!store.upsert(invalid), "A finish time preceding its captured creation is rejected")
        invalid.finished = nil; invalid.destination = .project(targetID: "  ")
        check(!store.upsert(invalid), "An empty exact navigation target is rejected")
        invalid.destination = nil; invalid.registration = " "
        check(!store.upsert(invalid), "Unowned output cannot enter Activity")

        let encoder = JSONEncoder()
        let valid = AIActivityState(records: [record("kept", state: .uncertain)])
        let validData = try encoder.encode(valid)
        var storageAttempts = 0
        func readOnly(_ data: Data) -> AIActivityStore {
            AIActivityStore(load: { data }, persist: { _ in storageAttempts += 1 })
        }
        let future = try encoder.encode(AIActivityState(version: 2, records: valid.records))
        check(readOnly(future).readOnly, "Unknown schema versions remain read-only")
        let corrupt = readOnly(Data("corrupt".utf8))
        check(corrupt.readOnly && !corrupt.upsert(record("replacement")) && corrupt.error != nil, "Corrupt output is preserved instead of silently reset")
        let loadFailure = AIActivityStore(load: { throw FixtureFailure.unavailable }, persist: { _ in storageAttempts += 1 })
        check(loadFailure.readOnly && !loadFailure.upsert(record("replacement")), "Storage read failures never become an empty writable history")
        var root = try JSONSerialization.jsonObject(with: validData) as! [String: Any]
        root["futureField"] = "keep"
        check(readOnly(try! JSONSerialization.data(withJSONObject: root)).readOnly, "Unknown envelope fields cannot be dropped by a later save")
        root.removeValue(forKey: "futureField")
        var rows = root["records"] as! [[String: Any]]
        rows[0]["futureField"] = "keep"
        root["records"] = rows
        check(readOnly(try! JSONSerialization.data(withJSONObject: root)).readOnly, "Unknown record fields remain preserved read-only")
        rows[0].removeValue(forKey: "futureField")
        rows[0]["state"] = "futureStatus"
        root["records"] = rows
        check(readOnly(try! JSONSerialization.data(withJSONObject: root)).readOnly, "Unknown states are retained instead of misreported as success")
        rows[0]["state"] = "uncertain"
        rows[0]["destination"] = ["project": ["targetID": "exact", "futureField": "keep"]]
        root["records"] = rows
        check(readOnly(try! JSONSerialization.data(withJSONObject: root)).readOnly, "Unknown exact-target metadata is never overwritten")
        let duplicate = try encoder.encode(AIActivityState(records: valid.records + valid.records))
        check(readOnly(duplicate).readOnly, "Ambiguous duplicate identities block writes")
        check(storageAttempts == 0, "Unknown and corrupt records trigger no replacement storage writes")

        var manyBytes: Data?
        let many = AIActivityStore(persist: { manyBytes = $0 })
        for index in 0..<180 {
            precondition(many.upsert(record("operation-\(index)", state: .succeeded, offset: Double(index))), "Completed operation identity must be saved")
        }
        let manyReload = AIActivityStore(load: { manyBytes })
        check(manyReload.records("account-a").count == 180, "Activity does not prune earlier operation identities")
        check(manyReload.records("account-a").last?.id == "operation-0", "The earliest completed record remains inspectable")
        for destination in [AIActivityDestination.assistant(), .review(targetID: "r"), .heartbeat(targetID: "h"),
                            .project(targetID: "p"), .calendar(targetID: "c"), .reminders(targetID: "m"), .feedback(targetID: "f")] {
            let destinationRecord = record(destination.title, state: .succeeded, destination: destination)
            let decoded = try JSONDecoder().decode(AIActivityRecord.self, from: encoder.encode(destinationRecord))
            check(decoded.destination == destination, "Navigation preserves exact destination \(destination.title)")
        }
        check(AIActivityStatus.failed.needsAttention && AIActivityStatus.uncertain.needsAttention && !AIActivityStatus.succeeded.needsAttention, "Failures and uncertain outcomes remain distinct from success")
        check(!AIActivityStatus.running.isTerminal && !AIActivityStatus.queued.isTerminal && AIActivityStatus.stopped.isTerminal, "Only final outcomes can be acknowledged")
        let base = Date(timeIntervalSince1970: 1_900_000_000)
        let history = (0..<(AIActivityStore.finishedHistory + 5)).map { index in
            AIActivityRecord(id: "finished-\(index)", registration: "fictional", kind: .action, state: .succeeded, title: "Reminder created", message: "Done", created: base.addingTimeInterval(Double(index)), finished: base.addingTimeInterval(Double(index)))
        } + [AIActivityRecord(id: "still-running", registration: "fictional", kind: .chat, state: .running, title: "Working", message: "", created: base)]
        let kept = AIActivityStore.retained(history)
        check(kept.count == AIActivityStore.finishedHistory + 1 && kept.contains { $0.id == "still-running" } && !kept.contains { $0.id == "finished-0" } && kept.contains { $0.id == "finished-\(AIActivityStore.finishedHistory + 4)" }, "Only the oldest finished activity is trimmed; running work stays")
        print("AI activity: \(checks)/\(checks) checks passed")
    }
}
