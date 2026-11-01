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
    /// The leading column when scrolling last rested; the all-day band is sized to the days from here.
    @State private var bandLeading = 0
    @State private var placedLeading: Date?
    @State private var writtenDate: Date?
    @State private var placement = 0
    private var calendar: Calendar { .current }
    private var mode: String { configuration.calendarMode }
    private var motion = MotionPreference()
    @Environment(\.calendarPreviewSnapshot) private var environmentSnapshot
    @Environment(\.widgetLayout) private var layout
    private var range: DateInterval {
        // Glances always look ahead from today, whatever view the full widget was left in.
        if layout.compact { let start = calendar.startOfDay(for:.now); return DateInterval(start:start,end:calendar.date(byAdding:.day,value:7,to:start)!) }
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
    private var events: [AgendaEvent] {
        snapshot.events.filter { !configuration.sourceExclusions.contains($0.calendarID) }.map { event in
            pendingMove?.id == event.id ? pendingMove! : event
        }
    }
    var body: some View {
        Group {
            if layout.compact { glance } else { full }
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
    /// What's left of today, then the coming days: a date and the next events, more of them as the widget grows.
    private var glance: some View {
        let now = Date.now
        func key(_ event: AgendaEvent) -> (Date, Int, Date) { (calendar.startOfDay(for:max(event.start,now)), event.allDay ? 0 : 1, event.start) }
        let ahead = events.filter { $0.end > now }.sorted { key($0) < key($1) }
        // Two-row sizes keep to today and the next day that has something on; a tall one shows the week.
        let horizon = ahead.first.flatMap { calendar.date(byAdding:.day,value:calendar.isDateInToday(key($0).0) ? 2 : 1,to:key($0).0) }
        let upcoming = layout.short ? ahead.filter { key($0).0 < horizon ?? .distantFuture } : ahead
        return VStack(alignment:.leading,spacing:layout == .small ? 8 : 10) {
            WidgetHeader(title:"Calendar",symbol:"calendar",meta:layout == .small ? now.formatted(.dateTime.weekday(.abbreviated).day()) : nil) {
                if layout == .medium {
                    SourceStatusIndicator(title:"Calendar",health:SourceHealth(lastSuccess:updated,error:error,loading:loading))
                    Button { model.newNativeItem(.event,date:.now) } label: { Image(systemName:"plus") }.help("New event").accessibilityLabel("New event").disabled(model.writing)
                }
            }.controlSize(.small)
            if let error, layout != .small { Text((updated == nil ? "" : "Stale · ") + error).font(.caption).foregroundStyle(.orange).lineLimit(2) }
            HStack(alignment:.top,spacing:16) {
                if layout == .medium {
                    VStack(alignment:.leading,spacing:0) {
                        Text(now.formatted(.dateTime.weekday(.wide)).uppercased()).font(.system(size:10.5,weight:.bold)).tracking(1).foregroundStyle(palette[.accent]).lineLimit(1)
                        Text(now.formatted(.dateTime.day())).font(.system(size:38,weight:.semibold,design:.rounded)).monospacedDigit()
                        Text(now.formatted(.dateTime.month(.wide))).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(width:78,alignment:.leading)
                }
                GlanceRows(items:upcoming,rowHeight:layout == .tall ? 40 : 32,empty:"Nothing else this week.",scrolls:layout == .tall) { event in glanceRow(event,now:now) }
            }
        }.contextMenu { if layout != .medium { Button("New event") { model.newNativeItem(.event,date:.now) }.disabled(model.writing) } }
    }
    private func glanceRow(_ event: AgendaEvent, now: Date) -> some View {
        let day = calendar.startOfDay(for:max(event.start,now))
        let when = event.allDay ? "All day" : event.start <= now ? "Now · until " + event.end.formatted(date:.omitted,time:.shortened) : event.start.formatted(date:.omitted,time:.shortened)
        let dayLabel = calendar.isDateInToday(day) ? nil : calendar.isDateInTomorrow(day) ? "Tomorrow" : day.formatted(.dateTime.weekday(.abbreviated).day())
        return Button { select(event) } label: {
            HStack(alignment:.top,spacing:7) {
                RoundedRectangle(cornerRadius:2).fill(color(event)).frame(width:3)
                VStack(alignment:.leading,spacing:2) {
                    Text(event.title).font(.callout.weight(.medium)).lineLimit(layout == .tall ? 2 : 1)
                    Text([dayLabel,when].compactMap { $0 }.joined(separator:" · ")).font(.caption).foregroundStyle(event.start <= now && !event.allDay ? palette[.accent] : .secondary).lineLimit(1)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).help(event.title + (event.location.isEmpty ? "" : " · " + event.location))
    }
    private var full: some View {
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
        }
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
            if let previewSnapshot = previewSnapshot ?? environmentSnapshot { value = previewSnapshot(range) }
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
            bandLeading = index
            withAnimation { timelinePosition.scrollTo(x:Double(index)*(weekColumnWidth+8)) }
            return
        }
        leadingIndex = index; bandLeading = index
        let x = Double(index)*(weekColumnWidth+8)
        if let y { timelinePosition.scrollTo(point:CGPoint(x:x,y:y)) } else { timelinePosition.scrollTo(x:x) }
    }
    /// Once scrolling rests, the remembered date moves with the strip so it keeps its place on screen.
    private func settleWeek() {
        guard mode == "week", dragCapture == nil, let placed = placedLeading else { return }
        bandLeading = leadingIndex
        let leading = CalendarWeekStrip.day(leadingIndex,from:stripStart), moved = CalendarWeekStrip.index(of:leading,from:placed)
        if moved != 0 { advanceDate(moved,leading:leading) }
        if !CalendarWeekStrip.comfortable(leadingIndex,visible:visibleColumns) { showWeek(from:leading) }
    }
    private func advanceDate(_ days: Int, leading: Date) {
        let date = calendar.date(byAdding:.day,value:days,to:configuration.date)!
        placedLeading = leading; writtenDate = date; configuration.date = date
    }
    /// Rebuilt whenever scrolling crosses a column, so each day's bounds come from one walk along the strip.
    private func timelineColumns(_ indices: Range<Int>, from start: Date, events: [AgendaEvent]) -> [CalendarTimelineColumn] {
        guard !indices.isEmpty else { return [] }
        let bounds = (indices.lowerBound...indices.upperBound).map { CalendarWeekStrip.day($0,from:start) }
        let nearby = events.filter { $0.start < bounds.last! && $0.end >= bounds[0] }
        return zip(indices,zip(bounds,bounds.dropFirst())).map { index,day in
            let interval = DateInterval(start:day.0,end:day.1)
            return CalendarTimelineColumn(id:index,day:day.0,events:nearby.filter { DateRules.overlaps($0,interval:interval) })
        }
    }
    private func colors(_ events: [AgendaEvent]) -> [String:Color] {
        Dictionary(events.map { ($0.calendarID,color($0)) },uniquingKeysWith:{ first,_ in first })
    }
    private func mostAllDayEvents(in interval: DateInterval, events: [AgendaEvent]) -> Int {
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
            let week = mode == "week", events = self.events
            let width = week ? weekColumnWidth : CalendarTimelineFocus.columnWidth(available:max(1,geometry.size.width-14),days:1)
            let indices = week ? CalendarWeekStrip.rendered(leading:leadingIndex,visible:visibleColumns) : 0..<1
            let columns = timelineColumns(indices,from:week ? stripStart : calendar.startOfDay(for:configuration.date),events:events)
            // Counted over the days on screen when scrolling last rested, like Calendar. Resizing
            // mid-scroll would shift the whole grid up and down under a sideways scroll.
            let visibleDays = week ? DateInterval(start:CalendarWeekStrip.day(bandLeading,from:stripStart),end:CalendarWeekStrip.day(bandLeading+visibleColumns,from:stripStart)) : range
            let allDayCount = mostAllDayEvents(in:visibleDays,events:events)
            let allDayHeight = Double(min(3,allDayCount))*24 + (allDayCount > 3 ? 20 : 0)
            let inset = Double(indices.lowerBound)*(width+8)
            ScrollView(week ? [.horizontal,.vertical] : .vertical) {
                LazyVStack(alignment:.leading,spacing:0,pinnedViews:[.sectionHeaders]) {
                    Section {
                        HStack(alignment:.top,spacing:8) {
                            ForEach(columns) { column in
                                let timed = column.events.filter { !$0.allDay }
                                CalendarDayTimeline(events:timed,day:column.day,colors:colors(timed),movable:Set(timed.filter(canDrag).map(\.id)),columnWidth:width,visibleDays:week ? 7 : 1,range:range,widgetID:widgetID,coordinateSpace:timelineSpace,activeDragID:dragCapture?.event.id,select:select,beginDrag:beginDrag,move:move)
                                    .equatable().frame(width:width)
                                    .zIndex(column.events.contains(where:{ $0.id == dragCapture?.event.id }) ? 1 : 0)
                            }
                        }.coordinateSpace(name:timelineSpace).padding(.leading,inset).padding(.bottom,10)
                    } header: {
                        HStack(alignment:.top,spacing:8) {
                            ForEach(columns) { column in
                                let items = column.events.filter(\.allDay)
                                CalendarDayHeader(day:column.day,today:calendar.isDateInToday(column.day),items:items,colors:colors(items),bandHeight:allDayCount > 0 ? allDayHeight : nil,animateBand:!motion.reduced,select:select,showAll:{ configuration.date = column.day; configuration.calendarMode = "agenda" })
                                    .equatable().frame(width:width,alignment:.leading)
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
/// One day's grid and timed events. Its action closures are rebuilt with every parent update,
/// so it compares only its data: a sideways scroll that just moves the rendered window then
/// leaves unchanged days alone instead of rebuilding every column each time it crosses one.
private struct CalendarDayTimeline: View, Equatable {
    var events: [AgendaEvent]; var day: Date; var colors: [String:Color]; var movable: Set<String>
    var columnWidth: Double; var visibleDays: Int; var range: DateInterval
    /// Compared but not shown: the action closures capture it.
    var widgetID: UUID?
    var coordinateSpace: String
    var activeDragID: String?
    var select: (AgendaEvent)->Void
    var beginDrag: (AgendaEvent)->Void
    var move: (AgendaEvent,Date?)->Void
    static func == (a: Self, b: Self) -> Bool {
        a.events == b.events && a.day == b.day && a.colors == b.colors && a.movable == b.movable && a.columnWidth == b.columnWidth && a.visibleDays == b.visibleDays
            && a.range == b.range && a.widgetID == b.widgetID && a.coordinateSpace == b.coordinateSpace && a.activeDragID == b.activeDragID
    }
    private var interval: DateInterval { Calendar.current.dateInterval(of:.day,for:day)! }
    private let hourHeight = CalendarTimelineFocus.hourHeight
    private func previewStart(_ event: AgendaEvent, _ dx: Double, _ dy: Double) -> Date? {
        CalendarTimelineMove.destination(start:event.start,day:day,dx:dx,dy:dy,columnWidth:columnWidth,visibleDays:visibleDays,range:range)
    }
    var body: some View {
        let interval = self.interval, hours = Int(interval.duration/3600)
        ZStack(alignment:.topLeading) {
            CalendarHourGrid(day:day)
            // The now line sits under the cards; the event under way is opaque, so the line never strikes through its title.
            // Ticks from midnight land on the minute, and the schedule stays the same across updates.
            TimelineView(.periodic(from:interval.start,by:60)) { context in
                if interval.contains(context.date) && context.date < interval.end {
                    HStack(spacing:0) {
                        Text(context.date.formatted(date:.omitted,time:.shortened)).font(.system(size:9.5,weight:.bold).monospacedDigit()).foregroundStyle(.white)
                            .lineLimit(1).fixedSize().padding(.horizontal,4).padding(.vertical,1).background(.red,in:Capsule()).frame(width:40,alignment:.trailing)
                        Rectangle().fill(.red).frame(height:2).shadow(color:.red.opacity(0.45),radius:3)
                    }.frame(height:14).offset(y:context.date.timeIntervalSince(interval.start)/3600*hourHeight-7)
                        .accessibilityLabel("Current time " + context.date.formatted(date:.omitted,time:.shortened)).allowsHitTesting(false)
                }
            }
            GeometryReader { geo in
                TimelineView(.periodic(from:interval.start,by:60)) { context in
                let status = CalendarEventStatus.resolver(events,interval:interval,now:context.date)
                ZStack(alignment:.topLeading) {
                    ForEach(CalendarTimelineLayout.segments(events,interval:interval)) { segment in
                        let height = max(CalendarTimelineFocus.minimumEventHeight,segment.end.timeIntervalSince(segment.start)/3600*hourHeight)
                        CalendarTimedEventCard(event:segment.event,color:colors[segment.event.calendarID] ?? .accentColor,height:height,status:status(segment.event),movable:movable.contains(segment.event.id),coordinateSpace:coordinateSpace,select:{ select(segment.event) },beginDrag:{ beginDrag(segment.event) },previewStart:{ dx,dy in previewStart(segment.event,dx,dy) },move:{ dx,dy in move(segment.event,previewStart(segment.event,dx,dy)) })
                            .frame(width:max(1,(geo.size.width-40)/CGFloat(segment.lanes)-3),height:height)
                            .offset(x:40+CGFloat(segment.lane)*(geo.size.width-40)/CGFloat(segment.lanes),y:segment.start.timeIntervalSince(interval.start)/3600*hourHeight)
                            .zIndex(segment.id == activeDragID ? 1 : 0)
                    }
                }
                }
            }
        }.frame(height:CGFloat(hours)*hourHeight).contentShape(Rectangle())
    }
}
/// Working hours, hour lines and labels: plain values, so SwiftUI skips it unless the day changes.
private struct CalendarHourGrid: View {
    var day: Date
    var body: some View {
        let interval = Calendar.current.dateInterval(of:.day,for:day)!, hourHeight = CalendarTimelineFocus.hourHeight
        let work = CalendarTimelineFocus.workingHours(on:day)
        ZStack(alignment:.topLeading) {
            Rectangle().fill(Color.accentColor.opacity(0.035)).padding(.leading,40).frame(height:work.duration/3600*hourHeight).offset(y:work.start.timeIntervalSince(interval.start)/3600*hourHeight)
            VStack(spacing:0) {
                ForEach(0..<Int(interval.duration/3600),id:\.self) { hour in
                    let date = Calendar.current.date(byAdding:.hour,value:hour,to:interval.start)!
                    HStack(alignment:.top,spacing:4) {
                        Text(date.formatted(.dateTime.hour().minute())).font(.system(size:10)).foregroundStyle(.secondary).frame(width:36)
                        Rectangle().fill(Color.primary.opacity(0.07)).frame(height:1)
                    }.frame(height:hourHeight,alignment:.top)
                        .help(date.formatted(date:.omitted,time:.shortened) + " " + (Calendar.current.timeZone.abbreviation(for:date) ?? ""))
                }
            }
        }
    }
}
/// A day's name and its all-day events above the grid; compared by its data, like the grid.
private struct CalendarDayHeader: View, Equatable {
    var day: Date; var today: Bool; var items: [AgendaEvent]; var colors: [String:Color]
    /// nil when no day on screen has an all-day event.
    var bandHeight: Double?
    var animateBand: Bool
    var select: (AgendaEvent)->Void
    var showAll: ()->Void
    static func == (a: Self, b: Self) -> Bool {
        a.day == b.day && a.today == b.today && a.items == b.items && a.colors == b.colors && a.bandHeight == b.bandHeight && a.animateBand == b.animateBand
    }
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Text(day.formatted(Calendar.current.component(.day,from:day) == 1 ? .dateTime.weekday(.abbreviated).day().month(.abbreviated) : .dateTime.weekday(.abbreviated).day())).font(.subheadline.weight(.semibold)).foregroundStyle(today ? Color.accentColor : Color.primary)
            if let bandHeight {
                VStack(alignment:.leading,spacing:3) {
                    ForEach(items.prefix(3)) { event in Button { select(event) } label: { Text("All day · " + event.title).font(.caption2).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading).padding(4).background((colors[event.calendarID] ?? .accentColor).opacity(0.12),in:RoundedRectangle(cornerRadius:4)) }.buttonStyle(.plain).help(event.title) }
                    if items.count > 3 { Button("+\(items.count-3) all-day events",action:showAll).font(.caption2).buttonStyle(.borderless) }
                }
                // Sized at rest, so a day scrolled in mid-scroll may hold more than fits until then.
                .frame(height:bandHeight,alignment:.top).clipped().animation(animateBand ? .smooth(duration:0.25) : nil,value:bandHeight)
            }
        }
    }
}

// Measure against the stationary timeline, never the moving card's local bounds.
/// Today's events: finished ones fade, the one under way fills as it runs, and the next is outlined.
enum CalendarEventStatus: Equatable {
    case normal, past, next, current(Double)
    static func resolver(_ events: [AgendaEvent], interval: DateInterval, now: Date) -> (AgendaEvent) -> CalendarEventStatus {
        guard interval.contains(now) else { return { _ in .normal } }
        let timed = events.filter { !$0.allDay }
        let underway = timed.contains { $0.start <= now && now < $0.end }
        let nextID = underway ? nil : timed.filter { $0.start > now && interval.contains($0.start) }.min { $0.start < $1.start }?.id
        return { event in
            if event.allDay { return .normal }
            if event.end <= now { return .past }
            if event.start <= now { return .current(min(1, now.timeIntervalSince(event.start) / max(60, event.end.timeIntervalSince(event.start)))) }
            return event.id == nextID ? .next : .normal
        }
    }
}

private struct CalendarTimedEventCard: View {
    var event: AgendaEvent
    var color: Color
    var height: Double
    var status: CalendarEventStatus = .normal
    @Environment(\.workspacePalette) private var palette
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
    /// Under half an hour: one line. About an hour: title, then "time · place". Longer: three lines.
    private var card: some View {
        let start = moving ? previewStart(Double(translation.width),Double(translation.height)) ?? event.start : event.start
        let time = start.formatted(date:.omitted,time:.shortened)
        let range = moving ? time : time + " – " + event.end.formatted(date:.omitted,time:.shortened)
        let detail = event.location.isEmpty ? range : range + " · " + event.location
        let current: Double? = { if case .current(let fraction) = status { return fraction }; return nil }()
        let shape = RoundedRectangle(cornerRadius:8,style:.continuous)
        return Group {
            if height < 30 {
                // The title wins in a narrow column; the time only shows when both fit.
                ViewThatFits(in:.horizontal) {
                    HStack(alignment:.firstTextBaseline,spacing:5) {
                        Text(event.title).font(.system(size:12,weight:.semibold)).lineLimit(1).fixedSize()
                        Text(time).font(.system(size:10.5)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                        Spacer(minLength:0)
                    }
                    Text(event.title).font(.system(size:12,weight:.semibold)).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                }.padding(.vertical,3)
            } else {
                VStack(alignment:.leading,spacing:1) {
                    Text(event.title).font(.system(size:12,weight:.semibold)).lineLimit(height >= 90 ? 2 : 1)
                    if height >= 72 {
                        Text(range).font(.system(size:10.5)).foregroundStyle(.secondary).lineLimit(1)
                        if !event.location.isEmpty { Text(event.location).font(.system(size:10.5)).foregroundStyle(.secondary).lineLimit(1) }
                    } else {
                        Text(detail).font(.system(size:10.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength:0)
                }.padding(.vertical,5)
            }
        }
        .padding(.leading,9).padding(.trailing,5).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .background {
            ZStack(alignment:.top) {
                if current != nil { palette[.widget] }
                color.opacity(moving ? 0.3 : 0.17)
                if let current { color.opacity(0.2).frame(height:height*current).frame(maxHeight:.infinity,alignment:.top) }
            }
        }
        .overlay(alignment:.leading) { Rectangle().fill(color).frame(width:3) }
        .clipShape(shape)
        .overlay { if moving { shape.stroke(color,lineWidth:1.5) } else if status == .next { shape.strokeBorder(color,lineWidth:1.5) } }
        .opacity(status == .past && !moving ? 0.5 : 1)
        .shadow(color:.black.opacity(current == nil ? 0 : 0.14),radius:6,y:3)
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

private struct CalendarPreviewSnapshotKey: EnvironmentKey { static let defaultValue: ((DateInterval) -> CalendarSnapshot)? = nil }
extension EnvironmentValues {
    /// Fictional events for DEBUG previews of the whole dashboard; nil in normal use.
    var calendarPreviewSnapshot: ((DateInterval) -> CalendarSnapshot)? { get { self[CalendarPreviewSnapshotKey.self] } set { self[CalendarPreviewSnapshotKey.self] = newValue } }
}
