import SwiftUI

struct CalendarWidgetView: View {
    @Environment(\.workspacePalette) private var palette
    @Bindable var model: DashboardModel
    @Binding var configuration: WidgetConfiguration
    var widgetID: UUID? = nil
    #if DEBUG
    var previewFixture: CalendarDragFixture? = nil
    var previewSnapshot: ((DateInterval) -> CalendarSnapshot)? = nil
    #endif
    @State private var snapshot = CalendarSnapshot(sources:[],events:[])
    @State private var loading = false
    @State private var error: String?
    @State private var updated: Date?
    @State private var showDatePicker = false
    @State private var selectedEvent: CalendarEventSelection?
    @State private var focusRequest = 0
    @State private var timelineSpace = UUID().uuidString
    @State private var dragCapture: CalendarEventDragCapture?
    @State private var pendingMove: AgendaEvent?
    @State private var moveError: String?
    @State private var mounted = false
    @State private var timelinePosition = ScrollPosition()
    @State private var timelineWidth = 0.0
    @State private var weekStrip: Date?
    @State private var leadingIndex = 0
    @State private var placedLeading: Date?
    @State private var writtenDate: Date?
    @State private var placement = 0
    private var calendar: Calendar { .current }
    private var mode: String { configuration.calendarMode }
    private var range: DateInterval {
        if mode == "month" {
            let month = calendar.dateInterval(of:.month,for:configuration.date)!
            let start = calendar.dateInterval(of:.weekOfYear,for:month.start)!.start
            return DateInterval(start:start,end:calendar.date(byAdding:.day,value:42,to:start)!)
        }
        if mode == "week" { return CalendarWeekStrip.loaded(leading:weekStrip == nil ? CalendarWeekStrip.index(of:configuration.date,from:stripStart) : leadingIndex,start:stripStart) }
        let start = calendar.startOfDay(for:configuration.date)
        return DateInterval(start:start,end:calendar.date(byAdding:.day,value:mode == "day" ? 1 : 7,to:start)!)
    }
    private var stripStart: Date { weekStrip ?? CalendarWeekStrip.start(around:configuration.date) }
    private var weekColumnWidth: Double { CalendarTimelineFocus.columnWidth(available:max(1,timelineWidth),days:7) }
    private var visibleColumns: Int { CalendarWeekStrip.visibleColumns(viewport:timelineWidth,columnWidth:weekColumnWidth) }
    private var dateTitle: String {
        if mode == "month" { return configuration.date.formatted(.dateTime.month(.wide).year()) }
        if mode == "week", weekStrip != nil, timelineWidth > 0 {
            let first = CalendarWeekStrip.day(leadingIndex,from:stripStart), last = CalendarWeekStrip.day(leadingIndex+visibleColumns-1,from:stripStart)
            return first < last ? (first..<last).formatted(.interval.day().month(.abbreviated)) : first.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
        }
        return configuration.date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
    }
    /// While showing today: the event under way and how long is left, or what's next and how soon.
    private func nextHeadline(_ now: Date) -> String? {
        guard calendar.isDate(configuration.date, inSameDayAs: now) else { return nil }
        let today = events.filter { !$0.allDay && calendar.isDate($0.start, inSameDayAs: now) }.sorted { $0.start < $1.start }
        func span(_ seconds: TimeInterval) -> String {
            let minutes = max(1, Int((seconds / 60).rounded()))
            return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h" + (minutes % 60 == 0 ? "" : " \(minutes % 60) min")
        }
        if let current = today.last(where: { $0.start <= now && now < $0.end }) { return current.title + " · " + span(current.end.timeIntervalSince(now)) + " left" }
        if let next = today.first(where: { $0.start > now }) { return next.title + " in " + span(next.start.timeIntervalSince(now)) }
        return today.isEmpty ? "Nothing on today" : "Nothing else today"
    }
    private var events: [AgendaEvent] {
        snapshot.events.filter { !configuration.sourceExclusions.contains($0.calendarID) }.map { event in
            pendingMove?.id == event.id ? pendingMove! : event
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            WidgetHeader(title:"Calendar",symbol:"calendar") {
                SourceStatusIndicator(title:"Calendar",health:SourceHealth(lastSuccess:updated,error:error,loading:loading))
                Menu { Button("Show all") { configuration.sourceExclusions = [] }; Divider(); ForEach(snapshot.sources) { source in
                    Toggle(source.displayLabel,isOn:Binding(get:{ !configuration.sourceExclusions.contains(source.id) },set:{ enabled in if enabled { configuration.sourceExclusions.remove(source.id) } else { configuration.sourceExclusions.insert(source.id) } }))
                } } label: { Image(systemName:"line.3.horizontal.decrease") }.menuStyle(.borderlessButton).fixedSize().help("Filter calendars").accessibilityLabel("Filter calendars")
                Button { model.newNativeItem(.event,date:configuration.date) } label: { Image(systemName:"plus") }.help("New event").accessibilityLabel("New event").disabled(model.writing)
                Picker("Calendar view",selection:$configuration.calendarMode) {
                    Text("Agenda").tag("agenda"); Text("Day").tag("day"); Text("Week").tag("week"); Text("Month").tag("month")
                }.pickerStyle(.menu).labelsHidden().frame(width:90)
            }.buttonStyle(.borderless).controlSize(.small)
            TimelineView(.periodic(from:.now,by:60)) { context in
                if let headline = nextHeadline(context.date) { WidgetHeadline(text:headline,lines:1) }
            }
            HStack(spacing:8) {
                Button { showDatePicker.toggle() } label: {
                    HStack(spacing:4) { Text(dateTitle).font(.callout.weight(.medium)); Image(systemName:"chevron.down").font(.caption2) }
                }.help("Choose calendar date").accessibilityLabel("Choose calendar date").popover(isPresented:$showDatePicker) {
                    DatePicker("Calendar date",selection:$configuration.date,displayedComponents:.date).datePickerStyle(.graphical).labelsHidden().padding(12)
                }
                Spacer(minLength:4)
                Button { navigate(-1) } label: { Image(systemName:"chevron.left") }.help("Previous calendar period").accessibilityLabel("Previous calendar period")
                Button(mode == "day" || mode == "week" ? "Now" : "Today",action:returnToToday)
                Button { navigate(1) } label: { Image(systemName:"chevron.right") }.help("Next calendar period").accessibilityLabel("Next calendar period")
            }.buttonStyle(.borderless).controlSize(.small)
            if let error { Text((updated == nil ? "" : "Stale · ") + error).font(.caption).foregroundStyle(.orange).lineLimit(2) }
            if mode == "month" { monthView }
            else if mode == "day" || mode == "week" { timelineView }
            else { agendaView }
        }.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .onAppear { mounted=true; returnToToday() }
            .onDisappear { mounted=false; dragCapture=nil }
            .onChange(of:widgetID) { dragCapture=nil; returnToToday() }
            .onChange(of:model.inference.activeID) { dragCapture=nil }
            .onChange(of:model.sourceRevision) { dragCapture=nil }
            .onChange(of:configuration.calendarMode) { dragCapture=nil }
            .onChange(of:configuration.sourceExclusions) { dragCapture=nil }
            .task(id:"\(range.start.timeIntervalSince1970):\(range.end.timeIntervalSince1970):\(model.widgetCalendars.revision)") { await load() }
            .onChange(of:configuration.date) { showDatePicker = false; dragCapture=nil }
            .sheet(item:$selectedEvent) { NativeItemEditor(model:model,target:.event($0.event)) }
            .alert("Calendar move",isPresented:Binding(get:{ moveError != nil },set:{ if !$0 { moveError=nil } })) {
                Button("OK",role:.cancel) { moveError=nil }
            } message: { Text(moveError ?? "") }
    }
    private func returnToToday() {
        configuration.date = .now
        focusRequest += 1
    }
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let value: CalendarSnapshot
            #if DEBUG
            if let previewSnapshot { value = previewSnapshot(range) }
            else if let previewFixture { value = try await model.eventKit.calendarDragSnapshot(previewFixture,range:range) }
            else { value = ProcessInfo.processInfo.arguments.contains("--sample") ? model.calendarData : try await model.widgetCalendars.load(range) }
            #else
            value = ProcessInfo.processInfo.arguments.contains("--sample") ? model.calendarData : try await model.widgetCalendars.load(range)
            #endif
            try Task.checkCancellation(); snapshot = value; error = nil; updated = .now
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func navigate(_ direction: Int) {
        // Week arrows scroll the strip by seven days from wherever it rests.
        if mode == "week", let placed = placedLeading, timelineWidth > 0 {
            let leading = CalendarWeekStrip.day(leadingIndex+7*direction,from:stripStart)
            advanceDate(CalendarWeekStrip.index(of:leading,from:placed),leading:leading)
            showWeek(from:leading,animated:true)
            return
        }
        configuration.date = calendar.date(byAdding:mode == "month" ? .month : .day,value:direction * (mode == "week" ? 7 : 1),to:configuration.date)!
    }
    /// Outside date changes, Now and view switches place the timeline; scrolling never refocuses it.
    private func placeTimeline() {
        guard timelineWidth > 0, mode == "day" || mode == "week" else { return }
        let week = mode == "week", visible = week ? visibleColumns : 1
        let leading = week ? CalendarWeekStrip.leading(for:configuration.date,visible:visible) : calendar.startOfDay(for:configuration.date)
        let shown = DateInterval(start:leading,end:CalendarWeekStrip.day(visible,from:leading))
        let focus = focusRequest > 0 && shown.contains(.now) ? max(calendar.dateInterval(of:.hour,for:.now)!.start.addingTimeInterval(-3600),calendar.startOfDay(for:.now)) : CalendarTimelineFocus.hour(on:leading,now:.now,events:events)
        guard week else { timelinePosition.scrollTo(y:CalendarTimelineFocus.offset(focus)); return }
        placedLeading = leading
        showWeek(from:leading,y:CalendarTimelineFocus.offset(focus))
    }
    private func showWeek(from leading: Date, y: Double? = nil, animated: Bool = false) {
        var index = CalendarWeekStrip.index(of:leading,from:stripStart)
        if weekStrip == nil || !CalendarWeekStrip.comfortable(index,visible:visibleColumns) {
            weekStrip = CalendarWeekStrip.start(around:leading); index = CalendarWeekStrip.index(of:leading,from:stripStart)
        } else if animated {
            withAnimation { timelinePosition.scrollTo(x:Double(index)*(weekColumnWidth+8)) }
            return
        }
        leadingIndex = index
        let x = Double(index)*(weekColumnWidth+8)
        if let y { timelinePosition.scrollTo(point:CGPoint(x:x,y:y)) } else { timelinePosition.scrollTo(x:x) }
    }
    /// Once scrolling rests, the remembered date moves with the strip so it keeps its place on screen.
    private func settleWeek() {
        guard mode == "week", dragCapture == nil, let placed = placedLeading else { return }
        let leading = CalendarWeekStrip.day(leadingIndex,from:stripStart), moved = CalendarWeekStrip.index(of:leading,from:placed)
        if moved != 0 { advanceDate(moved,leading:leading) }
        if !CalendarWeekStrip.comfortable(leadingIndex,visible:visibleColumns) { showWeek(from:leading) }
    }
    private func advanceDate(_ days: Int, leading: Date) {
        let date = calendar.date(byAdding:.day,value:days,to:configuration.date)!
        placedLeading = leading; writtenDate = date; configuration.date = date
    }
    private func timelineColumns(_ indices: Range<Int>, from start: Date) -> [CalendarTimelineColumn] {
        let days = indices.map { CalendarWeekStrip.day($0,from:start) }
        guard let first = days.first, let last = days.last, let end = calendar.date(byAdding:.day,value:1,to:last) else { return [] }
        let nearby = events.filter { $0.start < end && $0.end >= first }
        return zip(indices,days).map { index,day in CalendarTimelineColumn(id:index,day:day,events:nearby.filter { DateRules.overlaps($0,day:day) }) }
    }
    private func mostAllDayEvents(in interval: DateInterval) -> Int {
        let allDay = events.filter { $0.allDay && $0.start < interval.end && $0.end >= interval.start }
        var day = interval.start, most = 0
        while !allDay.isEmpty, day < interval.end {
            most = max(most,allDay.filter { DateRules.overlaps($0,day:day) }.count)
            day = calendar.date(byAdding:.day,value:1,to:day)!
        }
        return most
    }
    private func color(_ event: AgendaEvent) -> Color { DashboardView(model:model).sourceColor(event.calendarID,explicit:snapshot.sources.first { $0.id == event.calendarID }?.color) }
    private func dayEvents(_ date: Date) -> [AgendaEvent] { events.filter { DateRules.overlaps($0,day:date) } }
    private func select(_ event: AgendaEvent) { guard pendingMove == nil else { return }; selectedEvent = CalendarEventSelection(event:event) }
    private func canDrag(_ event: AgendaEvent) -> Bool {
        !model.writing && !model.assistant.busy && pendingMove == nil && !event.allDay && !ProcessInfo.processInfo.arguments.contains("--sample") && snapshot.sources.contains(where:{ $0.id == event.calendarID && $0.writable })
    }
    private func beginDrag(_ event: AgendaEvent) {
        guard dragCapture == nil, canDrag(event) else { return }
        dragCapture = CalendarEventDragCapture(event:event,account:model.inference.activeID,sourceRevision:model.sourceRevision,widgetID:widgetID,date:configuration.date,mode:mode,exclusions:configuration.sourceExclusions)
    }
    private func dragStillValid(_ capture: CalendarEventDragCapture) -> Bool {
        mounted && capture.account == model.inference.activeID && capture.sourceRevision == model.sourceRevision && capture.widgetID == widgetID && capture.date == configuration.date && capture.mode == mode && capture.exclusions == configuration.sourceExclusions
    }
    private func move(_ event: AgendaEvent, to start: Date?) {
        let capture = dragCapture; dragCapture=nil
        guard let capture, capture.event.id == event.id, dragStillValid(capture), canDrag(event), let start, start != event.start else { return }
        var preview=event; preview.start=start; preview.end=start.addingTimeInterval(event.end.timeIntervalSince(event.start))
        pendingMove=preview
        Task { @MainActor in
            defer { pendingMove=nil }
            do {
                try await model.moveCalendarEvent(capture.event,to:start,valid:{ dragStillValid(capture) })
                await load()
            } catch { await load(); moveError=error.localizedDescription }
        }
    }
    private func eventButton(_ event: AgendaEvent) -> some View {
        Button { select(event) } label: {
            HStack(alignment:.top,spacing:7) {
                RoundedRectangle(cornerRadius:2).fill(color(event)).frame(width:3)
                VStack(alignment:.leading,spacing:4) {
                    if !event.allDay { Text(event.start.formatted(date:.omitted,time:.shortened) + " – " + event.end.formatted(date:.omitted,time:.shortened)).font(.caption).foregroundStyle(.secondary) }
                    Text(event.title).font(.callout.weight(.medium)).lineLimit(3)
                    if !event.location.isEmpty { Text(event.location).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    Text(snapshot.sources.first(where:{ $0.id == event.calendarID })?.displayLabel ?? event.sourceLabel).font(.caption2).foregroundStyle(color(event)).lineLimit(1)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.padding(.vertical,5).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var agendaView: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:12) {
                ForEach(0..<7,id:\.self) { offset in
                    let day = calendar.date(byAdding:.day,value:offset,to:range.start)!, items = dayEvents(day)
                    // One row per day: a multi-day event repeats under each day with the same ID,
                    // and a lazy stack draws a repeated ID once, leaving blank rows elsewhere.
                    VStack(alignment:.leading,spacing:12) {
                        Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.subheadline.weight(.semibold))
                        if items.isEmpty { Text("Nothing scheduled").font(.callout).foregroundStyle(.secondary) }
                        ForEach(items.filter(\.allDay)) { eventButton($0) }
                        ForEach(items.filter { !$0.allDay }) { eventButton($0) }
                        Divider()
                    }
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
            let week = mode == "week"
            let width = week ? weekColumnWidth : CalendarTimelineFocus.columnWidth(available:max(1,geometry.size.width-14),days:1)
            let indices = week ? CalendarWeekStrip.rendered(leading:leadingIndex,visible:visibleColumns) : 0..<1
            let columns = timelineColumns(indices,from:week ? stripStart : calendar.startOfDay(for:configuration.date))
            // Counted over the loaded block, so the header height holds steady while scrolling.
            let allDayCount = mostAllDayEvents(in:range)
            let allDayHeight = Double(min(3,allDayCount))*24 + (allDayCount > 3 ? 20 : 0)
            let inset = Double(indices.lowerBound)*(width+8)
            ScrollView(week ? [.horizontal,.vertical] : .vertical) {
                LazyVStack(alignment:.leading,spacing:0,pinnedViews:[.sectionHeaders]) {
                    Section {
                        HStack(alignment:.top,spacing:8) {
                            ForEach(columns) { column in
                                CalendarDayTimeline(events:column.events.filter { !$0.allDay },day:column.day,color:color,select:select,canDrag:canDrag,coordinateSpace:timelineSpace,activeDragID:dragCapture?.event.id,beginDrag:beginDrag,previewStart:{ start,dx,dy in
                                    CalendarTimelineMove.destination(start:start,day:column.day,dx:dx,dy:dy,columnWidth:width,visibleDays:week ? 7 : 1,range:range)
                                },move:move).frame(width:width)
                                    .zIndex(column.events.contains(where:{ $0.id == dragCapture?.event.id }) ? 1 : 0)
                            }
                        }.coordinateSpace(name:timelineSpace).padding(.leading,inset).padding(.bottom,10)
                    } header: {
                        HStack(alignment:.top,spacing:8) {
                            ForEach(columns) { column in
                                let day = column.day
                                VStack(alignment:.leading,spacing:6) {
                                    Text(day.formatted(calendar.component(.day,from:day) == 1 ? .dateTime.weekday(.abbreviated).day().month(.abbreviated) : .dateTime.weekday(.abbreviated).day())).font(.subheadline.weight(.semibold)).foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : Color.primary)
                                    if allDayCount > 0 {
                                        let items = column.events.filter(\.allDay)
                                        VStack(alignment:.leading,spacing:3) {
                                            ForEach(items.prefix(3)) { event in Button { select(event) } label: { Text("All day · " + event.title).font(.caption2).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading).padding(4).background(color(event).opacity(0.12),in:RoundedRectangle(cornerRadius:4)) }.buttonStyle(.plain).help(event.title) }
                                            if items.count > 3 { Button("+\(items.count-3) all-day events") { configuration.date = day; configuration.calendarMode = "agenda" }.font(.caption2).buttonStyle(.borderless) }
                                        }.frame(height:allDayHeight,alignment:.top)
                                    }
                                }.frame(width:width,alignment:.leading)
                            }
                        }.padding(.leading,inset).padding(.vertical,8).frame(maxWidth:.infinity,alignment:.leading)
                            .background(palette[.widget])
                            .overlay(alignment:.bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height:1) }
                    }
                }.frame(width:Double(week ? CalendarWeekStrip.days : 1)*(width+8)-8,alignment:.leading)
            }
            .scrollPosition($timelinePosition)
            // A four-year strip's scroller thumb is a sliver that jumps months; scrolling and the arrows suffice.
            .scrollIndicators(.never,axes:.horizontal)
            .onScrollGeometryChange(for:Int.self) { week ? Int(($0.contentOffset.x/(width+8)).rounded()) : 0 } action: { _,leading in if week { leadingIndex = leading } }
        }
        .onGeometryChange(for:Double.self) { $0.size.width } action: { timelineWidth = $0 }
        .task(id:"\(mode):\(focusRequest):\(placement):\(timelineWidth > 0)") { await Task.yield(); placeTimeline() }
        .task(id:leadingIndex) { try? await Task.sleep(for:.milliseconds(500)); if !Task.isCancelled { settleWeek() } }
        .onChange(of:configuration.date) { _,date in if date == writtenDate { writtenDate = nil } else { placement += 1 } }
        .onChange(of:timelineWidth) { old,_ in if old > 0, mode == "week", let placedLeading { showWeek(from:placedLeading) } }
    }
}
private struct CalendarEventSelection: Identifiable {
    let id = UUID()
    var event: AgendaEvent
}
private struct CalendarTimelineColumn: Identifiable {
    var id: Int; var day: Date; var events: [AgendaEvent]
}
private struct CalendarEventDragCapture {
    var event: AgendaEvent; var account: String?; var sourceRevision: Int; var widgetID: UUID?
    var date: Date; var mode: String; var exclusions: Set<String>
}
private struct CalendarDayTimeline: View {
    var events: [AgendaEvent]; var day: Date; var color: (AgendaEvent)->Color; var select: (AgendaEvent)->Void
    var canDrag: (AgendaEvent)->Bool
    var coordinateSpace: String
    var activeDragID: String?
    var beginDrag: (AgendaEvent)->Void
    var previewStart: (Date,Double,Double)->Date?
    var move: (AgendaEvent,Date?)->Void
    private var interval: DateInterval { Calendar.current.dateInterval(of:.day,for:day)! }
    private let hourHeight = CalendarTimelineFocus.hourHeight
    var body: some View {
        let hours = Int(interval.duration/3600)
        let work = CalendarTimelineFocus.workingHours(on:day)
        ZStack(alignment:.topLeading) {
            Rectangle().fill(Color.accentColor.opacity(0.035)).padding(.leading,40).frame(height:work.duration/3600*hourHeight).offset(y:work.start.timeIntervalSince(interval.start)/3600*hourHeight)
            VStack(spacing:0) {
                ForEach(0..<hours,id:\.self) { hour in
                    let date = Calendar.current.date(byAdding:.hour,value:hour,to:interval.start)!
                    HStack(alignment:.top,spacing:4) {
                        Text(date.formatted(.dateTime.hour().minute())).font(.system(size:10)).foregroundStyle(.secondary).frame(width:36)
                        Rectangle().fill(Color.primary.opacity(0.07)).frame(height:1)
                    }.frame(height:hourHeight,alignment:.top)
                        .help(date.formatted(date:.omitted,time:.shortened) + " " + (Calendar.current.timeZone.abbreviation(for:date) ?? ""))
                }
            }
            GeometryReader { geo in
                ZStack(alignment:.topLeading) {
                    ForEach(CalendarTimelineLayout.segments(events,interval:interval)) { segment in
                        let height = max(CalendarTimelineFocus.minimumEventHeight,segment.end.timeIntervalSince(segment.start)/3600*hourHeight)
                        CalendarTimedEventCard(event:segment.event,color:color(segment.event),height:height,movable:canDrag(segment.event),coordinateSpace:coordinateSpace,select:{ select(segment.event) },beginDrag:{ beginDrag(segment.event) },previewStart:{ dx,dy in previewStart(segment.event.start,dx,dy) },move:{ dx,dy in move(segment.event,previewStart(segment.event.start,dx,dy)) })
                            .frame(width:max(1,(geo.size.width-40)/CGFloat(segment.lanes)-3),height:height)
                            .offset(x:40+CGFloat(segment.lane)*(geo.size.width-40)/CGFloat(segment.lanes),y:segment.start.timeIntervalSince(interval.start)/3600*hourHeight)
                            .zIndex(segment.id == activeDragID ? 1 : 0)
                    }
                }
            }
            TimelineView(.periodic(from:.now,by:60)) { context in
                if interval.contains(context.date) && context.date < interval.end {
                    HStack(spacing:0) { Circle().fill(.red).frame(width:6,height:6); Rectangle().fill(.red.opacity(0.8)).frame(height:1) }.padding(.leading,37).offset(y:context.date.timeIntervalSince(interval.start)/3600*hourHeight)
                        .accessibilityLabel("Current time " + context.date.formatted(date:.omitted,time:.shortened)).allowsHitTesting(false)
                }
            }
        }.frame(height:CGFloat(hours)*hourHeight).contentShape(Rectangle())
    }
}

// Measure against the stationary timeline, never the moving card's local bounds.
private struct CalendarTimedEventCard: View {
    var event: AgendaEvent
    var color: Color
    var height: Double
    var movable: Bool
    var coordinateSpace: String
    var select: ()->Void
    var beginDrag: ()->Void
    var previewStart: (Double,Double)->Date?
    var move: (Double,Double)->Void
    @GestureState private var translation = CGSize.zero
    private var moving: Bool { translation != .zero }
    private var title: String { event.title + " · " + event.start.formatted(date:.omitted,time:.shortened) }
    private var drag: some Gesture {
        DragGesture(minimumDistance:6,coordinateSpace:.named(coordinateSpace))
            .updating($translation) { value,state,transaction in transaction.disablesAnimations=true; state = value.translation }
            .onChanged { _ in beginDrag() }
            .onEnded { value in move(Double(value.translation.width),Double(value.translation.height)) }
    }
    private var card: some View {
        VStack(alignment:.leading,spacing:2) {
            Text(event.title).font(.caption2.weight(.medium)).lineLimit(height > 48 ? 3 : 1)
            if height > 38 { Text((moving ? previewStart(Double(translation.width),Double(translation.height)) ?? event.start : event.start).formatted(date:.omitted,time:.shortened)).font(.system(size:10)).foregroundStyle(.secondary) }
            Spacer(minLength:0)
        }.padding(.horizontal,5).padding(.vertical,height > 38 ? 5 : 2).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .background(color.opacity(moving ? 0.3 : 0.17),in:RoundedRectangle(cornerRadius:5))
            .overlay(alignment:.leading) { RoundedRectangle(cornerRadius:2).fill(color).frame(width:3) }.clipped()
            .overlay { if moving { RoundedRectangle(cornerRadius:5).stroke(color,lineWidth:1.5) } }
            .contentShape(Rectangle())
    }
    var body: some View {
        Group {
            if movable { card.gesture(drag.exclusively(before:TapGesture().onEnded { _ in select() })) } else { card.onTapGesture(perform:select) }
        }.offset(x:translation.width,y:translation.height).zIndex(moving ? 1 : 0)
            .transaction { $0.animation=nil }
            .help(title + (movable ? " · Drag to move this occurrence; click to edit." : " · Click to edit.")).accessibilityElement(children:.ignore).accessibilityLabel(title)
            .accessibilityAddTraits(.isButton).accessibilityAction(.default) { select() }
    }
}

#if DEBUG
// An isolated live check: only UUID-marked events in its own disposable calendar.
struct CalendarDragPreview: View {
    @Bindable var model: DashboardModel
    @State private var fixture: CalendarDragFixture?
    @State private var configuration = WidgetConfiguration(calendarMode:"day")
    @State private var error: String?
    var body: some View {
        VStack(spacing:8) {
            HStack {
                Text("Disposable Calendar drag check").font(.headline)
                Spacer()
                Button("Undo move") { model.undoLatest() }.disabled(model.latestUndo != "edit" || model.writing)
                Button("Verify native times") { Task { await verify() } }
                Button("Run save-path checks") { Task {
                    do { guard let fixture else { return }; error=try await CalendarDragValidation.run(model,fixture:fixture) }
                    catch { self.error=error.localizedDescription }
                } }.disabled(model.writing)
                Button("Remove fixtures and close") { Task {
                    do { if let fixture { try await model.eventKit.removeCalendarDragFixture(fixture) }; NSApp.terminate(nil) }
                    catch { self.error=error.localizedDescription }
                } }.disabled(model.writing)
            }.padding(.horizontal,16)
            if let error { Text(error).foregroundStyle(.orange) }
            if let fixture { CalendarWidgetView(model:model,configuration:$configuration,previewFixture:fixture) }
            else { ProgressView().task {
                do { fixture=try await model.eventKit.makeCalendarDragFixture(); configuration.date=fixture!.date }
                catch { self.error=error.localizedDescription }
            } }
        }.padding(.vertical,12)
    }
    private func verify() async {
        do {
            guard let fixture else { return }
            let range=DateInterval(start:fixture.date,end:fixture.date.addingTimeInterval(4*86400))
            let value=try await model.eventKit.calendarDragSnapshot(fixture,range:range)
            let data=try JSONEncoder().encode(value)
            try data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-calendar-drag-fixtures.json"),options:.atomic)
            error="Verified \(value.events.count) disposable occurrences; native times saved in the local diagnostic."
        } catch { self.error=error.localizedDescription }
    }
}
@MainActor private enum CalendarDragValidation {
    static func run(_ model: DashboardModel, fixture: CalendarDragFixture) async throws -> String {
        let range=DateInterval(start:fixture.date,end:fixture.date.addingTimeInterval(4*86400))
        func snapshot() async throws -> CalendarSnapshot { try await model.eventKit.calendarDragSnapshot(fixture,range:range) }
        func at(_ date: Date) async throws -> AgendaEvent {
            let matches=try await snapshot().events.filter{$0.start == date}
            guard matches.count == 1 else { throw IntegrationError.verification }; return matches[0]
        }
        var checks:[String:Bool]=[:]
        func check(_ condition: Bool,_ name: String) throws { checks[name]=condition; guard condition else { throw ActionFailure.message("Failed disposable check: " + name) } }
        let start=fixture.date.addingTimeInterval(9*3600), target=start.addingTimeInterval(5.25*3600)
        let original=try await at(start), details=try await model.eventKit.editSession(.event(original)).item
        let nativeZone=try await model.eventKit.calendarDragTimeZone(fixture,event:original)
        var stale=original; stale.modified = .distantPast
        var staleRefused=false
        do { try await model.moveCalendarEvent(stale,to:target) } catch { staleRefused=true }
        try check(staleRefused,"stale displayed native revision refused")
        try check(try await at(start).id == original.id,"stale revision refusal left native event unchanged")
        var validations=0,refused=false
        do {try await model.moveCalendarEvent(original,to:target,valid:{ validations += 1; return validations < 3 })} catch {refused=true}
        try check(refused && validations == 3,"controls changed immediately before save refused")
        try check(try await at(start).id == original.id,"refused move left native time unchanged")
        try await model.moveCalendarEvent(original,to:target)
        let moved=try await at(target), saved=try await model.eventKit.editSession(.event(moved)).item
        try check(saved.start == target && saved.end.timeIntervalSince(saved.start) == details.end.timeIntervalSince(details.start),"direct move saved start and preserved duration")
        try check(saved.title == details.title && saved.notes == details.notes && saved.location == details.location && saved.timeZoneID == details.timeZoneID && saved.alarms == details.alarms && saved.availability == details.availability,"notes location timezone alerts and availability preserved")
        try check(try await model.eventKit.calendarDragTimeZone(fixture,event:moved) == nativeZone,"native floating or explicit timezone representation preserved")
        _=try await model.undoAssistantAppleChange()
        try check(try await at(start).end == original.end,"direct move Undo restored original native time")
        let repeatedStart=fixture.date.addingTimeInterval(11*3600), repeatedTarget=repeatedStart.addingTimeInterval(2.25*3600)
        let repeated=try await at(repeatedStart)
        try await model.moveCalendarEvent(repeated,to:repeatedTarget)
        try check(try await at(repeatedTarget).end.timeIntervalSince(repeatedTarget) == 3600,"repeating occurrence moved directly")
        let later=try await snapshot().events.filter{$0.start >= fixture.date.addingTimeInterval(86400)}
        try check(later.count == 2 && later.allSatisfy{Calendar.current.component(.hour,from:$0.start) == 11},"later occurrences retained original time")
        _=try await model.undoAssistantAppleChange()
        try check(try await at(repeatedStart).end.timeIntervalSince(repeatedStart) == 3600,"repeating occurrence Undo restored selected time")
        let final=try await snapshot()
        try check(final.events.count == 5,"Undo did not duplicate repeating occurrences")
        let report:[String:Any]=["completed":Date.now.ISO8601Format(),"passed":checks.values.filter{$0}.count,"total":checks.count,"checks":checks,"scope":"Isolated UUID-marked native Calendar fixtures; production direct move and Undo, no AI or personal source reads."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:EvaluationOutput.url("/tmp/missioncontrol-calendar-drag-evaluation.json"),options:.atomic)
        return "PASS \(checks.count)/\(checks.count) native Calendar move checks."
    }
}
#endif
