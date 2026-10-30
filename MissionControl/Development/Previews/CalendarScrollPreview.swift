#if DEBUG
import SwiftUI

/// Fictional, read-only events for any range: checks week scrolling and multi-day Agenda rows without Calendar access.
struct CalendarScrollPreview: View {
    @Bindable var model: DashboardModel
    @State private var configuration = WidgetConfiguration(calendarMode:"week")
    @State private var narrow = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Picker("Widget width",selection:$narrow) { Text("Wide").tag(false); Text("Narrow").tag(true) }.pickerStyle(.segmented).frame(width:200)
            CalendarWidgetView(model:model,configuration:$configuration,previewSnapshot:Self.snapshot)
                .frame(maxWidth:narrow ? 470 : .infinity)
                .background(.background,in:RoundedRectangle(cornerRadius:16))
        }.padding(16)
    }
    static func snapshot(_ range: DateInterval) -> CalendarSnapshot {
        let calendar = Calendar.current, source = SourceOption(id:"fictional-preview",title:"Fictional",account:"Preview",writable:false)
        // Starts a week early so multi-day events already under way overlap the range, as a real load returns them.
        var events: [AgendaEvent] = [], day = calendar.date(byAdding:.day,value:-7,to:calendar.startOfDay(for:range.start))!
        while day < range.end {
            func add(_ hour: Int,_ minute: Int,_ length: Int,_ title: String,allDay: Bool = false,days: Int = 1) {
                let start = allDay ? day : calendar.date(bySettingHour:hour,minute:minute,second:0,of:day)!
                let end = allDay ? calendar.date(byAdding:.day,value:days,to:day)! : start.addingTimeInterval(Double(length)*60)
                events.append(AgendaEvent(id:"preview-\(title)-\(start.timeIntervalSince1970)",calendarID:source.id,title:title,start:start,end:end,allDay:allDay,location:"",sourceLabel:source.title))
            }
            let weekday = calendar.component(.weekday,from:day), date = day.formatted(.dateTime.day().month(.abbreviated))
            if (2...6).contains(weekday) { add(9,0,30,"Planning " + date) }
            if weekday == 2 || weekday == 4 { add(10,30,90,"Lecture") }
            if weekday == 3 || weekday == 5 { add(14,0,120,"Lab session") }
            if weekday == 6 { add(18,0,60,"Football") }
            if weekday == 7 { add(11,0,90,"Brunch " + date) }
            if weekday == 5 { add(0,0,0,"Field trip",allDay:true,days:4) }
            if calendar.component(.day,from:day) == 1 { add(0,0,0,"Month start",allDay:true) }
            day = calendar.date(byAdding:.day,value:1,to:day)!
        }
        return CalendarSnapshot(sources:[source],events:events.filter { $0.start < range.end && $0.end > range.start })
    }
}
#endif
