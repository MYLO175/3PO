import Foundation

/// Relative wording for local workspace deadlines ("yyyy-MM-dd"), never Apple due dates.
enum LifeDueUrgency { case late, soon, later }
enum LifeDue {
    static func date(_ value: String, calendar: Calendar = .current) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard value.count == 10, parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              calendar.component(.day, from: date) == parts[2] else { return nil }
        return date
    }
    static func local(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func days(_ value: String, now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let due = date(value, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: due).day
    }
    /// "2 days late", "Today", "Tomorrow", a weekday within the week, then "14 Nov".
    static func label(_ value: String, now: Date = .now, calendar: Calendar = .current) -> (text: String, urgency: LifeDueUrgency)? {
        guard let due = date(value, calendar: calendar), let n = days(value, now: now, calendar: calendar) else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_GB"); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        switch n {
        case ..<(-1): return ("\(-n) days late", .late)
        case -1: return ("1 day late", .late)
        case 0: return ("Today", .soon)
        case 1: return ("Tomorrow", .soon)
        case 2...6: formatter.dateFormat = "EEE"; return (formatter.string(from: due), n <= 3 ? .soon : .later)
        default:
            formatter.dateFormat = calendar.component(.year, from: due) == calendar.component(.year, from: now) ? "d MMM" : "d MMM yyyy"
            return (formatter.string(from: due), .later)
        }
    }
    /// Dated work first, soonest (including late) at the top; undated keeps its saved order.
    static func ordered(_ items: [LifeItem]) -> [LifeItem] {
        items.enumerated().sorted { a, b in
            switch (a.element.due, b.element.due) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }
}

/// Reads a trailing date phrase off a typed task: today, tomorrow, a weekday, next week,
/// in N days/weeks, "14 nov", "nov 14" or "14/11". Local only; no AI. A phrase with
/// nothing before it stays the title.
enum LifeDueParser {
    private static let weekdays: [String: Int] = ["sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3, "wed": 4, "weds": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5, "fri": 6, "friday": 6, "sat": 7, "saturday": 7]
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> (title: String, due: String?) {
        let today = calendar.startOfDay(for: now)
        var words = text.split(separator: " ").map(String.init)
        let lower = words.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }, n = lower.count
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        func month(_ word: String) -> Int? { word.count >= 3 && word.count <= 9 ? months.firstIndex { word.hasPrefix($0) }.map { $0 + 1 } : nil }
        func date(_ day: Int, _ month: Int) -> Date? {
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }
            var parts = calendar.dateComponents([.year], from: today); parts.month = month; parts.day = day
            guard let value = calendar.date(from: parts), calendar.component(.day, from: value) == day else { return nil }
            return value < today ? calendar.date(byAdding: .year, value: 1, to: value) : value
        }
        var match: (count: Int, due: Date)?
        if let last = lower.last {
            let slash = last.split(separator: "/")
            if ["today", "tonight"].contains(last) { match = (1, day(0)) }
            else if ["tomorrow", "tmrw", "tmr"].contains(last) { match = (1, day(1)) }
            else if n >= 2, lower[n-2] == "next", last == "week" { match = (2, day(7)) }
            else if n >= 3, lower[n-3] == "in", let amount = Int(lower[n-2]), (1...365).contains(amount), last.hasPrefix("day") || last.hasPrefix("week") {
                match = (3, day(last.hasPrefix("week") ? amount * 7 : amount))
            }
            else if let weekday = weekdays[last] {
                var offset = (weekday - calendar.component(.weekday, from: today) + 7) % 7
                if offset == 0 { offset = 7 }
                match = (n >= 2 && lower[n-2] == "next" ? 2 : 1, day(offset))
            }
            else if n >= 2, let d = Int(lower[n-2]), let m = month(last), let value = date(d, m) { match = (2, value) }
            else if n >= 2, let m = month(lower[n-2]), let d = Int(last), let value = date(d, m) { match = (2, value) }
            else if slash.count == 2, let d = Int(slash[0]), let m = Int(slash[1]), let value = date(d, m) { match = (1, value) }
        }
        guard let match, match.count < n else { return (text.trimmingCharacters(in: .whitespaces), nil) }
        words.removeLast(match.count)
        while words.count > 1, let last = words.last?.lowercased(), ["by", "on", "due"].contains(last) { words.removeLast() }
        return (words.joined(separator: " "), LifeDue.local(match.due, calendar: calendar))
    }
}

extension LifeProjectIndex {
    /// Every live, unarchived task below `parent` (everything when nil), in saved order.
    func tasks(under parent: UUID?) -> [LifeItem] {
        var result: [LifeItem] = [], seen = Set<UUID>()
        func visit(_ id: UUID?) {
            for child in children(of: id) where seen.insert(child.id).inserted {
                if child.kind.isWork && child.status != .archived { result.append(child) }
                visit(child.id)
            }
        }
        visit(parent); return result
    }
    func open(under parent: UUID?) -> [LifeItem] { tasks(under: parent).filter { $0.status != .done } }
    func nextDue(under parent: UUID) -> LifeItem? { LifeDue.ordered(open(under: parent).filter { $0.due != nil }).first }
    func lateCount(under parent: UUID?, now: Date = .now) -> Int {
        open(under: parent).filter { item in item.due.flatMap { LifeDue.days($0, now: now) }.map { $0 < 0 } ?? false }.count
    }
    /// Unfinished project work that is late or due within `days`, soonest first.
    func dueSoon(under parent: UUID?, within days: Int = 14, now: Date = .now) -> [LifeItem] {
        LifeDue.ordered(open(under: parent).filter { item in item.due.flatMap { LifeDue.days($0, now: now) }.map { $0 < days } ?? false })
    }
}
