import Foundation

struct CalendarTimelineSegment: Identifiable {
    var id: String { event.id }
    var event: AgendaEvent
    var start: Date
    var end: Date
    var lane: Int
    var lanes: Int
}
enum CalendarTimelineLayout {
    static func segments(_ events: [AgendaEvent], interval: DateInterval) -> [CalendarTimelineSegment] {
        let clipped = events.filter { !$0.allDay && $0.start < interval.end && ($0.end > interval.start || $0.end == $0.start && $0.start >= interval.start) }
            .sorted { ($0.start,$0.end,$0.id) < ($1.start,$1.end,$1.id) }
        var output: [CalendarTimelineSegment] = [], group: [CalendarTimelineSegment] = [], laneEnds: [Date] = [], groupEnd = interval.start
        func finish() { for var item in group { item.lanes = laneEnds.count; output.append(item) }; group = []; laneEnds = [] }
        for event in clipped {
            let start = max(event.start,interval.start), end = min(max(event.end,start),interval.end)
            // Minimum visual height is also reserved for collision layout.
            let visualEnd = min(interval.end,max(end,start.addingTimeInterval(CalendarTimelineFocus.minimumEventHeight/CalendarTimelineFocus.hourHeight*3600)))
            if !group.isEmpty && start >= groupEnd { finish(); groupEnd = interval.start }
            let lane = laneEnds.firstIndex(where: { $0 <= start }) ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(visualEnd) } else { laneEnds[lane] = visualEnd }
            groupEnd = max(groupEnd,visualEnd)
            group.append(.init(event:event,start:start,end:end,lane:lane,lanes:1))
        }
        finish(); return output
    }
}

// Clock-based focus preserves daylight-saving days rather than assuming 24 hours.
enum CalendarTimelineFocus {
    static let hourHeight = 52.0
    static let minimumEventHeight = 20.0
    static func columnWidth(available: Double, days: Int) -> Double {
        max(days == 1 ? 220 : 125,(available - Double(max(0,days-1))*8)/Double(max(1,days)))
    }
    static func hour(on day: Date, now: Date, events: [AgendaEvent], calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for:day)
        let target: Int
        if calendar.isDate(day,inSameDayAs:now) {
            target = min(17,max(8,calendar.component(.hour,from:now)-1))
        } else {
            let first = events.filter { !$0.allDay && DateRules.overlaps($0,day:day,calendar:calendar) }.map { max($0.start,start) }.min()
            target = first.map { min(8,max(0,calendar.component(.hour,from:$0)-1)) } ?? 8
        }
        return calendar.date(bySettingHour:target,minute:0,second:0,of:start) ?? start
    }
    /// Elapsed time from midnight, so repeated DST hours keep distinct offsets.
    static func offset(_ date: Date, calendar: Calendar = .current) -> Double {
        date.timeIntervalSince(calendar.startOfDay(for:date))/3600*hourHeight
    }
    static func workingHours(on day: Date, calendar: Calendar = .current) -> DateInterval {
        DateInterval(start:calendar.date(bySettingHour:9,minute:0,second:0,of:day)!,end:calendar.date(bySettingHour:18,minute:0,second:0,of:day)!)
    }
}

// Week view is one long strip of days, so horizontal scrolling runs across
// week boundaries. Only columns near the viewport are built and events load in
// four-week blocks; the strip is re-based only near its far ends.
enum CalendarWeekStrip {
    static let weeksEachSide = 104
    static let days = (2*weeksEachSide+1)*7
    static let buffer = 7
    static let block = 28
    static func start(around day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding:.weekOfYear,value:-weeksEachSide,to:calendar.dateInterval(of:.weekOfYear,for:day)!.start)!
    }
    /// Calendar days, not elapsed time, so DST days count once.
    static func index(of day: Date, from start: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day],from:calendar.startOfDay(for:start),to:calendar.startOfDay(for:day)).day ?? 0
    }
    static func day(_ index: Int, from start: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding:.day,value:index,to:calendar.startOfDay(for:start))!
    }
    static func visibleColumns(viewport: Double, columnWidth: Double) -> Int {
        guard viewport > 0, columnWidth > 0 else { return 1 }
        return max(1,Int(((viewport+8)/(columnWidth+8)+0.01).rounded(.down)))
    }
    /// Lead with the week's first day when the date still fits on screen; otherwise with the date.
    static func leading(for date: Date, visible: Int, calendar: Calendar = .current) -> Date {
        let week = calendar.dateInterval(of:.weekOfYear,for:date)!.start
        return index(of:date,from:week,calendar:calendar) < visible ? week : calendar.startOfDay(for:date)
    }
    static func rendered(leading: Int, visible: Int) -> Range<Int> {
        let lower = min(days,max(0,leading-buffer))
        return lower..<min(days,max(lower,leading+visible+buffer))
    }
    /// The leading column's block plus one either side: the visible days are always loaded.
    static func loaded(leading: Int, start: Date, calendar: Calendar = .current) -> DateInterval {
        let current = max(0,min(days-1,leading))/block
        return DateInterval(start:day(max(0,(current-1)*block),from:start,calendar:calendar),end:day(min(days,(current+2)*block),from:start,calendar:calendar))
    }
    static func comfortable(_ leading: Int, visible: Int) -> Bool { leading >= 2*block && leading+visible <= days-2*block }
}

enum CalendarTimelineMove {
    static func destination(start: Date, day: Date, dx: Double, dy: Double, columnWidth: Double, visibleDays: Int, range: DateInterval, calendar: Calendar = .current) -> Date? {
        guard let target = translated(start:max(start,calendar.startOfDay(for:day)),day:day,dx:dx,dy:dy,columnWidth:columnWidth,visibleDays:visibleDays,range:range,calendar:calendar), let displayed = self.start(on:target.day,y:target.y,calendar:calendar) else { return nil }
        // Overnight cards may be clipped at midnight. Move the real start by
        // the displayed segment's delta instead of shortening the event.
        return displayed.addingTimeInterval(min(0,start.timeIntervalSince(calendar.startOfDay(for:day))))
    }
    static func translated(start: Date, day: Date, dx: Double, dy: Double, columnWidth: Double, visibleDays: Int, range: DateInterval, calendar: Calendar = .current) -> (day: Date,y: Double)? {
        guard dx.isFinite, dy.isFinite, columnWidth > 0, visibleDays > 0, range.contains(day), let interval = calendar.dateInterval(of:.day,for:day) else { return nil }
        let columns = visibleDays == 1 ? 0 : Int(max(-Double(visibleDays),min(Double(visibleDays),(dx/(columnWidth+8)).rounded())))
        guard let targetDay = calendar.date(byAdding:.day,value:columns,to:day), range.contains(targetDay) else { return nil }
        let y = max(0,start.timeIntervalSince(interval.start)/3600*CalendarTimelineFocus.hourHeight + dy)
        return (targetDay,y)
    }
    /// Snap elapsed timeline coordinates, preserving both occurrences of repeated DST hours.
    static func start(on day: Date, y: Double, calendar: Calendar = .current) -> Date? {
        guard y.isFinite, y >= 0, let interval = calendar.dateInterval(of:.day,for:day) else { return nil }
        let elapsed = (y / CalendarTimelineFocus.hourHeight * 3600 / 900).rounded() * 900
        return interval.start.addingTimeInterval(min(max(0,elapsed),interval.duration-900))
    }
}
