import Foundation
@main struct Checks {
    static func main() throws {
        precondition(BriefingRequestAvailability().reason == nil)
        let blocked: [BriefingRequestAvailability] = [
            .init(contextEnabled:false), .init(verified:false), .init(paused:true),
            .init(connectionBusy:true), .init(assistantBusy:true), .init(writing:true), .init(hasAccount:false)
        ]
        precondition(blocked.allSatisfy { $0.reason?.isEmpty == false },"Every skipped explicit brief request needs a visible explanation")
        precondition(BriefingRequestAvailability(verified:false,paused:true).reason?.contains("paused") == true,"Explain paused subscription access before verification")
        let originalSource=BriefingSource(id:"calendar_0",label:"Test event",kind:"calendar",date:nil,originalID:"stable-event")
        let nativePayload:[String:Any]=["calendar":[["id":"calendar_0","title":"Test event","start":"2026-10-05T10:00:00+01:00"]],"calendarCoverage":"Seven days"]
        let originalSnapshot=try BriefingRules.sourceSnapshot(nativePayload,sources:[originalSource])
        for _ in 0..<100 {
            let reordered:[String:Any]=["calendarCoverage":"Seven days","calendar":[["start":"2026-10-05T10:00:00+01:00","title":"Test event","id":"calendar_0"]]]
            let reread=try BriefingRules.sourceSnapshot(reordered,sources:[originalSource])
            precondition(reread == originalSnapshot,"Equivalent re-read after a notification must remain valid")
        }
        var changedPayload=nativePayload;changedPayload["calendar"]=[["id":"calendar_0","title":"Test event","start":"2026-10-05T11:00:00+01:00"]]
        let changedSnapshot=try BriefingRules.sourceSnapshot(changedPayload,sources:[originalSource])
        precondition(changedSnapshot != originalSnapshot,"Real timing changes must reject stale prose")
        var changedIdentity=originalSource;changedIdentity.originalID="different-event"
        let identitySnapshot=try BriefingRules.sourceSnapshot(nativePayload,sources:[changedIdentity])
        precondition(identitySnapshot != originalSnapshot,"Equal titles must never hide a changed source identity")
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let midnight = ISO8601DateFormatter().date(from: "2026-10-01T23:00:00Z")!
        let dateOnly = TaskItem(id: "fixture", listID: "list", title: "Fictional", due: midnight, hasTime: false, sourceLabel: "Test", writable: true, recurring: false)
        assert(DateRules.reminderDue(dateOnly, calendar: london) == "2026-10-02")
        var timed = dateOnly; timed.hasTime = true
        assert(DateRules.reminderDue(timed, calendar: london) == "2026-10-02T00:00:00+01:00")
        let formatter = ISO8601DateFormatter()
        for (utc,expected) in [("2026-03-29T00:30:00Z","2026-03-29T00:30:00Z"),("2026-03-29T01:30:00Z","2026-03-29T02:30:00+01:00"),("2026-10-25T00:30:00Z","2026-10-25T01:30:00+01:00"),("2026-10-25T01:30:00Z","2026-10-25T01:30:00Z")] {
            let instant = formatter.date(from:utc)!
            let rendered = DateRules.localTimestamp(instant,calendar:london)
            assert(rendered == expected && formatter.date(from:rendered) == instant, "Local time must preserve exact instant across both DST changes")
        }
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date { c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))! }
        for (hour,minute,expected) in [(4,59,"evening"),(5,0,"morning"),(11,59,"morning"),(12,0,"afternoon"),(17,59,"afternoon"),(18,0,"evening"),(23,59,"evening")] {
            precondition(BriefingRules.period(date(2026,10,7,hour,minute),calendar:c) == expected)
        }
        let noonClock=BriefingRules.clockInput(date(2026,10,7,12),calendar:c)
        precondition(noonClock["now"] == "2026-10-07T12:00:00+01:00" && noonClock["greeting"] == "Good afternoon." && noonClock["dayPeriod"] == "afternoon" && noonClock["localDay"] == "2026-10-07")
        var newYork=c;newYork.timeZone=TimeZone(identifier:"America/New_York")!
        precondition(BriefingRules.greeting(date(2026,10,7,12),calendar:newYork) == "Good morning.","Greeting follows the supplied local timezone, not UTC or the machine's zone")
        for localDay in [date(2026,3,29,12),date(2026,10,25,12)] {
            precondition(BriefingRules.greeting(localDay,calendar:c) == "Good afternoon.","Noon remains afternoon across DST changes")
        }
        for day in [date(2026,3,29,7),date(2026,10,25,7),date(2026,12,31,7)] {
            assert(!BriefingRules.due(now: day, completed: [], calendar: c))
            let scheduled = c.date(bySettingHour: 7, minute: 30, second: 0, of: day)!
            assert(BriefingRules.due(now: scheduled, completed: [], calendar: c))
            let late = c.date(byAdding: .hour, value: 9, to: scheduled)!
            assert(BriefingRules.due(now: late, completed: [], calendar: c), "Catch up after sleep")
            assert(!BriefingRules.due(now: late, completed: [BriefingRules.day(late, calendar: c)], calendar: c), "No duplicate on relaunch")
        }
        var state = BriefingState()
        assert(state.claimNotification(day: "2026-10-02")); assert(!state.claimNotification(day: "2026-10-02"))
        let data = try JSONEncoder().encode(state)
        var restored = try JSONDecoder().decode(BriefingState.self, from: data)
        assert(!restored.claimNotification(day: "2026-10-02")); assert(restored.claimNotification(day: "2026-10-03"))
        let good = #"{"items":[{"text":"A meeting is scheduled.","sourceIDs":["known-event"]}]}"#
        let items = try BriefingRules.decode(good, allowedSources: ["known-event"]); assert(items.count == 1)
        let memoryInput=BriefingRules.memoryInput([["id":"fictional-memory-identity","text":"Fictional context"]])
        precondition(memoryInput[0]["id"] == "memory_0" && memoryInput[0]["memoryID"] == "fictional-memory-identity" && memoryInput[0]["text"] == "Fictional context","Memory records must use the same citation field as other sources without losing original identity")
        for (json,kind) in [(good.replacingOccurrences(of:"known-event",with:"invented-id"),"unknown"),(#"{"items":[{"text":"Event","sourceIDs":["known-event","known-event"]}]}"#,"duplicate")] {
            do {_ = try BriefingRules.decode(json,allowedSources:["known-event"]);preconditionFailure("Invalid citations must stay rejected")}
            catch BriefingFailure.unknownSources {precondition(kind == "unknown")}
            catch BriefingFailure.duplicateSources {precondition(kind == "duplicate")}
        }
        for invalid in [good.replacingOccurrences(of: "known-event", with: "invented-id"), #"{"items":[]}"#, #"{"items":[{"text":" ","sourceIDs":[]}]}"#, #"{"items":[{"text":"Event","sourceIDs":["known-event","known-event"]}]}"#] {
            var rejected = false; do { _ = try BriefingRules.decode(invalid, allowedSources: ["known-event"]) } catch { rejected = true }; assert(rejected)
        }
        let proseOutput = #"{"message":"Good morning. A meeting is scheduled today.","items":[{"text":"A meeting is scheduled.","sourceIDs":["known-event"]}]}"#
        let morningMessage = try BriefingRules.message(proseOutput); precondition(morningMessage == "Good morning. A meeting is scheduled today.")
        let legacyMessage = try BriefingRules.message(good); precondition(legacyMessage == nil)
        var blankRejected = false; do { _ = try BriefingRules.message(#"{"message":"  "}"#) } catch { blankRejected = true }; precondition(blankRejected)
        let morning = DailyBriefing(id:"morning",registration:"account",day:"2026-10-02",created:date(2026,10,2,7,30),items:items,sources:[],coverage:"partial",sourceScope:"scope",message:"Good morning")
        var fallback=morning;fallback.message=nil;fallback.created=date(2026,10,2,14)
        precondition(BriefingRules.prose(fallback,calendar:c).hasPrefix("Good afternoon."))
        fallback.created=date(2026,10,2,20)
        precondition(BriefingRules.prose(fallback,calendar:c).hasPrefix("Good evening."))
        precondition(BriefingRules.prose(morning,calendar:c) == "Good morning","Stored message prose remains immutable; the clock does not rewrite history")
        var update = morning; update.id = "update"; update.morningID = morning.id; update.created = date(2026,10,2,12); update.message = "This afternoon"
        let noon = date(2026,10,2,12)
        assert(BriefingRules.current(morning:morning,update:update,now:noon,calendar:c).id == "update")
        for invalid in 0..<5 {
            var changed = update
            switch invalid {
            case 0: changed.registration = "other"
            case 1: changed.morningID = "replaced-morning"
            case 2: changed.sourceScope = "excluded-source"
            case 3: changed.day = "2026-10-01"
            default: changed.created = date(2026,10,2,6)
            }
            assert(BriefingRules.current(morning:morning,update:changed,now:noon,calendar:c).id == "morning")
        }
        assert(BriefingRules.current(morning:morning,update:update,now:date(2026,10,3,8),calendar:c).id == "morning")
        restored.records = [morning]; restored.updatedBriefs = ["account":update]
        let roundTrip = try JSONDecoder().decode(BriefingState.self,from:JSONEncoder().encode(restored))
        assert(roundTrip.records.first?.message == "Good morning" && roundTrip.updatedBriefs?["account"]?.message == "This afternoon")
        assert(roundTrip.notificationClaims == restored.notificationClaims)
        let legacy = try JSONDecoder().decode(BriefingState.self,from:Data(#"{"records":[],"notificationClaims":[],"paused":false}"#.utf8))
        assert(legacy.updatedBriefs == nil)
        precondition(legacy.writingPrompt("account").text == BriefingRules.defaultWritingPrompt && legacy.writingPrompt("account").revision == nil)
        var promptState=restored
        let originalPrompt=promptState.writingPrompt("account")
        try promptState.setWritingPrompt("  Focus on engineering. Use three short bullet points.  ",expected:originalPrompt)
        let customPrompt=promptState.writingPrompt("account")
        precondition(customPrompt.text == "Focus on engineering. Use three short bullet points." && customPrompt.revision != originalPrompt.revision)
        precondition(promptState.writingPrompt("other").text == BriefingRules.defaultWritingPrompt,"Writing preferences cannot leak into another account")
        let promptRoundTrip=try JSONDecoder().decode(BriefingState.self,from:JSONEncoder().encode(promptState))
        precondition(promptRoundTrip.writingPrompt("account") == customPrompt && promptRoundTrip.records.map(\.id) == restored.records.map(\.id) && promptRoundTrip.updatedBriefs?["account"]?.id == update.id && promptRoundTrip.notificationClaims == restored.notificationClaims,"Prompt persistence must leave saved briefs and delivery claims intact")
        for invalid in [" ",String(repeating:"x",count:BriefingRules.writingPromptLimit+1)] {
            do {try promptState.setWritingPrompt(invalid,expected:customPrompt);preconditionFailure("Invalid prompt accepted")} catch BriefWritingPromptFailure.length {}
            precondition(promptState.writingPrompt("account") == customPrompt)
        }
        try promptState.setWritingPrompt(BriefingRules.defaultWritingPrompt,expected:customPrompt)
        precondition(promptState.writingPrompts?["account"] == nil && promptState.writingPrompt("account").text == originalPrompt.text && promptState.writingPrompt("account") != originalPrompt,"Restoring defaults cannot make an old in-flight capture valid again")
        do {try promptState.setWritingPrompt("Stale editor",expected:originalPrompt);preconditionFailure("Stale prompt capture accepted")} catch BriefWritingPromptFailure.changed {}
        var laterMorning=morning;laterMorning.id="legacy-second";laterMorning.created=noon;laterMorning.sourceScope="new-sources"
        var otherMorning=morning;otherMorning.registration="other-account"
        var invalidMorning=morning;invalidMorning.id="invalid";invalidMorning.created=date(2026,10,2,6);invalidMorning.invalidated=true
        let allRecords=[laterMorning,otherMorning,invalidMorning,morning,update]
        assert(BriefingRules.morning(records:allRecords,registration:"account",day:morning.day)?.id==morning.id)
        assert(BriefingRules.completedDays(records:allRecords,registration:"account")==[morning.day])
        assert(!BriefingRules.due(now:noon,completed:BriefingRules.completedDays(records:allRecords,registration:"account"),calendar:c))
        assert(BriefingRules.morning(records:allRecords,registration:"missing",day:morning.day)==nil)
        assert(BriefingRules.morning(records:allRecords,registration:"account",day:"2026-10-03")==nil)
        assert(BriefingRules.earlierMessage(morning:morning,sourceScope:"scope")=="Good morning")
        assert(BriefingRules.earlierMessage(morning:morning,sourceScope:"new-sources")==nil)
        var freshUpdate=update;freshUpdate.sourceScope="new-sources"
        assert(BriefingRules.current(morning:morning,update:freshUpdate,sourceScope:"new-sources",now:noon,calendar:c).id==freshUpdate.id)
        assert(BriefingRules.current(morning:morning,update:freshUpdate,sourceScope:"third-scope",now:noon,calendar:c).id==morning.id)
        var newState=restored;newState.records=allRecords;newState.updatedBriefs=["account":freshUpdate]
        let preserved=try JSONDecoder().decode(BriefingState.self,from:JSONEncoder().encode(newState))
        assert(preserved.records.map(\.id)==allRecords.map(\.id) && preserved.notificationClaims==restored.notificationClaims)
        assert(preserved.updatedBriefs?["account"]?.morningID==morning.id)
        var heartbeat=DailyBriefing(id:"heartbeat",registration:"owner",day:"2026-10-07",created:Date.now,items:[],sources:[originalSource],coverage:"Fictional",message:"Current brief",heartbeatID:"run-1")
        precondition(BriefingRules.latest(morning:nil,update:heartbeat,registration:"owner",day:heartbeat.day)?.id == heartbeat.id)
        precondition(BriefingRules.latest(morning:nil,update:heartbeat,registration:"another",day:heartbeat.day) == nil)
        precondition(BriefingRules.latest(morning:nil,update:heartbeat,registration:"owner",day:"2026-10-08") == nil)
        var cycleMorning=heartbeat;cycleMorning.id="later-morning";cycleMorning.created=heartbeat.created.addingTimeInterval(60);cycleMorning.heartbeatID=nil
        precondition(BriefingRules.latest(morning:cycleMorning,update:heartbeat,registration:"owner",day:heartbeat.day)?.id == cycleMorning.id)
        heartbeat.created=cycleMorning.created.addingTimeInterval(60);heartbeat.morningID=cycleMorning.id
        precondition(BriefingRules.latest(morning:cycleMorning,update:heartbeat,registration:"owner",day:heartbeat.day)?.id == heartbeat.id)
        let questionResponse = #"{"question":{"question":"Does the meeting still need preparation?","sourceIDs":["calendar_0"]}}"#
        let question=try BriefingRules.reviewQuestion(questionResponse,snapshot:heartbeat)!
        precondition(BriefingRules.unreportedQuestion(question,prior:[]))
        var dismissed=question;dismissed.dismissed=true;dismissed.question="Rephrased same uncertainty"
        precondition(!BriefingRules.unreportedQuestion(question,prior:[dismissed]),"Rephrasing a dismissed question cannot raise the same source again")
        var otherOwner=question;otherOwner.snapshot.registration="other"
        precondition(BriefingRules.unreportedQuestion(question,prior:[otherOwner]))
        let noQuestion=try BriefingRules.reviewQuestion(#"{"question":null}"#,snapshot:heartbeat);precondition(noQuestion == nil)
        for invalid in [questionResponse.replacingOccurrences(of:"calendar_0",with:"invented"),#"{"question":{"question":"Why?","sourceIDs":[]}}"#] {
            do {_ = try BriefingRules.reviewQuestion(invalid,snapshot:heartbeat);preconditionFailure("Invalid source question accepted")} catch {}
        }
        var manualOnly=heartbeat;manualOnly.morningID=nil;manualOnly.heartbeatID=nil;manualOnly.widgetOnly=true
        precondition(BriefingRules.latest(morning:nil,update:manualOnly,registration:"owner",day:manualOnly.day)?.id == manualOnly.id,"Manual refresh of a standalone heartbeat brief stays widget-only")
        var questionState=BriefingState();questionState.reviewQuestions=[dismissed];questionState.updatedBriefs=["owner":heartbeat]
        let decodedState=try JSONDecoder().decode(BriefingState.self,from:JSONEncoder().encode(questionState))
        precondition(decodedState.reviewQuestions?.first?.dismissed == true && decodedState.updatedBriefs?["owner"]?.heartbeatID == "run-1")
        precondition(decodedState.records.isEmpty && decodedState.notificationClaims.isEmpty,"Heartbeat updates never claim a morning delivery or notification")
        print("PASS: account-scoped prompt/default persistence and stale captures; local dayparts/timezone/DST, immutable prose, catch-up, delivery claims and source validation")
    }
}
