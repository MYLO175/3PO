import SwiftUI
import SwiftData
import AppKit
import EventKit

@MainActor @Observable final class DashboardModel {
    var calendarData = CalendarSnapshot(sources: [], events: [])
    var reminderData = ReminderSnapshot(sources: [], reminders: [])
    var mailData = MailSnapshot(messages: [], accounts: [], errors: [])
    var calendarHealth = SourceHealth()
    var reminderHealth = SourceHealth()
    var mailHealth = SourceHealth()
    var selectedDate = Calendar.current.startOfDay(for: .now)
    var excludedCalendars: Set<String> = [] { didSet { saveFilters() } }
    var excludedLists: Set<String> = [] { didSet { saveFilters() } }
    var excludedAccounts: Set<String> = [] { didSet { saveFilters() } }
    var selectedMessage: MailMessage?
    var preview = ""
    var previewLoading = false
    var previewError: String?
    var writeError: String?
    var writing = false
    var undoToken: String?
    var undoTitle = ""
    var validationReport: String?
    var storageError: String?
    let eventKit = EventKitService()
    let mail = MailService()
    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private var changes: Task<Void, Never>?
    private var poll: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var pendingCalendarRefresh = false
    private var pendingReminderRefresh = false
    private var started = false
    private var mailSuspended = UserDefaults.standard.bool(forKey: "mailSuspended")
    private var sample: Bool { ProcessInfo.processInfo.arguments.contains("--sample") }

    init() {
        excludedCalendars = Set(UserDefaults.standard.stringArray(forKey: "excludedCalendars") ?? [])
        excludedLists = Set(UserDefaults.standard.stringArray(forKey: "excludedLists") ?? [])
        excludedAccounts = Set(UserDefaults.standard.stringArray(forKey: "excludedAccounts") ?? [])
        do {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mission Control", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let configuration = ModelConfiguration(url: directory.appendingPathComponent("Dashboard.store"), cloudKitDatabase: .none)
            container = try ModelContainer(for: CachedDashboard.self, configurations: configuration)
            restore()
        } catch { storageError = "Local cache unavailable: " + error.localizedDescription }
    }
    func start() {
        guard !started else { return }; started = true
        if sample { loadSample(); return }
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.changes?.cancel()
                self.changes = Task {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    await self.refreshCalendar(); await self.refreshReminders()
                }
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh(retryMail: false) } })
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                await self?.refreshMail()
            }
        }
        refresh(retryMail: false)
        if ProcessInfo.processInfo.arguments.contains("--validate-live") {
            Task {
                do { validationReport = try await eventKit.validateDisposableReminders() }
                catch { validationReport = "Live reminder validation failed: " + error.localizedDescription }
                persist("validationReport", validationReport)
                await refreshReminders()
            }
        }
    }
    func refresh(retryMail: Bool = true) {
        if retryMail { mailSuspended = false; UserDefaults.standard.set(false, forKey: "mailSuspended") }
        guard !sample else { loadSample(); return }
        Task { await refreshCalendar() }
        Task { await refreshReminders() }
        Task { await refreshMail() }
    }
    func navigate(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        Task { await refreshCalendar() }
    }
    func refreshCalendar() async {
        guard !sample else { return }
        if calendarHealth.loading { pendingCalendarRefresh = true; return }
        calendarHealth.loading = true
        let start = selectedDate
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        do {
            let snapshot = try await eventKit.calendar(from: start, to: end)
            calendarData = snapshot
            calendarHealth = .init(lastSuccess: .now)
            persist("calendar", snapshot); persist("calendarHealth", calendarHealth)
        } catch { calendarHealth.error = error.localizedDescription; calendarHealth.loading = false }
        if pendingCalendarRefresh { pendingCalendarRefresh = false; await refreshCalendar() }
    }
    func refreshReminders() async {
        guard !sample else { return }
        if reminderHealth.loading { pendingReminderRefresh = true; return }
        reminderHealth.loading = true
        do {
            let snapshot = try await eventKit.reminders()
            reminderData = snapshot
            reminderHealth = .init(lastSuccess: .now)
            persist("reminders", snapshot); persist("reminderHealth", reminderHealth)
        } catch { reminderHealth.error = error.localizedDescription; reminderHealth.loading = false }
        if pendingReminderRefresh { pendingReminderRefresh = false; await refreshReminders() }
    }
    func refreshMail() async {
        if ProcessInfo.processInfo.arguments.contains("--skip-mail") { mailHealth.error = "Mail paused for validation"; return }
        guard !sample, !mailHealth.loading else { return }
        if mailSuspended { mailHealth.error = "Mail paused after timeout. Click Refresh to retry when Mail is responsive."; return }
        mailHealth.loading = true
        do {
            let snapshot = try await mail.headers()
            if snapshot.errors.isEmpty {
                mailData = snapshot
                mailHealth = .init(lastSuccess: .now)
                persist("mail", snapshot); persist("mailHealth", mailHealth)
            } else {
                // Reconcile successful accounts; retain cached records only for failed accounts.
                let successful = Set(snapshot.accounts.map(\.id))
                let failed = Set(mailData.accounts.filter { account in snapshot.errors.contains { $0.hasPrefix("Account " + account.id + ":") } }.map(\.id))
                let retainAll = snapshot.errors.contains { $0.hasPrefix("Mail:") }
                mailData = MailSnapshot(messages: (snapshot.messages + mailData.messages.filter { (retainAll || failed.contains($0.accountID)) && !successful.contains($0.accountID) }).sorted { $0.received > $1.received }, accounts: snapshot.accounts + mailData.accounts.filter { (retainAll || failed.contains($0.id)) && !successful.contains($0.id) }, errors: snapshot.errors)
                mailHealth.error = snapshot.errors.joined(separator: "; ")
                mailHealth.loading = false
                persist("mail", mailData)
            }
        } catch {
            mailHealth.error = error.localizedDescription; mailHealth.loading = false
            if case MailServiceError.timedOut = error {
                mailSuspended = true
                UserDefaults.standard.set(true, forKey: "mailSuspended")
                mailHealth.error = "Mail timed out. Automatic reads paused; click Refresh to retry when Mail is responsive."
            }
        }
    }
    func complete(_ reminder: TaskItem) {
        guard !sample, !writing else { return }
        writing = true; writeError = nil
        Task {
            do {
                undoToken = try await eventKit.complete(id: reminder.id)
                undoTitle = reminder.title
                await refreshReminders()
            } catch { writeError = error.localizedDescription; await refreshReminders() }
            writing = false
        }
    }
    func undo() {
        guard let token = undoToken, !writing else { return }
        writing = true; writeError = nil
        Task {
            do { try await eventKit.undo(token: token); undoToken = nil; await refreshReminders() }
            catch { writeError = error.localizedDescription; await refreshReminders() }
            writing = false
        }
    }
    func select(_ message: MailMessage) {
        previewTask?.cancel()
        selectedMessage = message; preview = ""; previewError = nil; previewLoading = true
        previewTask = Task {
            do {
                let body = try await mail.body(accountID: message.accountID, messageID: message.messageID)
                guard !Task.isCancelled, selectedMessage?.id == message.id else { return }
                preview = body.isEmpty ? "This message has no plain-text body." : body
            } catch {
                guard !Task.isCancelled, selectedMessage?.id == message.id else { return }
                previewError = error.localizedDescription
            }
            previewLoading = false
        }
    }
    func openMessage(_ message: MailMessage) {
        guard !message.internetMessageID.isEmpty else { writeError = "This message has no Internet Message-ID. Open it in Mail using its subject."; return }
        let identifier = message.internetMessageID.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@._-"))
        if let encoded = identifier.addingPercentEncoding(withAllowedCharacters: allowed), let url = URL(string: "message://%3C\(encoded)%3E") { NSWorkspace.shared.open(url) }
    }
    var visibleEvents: [AgendaEvent] { calendarData.events.filter { !excludedCalendars.contains($0.calendarID) } }
    var visibleReminders: [TaskItem] { reminderData.reminders.filter { !excludedLists.contains($0.listID) } }
    var visibleMessages: [MailMessage] { mailData.messages.filter { !excludedAccounts.contains($0.accountID) }.sorted { $0.received > $1.received } }
    private func saveFilters() {
        UserDefaults.standard.set(Array(excludedCalendars), forKey: "excludedCalendars")
        UserDefaults.standard.set(Array(excludedLists), forKey: "excludedLists")
        UserDefaults.standard.set(Array(excludedAccounts), forKey: "excludedAccounts")
    }
    private func persist<T: Encodable>(_ key: String, _ value: T) {
        guard !sample, let container else { return }
        do {
            let data = try JSONEncoder().encode(value)
            let context = container.mainContext
            let records = try context.fetch(FetchDescriptor<CachedDashboard>())
            if let record = records.first(where: { $0.key == key }) { record.data = data; record.updated = .now }
            else { context.insert(CachedDashboard(key: key, data: data)) }
            try context.save()
        } catch { storageError = "Cache could not be saved: " + error.localizedDescription }
    }
    private func restore() {
        guard !sample, let container else { return }
        do {
            let records = try container.mainContext.fetch(FetchDescriptor<CachedDashboard>())
            func read<T: Decodable>(_ key: String, _ type: T.Type) -> T? { records.first { $0.key == key }.flatMap { try? JSONDecoder().decode(type, from: $0.data) } }
            calendarData = read("calendar", CalendarSnapshot.self) ?? calendarData
            reminderData = read("reminders", ReminderSnapshot.self) ?? reminderData
            mailData = read("mail", MailSnapshot.self) ?? mailData
            calendarHealth = read("calendarHealth", SourceHealth.self) ?? calendarHealth
            reminderHealth = read("reminderHealth", SourceHealth.self) ?? reminderHealth
            mailHealth = read("mailHealth", SourceHealth.self) ?? mailHealth
            for key in ["calendar", "reminders", "mail"] {
                switch key {
                case "calendar": if calendarHealth.lastSuccess != nil { calendarHealth.error = "Cached data · refresh pending" }
                case "reminders": if reminderHealth.lastSuccess != nil { reminderHealth.error = "Cached data · refresh pending" }
                default: if mailHealth.lastSuccess != nil { mailHealth.error = "Cached data · refresh pending" }
                }
            }
        } catch { storageError = "Cache could not be read: " + error.localizedDescription }
    }
    private func loadSample() {
        calendarData = SampleCalendarService().snapshot()
        reminderData = SampleReminderService().snapshot()
        mailData = SampleMailService().snapshot()
    }
}
