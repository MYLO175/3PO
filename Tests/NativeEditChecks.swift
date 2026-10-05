import Foundation
@main struct NativeEditChecks {
    static func main() throws {
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"Europe/London")!
        func date(_ day: Int, _ hour: Int = 0) -> Date { calendar.date(from:DateComponents(year:2026,month:10,day:day,hour:hour))! }
        let base = NativeEditDetails(kind:.event,itemID:"stable",occurrenceID:"occurrence",sourceID:"calendar",title:"Same title",notes:"Original notes",start:date(25,1),end:date(25,3),writable:true)
        var draft = base; draft.title = "Updated"; draft.notes = "Updated notes"; try NativeEditRules.validate(draft,baseline:base)
        func rejects(_ value: NativeEditDetails, _ original: NativeEditDetails) { do { try NativeEditRules.validate(value,baseline:original); preconditionFailure("Invalid edit accepted") } catch {} }
        var wrong = draft; wrong.itemID = "duplicate-title-other-ID"; rejects(wrong,base)
        wrong = draft; wrong.occurrenceID = "other-occurrence"; rejects(wrong,base)
        wrong = draft; wrong.end = wrong.start; rejects(wrong,base)
        wrong = draft; wrong.title = " \n"; rejects(wrong,base)
        var readOnly = base; readOnly.writable = false; rejects(draft,readOnly)
        var recurring = base; recurring.recurring = true; var move = recurring; move.sourceID = "different"; try NativeEditRules.validate(move,baseline:recurring)
        let proposal = NativeEventMoveProposal(occurrenceID:base.occurrenceID,sourceID:base.sourceID,originalStart:base.start,originalEnd:base.end,start:date(26,23))
        let moved = try NativeEditRules.moved(base,proposal:proposal)
        precondition(moved.start == proposal.start && moved.end.timeIntervalSince(moved.start) == base.end.timeIntervalSince(base.start))
        precondition(moved.notes == base.notes && moved.sourceID == base.sourceID && moved.timeZoneID == base.timeZoneID && moved.occurrenceID == base.occurrenceID)
        func rejectsMove(_ value: NativeEditDetails, _ proposed: NativeEventMoveProposal) { do { _ = try NativeEditRules.moved(value,proposal:proposed); preconditionFailure("Invalid move accepted") } catch {} }
        var changed = base; changed.start = changed.start.addingTimeInterval(60); rejectsMove(changed,proposal)
        rejectsMove(readOnly,proposal)
        var wrongProposal = proposal; wrongProposal.occurrenceID = "duplicate-other-occurrence"; rejectsMove(base,wrongProposal)
        wrongProposal = proposal; wrongProposal.sourceID = "other-calendar"; rejectsMove(base,wrongProposal)
        let movedRecurring = try NativeEditRules.moved(recurring,proposal:proposal); precondition(movedRecurring.recurring && movedRecurring.sourceID == recurring.sourceID)
        var verified = moved; verified.itemID = "verified-native-ID"; verified.occurrenceID = "verified-moved-occurrence"; verified.modified = .now
        let restored = try NativeEditRules.restoring(NativeEditUndo(original:base,saved:verified))
        precondition(restored.start == base.start && restored.end == base.end && restored.notes == base.notes)
        precondition(restored.itemID == verified.itemID && restored.occurrenceID == verified.occurrenceID && restored.modified == verified.modified)
        var unavailableUndo = verified; unavailableUndo.writable = false
        do { _ = try NativeEditRules.restoring(.init(original:base,saved:unavailableUndo)); preconditionFailure("Read-only Undo accepted") } catch {}
        let allDay = NativeEditRules.allDay(base,enabled:true,calendar:calendar)
        precondition(allDay.start == date(25) && allDay.end == date(26))
        precondition(allDay.end.timeIntervalSince(allDay.start) == 25*3600, "DST all-day duration follows calendar boundaries")
        let shiftedDay = NativeEditRules.movingStart(allDay,to:date(26,10),calendar:calendar)
        precondition(shiftedDay.start == date(26) && shiftedDay.end == date(27) && shiftedDay.end.timeIntervalSince(shiftedDay.start) == 24*3600)
        var multipleDays = allDay; multipleDays.start = date(24); multipleDays.end = date(27)
        let shiftedMultiple = NativeEditRules.movingStart(multipleDays,to:date(28,11),calendar:calendar)
        precondition(shiftedMultiple.start == date(28) && shiftedMultiple.end == date(31))
        let shiftedTimed = NativeEditRules.movingStart(base,to:date(26,22),calendar:calendar)
        precondition(shiftedTimed.end.timeIntervalSince(shiftedTimed.start) == base.end.timeIntervalSince(base.start))
        precondition(shiftedTimed.notes == base.notes && shiftedTimed.timeZoneID == base.timeZoneID && shiftedTimed.itemID == base.itemID)
        var midnight = base; midnight.start = date(24,20); midnight.end = date(25)
        let midnightDay = NativeEditRules.allDay(midnight,enabled:true,calendar:calendar)
        precondition(midnightDay.start == date(24) && midnightDay.end == date(25), "Exclusive midnight endpoint is preserved")
        precondition(NativeEditRules.allDay(allDay,enabled:true,calendar:calendar) == allDay)
        let timed = NativeEditRules.allDay(allDay,enabled:false,calendar:calendar)
        precondition(timed.end.timeIntervalSince(timed.start) == 3600 && calendar.component(.hour,from:timed.start) == 9)
        let reminder = NativeEditDetails(kind:.reminder,itemID:"reminder",occurrenceID:"reminder",sourceID:"list",title:"Same title",notes:"",writable:true)
        var due = reminder; due.hasTime = true; rejects(due,reminder)
        due.due = date(25,8); try NativeEditRules.validate(due,baseline:reminder)
        var recurringReminder = reminder; recurringReminder.recurring = true
        try NativeEditRules.validate(recurringReminder,baseline:recurringReminder)
        try NativeEditRules.validateDeletion(.reminderSeries,baseline:recurringReminder)
        func rejectsScope(_ scope:NativeChangeScope,_ baseline:NativeEditDetails,_ edited:NativeEditDetails) { do {try NativeEditRules.validateScope(scope,baseline:baseline,edited:edited);preconditionFailure("Invalid scope accepted")} catch {} }
        rejectsScope(.occurrence,recurring,move)
        try NativeEditRules.validateScope(.futureEvents,baseline:recurring,edited:move)
        rejectsScope(.occurrence,recurringReminder,recurringReminder)
        rejectsScope(.futureEvents,base,base)
        rejectsScope(.reminderSeries,recurring,recurring)
        try NativeEditRules.validateDeletion(.futureEvents,baseline:recurring)
        try NativeEditRules.validateDeletion(.occurrence,baseline:recurring)
        var repeated=recurring;repeated.recurrenceRules=[.init(frequency:"weekly",interval:2,weekdays:[.init(weekday:2),.init(weekday:6)])]
        rejectsScope(.occurrence,recurring,repeated)
        try NativeEditRules.validateScope(.futureEvents,baseline:recurring,edited:repeated)
        precondition(!NativeEditRules.supportsUndo(baseline:recurring,edited:repeated,scope:.futureEvents))
        try repeated.recurrenceRules[0].validate()
        for rule in [NativeRecurrence(interval:0),NativeRecurrence(frequency:"weekly",weekdays:[.init(weekday:2,week:1)]),NativeRecurrence(frequency:"monthly",monthDays:[0]),NativeRecurrence(frequency:"yearly",months:[13]),NativeRecurrence(endDate:.now,count:4)] {do {try rule.validate();preconditionFailure("Invalid recurrence accepted")} catch {}}
        try NativeRecurrence(frequency:"monthly",weekdays:[.init(weekday:6,week:-1)]).validate()
        try NativeRecurrence(frequency:"monthly",monthDays:[-1]).validate()
        var repeatDue=recurringReminder;repeatDue.recurrenceRules=[.init()];rejects(repeatDue,reminder)
        repeatDue.due=date(25);try NativeEditRules.validate(repeatDue,baseline:reminder)
        var imported=recurring;imported.recurrenceRules=[.init(calendarIdentifier:"hebrew")]
        var replaceImported=imported;replaceImported.recurrenceRules=[.init()]
        rejectsScope(.futureEvents,imported,replaceImported)
        var renameImported=imported;renameImported.title="Renamed"
        try NativeEditRules.validate(renameImported,baseline:imported)
        try NativeEditRules.validateScope(.futureEvents,baseline:imported,edited:renameImported)
        replaceImported.recurrenceRules=[];try NativeEditRules.validateScope(.futureEvents,baseline:imported,edited:replaceImported)
        var tooMany=base;tooMany.alarms=[.init(offset:.infinity)];rejects(tooMany,base)
        var outside=base;outside.priority=10;rejects(outside,base)
        var link=base;link.url="javascript:alert(1)";rejects(link,base)
        precondition(reminder == NativeEditDetails(kind:.reminder,itemID:"reminder",occurrenceID:"reminder",sourceID:"list",title:"Same title",notes:"",writable:true), "Reminder baseline fields are stable across fresh reads")
        print("PASS: edit identity, stale-field comparison foundation, read-only/recurrence rules, date validation, deterministic reminder baseline and inclusive all-day/DST boundaries")
    }
}
