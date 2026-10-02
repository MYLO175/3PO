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
    var mailIndex = MailIndexState()
    var mailCoverage: String { sample ? "Sample data" : mailIndex.coverage(accounts: mailData.accounts) }
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
    let chatGPT = ChatGPTConnection()
    @ObservationIgnored lazy var assistant = AssistantService(connection: chatGPT, container: container)
    let eventKit = EventKitService()
    let mail = MailService()
    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private var changes: Task<Void, Never>?
    private var poll: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var mailContinuation: Task<Void, Never>?
    private var pendingCalendarRefresh = false
    private var pendingReminderRefresh = false
    private var started = false
    private var mailSuspended = UserDefaults.standard.bool(forKey: "mailSuspended")
    private var sample: Bool { ProcessInfo.processInfo.arguments.contains("--sample") }

    init() {
        // Read all saved filters before observable property setters persist any
        // values; otherwise the first setter erases later filters during init.
        let savedCalendars = Set(UserDefaults.standard.stringArray(forKey: "excludedCalendars") ?? [])
        let savedLists = Set(UserDefaults.standard.stringArray(forKey: "excludedLists") ?? [])
        let savedAccounts = Set(UserDefaults.standard.stringArray(forKey: "excludedAccounts") ?? [])
        excludedCalendars = savedCalendars
        excludedLists = savedLists
        excludedAccounts = savedAccounts
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
        if retryMail { mailContinuation?.cancel(); mailSuspended = false; UserDefaults.standard.set(false, forKey: "mailSuspended") }
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
    func validateCalendarIntegration() {
        Task {
            do { validationReport = try await eventKit.validateDisposableCalendarEvents() }
            catch { validationReport = "Calendar validation: " + error.localizedDescription }
            persist("validationReport", validationReport)
            await refreshCalendar()
        }
    }
    private func persistMailCheckpoint() {
        persist("mailCheckpoint", MailCheckpoint(snapshot: mailData, index: mailIndex))
    }
    func refreshMail() async {
        if ProcessInfo.processInfo.arguments.contains("--skip-mail") { mailHealth.error = "Mail paused for validation"; return }
        guard !sample, !mailHealth.loading else { return }
        if mailSuspended { mailHealth.error = "Mail paused after timeout. Click Refresh to resume when Mail is responsive."; return }
        mailHealth.loading = true
        do {
            let discovery = try await mail.discoverAccounts()
            if !discovery.errors.isEmpty { throw MailServiceError.mail(discovery.errors.joined(separator: "; ")) }
            let accounts = discovery.accounts
            let enabled = Set(accounts.map(\.id))
            mailData = MailSnapshot(messages: mailData.messages.filter { enabled.contains($0.accountID) && $0.received >= Date.now.addingTimeInterval(-30 * 86400) }, accounts: accounts, errors: [])
            mailIndex.prepare(accounts: accounts)
            persistMailCheckpoint()
            // Round-robin accounts, newest unfinished day first. Six small pages
            // form a checkpoint; each page is saved and displayed immediately.
            for job in 0..<6 where !accounts.isEmpty {
                let account = accounts[job % accounts.count]
                guard let window = mailIndex.windows.filter({ $0.accountID == account.id && !$0.complete }).sorted(by: { $0.start > $1.start }).first else { continue }
                do {
                    let batch = try await mail.batch(accountID: account.id, window: window)
                    mailData = mailIndex.apply(batch, to: window.id, snapshot: mailData)
                    mailHealth.lastSuccess = .now; mailHealth.error = nil
                    persistMailCheckpoint()
                    persist("mailHealth", SourceHealth(lastSuccess: .now))
                } catch {
                    // A changed/moved message invalidates the saved ID list for
                    // this day. Rebuild it on a user retry; keep cached rows.
                    if case MailServiceError.mail(let detail) = error,
                       detail.contains("changed or moved") || detail.contains("-1728"),
                       let index = mailIndex.windows.firstIndex(where: { $0.id == window.id }) {
                        mailIndex.windows[index].offset = 0
                        mailIndex.windows[index].messageIDs = nil
                        mailIndex.windows[index].seenIDs = []
                    }
                    // Timeout/transport errors preserve the last successful page
                    // cursor and ID list, so Refresh retries only the failed page.
                    persistMailCheckpoint()
                    mailHealth.error = account.title + " Inbox: " + error.localizedDescription
                    if case MailServiceError.timedOut = error {
                        mailSuspended = true; UserDefaults.standard.set(true, forKey: "mailSuspended")
                        mailHealth.error = (mailHealth.error ?? "Mail timed out") + " Automatic reads paused; Refresh resumes saved progress."
                    }
                    mailHealth.loading = false
                    return
                }
            }
            mailHealth.loading = false
            if accounts.isEmpty { mailHealth.lastSuccess = .now }
            // A relaunch inside the refresh interval can have no due windows.
            // Successful discovery confirms availability; retain the real last
            // header timestamp but clear the temporary launch-cache banner.
            if !mailIndex.pending {
                mailHealth.error = nil
                persist("mailHealth", SourceHealth(lastSuccess: mailHealth.lastSuccess))
            }
            if mailIndex.pending {
                mailContinuation = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    await self?.refreshMail()
                }
            }
        } catch {
            mailHealth.error = error.localizedDescription; mailHealth.loading = false
            if case MailServiceError.timedOut = error {
                mailSuspended = true; UserDefaults.standard.set(true, forKey: "mailSuspended")
                mailHealth.error = "Mail timed out. Automatic reads paused; Refresh resumes saved progress."
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
                let body = try await mail.body(accountID: message.accountID, messageID: message.messageID, expectedInternetMessageID: message.internetMessageID)
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
            mailIndex = read("mailIndex", MailIndexState.self) ?? mailIndex
            if let checkpoint = read("mailCheckpoint", MailCheckpoint.self) {
                mailData = checkpoint.snapshot; mailIndex = checkpoint.index
            }
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
