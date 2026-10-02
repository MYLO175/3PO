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
            let visualEnd = min(interval.end,max(end,start.addingTimeInterval(12/44*3600)))
            if !group.isEmpty && start >= groupEnd { finish(); groupEnd = interval.start }
            let lane = laneEnds.firstIndex(where: { $0 <= start }) ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(visualEnd) } else { laneEnds[lane] = visualEnd }
            groupEnd = max(groupEnd,visualEnd)
            group.append(.init(event:event,start:start,end:end,lane:lane,lanes:1))
        }
        finish(); return output
    }
}
