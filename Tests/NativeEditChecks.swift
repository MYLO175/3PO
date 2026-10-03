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
        var recurring = base; recurring.recurring = true; var move = recurring; move.sourceID = "different"; rejects(move,recurring)
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
        let allDay = NativeEditRules.allDay(base,enabled:true,calendar:calendar)
        precondition(allDay.start == date(25) && allDay.end == date(26))
        precondition(allDay.end.timeIntervalSince(allDay.start) == 25*3600, "DST all-day duration follows calendar boundaries")
        var midnight = base; midnight.start = date(24,20); midnight.end = date(25)
        let midnightDay = NativeEditRules.allDay(midnight,enabled:true,calendar:calendar)
        precondition(midnightDay.start == date(24) && midnightDay.end == date(25), "Exclusive midnight endpoint is preserved")
        precondition(NativeEditRules.allDay(allDay,enabled:true,calendar:calendar) == allDay)
        let timed = NativeEditRules.allDay(allDay,enabled:false,calendar:calendar)
        precondition(timed.end.timeIntervalSince(timed.start) == 3600 && calendar.component(.hour,from:timed.start) == 9)
        let reminder = NativeEditDetails(kind:.reminder,itemID:"reminder",occurrenceID:"reminder",sourceID:"list",title:"Same title",notes:"",writable:true)
        var due = reminder; due.hasTime = true; rejects(due,reminder)
        due.due = date(25,8); try NativeEditRules.validate(due,baseline:reminder)
        var recurringReminder = reminder; recurringReminder.recurring = true; rejects(recurringReminder,recurringReminder)
        precondition(reminder == NativeEditDetails(kind:.reminder,itemID:"reminder",occurrenceID:"reminder",sourceID:"list",title:"Same title",notes:"",writable:true), "Reminder baseline fields are stable across fresh reads")
        print("PASS: edit identity, stale-field comparison foundation, read-only/recurrence rules, date validation, deterministic reminder baseline and inclusive all-day/DST boundaries")
    }
}
