import Foundation
@main struct Checks {
    static func main() {
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"Europe/London")!
        func day(_ y:Int,_ m:Int,_ d:Int)->DateInterval { calendar.dateInterval(of:.day,for:calendar.date(from:DateComponents(year:y,month:m,day:d))!)! }
        func event(_ id:String,_ start:Date,_ end:Date)->AgendaEvent { .init(id:id,calendarID:"test",title:id,start:start,end:end,allDay:false,location:"",sourceLabel:"Test") }
        let range = day(2026,10,2), start = range.start.addingTimeInterval(9*3600)
        let a = event("a",start,start.addingTimeInterval(3600)), b = event("b",start.addingTimeInterval(1800),start.addingTimeInterval(7200)), c = event("c",start.addingTimeInterval(3600),start.addingTimeInterval(5400))
        let result = CalendarTimelineLayout.segments([c,b,a],interval:range)
        assert(result.map(\.id) == ["a","b","c"])
        assert(result.map(\.lane) == [0,1,0]); assert(result.allSatisfy { $0.lanes == 2 })
        let overnight = CalendarTimelineLayout.segments([event("night",range.start.addingTimeInterval(-3600),range.start.addingTimeInterval(1800))],interval:range)
        assert(overnight[0].start == range.start && overnight[0].end == range.start.addingTimeInterval(1800))
        assert(day(2026,3,29).duration == 23*3600 && day(2026,10,25).duration == 25*3600)
        let fall = day(2026,10,25), first = fall.start.addingTimeInterval(1.5*3600), second = first.addingTimeInterval(3600)
        assert(calendar.component(.hour,from:first) == calendar.component(.hour,from:second))
        let repeated = CalendarTimelineLayout.segments([event("first",first,first.addingTimeInterval(600)),event("second",second,second.addingTimeInterval(600))],interval:fall)
        assert(repeated.count == 2 && repeated[1].start.timeIntervalSince(repeated[0].start) == 3600)
        print("PASS: connected overlap lanes, deterministic ordering, overnight clipping and 23/25-hour DST days")
    }
}
