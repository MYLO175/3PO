import SwiftUI

struct CalendarWidgetView: View {
    @Bindable var model: DashboardModel
    @Binding var configuration: WidgetConfiguration
    @State private var snapshot = CalendarSnapshot(sources:[],events:[])
    @State private var loading = false
    @State private var error: String?
    @State private var updated: Date?
    @State private var selectedEvent: AgendaEvent?
    private var calendar: Calendar { .current }
    private var mode: String { configuration.calendarMode }
    private var range: DateInterval {
        if mode == "month" {
            let month = calendar.dateInterval(of:.month,for:configuration.date)!
            let start = calendar.dateInterval(of:.weekOfYear,for:month.start)!.start
            return DateInterval(start:start,end:calendar.date(byAdding:.day,value:42,to:start)!)
        }
        if mode == "week" { return calendar.dateInterval(of:.weekOfYear,for:configuration.date)! }
        let start = calendar.startOfDay(for:configuration.date)
        return DateInterval(start:start,end:calendar.date(byAdding:.day,value:mode == "day" ? 1 : 7,to:start)!)
    }
    private var events: [AgendaEvent] { snapshot.events.filter { !configuration.sourceExclusions.contains($0.calendarID) } }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label("Calendar",systemImage:"calendar").font(.title3.weight(.semibold))
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Picker("Calendar view",selection:$configuration.calendarMode) {
                    Text("Agenda").tag("agenda"); Text("Day").tag("day"); Text("Week").tag("week"); Text("Month").tag("month")
                }.labelsHidden().frame(maxWidth:115)
            }
            if let error { Text("Stale · " + error).font(.caption).foregroundStyle(.orange).lineLimit(2) }
            else if let updated { Text("Updated " + updated.formatted(date:.omitted,time:.shortened)).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Menu { Button("Show all") { configuration.sourceExclusions = [] }; Divider(); ForEach(snapshot.sources) { source in
                    Toggle(source.label,isOn:Binding(get:{ !configuration.sourceExclusions.contains(source.id) },set:{ enabled in if enabled { configuration.sourceExclusions.remove(source.id) } else { configuration.sourceExclusions.insert(source.id) } }))
                } } label: { Label("Calendars",systemImage:"line.3.horizontal.decrease") }.controlSize(.small)
                Spacer()
                Button("Today") { configuration.date = .now }.controlSize(.small)
            }
            HStack {
                Button { navigate(-1) } label: { Image(systemName:"chevron.left") }.buttonStyle(.borderless).accessibilityLabel("Previous calendar period")
                DatePicker("Date",selection:$configuration.date,displayedComponents:.date).labelsHidden()
                Spacer(minLength:4)
                Button { navigate(1) } label: { Image(systemName:"chevron.right") }.buttonStyle(.borderless).accessibilityLabel("Next calendar period")
            }
            Divider()
            if mode == "month" { monthView }
            else if mode == "day" || mode == "week" { timelineView }
            else { agendaView }
        }.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .task(id:"\(range.start.timeIntervalSince1970):\(range.end.timeIntervalSince1970):\(model.widgetCalendars.revision)") { await load() }
            .sheet(item:$selectedEvent) { event in
                VStack(alignment:.leading,spacing:14) {
                    Text(event.title).font(.title2.weight(.semibold)); Text(event.sourceLabel).font(.callout).foregroundStyle(.secondary)
                    Text(event.allDay ? "All day · " + event.start.formatted(date:.complete,time:.omitted) : event.start.formatted(date:.abbreviated,time:.shortened) + " – " + event.end.formatted(date:.abbreviated,time:.shortened))
                    if !event.location.isEmpty { Label(event.location,systemImage:"location") }
                    Spacer(); HStack { Spacer(); Button("Done") { selectedEvent = nil }.keyboardShortcut(.cancelAction) }
                }.padding(24).frame(width:440,height:250)
            }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let value = ProcessInfo.processInfo.arguments.contains("--sample") ? model.calendarData : try await model.widgetCalendars.load(range)
            try Task.checkCancellation(); snapshot = value; error = nil; updated = .now
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func navigate(_ direction: Int) {
        configuration.date = calendar.date(byAdding:mode == "month" ? .month : .day,value:direction * (mode == "week" ? 7 : 1),to:configuration.date)!
    }
    private func color(_ event: AgendaEvent) -> Color { DashboardView(model:model).sourceColor(event.calendarID,explicit:snapshot.sources.first { $0.id == event.calendarID }?.color) }
    private func dayEvents(_ date: Date) -> [AgendaEvent] { events.filter { DateRules.overlaps($0,day:date) } }
    private func eventButton(_ event: AgendaEvent) -> some View {
        Button { selectedEvent = event } label: {
            HStack(alignment:.top,spacing:7) {
                RoundedRectangle(cornerRadius:2).fill(color(event)).frame(width:3)
                VStack(alignment:.leading,spacing:4) {
                    if !event.allDay { Text(event.start.formatted(date:.omitted,time:.shortened) + " – " + event.end.formatted(date:.omitted,time:.shortened)).font(.caption).foregroundStyle(.secondary) }
                    Text(event.title).font(.callout.weight(.medium)).lineLimit(3)
                    if !event.location.isEmpty { Text(event.location).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    Text(event.sourceLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.padding(.vertical,5).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var agendaView: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:12) {
                ForEach(0..<7,id:\.self) { offset in
                    let day = calendar.date(byAdding:.day,value:offset,to:range.start)!, items = dayEvents(day)
                    Text(day.formatted(date:.abbreviated,time:.omitted)).font(.subheadline.weight(.semibold))
                    if items.isEmpty { Text("Nothing scheduled").font(.callout).foregroundStyle(.secondary) }
                    ForEach(items.filter(\.allDay)) { eventButton($0) }
                    ForEach(items.filter { !$0.allDay }) { eventButton($0) }
                    Divider()
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private var monthView: some View {
        GeometryReader { geo in
            let height = max(64,(geo.size.height-28)/6)
            VStack(spacing:4) {
                HStack { ForEach(0..<7,id:\.self) { i in Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday-1+i)%7]).font(.caption.weight(.semibold)).frame(maxWidth:.infinity) } }
                ScrollView {
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:7),spacing:4) {
                        ForEach(0..<42,id:\.self) { offset in
                            let date = calendar.date(byAdding:.day,value:offset,to:range.start)!, items = dayEvents(date)
                            VStack(alignment:.leading,spacing:4) {
                                Button { configuration.date = date; configuration.calendarMode = "day" } label: {
                                    Text(date.formatted(.dateTime.day())).font(.caption.weight(.semibold)).foregroundStyle(calendar.isDateInToday(date) ? Color.accentColor : Color.primary)
                                }.buttonStyle(.plain).accessibilityLabel("Open " + date.formatted(date:.complete,time:.omitted))
                                ForEach(items.prefix(max(1,Int((height-28)/21)))) { event in Button { selectedEvent = event } label: { Text(event.title).font(.caption2).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading).padding(3).background(color(event).opacity(0.12),in:RoundedRectangle(cornerRadius:3)) }.buttonStyle(.plain) }
                                if items.count > max(1,Int((height-28)/21)) { Text("+\(items.count-max(1,Int((height-28)/21))) more").font(.caption2).foregroundStyle(.secondary) }
                                Spacer(minLength:0)
                            }.padding(6).frame(maxWidth:.infinity).frame(height:height).background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:5))
                                .opacity(calendar.component(.month,from:date) == calendar.component(.month,from:configuration.date) ? 1 : 0.45)
                        }
                    }
                }
            }
        }
    }
    private var timelineView: some View {
        ScrollView([.horizontal,.vertical]) {
            HStack(alignment:.top,spacing:6) {
                ForEach(0..<(mode == "week" ? 7 : 1),id:\.self) { offset in
                    let day = calendar.date(byAdding:.day,value:offset,to:range.start)!
                    VStack(alignment:.leading,spacing:8) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).day())).font(.subheadline.weight(.semibold))
                        ForEach(dayEvents(day).filter(\.allDay)) { event in Button { selectedEvent = event } label: { Text("All day · " + event.title).font(.caption).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading).padding(5).background(color(event).opacity(0.12),in:RoundedRectangle(cornerRadius:4)) }.buttonStyle(.plain) }
                        CalendarDayTimeline(events:dayEvents(day).filter { !$0.allDay },day:day,color:color,select:{ selectedEvent = $0 })
                    }.frame(width:mode == "week" ? 140 : 290)
                }
            }.padding(.bottom,10)
        }
    }
}
private struct CalendarDayTimeline: View {
    var events: [AgendaEvent]; var day: Date; var color: (AgendaEvent)->Color; var select: (AgendaEvent)->Void
    private var interval: DateInterval { Calendar.current.dateInterval(of:.day,for:day)! }
    var body: some View {
        let hours = Int(interval.duration/3600)
        ZStack(alignment:.topLeading) {
            ForEach(0..<hours,id:\.self) { hour in
                let date = Calendar.current.date(byAdding:.hour,value:hour,to:interval.start)!
                HStack(alignment:.top,spacing:3) { Text(date.formatted(.dateTime.hour().minute())).font(.system(size:9)).foregroundStyle(.secondary).frame(width:32); Rectangle().fill(Color.primary.opacity(0.07)).frame(height:1) }.offset(y:CGFloat(hour)*44)
            }
            ForEach(CalendarTimelineLayout.segments(events,interval:interval)) { segment in
                GeometryReader { geo in
                    Button { select(segment.event) } label: {
                        VStack(alignment:.leading,spacing:2) { Text(segment.event.start.formatted(date:.omitted,time:.shortened)).font(.system(size:9)); Text(segment.event.title).font(.caption2.weight(.medium)).lineLimit(3); Spacer(minLength:0) }.padding(4).frame(maxWidth:.infinity,alignment:.leading).background(color(segment.event).opacity(0.16),in:RoundedRectangle(cornerRadius:4)).clipped()
                    }.buttonStyle(.plain).help(segment.event.title).frame(width:(geo.size.width-36)/CGFloat(segment.lanes)-2,height:max(12,segment.end.timeIntervalSince(segment.start)/3600*44)).offset(x:36+CGFloat(segment.lane)*(geo.size.width-36)/CGFloat(segment.lanes),y:segment.start.timeIntervalSince(interval.start)/3600*44)
                }
            }
        }.frame(height:CGFloat(hours)*44)
    }
}
