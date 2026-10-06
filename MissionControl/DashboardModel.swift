import SwiftUI
import SwiftData
import AppKit
import EventKit

@MainActor @Observable final class DashboardModel {
    let whatsapp = WhatsAppService()
    var calendarData = CalendarSnapshot(sources: [], events: [])
    var paOrientation: PAOrientation?
    var paOrientationHealth = SourceHealth()
    private var lastOrientationCheck = Date.distantPast
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
    var assistantFocusRequest: AssistantFocusRequest?
    func openAssistantComposer() {
        assistant.openPA()
        workspace.showAssistant()
        guard let widget = workspace.selected.widgets.first(where:{ $0.kind == .conversation }) else { return }
        assistantFocusRequest = AssistantFocusRequest(widgetID:widget.id)
    }
    var selectedMessage: MailMessage?
    var editTarget: NativeEditTarget?
    var nativeWriteNotice: String?
    var preview = ""
    var previewLoading = false
    var previewError: String?
    var writeError: String?
    var writing = false
    var undoToken: String? { didSet { completionUndoDate = undoToken == nil ? nil : .now } }
    private var completionUndoDate: Date?
    private var editUndo: NativeEditUndo?
    var feedbackDate: Date?
    var undoTitle = ""
    var validationReport: String?
    #if DEBUG
    func validateProactivePrompt() {
        validationReport = "Checking the proactive prompt with fictional sources…"
        Task { [self] in
            let result: String
            do { result = try await proactive.validate(self) } catch { result = error.localizedDescription }
            validationReport = result
            UserDefaults.standard.set(["completed":Date.now.ISO8601Format(),"result":result],forKey:"debugProactiveValidation")
        }
    }
    func validateMailFolders() {
        validationReport = "Checking bounded Mail folder reads…"
        Task { [self] in
            let result: String
            do { result = try await mail.validateSearchFolders() } catch { result = error.localizedDescription }
            validationReport = result
            UserDefaults.standard.set(["completed":Date.now.ISO8601Format(),"result":result],forKey:"debugMailFolderValidation")
        }
    }
    func validateMemoryLearning() {
        validationReport = "Checking the memory prompt with fictional source-free messages…"
        Task { [self] in
            do { validationReport = try await memoryLearning.validate(self) }
            catch { validationReport = error.localizedDescription }
        }
    }
    func validateLifeNotebook() {
        validationReport="Checking life organisation and recall with fictional facts…"
        Task { [self] in
            let result:[String:Any]
            do { result=try await LifeNotebookEvaluation.run(self);validationReport="Life notebook evaluation: \(result["passed"] ?? 0)/\(result["total"] ?? 0) checks passed." }
            catch { result=["completed":Date.now.ISO8601Format(),"error":String(error.localizedDescription.prefix(500))];validationReport=error.localizedDescription }
            if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-life-notebook-evaluation.json"),options:.atomic) }
            if ProcessInfo.processInfo.arguments.contains("--validate-life-notebook") { NSApp.terminate(nil) }
        }
    }
    #endif
    var storageError: String?
    @ObservationIgnored lazy var weather = WeatherService(container:container)
    let chatGPT = ChatGPTConnection()
    @ObservationIgnored lazy var workspace = WorkspaceStore(container:container,calendars:excludedCalendars,lists:excludedLists,accounts:excludedAccounts,date:selectedDate)
    @ObservationIgnored lazy var widgetCalendars = WidgetCalendarStore(service:eventKit)
    @ObservationIgnored lazy var assistant:AssistantService = {
        let service=AssistantService(connection:chatGPT,container:container)
        service.memory.sourceIsPermitted = { [weak self,weak service] record in
            guard let self,service?.contextEnabled == true else { return false }
            return SourceContextRules.permitted(record,access:self.whatsapp.access(for:record.registration),linkedIdentity:self.whatsapp.linkedIdentity,messages:self.whatsapp.messages)
        }
        return service
    }()
    @ObservationIgnored lazy var assistantActions = AssistantActions(container: container)
    @ObservationIgnored lazy var emailSummaries = EmailSummaryService(container: container)
    @ObservationIgnored lazy var heartbeat = HeartbeatService(container:container)
    private var briefingPoll: Task<Void, Never>?
    @ObservationIgnored lazy var memoryLearning = MemoryLearningService(container:container)
    @ObservationIgnored lazy var sourceLearning = SourceContextLearningService(container:container)
    @ObservationIgnored lazy var learningBudget = LearningBudget(container:container)
    @ObservationIgnored let projectPlacement = LifePlacementService()
    @ObservationIgnored lazy var lifeOrganisation = LifeOrganisationService(container:container)
    @ObservationIgnored lazy var nativeCreations = NativeCreationStore(container:container)
    @ObservationIgnored lazy var proactive = ProactiveService(container:container)
    var sourceRevision = 0
    @ObservationIgnored lazy var briefings = BriefingService(container: container)
    let eventKit = EventKitService()
    let mail = MailService()
    let mailLookup = MailLookup()
    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private var changes: Task<Void, Never>?
    private var poll: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var pendingCalendarRefresh = false
    private var pendingReminderRefresh = false
    private var started = false
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
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--render-projects") || ProcessInfo.processInfo.arguments.contains("--validate-projects") || ProcessInfo.processInfo.arguments.contains("--preview-projects") || ProcessInfo.processInfo.arguments.contains("--validate-placement") || ProcessInfo.processInfo.arguments.contains("--validate-mail-monitoring") || ProcessInfo.processInfo.arguments.contains("--validate-mail-dates") {
                container = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                return
            }
            #endif
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mission Control", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let configuration = ModelConfiguration(url: directory.appendingPathComponent("Dashboard.store"), cloudKitDatabase: .none)
            container = try ModelContainer(for: CachedDashboard.self, configurations: configuration)
            restore()
        } catch { storageError = "Local cache unavailable: " + error.localizedDescription }
    }
    func start() {
        guard !started else { return }; started = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--validate-mail-dates") {
            Task {
                let result=(try? await mail.validateDates()) ?? "Unavailable"
                try? Data(result.utf8).write(to:URL(fileURLWithPath:"/tmp/missioncontrol-mail-dates.json"),options:.atomic)
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-mail-monitoring") {
            Task {
                let result:[String:Any]
                do { result = try await mail.validateMonitoring() } catch { result = ["unavailable":true] }
                if let data = try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-mail-monitor-live.json"),options:.atomic) }
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-projects") { return }
        if ProcessInfo.processInfo.arguments.contains("--validate-placement") {
            Task {
                let result:[String:Any]
                do { result=try await LifePlacementEvaluation.run(self) } catch { result=["error":error.localizedDescription,"completed":Date.now.ISO8601Format()] }
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-placement-evaluation.json"),options:.atomic) }
                NSApp.terminate(nil)
            };return
        }

        if ProcessInfo.processInfo.arguments.contains("--render-projects") {
            Task { try? await Task.sleep(for:.milliseconds(250)); await LifeProjectPreview.render(self); NSApp.terminate(nil) }; return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-projects") {
            Task {
                let result: [String:Any]
                do { result = try await LifeWorkspaceEvaluation.run(self) }
                catch { result = ["error":error.localizedDescription, "completed":Date.now.ISO8601Format()] }
                if let data = try? JSONSerialization.data(withJSONObject:result, options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-project-evaluation.json"), options:.atomic) }
                NSApp.terminate(nil)
            }; return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-native-editors") {
            Task { [self] in
                let result:String
                do {result=try await eventKit.validateNativeEditors()} catch {result=error.localizedDescription}
                try? Data(result.utf8).write(to:URL(fileURLWithPath:"/tmp/missioncontrol-native-editors-result.txt"),options:.atomic)
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-native-capabilities") {
            Task { [self] in
                let result:[String:Any]
                do {result=try await NativeCapabilitiesEvaluation.run(self)} catch {result=["error":error.localizedDescription]}
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-native-capabilities-evaluation.json"),options:.atomic)}
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-focus-workflow") {
            Task {
                let result:[String:Any]
                do { result=try await WorkflowEvaluation.run(self) }
                catch { result=["error":error.localizedDescription,"completed":Date.now.ISO8601Format()] }
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-workflow-evaluation.json"),options:.atomic) }
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-source-context") {
            Task {
                let result:[String:Any]
                do { result=try await SourceContextEvaluation.run(self) }
                catch { result=["error":error.localizedDescription,"completed":Date.now.ISO8601Format()] }
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-source-context-evaluation.json"),options:.atomic) }
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--render-weather") {
            Task { try? await Task.sleep(for:.milliseconds(250));WeatherWidgetPreview.render();NSApp.terminate(nil) };return
        }
        if ProcessInfo.processInfo.arguments.contains("--render-life-map") {
            Task { try? await Task.sleep(for:.milliseconds(250));LifeNotebookPreview.render();DateClockPreview.render();NSApp.terminate(nil) };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-life-notebook") { validateLifeNotebook();return }
        #endif
        if !sample { whatsapp.resumeAtLaunch() }
        if sample { loadSample(); return }
        weather.startRefresh(allowPrompt:true)
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sourceRevision += 1
                self.changes?.cancel()
                self.changes = Task {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    self.widgetCalendars.invalidate(); await self.refreshCalendar(); await self.refreshReminders(); await self.refreshPAOrientation()
                }
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh(retryMail: false); if let self { self.heartbeat.check(self); self.briefings.check(self) } } })
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1800))
                guard !Task.isCancelled else { return }
                if let self { self.heartbeat.check(self) }
                self?.weather.startRefresh()
            }
        }
        briefingPoll = Task { [weak self] in
            while !Task.isCancelled {
                if let self { self.heartbeat.check(self); if !self.heartbeat.busy { self.projectPlacement.check(self); self.briefings.check(self); self.memoryLearning.recoverDelivery(self); self.memoryLearning.check(self); self.proactive.recoverDelivery(self); self.sourceLearning.check(self); self.lifeOrganisation.check(self); if Date.now.timeIntervalSince(self.lastOrientationCheck) >= 900 { await self.refreshPAOrientation() } } }
                try? await Task.sleep(for: .seconds(60))
            }
        }
        refresh(retryMail: false)
        heartbeat.check(self)
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
        widgetCalendars.invalidate()
        if retryMail { mailIndex.resume() }
        guard !sample else { loadSample(); return }
        weather.startRefresh()
        Task { await refreshCalendar() }
        Task { await refreshReminders() }
        Task { await refreshPAOrientation() }
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
    func refreshPAOrientation() async {
        guard !sample, assistant.contextEnabled, !paOrientationHealth.loading else { return }
        lastOrientationCheck = .now; paOrientationHealth.loading = true
        let start = Calendar.current.startOfDay(for:.now), end = Calendar.current.date(byAdding:.day,value:90,to:start)!, revision = sourceRevision
        do {
            let snapshot = try await eventKit.calendar(from:start,to:end)
            guard revision == sourceRevision else { paOrientationHealth.loading = false; paOrientationHealth.error = "Source changed during orientation; refresh pending."; return }
            paOrientation = PAOrientation(start:start,end:end,refreshed:.now,calendar:snapshot)
            paOrientationHealth = .init(lastSuccess:.now)
            persist("paOrientation",paOrientation); persist("paOrientationHealth",paOrientationHealth)
        } catch { paOrientationHealth.error = error.localizedDescription; paOrientationHealth.loading = false }
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
        mailHealth.loading = true
        defer { mailHealth.loading = false }
        do {
            let discovery = try await mail.discoverAccounts()
            if !discovery.errors.isEmpty { throw MailServiceError.mail(discovery.errors.joined(separator: "; ")) }
            let accounts = discovery.accounts
            let enabled = Set(accounts.map(\.id))
            mailData = MailSnapshot(messages: mailData.messages.filter { enabled.contains($0.accountID) && $0.received >= Date.now.addingTimeInterval(-30 * 86400) }, accounts: accounts, errors: [])
            mailIndex.prepare(accounts: accounts,lastCheck:mailHealth.lastSuccess)
            persistMailCheckpoint()
            // All accounts get an arrival page before background work. Two arrival
            // pages/account/check; only one history/reconciliation page per five
            // minutes. Never recursively drain or rebuild the month's cache.
            for account in accounts where mailIndex.available(account.id) {
                if let window = mailIndex.monitor(account.id) { await readMailPage(window,account:account) }
            }
            for account in accounts where mailIndex.available(account.id) {
                if let window = mailIndex.monitor(account.id) { await readMailPage(window,account:account) }
                if mailIndex.available(account.id), let window = mailIndex.background(account.id) { await readMailPage(window,account:account) }
            }
            mailHealth.error = accounts.compactMap { account in
                mailIndex.accountErrors?[account.id].map { account.title + " Inbox: " + $0 + " Cached mail retained; automatic retry backs off up to 30 minutes. Refresh retries now." }
            }.joined(separator:"; ")
            if mailHealth.error?.isEmpty == true { mailHealth.error = nil }
            if accounts.isEmpty { mailHealth.lastSuccess = .now }
            persistMailCheckpoint()
            persist("mailHealth", SourceHealth(lastSuccess:mailHealth.lastSuccess,error:mailHealth.error))
        } catch {
            mailHealth.error = error.localizedDescription + " Cached mail retained; monitoring retries on its next check."
        }
    }
    private func readMailPage(_ window: MailWindowProgress, account: MailAccount) async {
        do {
            let batch = try await mail.batch(accountID:account.id,window:window,knownMessages:window.id.hasPrefix("monitor:") ? mailData.messages : nil)
            mailData = mailIndex.apply(batch,to:window.id,snapshot:mailData)
            mailHealth.lastSuccess = .now
        } catch {
            // Reset only a stale exact page, retaining cached rows and all other
            // account cursors. Transport failures keep their immutable ID list.
            if case MailServiceError.mail(let detail) = error,
               detail.contains("changed or moved") || detail.contains("-1728") {
                mailIndex.resetCursor(window.id)
            }
            mailIndex.failed(account.id,detail:error.localizedDescription)
        }
        persistMailCheckpoint()
    }
    func complete(_ reminder: TaskItem) {
        guard !sample, !writing else { return }
        writing = true; writeError = nil
        Task {
            do {
                undoToken = try await eventKit.complete(id: reminder.id)
                undoTitle = reminder.title
                showFeedback("Completed: " + reminder.title)
                await refreshReminders()
            } catch { writeError = error.localizedDescription; await refreshReminders() }
            writing = false
        }
    }
    func newNativeItem(_ kind: NativeItemKind, date: Date? = nil) {
        editTarget = .create(NativeCreationRequest(kind:kind,registration:chatGPT.activeID,preferredDate:date))
    }
    func reviewDiscovery(_ record:PADiscovery,as kind:NativeItemKind? = nil) {
        guard proactive.visible(record,model:self),record.registration == chatGPT.activeID,let id=UUID(uuidString:record.id) else { return }
        let label:String,title:String
        if record.sourceKind == "whatsapp" { label="WhatsApp · " + (record.sourceLabel ?? "Selected chat");title=record.sourceTitle ?? "Follow up: " + (record.sourceLabel ?? "WhatsApp") }
        else {
            guard let message=emailSummaries.highlights(self).first(where:{$0.0.id == record.mailID})?.0 else { return }
            label=message.account + " · " + message.subject;title=record.sourceTitle ?? message.subject
        }
        let selectedKind=kind ?? (record.kind == "calendar" ? .event : .reminder)
        editTarget = .create(NativeCreationRequest(id:id,kind:selectedKind,registration:record.registration,title:String(title.prefix(500)),notes:"Source: " + label + "\n" + record.evidence,discoveryID:record.id,evidence:record.message + "\n\n" + label + ": " + record.evidence,requiresDateSelection:selectedKind == .event))
    }
    func createNativeItem(_ request: NativeCreationRequest, baseline: NativeEditDetails, edited: NativeEditDetails, dateSelected: Bool) async throws {
        guard !sample, !writing, !assistant.busy, request.registration == chatGPT.activeID else { throw ActionFailure.message("Another change or account switch is in progress; reopen the form when ready.") }
        if request.requiresDateSelection && !dateSelected { throw ActionFailure.message("Choose the event's date and time before creating it.") }
        if let discovery = request.discoveryID {
            guard let record = proactive.state.records.first(where:{ $0.id == discovery && $0.registration == request.registration }), proactive.visible(record,model:self) else { throw ActionFailure.message("This suggestion or its enabled source changed; reopen it before creating anything.") }
        }
        try NativeCreationRules.validate(request:request,baseline:baseline,edited:edited)
        try nativeCreations.begin(request)
        writing = true; writeError = nil; nativeWriteNotice = nil
        defer { writing = false }
        do {
            let receipt = try await eventKit.createItem(request:request,baseline:baseline,edited:edited,scope:proactive.scope(self))
            try nativeCreations.complete(request,receipt:receipt)
            showFeedback("Created " + receipt.title + " · " + receipt.destination)
            widgetCalendars.invalidate(); await refreshCalendar(); await refreshReminders(); await refreshPAOrientation()
        } catch {
            let text = error.localizedDescription + " Check Apple Calendar or Reminders before creating another item; this save will not be repeated automatically."
            writeError = text; throw ActionFailure.message(text)
        }
    }
    func saveNativeEdit(baseline: NativeEditDetails, edited: NativeEditDetails, scope: NativeChangeScope = .occurrence) async throws {
        guard !sample, !writing, !assistant.busy else { throw ActionFailure.message("Another change is in progress; wait before saving.") }
        writing = true; writeError = nil
        defer { writing = false }
        do {
            let saved = try await eventKit.saveEdit(baseline:baseline,edited:edited,scope:scope)
            editUndo = NativeEditRules.supportsUndo(baseline:baseline,edited:edited,scope:scope) ? NativeEditUndo(original:baseline,saved:saved) : nil
            showFeedback("Updated: " + saved.title)
            widgetCalendars.invalidate()
            await refreshCalendar(); await refreshReminders()
        } catch { writeError = error.localizedDescription; throw error }
    }
    func deleteNativeItem(baseline: NativeEditDetails, scope: NativeChangeScope, requestID: UUID) async throws {
        guard !sample, !writing, !assistant.busy else { throw ActionFailure.message("Another change is in progress.") }
        writing=true;defer {writing=false}
        let result=try await assistantActions.performNativeDeletion(baseline:baseline,scope:scope,requestID:requestID,model:self)
        editUndo=nil;showFeedback(result);widgetCalendars.invalidate()
        await refreshCalendar();await refreshReminders();await refreshPAOrientation()
    }
    func clearNativeEditUndo() { editUndo=nil }
    func recordAssistantEditUndo(_ receipt: NativeEditUndo) { editUndo = receipt; widgetCalendars.invalidate() }
    func showFeedback(_ text: String) { nativeWriteNotice = text; feedbackDate = .now }
    var latestUndo: String? {
        UndoOrder.latest(layout:workspace.canUndo ? workspace.undoDate : nil,completion:undoToken == nil ? nil : completionUndoDate,edit:editUndo?.created,email:emailSummaries.undoDate(chatGPT.activeID),discovery:proactive.undoDate(chatGPT.activeID),question:memoryLearning.undoDate(chatGPT.activeID),project:assistant.projects.undoDate(chatGPT.activeID))
    }
    var latestUndoDate: Date? {
        switch latestUndo {
        case "layout": return workspace.undoDate
        case "completion": return completionUndoDate
        case "edit": return editUndo?.created
        case "email": return emailSummaries.undoDate(chatGPT.activeID)
        case "discovery": return proactive.undoDate(chatGPT.activeID)
        case "question": return memoryLearning.undoDate(chatGPT.activeID)
        case "project": return assistant.projects.undoDate(chatGPT.activeID)
        default: return nil
        }
    }
    var undoLabel: String {
        switch latestUndo {
        case "edit": return "Undo edit"
        case "completion": return "Undo reminder completion"
        case "layout": return "Undo dashboard change"
        case "email": return "Undo email dismissal"
        case "discovery": return "Undo suggestion dismissal"
        case "question": return "Undo question dismissal"
        case "project": return "Undo project edit"
        default: return "Undo"
        }
    }
    func undoAssistantAppleChange() async throws -> String {
        guard !sample, !writing else { throw ActionFailure.message("Another write is in progress.") }
        let latest = UndoOrder.latest(layout:nil,completion:undoToken == nil ? nil : completionUndoDate,edit:editUndo?.created)
        guard latest != nil else { throw ActionFailure.message("No supported Apple edit/completion remains to undo. Creation/deletion are outside this Undo.") }
        writing = true; defer { writing = false }
        let result: String
        if latest == "edit", let ticket = editUndo {
            try await eventKit.undoEdit(ticket); editUndo = nil; widgetCalendars.invalidate(); result = "Edit undone: " + ticket.original.title
        } else if let token = undoToken {
            try await eventKit.undo(token:token); undoToken = nil; result = "Reminder restored: " + undoTitle
            do { try assistantActions.recordUndo(token:token) } catch { writeError = "Reminder restored; action receipt update failed." }
        } else { throw ActionFailure.message("Undo receipt is unavailable.") }
        showFeedback(result); await refreshCalendar(); await refreshReminders(); await refreshPAOrientation(); return result
    }
    func undoLatest() {
        guard !writing, !assistant.busy else { return }
        if latestUndo == "project" {
            do { try assistant.projects.undo(chatGPT.activeID); showFeedback("Project edit undone") } catch { writeError = error.localizedDescription }
            return
        }
        if latestUndo == "email" { emailSummaries.undoDismiss(self); return }
        if latestUndo == "discovery" { proactive.undo(self); return }
        if latestUndo == "question" { memoryLearning.undoQuestion(chatGPT.activeID); return }
        if latestUndo == "layout" { workspace.undo(); if workspace.error == nil { showFeedback("Dashboard change undone") }; return }
        if latestUndo == "completion" { undo(); return }
        guard latestUndo == "edit", let ticket = editUndo else { return }
        writing = true; writeError = nil
        Task {
            defer { writing = false }
            do {
                try await eventKit.undoEdit(ticket); editUndo = nil; showFeedback("Edit undone: " + ticket.original.title)
                widgetCalendars.invalidate(); await refreshCalendar(); await refreshReminders(); await refreshPAOrientation()
            } catch { writeError = "Could not undo the edit. The item may have changed outside 3PO. " + error.localizedDescription }
        }
    }
    func undo() {
        guard let token = undoToken, !writing else { return }
        writing = true; writeError = nil
        Task {
            do {
                try await eventKit.undo(token: token); undoToken = nil
                showFeedback("Reminder restored: " + undoTitle)
                do { try assistantActions.recordUndo(token:token) } catch { writeError = "Reminder restored; its action receipt could not be updated." }
                await refreshReminders()
            }
            catch { writeError = error.localizedDescription; await refreshReminders() }
            writing = false
        }
    }
    func select(_ message: MailMessage) {
        previewTask?.cancel()
        selectedMessage = message; preview = ""; previewError = nil; previewLoading = true
        previewTask = Task {
            do {
                let body = try await mail.body(accountID: message.accountID, messageID: message.messageID, expectedInternetMessageID: message.internetMessageID, mailboxName:message.mailboxName)
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
            paOrientation = read("paOrientation",PAOrientation.self)
            paOrientationHealth = read("paOrientationHealth",SourceHealth.self) ?? paOrientationHealth
            if paOrientation != nil { paOrientationHealth.error = "Cached data · refresh pending" }
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

struct AssistantFocusRequest: Equatable {
    let id = UUID()
    let widgetID: UUID
}
