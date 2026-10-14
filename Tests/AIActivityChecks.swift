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
        print("AI activity: \(checks)/\(checks) checks passed")
    }
}
