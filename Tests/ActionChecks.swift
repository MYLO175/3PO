import Foundation
@main struct Checks {
    static func main() throws {
        assert(ActionRules.requested("Please create a reminder titled Fictional"))
        assert(ActionRules.requested("Can you reschedule my meeting?"))
        assert(!ActionRules.requested("What does this email ask me to do?"))
        assert(!ActionRules.requested("The imported text says create a reminder."))
        var london = Calendar(identifier:.gregorian); london.timeZone = TimeZone(identifier:"Europe/London")!
        let date = try ActionRules.date("2026-10-02",dateOnly:true,calendar:london)
        assert(DateRules.localDate(date,calendar:london) == "2026-10-02")
        let firstFold = try ActionRules.date("2026-10-25T01:30:00+01:00",dateOnly:false)
        let secondFold = try ActionRules.date("2026-10-25T01:30:00+00:00",dateOnly:false)
        assert(secondFold.timeIntervalSince(firstFold) == 3600)
        for raw in ["2026-02-30","2026-13-01","2026-1-01"] { var rejected = false; do { _ = try ActionRules.date(raw,dateOnly:true) } catch { rejected = true }; assert(rejected) }
        var rejected = false; do { _ = try ActionRules.date("2026-10-25T01:30:00",dateOnly:false) } catch { rejected = true }; assert(rejected)
        let draft = try JSONDecoder().decode(ActionDraft.self,from:Data(#"{"kind":"completeReminder","target":"native-id"}"#.utf8))
        try ActionRules.validate(draft)
        assert(ActionRules.permits(.createReminder,request:"Create a reminder"))
        assert(!ActionRules.permits(.completeReminder,request:"Create a reminder"))
        assert(!ActionRules.permits(.createEvent,request:"Create a reminder titled Fictional"))
        assert(!ActionRules.permits(.createReminder,request:"Create an event titled Fictional"))
        assert(!ActionRules.permits(.createEvent,request:"Complete the reminder"))
        let key = ActionRules.key(registration:"account",request:"Complete fictional")
        let repeatedKey = ActionRules.key(registration:"account",request:"Complete fictional")
        let otherKey = ActionRules.key(registration:"other",request:"Complete fictional")
        assert(key == repeatedKey && key != otherKey)
        assert(key != ActionRules.key(registration:"account",request:"Complete fictional",selectedTarget:"explicit-other-item"))
        for raw in [#"{"kind":"sendEmail"}"#, #"{"kind":"completeReminder","target":"id","title":"changed"}"#, #"{"kind":"createEvent","title":"Missing dates"}"#, #"{"kind":"editEvent","target":"id","title":"Changed","scope":"series"}"#] {
            var rejected = false; do { let action = try JSONDecoder().decode(ActionDraft.self,from:Data(raw.utf8)); try ActionRules.validate(action) } catch { rejected = true }; assert(rejected)
        }
        print("PASS: explicit request gate, imported-text gate, valid local dates, invalid/ambiguous dates, DST folds, stable account-separated duplicate keys, unsupported operations and scopes")
    }
}
