import SwiftUI
import ServiceManagement
import AppKit

struct DashboardView: View {
    @Bindable var model: DashboardModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mission Control").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text(Date.now.formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)
                }
                Spacer()
                if ProcessInfo.processInfo.arguments.contains("--sample") { Text("Sample data").foregroundStyle(.secondary) }
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Settings")
            }.padding(24)
            Divider()
            if let error = model.storageError { errorBanner(error) }
            if let error = model.writeError { errorBanner(error) }
            if model.undoToken != nil {
                HStack {
                    Label("Completed: \(model.undoTitle)", systemImage: "checkmark.circle")
                    Spacer()
                    Button("Undo") { model.undo() }.disabled(model.writing)
                    Button { model.undoToken = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.font(.callout).padding(12).background(.green.opacity(0.08))
            }
            GeometryReader { geometry in
                if geometry.size.width >= 1040 {
                    HStack(alignment: .top, spacing: 14) {
                        calendarPanel.frame(width: max(320, geometry.size.width * 0.31))
                        remindersPanel.frame(width: max(260, geometry.size.width * 0.25))
                        inboxPanel.frame(maxWidth: .infinity)
                    }.padding(16)
                } else {
                    VSplitView {
                        HStack(alignment: .top, spacing: 14) { calendarPanel; remindersPanel }.padding([.top, .horizontal], 14).frame(minHeight: 260)
                        inboxPanel.padding(14).frame(minHeight: 250)
                    }
                }
            }
            HStack {
                Text("Local dashboard").font(.caption)
                Spacer()
                Text("Apple apps remain the source of truth · No AI processing").font(.caption)
            }.foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 10)
        }.frame(minWidth: 780, minHeight: 580).background(Color(nsColor: .windowBackgroundColor)).task { model.start() }
        .sheet(item: $model.selectedMessage) { message in previewSheet(message) }
    }
    func errorBanner(_ text: String) -> some View {
        HStack { Image(systemName: "exclamationmark.triangle"); Text(text).textSelection(.enabled); Spacer() }.font(.callout).foregroundStyle(.orange).padding(10)
    }
    func panelHeader(_ title: String, icon: String, health: SourceHealth) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Label(title, systemImage: icon).font(.title3.weight(.semibold)); Spacer(); if health.loading { ProgressView().controlSize(.small) } }
            Text(health.detail).font(.caption).foregroundStyle(health.error == nil ? Color.secondary : Color.orange).lineLimit(3).textSelection(.enabled)
        }
    }
    func sourceMenu(_ title: String, sources: [SourceOption], exclusions: Binding<Set<String>>) -> some View {
        Menu {
            Button("Enable all") { exclusions.wrappedValue = [] }
            Divider()
            ForEach(sources) { source in
                Toggle(source.label, isOn: Binding(get: { !exclusions.wrappedValue.contains(source.id) }, set: { enabled in
                    if enabled { exclusions.wrappedValue.remove(source.id) } else { exclusions.wrappedValue.insert(source.id) }
                }))
            }
        } label: { Label(title, systemImage: "line.3.horizontal.decrease") }.controlSize(.small).disabled(sources.isEmpty)
    }
    var calendarPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader("Calendar", icon: "calendar", health: model.calendarHealth)
            sourceMenu("Calendars", sources: model.calendarData.sources, exclusions: $model.excludedCalendars)
            HStack {
                Button { moveDate(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                DatePicker("Date", selection: Binding(get: { model.selectedDate }, set: { model.navigate($0) }), displayedComponents: .date).labelsHidden()
                Button { moveDate(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                Spacer(minLength: 0)
                Button("Today") { model.navigate(.now) }.controlSize(.small)
            }
            HStack(spacing: 4) {
                ForEach(0..<7) { index in
                    let date = Calendar.current.date(byAdding: .day, value: index, to: model.selectedDate)!
                    let count = model.visibleEvents.filter { DateRules.overlaps($0, day: date) }.count
                    VStack(spacing: 4) {
                        Text(date.formatted(.dateTime.weekday(.narrow))).font(.caption).foregroundStyle(.secondary)
                        Text(date.formatted(.dateTime.day())).font(.callout.weight(.medium))
                        Text("\(count)").font(.caption2).foregroundStyle(count == 0 ? Color.secondary : Color.accentColor)
                    }.frame(maxWidth: .infinity).padding(.vertical, 7).background(index == 0 ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)).onTapGesture { model.navigate(date) }
                }
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<2) { offset in
                        let day = Calendar.current.date(byAdding: .day, value: offset, to: model.selectedDate)!
                        let events = model.visibleEvents.filter { DateRules.overlaps($0, day: day) }
                        Text(day.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.semibold)).padding(.top, 4)
                        if events.isEmpty { Text("No events").font(.callout).foregroundStyle(.secondary) }
                        let allDay = events.filter(\.allDay)
                        let timed = events.filter { !$0.allDay }
                        if !allDay.isEmpty {
                            Text("ALL DAY").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(allDay) { eventRow($0, day: day) }
                        }
                        ForEach(timed) { eventRow($0, day: day) }
                        if offset == 0 { Divider().padding(.vertical, 4) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.panelStyle()
    }
    func moveDate(_ delta: Int) { model.navigate(Calendar.current.date(byAdding: .day, value: delta, to: model.selectedDate)!) }
    func eventRow(_ event: AgendaEvent, day: Date) -> some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.7)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                if !event.allDay {
                    Text(eventTime(event, day: day)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(event.title).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                if !event.location.isEmpty { Label(event.location, systemImage: "location").font(.caption).foregroundStyle(.secondary) }
                Text(event.sourceLabel).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 3)
    }
    func eventTime(_ event: AgendaEvent, day: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.isDate(event.start, inSameDayAs: day) ? event.start.formatted(date: .omitted, time: .shortened) : event.start.formatted(date: .abbreviated, time: .shortened)
        let end = calendar.isDate(event.end, inSameDayAs: day) ? event.end.formatted(date: .omitted, time: .shortened) : event.end.formatted(date: .abbreviated, time: .shortened)
        return "\(start) – \(end)"
    }
    var remindersPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader("Reminders", icon: "checklist", health: model.reminderHealth)
            sourceMenu("Lists", sources: model.reminderData.sources, exclusions: $model.excludedLists)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(["Overdue", "Today", "Upcoming", "Undated"], id: \.self) { group in
                        let items = model.visibleReminders.filter { DateRules.group($0) == group }
                        HStack { Text(group).font(.subheadline.weight(.semibold)); Spacer(); Text("\(items.count)").foregroundStyle(.secondary).font(.caption) }
                        if items.isEmpty { Text("Nothing here").font(.caption).foregroundStyle(.tertiary) }
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Button { model.complete(item) } label: { Image(systemName: item.writable ? "circle" : "lock.circle").font(.title3) }.buttonStyle(.plain).disabled(!item.writable || model.writing).help(item.writable ? "Complete reminder" : "Read-only list")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.callout).fixedSize(horizontal: false, vertical: true)
                                    if let due = item.due { Text(due.formatted(date: .abbreviated, time: item.hasTime ? .shortened : .omitted)).font(.caption).foregroundStyle(group == "Overdue" ? Color.orange : Color.secondary) }
                                    HStack(spacing: 4) { Text(item.sourceLabel); if item.recurring { Image(systemName: "repeat") } }.font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(.vertical, 3)
                        }
                        Divider()
                    }
                }
            }
        }.panelStyle()
    }
    var inboxPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader("Inbox", icon: "tray", health: model.mailHealth)
            HStack {
                Menu {
                    Button("Enable all") { model.excludedAccounts = [] }
                    Divider()
                    ForEach(model.mailData.accounts) { account in
                        Toggle(account.title, isOn: Binding(get: { !model.excludedAccounts.contains(account.id) }, set: { enabled in
                            if enabled { model.excludedAccounts.remove(account.id) } else { model.excludedAccounts.insert(account.id) }
                        }))
                    }
                } label: { Label("Accounts", systemImage: "line.3.horizontal.decrease") }.controlSize(.small)
                Spacer()
                Text("Last 30 days · \(model.visibleMessages.count)").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            if model.visibleMessages.isEmpty {
                ContentUnavailableView("No inbox messages", systemImage: "tray", description: Text(model.mailHealth.error == nil ? "Recent messages appear here after Mail connects." : "Check the Mail connection status above."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.visibleMessages) { message in
                            Button { model.select(message) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        if message.unread { Circle().fill(Color.accentColor).frame(width: 6, height: 6) }
                                        Text(message.sender).font(.callout.weight(message.unread ? .semibold : .regular)).lineLimit(1)
                                        Spacer(minLength: 4)
                                        if message.flagged { Image(systemName: "flag.fill").foregroundStyle(.orange) }
                                        if message.replied { Image(systemName: "arrowshape.turn.up.left").foregroundStyle(.secondary) }
                                    }
                                    Text(message.subject.isEmpty ? "(No subject)" : message.subject).font(.callout).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    HStack { Text(message.account).lineLimit(1); Spacer(); Text(message.received.formatted(date: .abbreviated, time: .shortened)) }.font(.caption2).foregroundStyle(.secondary)
                                }.padding(.vertical, 11).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }.panelStyle()
    }
    func previewSheet(_ message: MailMessage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(message.subject.isEmpty ? "(No subject)" : message.subject).font(.title2.weight(.semibold)); Spacer(); Button("Done") { model.selectedMessage = nil }.keyboardShortcut(.cancelAction) }
            Text(message.sender).textSelection(.enabled)
            Text("\(message.account) · \(message.received.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            Divider()
            if model.previewLoading { ProgressView("Loading plain-text preview…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error = model.previewError { ContentUnavailableView("Preview unavailable", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else { ScrollView { Text(model.preview).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
            Divider()
            HStack { Text("Reading previews does not mark mail as read.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Open in Mail") { model.openMessage(message) } }
        }.padding(24).frame(width: 700, height: 580)
    }
}
private extension View {
    func panelStyle() -> some View {
        self.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.06)))
    }
}
struct SettingsView: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?
    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $enabled).onChange(of: enabled) { _, value in
                    do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; error = nil }
                    catch { self.error = error.localizedDescription }
                    enabled = SMAppService.mainApp.status == .enabled
                    if SMAppService.mainApp.status == .requiresApproval { error = "Allow Mission Control in System Settings → General → Login Items." }
                }
                Text("Closing the dashboard keeps the menu bar app running. Choose Quit to stop it.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Connections") {
                Text("Calendar and Reminders use macOS permissions. Mail uses Automation permission. All data stays on this Mac; Stage 1 makes no AI requests.").font(.callout)
                Button("Open Privacy & Security") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!) }
            }
            if let error { Text(error).foregroundStyle(.orange) }
        }.formStyle(.grouped).padding().frame(width: 470, height: 340)
    }
}
