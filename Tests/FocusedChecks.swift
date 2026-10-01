import Foundation

@main struct FocusedChecks {
    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }
        func event(_ start: Date, _ end: Date, allDay: Bool = false) -> AgendaEvent {
            .init(id: "id", calendarID: "source", title: "Test", start: start, end: end, allDay: allDay, location: "", sourceLabel: "Test")
        }
        let dstDay = date(2026, 10, 25)
        assert(DateRules.day(dstDay, calendar: calendar).duration == 25*3600)
        let springDay = date(2026, 3, 29)
        assert(DateRules.day(springDay, calendar: calendar).duration == 23*3600)
        let overnight = event(date(2026, 10, 24, 23), date(2026, 10, 25, 2))
        assert(DateRules.overlaps(overnight, day: date(2026, 10, 24), calendar: calendar))
        assert(DateRules.overlaps(overnight, day: dstDay, calendar: calendar))
        assert(!DateRules.overlaps(overnight, day: date(2026, 10, 26), calendar: calendar))
        let allDay = event(dstDay, date(2026, 10, 26), allDay: true)
        assert(DateRules.overlaps(allDay, day: dstDay, calendar: calendar))
        assert(!DateRules.overlaps(allDay, day: date(2026, 10, 26), calendar: calendar))
        let zeroLength = event(date(2026, 10, 25, 12), date(2026, 10, 25, 12))
        assert(DateRules.overlaps(zeroLength, day: dstDay, calendar: calendar))
        assert(DateRules.occurrenceID("recurring", start: dstDay) != DateRules.occurrenceID("recurring", start: date(2026, 10, 26)))
        func reminder(_ id: String, _ due: Date?, timed: Bool = false) -> TaskItem {
            .init(id: id, listID: "list", title: "Duplicate title", due: due, hasTime: timed, sourceLabel: "Test", writable: true, recurring: false)
        }
        let now = date(2026, 10, 25, 12)
        let early = reminder("1", date(2026, 10, 25, 10), timed: true)
        let today = reminder("2", dstDay)
        let future = reminder("3", date(2026, 10, 26))
        let undated = reminder("4", nil)
        assert(DateRules.group(early, now: now, calendar: calendar) == "Overdue")
        assert(DateRules.group(today, now: now, calendar: calendar) == "Today")
        assert(DateRules.group(future, now: now, calendar: calendar) == "Upcoming")
        assert(DateRules.group(undated, now: now, calendar: calendar) == "Undated")
        assert(DateRules.ordered([undated, future, early, today]).map(\.id) == ["2", "1", "3", "4"])
        assert(Set([early, today].map(\.id)).count == 2)
        do { try SampleReminderService().complete(id: "task"); assertionFailure("Sample read-only source must reject writes") }
        catch IntegrationError.readOnly { }
        let fixture = #"{"messages":[{"id":"a:1","accountID":"a","account":"Example","messageID":1,"internetMessageID":"id@example.invalid","sender":"Test","subject":"Test","received":"2026-10-01T12:00:00.000Z","unread":true,"replied":false,"flagged":true}],"accounts":[{"id":"a","title":"Example"}],"errors":[]}"#.data(using: .utf8)!
        let mail = try JSONDecoder().decode(MailSnapshot.self, from: fixture)
        let restored = try JSONDecoder().decode(MailSnapshot.self, from: JSONEncoder().encode(mail))
        assert(restored.messages[0].received == mail.messages[0].received)
        assert(restored.messages[0].unread && restored.messages[0].flagged)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("missioncontrol-timeout-\(UUID()).js")
        try "function run(argv) { delay(10); return '{}'; }".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = MailService(scriptURL: tmp, timeout: 0.1)
        do { _ = try await service.headers(); assertionFailure("Timeout must fail") }
        catch MailServiceError.timedOut { }
        catch { throw error }
        print("PASS: DST/overnight/all-day/zero duration, occurrence identity, reminder grouping/order/duplicate identity, read-only write rejection, Mail cache round-trip/unread flags, helper timeout.")
    }
}
