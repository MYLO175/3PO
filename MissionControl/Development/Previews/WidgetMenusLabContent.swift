#if DEBUG
import SwiftUI

/// What each lab widget shows, shared by every design; only the controls around it change.
struct LabWidgetContent: View {
    let widget: LabWidget
    let design: WidgetMenuDesign
    @Bindable var lab: WidgetLabState
    var body: some View {
        switch widget {
        case .calendar: LabCalendarContent(design: design, lab: lab)
        case .brief: LabBriefContent(design: design, lab: lab)
        case .reminders: LabRemindersContent(design: design, lab: lab)
        case .chat: LabChatContent(design: design, lab: lab)
        }
    }
}

// MARK: Calendar

struct LabCalendarContent: View {
    let design: WidgetMenuDesign
    @Bindable var lab: WidgetLabState
    @Environment(\.workspacePalette) private var palette
    /// Day, Week and Month keep their date line in every design; Agenda drops it unless the design needs it.
    private var showsDateRow: Bool { design == .today || design == .inline || lab.calendarMode != "agenda" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsDateRow { dateRow }
            if design == .today, lab.problem { LabStaleNote(source: "Calendar") }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(lab.days.enumerated()), id: \.offset) { index, day in
                        let events = WidgetLabFixtures.events(on: day).filter { !lab.hiddenCalendars.contains($0.calendar.id) }
                        if index > 0 { Divider() }
                        // A date line already names the first day, so the list doesn't repeat it.
                        if !(index == 0 && design != .today && showsDateRow) {
                            Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.subheadline.weight(.semibold))
                        }
                        if events.isEmpty { Text("Nothing on").font(.callout).foregroundStyle(palette[.text].opacity(0.5)) }
                        ForEach(events) { LabEventRow(event: $0) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 6)
            }.scrollEdgeFade(design != .today)
        }
        .popover(isPresented: $lab.choosingDate, arrowEdge: .top) {
            DatePicker("Calendar date", selection: $lab.date, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().padding(12)
        }
    }
    private var dateRow: some View {
        HStack(spacing: 8) {
            Button { lab.choosingDate.toggle() } label: {
                HStack(spacing: 4) { Text(lab.date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))).font(.callout.weight(.medium)); Image(systemName: "chevron.down").font(.caption2) }
            }.help("Choose calendar date")
            Spacer(minLength: 4)
            Group {
                Button { lab.step(-1) } label: { Image(systemName: "chevron.left") }.help(lab.stepTitle(-1))
                Button(lab.calendarMode == "day" || lab.calendarMode == "week" ? "Now" : "Today") { lab.date = .now }
                Button { lab.step(1) } label: { Image(systemName: "chevron.right") }.help(lab.stepTitle(1))
            }.opacity(design == .inline ? 0.6 : 1)
        }.buttonStyle(.borderless).controlSize(.small)
    }
}

struct LabEventRow: View {
    let event: LabEvent
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5).fill(event.calendar.colour).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                if !event.allDay {
                    Text(event.start.formatted(date: .omitted, time: .shortened) + " – " + event.end.formatted(date: .omitted, time: .shortened))
                        .font(.caption.monospacedDigit()).foregroundStyle(palette[.text].opacity(0.6))
                }
                Text(event.title).font(.system(size: 14, weight: .semibold))
                if !event.place.isEmpty { Text(event.place).font(.caption).foregroundStyle(palette[.text].opacity(0.6)) }
                Text(event.calendar.title).font(.caption.weight(.medium)).foregroundStyle(event.calendar.colour)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Brief

struct LabBriefContent: View {
    let design: WidgetMenuDesign
    @Bindable var lab: WidgetLabState
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        let size = lab.textSize
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    WidgetHeadline(text: WidgetLabFixtures.greeting(.now), size: (30 * size / 14).rounded(), lines: 2)
                    if design == .inline {
                        HStack(spacing: 6) {
                            Text("Updated " + lab.updated.formatted(date: .omitted, time: .shortened))
                            Text("·")
                            Button("Refresh") {}.buttonStyle(.link)
                        }.font(.caption).foregroundStyle(palette[.text].opacity(0.5))
                    }
                }
                Text(LabMarkdown.text(WidgetLabFixtures.brief)).font(.system(size: size)).lineSpacing(5 * size / 14).frame(maxWidth: .infinity, alignment: .leading)
                if lab.showsWeather {
                    Label("11° now · light rain from 16:00", systemImage: "cloud.drizzle").font(.callout).foregroundStyle(palette[.text].opacity(0.75))
                        .padding(.horizontal, 12).padding(.vertical, 8).background(palette[.text].opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }.padding(.trailing, 6)
        }.scrollEdgeFade(design != .today)
    }
}

// MARK: Reminders

struct LabRemindersContent: View {
    let design: WidgetMenuDesign
    @Bindable var lab: WidgetLabState
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        let reminders = WidgetLabFixtures.reminders(.now).filter { !lab.hiddenLists.contains($0.list.id) }
        VStack(alignment: .leading, spacing: 12) {
            if design == .today {
                if lab.problem { LabStaleNote(source: "Reminders") }
                HStack(spacing: 8) {
                    Menu { LabListToggles(lab: lab) } label: { Label("Lists", systemImage: "line.3.horizontal.decrease") }.menuStyle(.borderlessButton).controlSize(.small).fixedSize()
                    Spacer(minLength: 0)
                    Picker("Group reminders", selection: $lab.grouping) { Text("Lists").tag("lists"); Text("Due date").tag("due") }
                        .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
                }
                Divider()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if lab.grouping == "lists" {
                        ForEach(WidgetLabFixtures.lists.filter { !lab.hiddenLists.contains($0.id) }) { list in
                            let items = reminders.filter { $0.list.id == list.id }
                            DisclosureGroup(isExpanded: lab.expanded(list.id)) {
                                VStack(alignment: .leading, spacing: 12) { ForEach(items) { LabReminderRow(reminder: $0, showsList: false) } }.padding(.top, 8)
                            } label: {
                                HStack {
                                    Text(list.title + " · iCloud").font(.subheadline.weight(.semibold)).foregroundStyle(list.colour).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(items.count)").font(.caption).foregroundStyle(palette[.text].opacity(0.6))
                                }
                            }.tint(list.colour)
                            Divider()
                        }
                    } else {
                        ForEach(LabDueGroup.allCases) { group in
                            let items = reminders.filter { LabDueGroup($0) == group }
                            if !items.isEmpty {
                                Text(group.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(group == .overdue ? Color.red : palette[.text])
                                ForEach(items) { LabReminderRow(reminder: $0, showsList: true) }
                                Divider()
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 6)
            }.scrollEdgeFade(design != .today)
            // Pinned under the list, like the chat's message field, so it never scrolls out of reach.
            if design == .inline {
                Button {} label: { Label("New reminder", systemImage: "plus").font(.callout) }
                    .buttonStyle(.borderless).foregroundStyle(palette[.accent]).opacity(0.85)
            }
        }
    }
}

struct LabReminderRow: View {
    let reminder: LabReminder
    var showsList: Bool
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "circle").font(.system(size: 17, weight: .light)).foregroundStyle(palette[.text].opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title).font(.system(size: 14)).lineLimit(2)
                if reminder.repeats || showsList {
                    HStack(spacing: 5) {
                        if reminder.repeats { Image(systemName: "repeat") }
                        if showsList { Text(reminder.list.title).foregroundStyle(reminder.list.colour) }
                    }.font(.caption2).foregroundStyle(palette[.text].opacity(0.55))
                }
            }
            Spacer(minLength: 6)
            if let due = reminder.due { DueBadge(due: due, hasTime: reminder.hasTime) }
        }
    }
}

struct LabListToggles: View {
    @Bindable var lab: WidgetLabState
    var body: some View {
        Button("Show all") { lab.hiddenLists = [] }
        Divider()
        ForEach(WidgetLabFixtures.lists) { list in
            Toggle(list.title, isOn: Binding(get: { !lab.hiddenLists.contains(list.id) }, set: { if $0 { lab.hiddenLists.remove(list.id) } else { lab.hiddenLists.insert(list.id) } }))
        }
    }
}

struct LabCalendarToggles: View {
    @Bindable var lab: WidgetLabState
    var body: some View {
        Button("Show all") { lab.hiddenCalendars = [] }
        Divider()
        ForEach(WidgetLabFixtures.calendars) { calendar in
            Toggle(calendar.title, isOn: Binding(get: { !lab.hiddenCalendars.contains(calendar.id) }, set: { if $0 { lab.hiddenCalendars.remove(calendar.id) } else { lab.hiddenCalendars.insert(calendar.id) } }))
        }
    }
}

/// Today's in-widget warning line when a source couldn't refresh.
struct LabStaleNote: View {
    var source: String
    var body: some View { Text("Stale · \(source) couldn’t refresh").font(.caption).foregroundStyle(.orange).lineLimit(2) }
}

// MARK: Chat

struct LabChatContent: View {
    let design: WidgetMenuDesign
    @Bindable var lab: WidgetLabState
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(design == .inline ? "Today · heartbeat " + lab.updated.formatted(date: .omitted, time: .shortened) : "Today")
                        .font(.caption.weight(.medium)).foregroundStyle(palette[.text].opacity(0.55)).frame(maxWidth: .infinity)
                    if lab.chat.isEmpty {
                        Text("Ask about your day, your reminders or your inbox.").font(.callout).foregroundStyle(palette[.text].opacity(0.5))
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    ForEach(lab.chat) { message in
                        bubble(message).contextMenu {
                            // A message keeps its own actions; the widget's options follow them.
                            Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) }
                            Button("Sources & searches…") {}.disabled(message.mine)
                            if design != .today { Divider(); LabWidgetMenu(widget: .chat, lab: lab) }
                        }
                    }
                }.padding(.trailing, 6)
            }.scrollEdgeFade(design != .today)
            composer
        }
    }
    @ViewBuilder private func bubble(_ message: LabMessage) -> some View {
        if message.mine {
            HStack {
                Spacer(minLength: 48)
                Text(message.text).font(.system(size: 14)).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(palette[.userBubble], in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        } else {
            Text(LabMarkdown.text(message.text)).font(.system(size: 14)).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var composer: some View {
        HStack(spacing: 10) {
            if design == .inline {
                Button { lab.newChat() } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.borderless).help("New chat")
            }
            Image(systemName: "mic").foregroundStyle(palette[.text].opacity(0.6))
            TextField("Message 3PO", text: $lab.draft).textFieldStyle(.plain).font(.system(size: 14)).onSubmit(lab.send)
            Button(action: lab.send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 24)) }
                .buttonStyle(.borderless).foregroundStyle(palette[.accent]).disabled(lab.draft.isEmpty)
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
        .background(palette[.input], in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette[.border]))
    }
}

enum LabMarkdown {
    static func text(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
    }
}

// MARK: Fictional data

struct LabCalendar: Identifiable { let id: String; let title: String; let colour: Color }
struct LabEvent: Identifiable { let id: String; let calendar: LabCalendar; let title: String; let start: Date; let end: Date; let allDay: Bool; let place: String }
struct LabList: Identifiable { let id: String; let title: String; let colour: Color }
struct LabReminder: Identifiable { let id: String; let list: LabList; let title: String; let due: Date?; let hasTime: Bool; let repeats: Bool }
struct LabMessage: Identifiable { let id = UUID(); let mine: Bool; let text: String }

enum LabDueGroup: String, CaseIterable, Identifiable {
    case overdue = "Overdue", today = "Today", upcoming = "Upcoming", undated = "Undated"
    var id: String { rawValue }
    init(_ reminder: LabReminder, now: Date = .now) {
        guard let due = reminder.due else { self = .undated; return }
        switch DueBadge.urgency(due, hasTime: reminder.hasTime, now: now) {
        case .overdue: self = .overdue
        case .today: self = .today
        case .tomorrow, .later: self = .upcoming
        }
    }
}

/// Made-up calendars, reminders, brief and chat; dates are relative to today.
enum WidgetLabFixtures {
    static let calendars = [LabCalendar(id: "personal", title: "Personal", colour: .green), LabCalendar(id: "lectures", title: "Lectures", colour: .purple), LabCalendar(id: "sport", title: "Sport", colour: .orange)]
    static let lists = [LabList(id: "todo", title: "To do", colour: .green), LabList(id: "uni", title: "Uni", colour: .blue), LabList(id: "shopping", title: "Shopping", colour: .orange)]

    static func events(on day: Date) -> [LabEvent] {
        let calendar = Calendar.current, start = calendar.startOfDay(for: day)
        let weekday = calendar.component(.weekday, from: day), offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: start).day ?? 0
        func source(_ id: String) -> LabCalendar { calendars.first { $0.id == id }! }
        func at(_ hour: Int, _ minute: Int, _ minutes: Int, _ id: String, _ title: String, _ place: String = "") -> LabEvent {
            let begins = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start)!
            return LabEvent(id: "\(title)-\(begins.timeIntervalSince1970)", calendar: source(id), title: title, start: begins, end: begins.addingTimeInterval(Double(minutes) * 60), allDay: false, place: place)
        }
        func allDay(_ id: String, _ title: String) -> LabEvent { LabEvent(id: "\(title)-\(start.timeIntervalSince1970)", calendar: source(id), title: title, start: start, end: start, allDay: true, place: "") }
        var events: [LabEvent] = []
        if offset == 0 { events.append(allDay("personal", "Bins out tonight")) }
        if offset == 2 { events.append(allDay("personal", "Sam’s birthday")) }
        if weekday == 1 || weekday == 7 {
            events += [at(10, 0, 45, "sport", "Morning run", "Park loop"), at(19, 0, 120, "personal", "Dinner with flatmates", "Kitchen")]
        } else {
            events += [at(9, 5, 50, "lectures", "Signals and Systems", "Lecture theatre 1"), at(11, 0, 50, "lectures", "Fluid Mechanics", "Lecture theatre 2")]
            if weekday == 2 || weekday == 4 { events.append(at(13, 0, 60, "personal", "Lunch with Alex", "Café by the library")) }
            if weekday == 3 || weekday == 5 { events.append(at(16, 30, 30, "personal", "Supervision with Dr Reed", "Room 214")) }
            if weekday == 4 { events.append(at(18, 0, 60, "sport", "Five-a-side", "Sports centre")) }
        }
        return events
    }

    static func reminders(_ now: Date) -> [LabReminder] {
        let calendar = Calendar.current, today = calendar.startOfDay(for: now)
        func list(_ id: String) -> LabList { lists.first { $0.id == id }! }
        func item(_ listID: String, _ title: String, _ days: Int?, hour: Int? = nil, repeats: Bool = false) -> LabReminder {
            var due = days.flatMap { calendar.date(byAdding: .day, value: $0, to: today) }
            if let hour, let day = due { due = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) }
            return LabReminder(id: listID + title, list: list(listID), title: title, due: due, hasTime: hour != nil, repeats: repeats)
        }
        return [
            item("todo", "Book a dentist check-up", -1), item("todo", "Renew bike insurance", 0), item("todo", "Back up laptop", 0, repeats: true),
            item("todo", "Post Sam’s birthday card", 1), item("todo", "Apply for the travel grant", 8), item("todo", "Plan summer trip", nil),
            item("uni", "Problem sheet 4", 1, hour: 17), item("uni", "Return library books", 4), item("uni", "Email tutor about the essay", 6),
            item("shopping", "Oat milk", 0), item("shopping", "Printer paper", nil),
        ]
    }

    static func greeting(_ now: Date) -> String {
        switch Calendar.current.component(.hour, from: now) { case 5..<12: "Good morning."; case 12..<18: "Good afternoon."; default: "Good evening." }
    }
    static let brief = """
    **Problem sheet 4 comes first.** It’s due **tomorrow at 17:00**, and the last question needs the worked example from this week’s Signals lecture. The library books are due back in four days.

    **Tomorrow:** Signals and Systems at 09:05, then Fluid Mechanics at 11:00. Rain is likely from 16:00, so take a coat if you head out after lectures.

    **Later this week:** Sam’s birthday is in two days and the card still needs posting. The travel grant closes next week.
    """
    static let chat = [
        LabMessage(mine: true, text: "What’s left for today?"),
        LabMessage(mine: false, text: "Two things: renew your bike insurance and back up your laptop. Problem sheet 4 is due tomorrow at 17:00, so tonight is a good time to finish the last question."),
        LabMessage(mine: true, text: "Add oat milk to my shopping"),
        LabMessage(mine: false, text: "Done. I’ve added **Oat milk** to Shopping for today. It’s date-only, so it has no set time."),
    ]
}
#endif
