import Foundation
@main struct Checks {
    static func main() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date { c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))! }
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
        for invalid in [good.replacingOccurrences(of: "known-event", with: "invented-id"), #"{"items":[]}"#, #"{"items":[{"text":" ","sourceIDs":[]}]}"#, #"{"items":[{"text":"Event","sourceIDs":["known-event","known-event"]}]}"#] {
            var rejected = false; do { _ = try BriefingRules.decode(invalid, allowedSources: ["known-event"]) } catch { rejected = true }; assert(rejected)
        }
        print("PASS: 7:30 threshold, DST dates, sleep catch-up, saved completion, notification claim round-trip, source identity validation")
    }
}
