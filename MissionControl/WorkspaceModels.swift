import Foundation

enum WidgetKind: String, Codable, CaseIterable {
    case calendar
    case reminders
    case mail
    case conversation
    case overview // Saved legacy kind, now Today’s brief.
    case emailSummary
    case clock
    case weather
    case tasks
    case memoryGraph
    case projects

    var title: String {
        switch self {
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .mail: return "Mail"
        case .conversation: return "Conversation"
        case .overview: return "Today’s brief"
        case .emailSummary: return "Email summary"
        case .memoryGraph: return "Life map"
        case .tasks: return "Tasks for you"
        case .clock: return "Date & clock"
        case .weather: return "Weather"
        case .projects: return "Projects"
        }
    }

    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .mail: return "envelope"
        case .conversation: return "bubble.left.and.bubble.right"
        case .overview: return "sun.max"
        case .emailSummary: return "envelope.badge"
        case .memoryGraph: return "point.3.connected.trianglepath.dotted"
        case .tasks: return "tray.full"
        case .clock: return "clock"
        case .weather: return "cloud.sun"
        case .projects: return "folder"
        }
    }

    var minimumColumns: Int {
        switch self {
        case .calendar, .conversation, .overview, .emailSummary, .tasks, .memoryGraph, .projects: return 4
        case .reminders: return 3
        case .mail: return 4
        case .clock: return 3
        case .weather: return 3
        }
    }

    var minimumRows: Int {
        switch self {
        case .calendar, .conversation: return 5
        case .reminders: return 4
        case .mail, .overview, .emailSummary, .tasks, .memoryGraph, .projects: return 4
        case .clock: return 2
        case .weather: return 3
        }
    }
}

struct WidgetConfiguration: Codable, Equatable {
    var sourceExclusions: Set<String> = []
    var date: Date = .now
    var calendarMode: String = "agenda"
    var reminderGrouping: String = "lists"
    var conversationID: UUID? = nil
    var conversationSelections: [String:UUID]? = nil
    // Empty string is explicit general PA mode, distinct from an unmigrated legacy selection.
    var paTopicSelections: [String:String]? = nil
    var lifeFocusSelections:[String:[String]]? = nil
    var colourProfiles: [String:[String:String]]? = nil
    var clockShowsTime: Bool? = nil
    var clockShowsSeconds: Bool? = nil
    var clockStyle:String? = nil
    var clockAlignment:String? = nil
    var clockUses24Hour:Bool? = nil
    var projectRoots: [String:String]? = nil
    var projectCollapsed: [String:[String]]? = nil
    var projectView: String? = nil
    var projectOnlyUnfinished: Bool? = nil
}

struct GridRect: Codable, Equatable {
    var x: Int
    var y: Int
    var w: Int
    var h: Int

    func overlaps(_ other: GridRect) -> Bool {
        x < other.x + other.w && other.x < x + w &&
            y < other.y + other.h && other.y < y + h
    }
}

struct WidgetPlacement: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kindRaw: String
    var rect: GridRect
    var configuration: WidgetConfiguration = WidgetConfiguration()

    var kind: WidgetKind? { WidgetKind(rawValue: kindRaw) }

    init(
        id: UUID = UUID(),
        kindRaw: String,
        rect: GridRect,
        configuration: WidgetConfiguration = WidgetConfiguration()
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.rect = rect
        self.configuration = configuration
    }

    init(
        id: UUID = UUID(),
        kind: WidgetKind,
        rect: GridRect,
        configuration: WidgetConfiguration = WidgetConfiguration()
    ) {
        self.init(id: id, kindRaw: kind.rawValue, rect: rect, configuration: configuration)
    }
}

enum DashboardSymbols {
    static let choices=["square.grid.2x2","sun.max","calendar","checklist","bubble.left.and.bubble.right","envelope","graduationcap","book","pencil","wrench.and.screwdriver","briefcase","sportscourt","figure.run","person.2","house","heart","airplane","map","leaf","star","music.note","cup.and.saucer","brain","sparkles"]
}
struct DashboardPage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var widgets: [WidgetPlacement]
    var canvasRows: Int?
    var symbol: String? = nil
    var displayIcon: String { symbol ?? (widgets.count == 1 ? widgets[0].kind?.icon ?? "square" : "square.grid.2x2") }

    init(id: UUID = UUID(), title: String, widgets: [WidgetPlacement], canvasRows: Int? = nil) {
        self.id = id
        self.title = title
        self.widgets = widgets
        self.canvasRows = canvasRows
    }
}

struct WorkspaceState: Codable, Equatable {
    var schemaVersion: Int = 1
    var pages: [DashboardPage]
    var selectedPageID: UUID

    init(schemaVersion: Int = 1, pages: [DashboardPage], selectedPageID: UUID) {
        self.schemaVersion = schemaVersion
        self.pages = pages
        self.selectedPageID = selectedPageID
    }
}

enum GridRules {
    static let columns = 12
    static let rowHeight: Double = 64
    static let gap: Double = 12
    static func rows(_ page: DashboardPage) -> Int { max(8,page.canvasRows ?? page.widgets.map { $0.rect.y+$0.rect.h }.max() ?? 8) }

    static func valid(
        _ rect: GridRect,
        among placements: [WidgetPlacement],
        excluding excludedID: UUID? = nil,
        rowLimit: Int? = nil
    ) -> Bool {
        guard rect.x >= 0, rect.y >= 0, rect.w >= 1, rect.h >= 1,
              rect.x + rect.w <= columns,
              rowLimit == nil || rect.y + rect.h <= rowLimit! else { return false }

        return !placements.contains { placement in
            placement.id != excludedID && rect.overlaps(placement.rect)
        }
    }

    static func firstFree(kind: WidgetKind, in placements: [WidgetPlacement]) -> GridRect {
        let width = kind.minimumColumns
        let height = kind.minimumRows
        let lastOccupiedRow = placements
            .map { max(0, $0.rect.y + max(0, $0.rect.h)) }
            .max() ?? 0

        for y in 0...lastOccupiedRow {
            for x in 0...(columns - width) {
                let candidate = GridRect(x: x, y: y, w: width, h: height)
                if valid(candidate, among: placements) { return candidate }
            }
        }

        // A free position always exists immediately after the last occupied row.
        return GridRect(x: 0, y: lastOccupiedRow, w: width, h: height)
    }
    static func firstFree(kind: WidgetKind, in placements: [WidgetPlacement], rows: Int) -> GridRect? {
        guard rows >= kind.minimumRows else { return nil }
        for y in 0...(rows-kind.minimumRows) {
            for x in 0...(columns-kind.minimumColumns) {
                let candidate = GridRect(x:x,y:y,w:kind.minimumColumns,h:kind.minimumRows)
                if valid(candidate,among:placements,rowLimit:rows) { return candidate }
            }
        }
        return nil
    }

    static func defaults() -> WorkspaceState {
        let today = DashboardPage(title: "Today", widgets: [
            WidgetPlacement(kind: .calendar, rect: GridRect(x: 0, y: 0, w: 4, h: 7)),
            WidgetPlacement(kind: .reminders, rect: GridRect(x: 4, y: 0, w: 3, h: 7)),
            WidgetPlacement(kind: .overview, rect: GridRect(x: 7, y: 0, w: 5, h: 7))
        ])
        let planning = DashboardPage(title: "Planning", widgets: [
            WidgetPlacement(kind: .calendar, rect: GridRect(x: 0, y: 0, w: 12, h: 10))
        ])
        let sources = DashboardPage(title: "Sources", widgets: [
            WidgetPlacement(kind: .mail, rect: GridRect(x: 0, y: 0, w: 12, h: 8))
        ])

        return WorkspaceState(pages: [today, planning, sources], selectedPageID: today.id)
    }
}
