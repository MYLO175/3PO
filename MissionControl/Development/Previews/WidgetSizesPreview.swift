#if DEBUG
import SwiftUI
import AppKit

/// `--preview-widget-sizes --sample`: the real dashboard with one page per widget, each holding that
/// widget at every preset size, fed made-up data. Storage is disposable, sources, helpers and AI never
/// start, and sample mode blocks every Apple write and Mail read.
struct WidgetSizesPreview: View {
    @Bindable var model: DashboardModel
    private let sample = ProcessInfo.processInfo.arguments.contains("--sample")
    init(model: DashboardModel) {
        self.model = model
        // Set up before the first frame, so the default pages never mount.
        if sample { Self.prepare(model) }
    }
    var body: some View {
        if sample {
            WorkspaceView(model: model).environment(\.calendarPreviewSnapshot, DesignFixtures.events)
        } else {
            ContentUnavailableView("Open with --sample", systemImage: "exclamationmark.triangle", description: Text("scripts/preview.sh --preview-widget-sizes --sample keeps every Apple write blocked."))
                .frame(minWidth: 500, minHeight: 300)
        }
    }
    @MainActor private static var prepared = false
    @MainActor static func prepare(_ model: DashboardModel) {
        guard !prepared else { return }; prepared = true
        model.inference.useChatGPTForFictionalEvaluation()
        model.chatGPT.activeID = "fictional-widget-sizes"
        let registration = model.inference.activeID
        // The preview copy's own settings: Review and Email summary show only with context and monitoring on.
        model.assistant.contextEnabled = true
        model.emailSummaries.enabled = true
        DesignFixtures.seedReminders(model)
        try? seedMail(model, registration: registration)
        try? model.briefings.seedWidgetSizesPreview(model)
        model.weather.seedWidgetSizesPreview(forecast)
        model.assistant.seedWidgetSizesPreview()
        LifeProjectPreview.seedOverview(model, registration: registration)
        seedMemory(model, registration: registration)
        let store = model.workspace, original = store.state.pages.map(\.id)
        // Placed in this order the six sizes tile one 12 × 8 page: Extra large and Large across the
        // top, Wide, Tall and Small below, then Medium.
        for kind in [WidgetKind.overview, .calendar, .reminders, .weather, .clock, .conversation, .tasks, .mail, .emailSummary, .projects, .memoryGraph] {
            store.addPage(kind.title)
            for size in [WidgetSize.extraLarge, .large, .wide, .tall, .small, .medium] { store.addWidget(kind, size: size) }
        }
        for id in original { store.removePage(id) }
        if let first = store.state.pages.first?.id { store.select(first) }
    }
    /// `--snapshot`: every page drawn offscreen in light and dark, written to /tmp, then quits.
    @MainActor static func render(_ model: DashboardModel) async {
        prepare(model)
        let store = model.workspace
        for (number, page) in store.state.pages.enumerated() {
            store.select(page.id)
            for mode in ["light", "dark"] {
                let hosting = NSHostingView(rootView: WorkspaceView(model: model).environment(\.calendarPreviewSnapshot, DesignFixtures.events))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = hosting
                window.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
                window.orderFront(nil)
                try? await Task.sleep(for: .milliseconds(900))
                hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
                if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: EvaluationOutput.url("/tmp/missioncontrol-widget-sizes-\(number)-\(mode).png"), options: .atomic)
                }
                window.close()
            }
        }
    }
    /// Today and the next six days, as if fetched just now.
    private static var forecast: WeatherForecast {
        let codes = [2, 61, 0, 3, 80, 1, 0], highs = [17.0, 14, 19, 16, 13, 18, 20], lows = [8.0, 9, 7, 9, 6, 8, 10], rain = [10.0, 70, 5, 30, 80, 15, 5]
        let days = (0..<7).map { offset in
            WeatherDay(date: WeatherRules.day(Calendar.current.date(byAdding: .day, value: offset, to: .now)!, timezone: .current), code: codes[offset], low: lows[offset], high: highs[offset], rainChance: rain[offset], windKmh: 12 + Double(offset) * 2)
        }
        return WeatherForecast(fetched: .now, timezone: TimeZone.current.identifier, days: days)
    }
    private static func seedMail(_ model: DashboardModel, registration: String) throws {
        let now = Date.now
        func message(_ id: String, _ number: Int, _ sender: String, _ subject: String, minutes: Double, unread: Bool) throws -> MailMessage {
            let raw: [String: Any] = ["id": id, "accountID": "fictional-mail", "account": "Fictional Mail", "messageID": number, "internetMessageID": id + "@example.invalid", "sender": sender, "subject": subject,
                                      "received": now.addingTimeInterval(-minutes * 60).ISO8601Format(), "unread": unread, "replied": false, "flagged": false]
            return try JSONDecoder().decode(MailMessage.self, from: JSONSerialization.data(withJSONObject: raw))
        }
        let tutor = try message("fictional-tutor", 1, "Dr Rivera", "Printed drafts for Monday’s studio", minutes: 25, unread: true)
        let library = try message("fictional-library", 2, "University Library", "Your loan is due back on Friday", minutes: 90, unread: true)
        let alex = try message("fictional-alex", 3, "Alex", "Lunch at the café?", minutes: 180, unread: false)
        let club = try message("fictional-club", 4, "Climbing Club", "Saturday session moved to 11:00", minutes: 400, unread: true)
        let shop = try message("fictional-shop", 5, "Print Shop", "Your order is ready to collect", minutes: 1500, unread: false)
        model.mailData = .init(messages: [tutor, library, alex, club, shop], accounts: [.init(id: "fictional-mail", title: "Fictional Mail")], errors: [])
        func summary(_ message: MailMessage, _ text: String, attention: Bool, reason: String) -> EmailSummary {
            EmailSummary(id: message.id, registration: registration, fingerprint: EmailSummary.fingerprint(message), summary: text, attention: attention, reason: reason, evidence: text, bodyFingerprint: EmailSummary.fingerprintBody(text), messageReceived: message.received, message: message, worthReading: true, needsReply: false, completionEvidenceChecked: true)
        }
        let loan = summary(library, "Two library books are due back on Friday.", attention: false, reason: "")
        try model.emailSummaries.seedAdviceFixture([
            summary(tutor, "Bring two printed drafts of your essay to Monday’s studio.", attention: true, reason: "Your tutor asked for printed drafts."),
            summary(club, "Saturday’s climbing session now starts at 11:00.", attention: true, reason: "A plan you joined has changed."),
            loan
        ])
        let books = model.reminderData.reminders.first { $0.title == "Return library books" }
        let records = books.map { task in
            [PADiscovery(id: UUID().uuidString, registration: registration, mailID: library.id, kind: "change", message: "The library says your books are due on Friday. Move the reminder to match?", evidence: "Two library books are due back on Friday.", created: now, scope: "fixture",
                         sourceRevision: loan.fingerprint, sourceAssessmentRevision: loan.adviceRevision(replied: false),
                         proposedChange: DiscoveryDateChange(target: .reminder(task), newDate: LifeDue.local(Calendar.current.date(byAdding: .day, value: 3, to: now)!), hasTime: false, connection: "The library loan matches this reminder.", timeZoneID: TimeZone.current.identifier))]
        } ?? []
        try model.proactive.seedAdviceFixture(records, model: model)
    }
    private static func seedMemory(_ model: DashboardModel, registration: String) {
        let facts: [(LifeArea, String)] = [
            (.studies, "I’m in my final year of Engineering."), (.studies, "My essay draft is due on Monday."), (.studies, "Design studio meets in Room 2.14."),
            (.people, "Alex is a close friend from my course."), (.people, "Dr Rivera is my tutor."),
            (.wellbeing, "I go climbing on Saturdays."), (.wellbeing, "I run the park loop most mornings."),
            (.career, "I’m applying for graduate engineering roles."), (.home, "I’m moving out at the end of term."),
            (.interests, "I like sketching buildings."), (.administration, "My railcard renews in December.")
        ]
        for (area, text) in facts {
            model.assistant.memory.put(PAMemory(registration: registration, text: text, kind: .context, provenance: "Fictional preview", evidence: text, certainty: .stated, organisation: .init(areas: [area], connections: [])))
        }
    }
}
#endif
