import SwiftUI

struct CalendarWidgetView: View {
    @Bindable var model: DashboardModel
    @Binding var configuration: WidgetConfiguration
    @State private var snapshot = CalendarSnapshot(sources:[],events:[])
    @State private var loading = false
    @State private var error: String?
    @State private var updated: Date?
    @State private var selectedEvent: CalendarEventSelection?
    @State private var dragToken = UUID().uuidString
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
                Button { model.newNativeItem(.event,date:configuration.date) } label: { Image(systemName:"plus") }.buttonStyle(.borderless).help("New event").accessibilityLabel("New event").disabled(model.writing)
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
            if mode == "day" || mode == "week" { Text("Drag a timed event to another slot to review its time.").font(.caption2).foregroundStyle(.secondary) }
            if mode == "month" { monthView }
            else if mode == "day" || mode == "week" { timelineView }
            else { agendaView }
        }.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .task(id:"\(range.start.timeIntervalSince1970):\(range.end.timeIntervalSince1970):\(model.widgetCalendars.revision)") { await load() }
            .sheet(item:$selectedEvent) { NativeItemEditor(model:model,target:.event($0.event),proposedMove:$0.move) }
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
    private func select(_ event: AgendaEvent) { selectedEvent = CalendarEventSelection(event:event) }
    private func dragValue(_ event: AgendaEvent) -> String? {
        guard !model.writing, !event.allDay, !ProcessInfo.processInfo.arguments.contains("--sample"), snapshot.sources.contains(where:{ $0.id == event.calendarID && $0.writable }) else { return nil }
        return dragToken + ":" + event.id
    }
    private func drop(_ values: [String], point: CGPoint, day: Date) -> Bool {
        guard values.count == 1, let value = values.first, value.hasPrefix(dragToken+":"), !model.writing else { return false }
        let id = String(value.dropFirst(dragToken.count+1))
        guard let event = events.first(where:{ $0.id == id }), dragValue(event) != nil, let start = CalendarTimelineMove.start(on:day,y:point.y), start != event.start else { return false }
        let proposal = NativeEventMoveProposal(occurrenceID:event.id,sourceID:event.calendarID,originalStart:event.start,originalEnd:event.end,start:start)
        selectedEvent = CalendarEventSelection(event:event,move:proposal); return true
    }
    private func eventButton(_ event: AgendaEvent) -> some View {
        Button { select(event) } label: {
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
                                ForEach(items.prefix(max(1,Int((height-28)/21)))) { event in Button { select(event) } label: { Text(event.title).font(.caption2).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading).padding(3).background(color(event).opacity(0.12),in:RoundedRectangle(cornerRadius:3)) }.buttonStyle(.plain) }
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
        GeometryReader { geometry in
            let days = mode == "week" ? 7 : 1
            let width = CalendarTimelineFocus.columnWidth(available:geometry.size.width,days:days)
            let focusDay = days == 7 && range.contains(Date.now) ? Date.now : range.start
            let focus = CalendarTimelineFocus.hour(on:focusDay,now:.now,events:events)
            let allDayCount = (0..<days).map { dayEvents(calendar.date(byAdding:.day,value:$0,to:range.start)!).filter(\.allDay).count }.max() ?? 0
            let allDayHeight = Double(min(3,allDayCount))*24 + (allDayCount > 3 ? 20 : 0)
            ScrollViewReader { proxy in
                ScrollView([.horizontal,.vertical]) {
                    HStack(alignment:.top,spacing:8) {
                        ForEach(0..<days,id:\.self) { offset in
                            let day = calendar.date(byAdding:.day,value:offset,to:range.start)!
                            VStack(alignment:.leading,spacing:8) {
                                Text(day.formatted(.dateTime.weekday(.abbreviated).day())).font(.subheadline.weight(.semibold)).foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : Color.primary)
                                if allDayCount > 0 {
                                    let items = dayEvents(day).filter(\.allDay)
                                    VStack(alignment:.leading,spacing:3) {
                                        ForEach(items.prefix(3)) { event in Button { select(event) } label: { Text("All day · " + event.title).font(.caption2).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading).padding(4).background(color(event).opacity(0.12),in:RoundedRectangle(cornerRadius:4)) }.buttonStyle(.plain).help(event.title) }
                                        if items.count > 3 { Button("+\(items.count-3) all-day events") { configuration.date = day; configuration.calendarMode = "agenda" }.font(.caption2).buttonStyle(.borderless) }
                                    }.frame(height:allDayHeight,alignment:.top)
                                }
                                CalendarDayTimeline(events:dayEvents(day).filter { !$0.allDay },day:day,color:color,select:select,dragValue:dragValue,drop:{ values,point in drop(values,point:point,day:day) })
                            }.frame(width:width)
                        }
                    }.padding(.bottom,10)
                }
                .task(id:"\(mode):\(range.start.timeIntervalSince1970)") {
                    await Task.yield()
                    proxy.scrollTo(CalendarTimelineFocus.anchor(focus),anchor:.top)
                }
            }
        }
    }
}
private struct CalendarEventSelection: Identifiable {
    let id = UUID()
    var event: AgendaEvent
    var move: NativeEventMoveProposal? = nil
}
private struct CalendarDayTimeline: View {
    var events: [AgendaEvent]; var day: Date; var color: (AgendaEvent)->Color; var select: (AgendaEvent)->Void
    var dragValue: (AgendaEvent)->String?
    var drop: ([String],CGPoint)->Bool
    @State private var dropTargeted = false
    private var interval: DateInterval { Calendar.current.dateInterval(of:.day,for:day)! }
    private let hourHeight = CalendarTimelineFocus.hourHeight
    var body: some View {
        let hours = Int(interval.duration/3600)
        let work = CalendarTimelineFocus.workingHours(on:day)
        ZStack(alignment:.topLeading) {
            Rectangle().fill(Color.accentColor.opacity(0.035)).padding(.leading,40).frame(height:work.duration/3600*hourHeight).offset(y:work.start.timeIntervalSince(interval.start)/3600*hourHeight)
            ForEach(0..<hours,id:\.self) { hour in
                let date = Calendar.current.date(byAdding:.hour,value:hour,to:interval.start)!
                HStack(alignment:.top,spacing:4) {
                    Text(date.formatted(.dateTime.hour().minute())).font(.system(size:10)).foregroundStyle(.secondary).frame(width:36)
                    Rectangle().fill(Color.primary.opacity(0.07)).frame(height:1)
                }.offset(y:CGFloat(hour)*hourHeight).id(CalendarTimelineFocus.anchor(date))
                    .help(date.formatted(date:.omitted,time:.shortened) + " " + (Calendar.current.timeZone.abbreviation(for:date) ?? ""))
            }
            ForEach(CalendarTimelineLayout.segments(events,interval:interval)) { segment in
                GeometryReader { geo in
                    let height = max(CalendarTimelineFocus.minimumEventHeight,segment.end.timeIntervalSince(segment.start)/3600*hourHeight)
                    let button = Button { select(segment.event) } label: {
                        VStack(alignment:.leading,spacing:2) {
                            Text(segment.event.title).font(.caption2.weight(.medium)).lineLimit(height > 48 ? 3 : 1)
                            if height > 38 { Text(segment.event.start.formatted(date:.omitted,time:.shortened)).font(.system(size:10)).foregroundStyle(.secondary) }
                            Spacer(minLength:0)
                        }.padding(.horizontal,5).padding(.vertical,height > 38 ? 5 : 2).frame(maxWidth:.infinity,alignment:.leading).background(color(segment.event).opacity(0.17),in:RoundedRectangle(cornerRadius:5)).overlay(alignment:.leading) { RoundedRectangle(cornerRadius:2).fill(color(segment.event)).frame(width:3) }.clipped()
                    }.buttonStyle(.plain).help(segment.event.title + " · " + segment.event.start.formatted(date:.omitted,time:.shortened)).frame(width:max(1,(geo.size.width-40)/CGFloat(segment.lanes)-3),height:height).offset(x:40+CGFloat(segment.lane)*(geo.size.width-40)/CGFloat(segment.lanes),y:segment.start.timeIntervalSince(interval.start)/3600*hourHeight)
                    if let value = dragValue(segment.event) { button.draggable(value) } else { button }
                }
            }
            TimelineView(.periodic(from:.now,by:60)) { context in
                if interval.contains(context.date) && context.date < interval.end {
                    HStack(spacing:0) { Circle().fill(.red).frame(width:6,height:6); Rectangle().fill(.red.opacity(0.8)).frame(height:1) }.padding(.leading,37).offset(y:context.date.timeIntervalSince(interval.start)/3600*hourHeight)
                        .accessibilityLabel("Current time " + context.date.formatted(date:.omitted,time:.shortened)).allowsHitTesting(false)
                }
            }
        }.frame(height:CGFloat(hours)*hourHeight).contentShape(Rectangle())
            .overlay { if dropTargeted { RoundedRectangle(cornerRadius:5).stroke(Color.accentColor.opacity(0.6),lineWidth:2).allowsHitTesting(false) } }
            .dropDestination(for:String.self,action:drop,isTargeted:{ dropTargeted = $0 })
    }
}
