import Foundation

struct SavedWorkspaceTheme:Codable,Identifiable,Equatable {
    var id=UUID()
    var name:String
    var colorOverrides:String
    var baseTheme:String
    var accent:String
    var revision=UUID()
}
enum WorkspaceThemeFailure:LocalizedError {
    case message(String)
    var errorDescription:String? {if case .message(let value)=self {return value};return nil}
}
/// Local recipes preserve inherited roles and unknown JSON fields; invalid libraries remain untouched.
struct WorkspaceThemeLibrary {
    private var object:[String:Any]
    private(set) var themes:[SavedWorkspaceTheme]
    init(raw:String)throws {
        guard raw.utf8.count <= 1_048_576,let root=try JSONSerialization.jsonObject(with:Data(raw.utf8)) as? [String:Any],root["version"] == nil || root["version"] as? Int == 1,
              root["themes"] == nil || root["themes"] is [[String:Any]] else {throw WorkspaceThemeFailure.message("Saved themes are unavailable. Their storage is preserved.")}
        let rows=root["themes"] as? [[String:Any]] ?? []
        let decoded=try rows.map{try JSONDecoder().decode(SavedWorkspaceTheme.self,from:JSONSerialization.data(withJSONObject:$0))}
        guard Set(decoded.map(\.id)).count == decoded.count,Set(decoded.map{Self.nameKey($0.name)}).count == decoded.count,decoded.allSatisfy(Self.valid) else {throw WorkspaceThemeFailure.message("Saved themes are unavailable. Their storage is preserved.")}
        object=root;themes=decoded
    }
    static func validColors(_ raw:String)->Bool {
        guard let root=(try? JSONSerialization.jsonObject(with:Data(raw.utf8))) as? [String:Any] else {return false}
        guard let profiles=root["profiles"] else {return true}
        guard let modes=profiles as? [String:[String:String]] else {return false}
        return modes.allSatisfy{!$0.key.isEmpty && $0.value.allSatisfy{!$0.key.isEmpty && validHex($0.value)}}
    }
    private static func validHex(_ raw:String)->Bool {
        let hex=raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        return hex.count == 6 && hex.allSatisfy(\.isHexDigit) && UInt32(hex,radix:16) != nil
    }
    private static func nameKey(_ name:String)->String {name.trimmingCharacters(in:.whitespacesAndNewlines).folding(options:[.caseInsensitive],locale:Locale(identifier:"en_GB"))}
    private static func valid(_ value:SavedWorkspaceTheme)->Bool {!nameKey(value.name).isEmpty && value.name.count <= 60 && validColors(value.colorOverrides) && !value.baseTheme.isEmpty && !value.accent.isEmpty}
    func selected(_ id:String,colors:String,baseTheme:String,accent:String)->SavedWorkspaceTheme? {
        guard let uuid=UUID(uuidString:id),let value=themes.first(where:{$0.id == uuid}),value.baseTheme == baseTheme,value.accent == accent,
              let current=(try? JSONSerialization.jsonObject(with:Data(colors.utf8))) as? [String:Any],
              let saved=(try? JSONSerialization.jsonObject(with:Data(value.colorOverrides.utf8))) as? [String:Any],
              NSDictionary(dictionary:current).isEqual(to:saved) else {return nil}
        return value
    }
    var encoded:String {get throws {
        let data=try JSONSerialization.data(withJSONObject:object,options:.sortedKeys)
        guard data.count <= 1_048_576 else {throw WorkspaceThemeFailure.message("Saved themes are full. Remove an unused theme before saving another.")}
        return String(decoding:data,as:UTF8.self)
    }}
    mutating func save(_ value:SavedWorkspaceTheme,expected:SavedWorkspaceTheme? = nil)throws {
        guard Self.valid(value) else {throw WorkspaceThemeFailure.message("Choose a name of up to 60 characters and valid colours.")}
        if let expected {guard themes.first(where:{$0.id == value.id}) == expected else {throw WorkspaceThemeFailure.message("This theme changed. Reopen it before saving.")}}
        else {guard !themes.contains(where:{$0.id == value.id}) else {throw WorkspaceThemeFailure.message("This theme already exists.")}}
        guard !themes.contains(where:{$0.id != value.id && Self.nameKey($0.name) == Self.nameKey(value.name)}) else {throw WorkspaceThemeFailure.message("A theme with that name exists. Choose another name or update it.")}
        var updated=value;updated.name=updated.name.trimmingCharacters(in:.whitespacesAndNewlines);updated.revision=UUID()
        var rows=object["themes"] as? [[String:Any]] ?? []
        let fields=try JSONSerialization.jsonObject(with:JSONEncoder().encode(updated)) as! [String:Any]
        if let index=rows.firstIndex(where:{($0["id"] as? String).flatMap(UUID.init(uuidString:)) == value.id}) {rows[index].merge(fields){_,new in new}}
        else {rows.append(fields)}
        var next=object;next["themes"]=rows;next["version"]=1
        guard try JSONSerialization.data(withJSONObject:next,options:.sortedKeys).count <= 1_048_576 else {throw WorkspaceThemeFailure.message("Saved themes are full. Remove an unused theme before saving another.")}
        object=next
        themes.removeAll{$0.id == value.id};themes.append(updated)
    }
    mutating func remove(_ expected:SavedWorkspaceTheme)throws {
        guard themes.first(where:{$0.id == expected.id}) == expected else {throw WorkspaceThemeFailure.message("This theme changed. Reopen it before removing it.")}
        object["themes"]=(object["themes"] as? [[String:Any]] ?? []).filter{($0["id"] as? String).flatMap(UUID.init(uuidString:)) != expected.id}
        themes.removeAll{$0.id == expected.id}
    }
}

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
        case .tasks: return "Review inbox"
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

    /// Every widget can shrink to the Small preset; each has a glance for two-row and two-column sizes.
    var minimumColumns: Int { WidgetSize.small.columns }
    var minimumRows: Int { WidgetSize.small.rows }

    /// The size a plain Add widget uses: the full widget's comfortable size, as before presets.
    var defaultColumns: Int {
        switch self {
        case .calendar, .conversation, .overview, .emailSummary, .tasks, .memoryGraph, .projects, .mail: return 4
        case .reminders, .clock, .weather: return 3
        }
    }

    var defaultRows: Int {
        switch self {
        case .calendar, .conversation: return 5
        case .reminders, .mail, .overview, .emailSummary, .tasks, .memoryGraph, .projects: return 4
        case .clock: return 2
        case .weather: return 3
        }
    }
}

/// Preset sizes offered when adding or resizing a widget (1 November). Free resizing still works
/// between them; Small is every widget's minimum.
enum WidgetSize: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge, tall, wide
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra large"
        case .tall: return "Tall"
        case .wide: return "Wide"
        }
    }
    var columns: Int { switch self { case .small, .tall: return 2; case .medium, .large: return 4; case .extraLarge, .wide: return 8 } }
    var rows: Int { switch self { case .small, .medium, .wide: return 2; case .large, .extraLarge, .tall: return 4 } }
    static func matching(_ rect: GridRect) -> WidgetSize? { allCases.first { $0.columns == rect.w && $0.rows == rect.h } }
}

/// How a widget arranges itself. Two rows or columns get a glance (small, medium, tall); anything
/// larger is the full widget. The points check keeps a small window from squeezing the full widget.
enum WidgetLayout: Equatable {
    case small, medium, tall, large
    init(rect: GridRect, size: CGSize) {
        let narrow = rect.w <= 2 || size.width < 230, short = rect.h <= 2 || size.height < 190
        self = narrow ? (short ? .small : .tall) : (short ? .medium : .large)
    }
    var compact: Bool { self != .large }
    var short: Bool { self == .small || self == .medium }
}

enum ProjectPageSection:String,CaseIterable,Identifiable {
    case spaces,tasks,notes
    var id:String {rawValue}
    var title:String {switch self {case .spaces:"Subprojects";case .tasks:"Tasks";case .notes:"Notes"}}
}

struct WidgetConfiguration: Codable, Equatable {
    var sourceExclusions: Set<String> = []
    var date: Date = .now
    var calendarMode: String = "agenda"
    var reminderGrouping: String = "lists"
    var reminderCollapsedLists:[String:[String]]? = nil
    var conversationID: UUID? = nil
    var conversationSelections: [String:UUID]? = nil
    // Empty string is explicit general PA mode, distinct from an unmigrated legacy selection.
    var paTopicSelections: [String:String]? = nil
    var lifeFocusSelections:[String:[String]]? = nil
    var colourProfiles: [String:[String:String]]? = nil
    var briefShowsWeather:Bool? = nil
    /// Points for the brief's prose; nil is the default 14. The greeting scales with it.
    var briefTextSize:Double? = nil
    var clockShowsTime: Bool? = nil
    var clockShowsSeconds: Bool? = nil
    var clockStyle:String? = nil
    var clockAlignment:String? = nil
    var clockUses24Hour:Bool? = nil
    var projectRoots: [String:String]? = nil
    var projectCollapsed: [String:[String]]? = nil
    var lifeMapView: String? = nil
    var projectView: String? = nil
    /// Widget-local presentation, separately remembered for each account's folder.
    var projectFolderViews:[String:[String:String]]? = nil
    var projectOnlyUnfinished: Bool? = nil
    /// Account → folders whose board and list also gather tasks from subprojects. Browsing presentation only.
    var projectIncludeSubfolders:[String:[String]]? = nil
    /// Account/folder presentation only. Unknown section names survive later edits.
    var projectHiddenSections:[String:[String:[String]]]? = nil
    /// Browsing state (visible date, view modes, collapsed rows, open chat) changes
    /// constantly; only layout and genuine setting changes become the dashboard Undo.
    var settings: WidgetConfiguration {
        var value = self
        value.date = .distantPast; value.calendarMode = ""; value.reminderGrouping = ""; value.reminderCollapsedLists = nil
        value.conversationID = nil; value.conversationSelections = nil
        value.projectCollapsed = nil; value.lifeMapView = nil; value.projectView = nil; value.projectFolderViews = nil; value.projectOnlyUnfinished = nil; value.projectIncludeSubfolders = nil
        return value
    }
    func showsProjectSection(_ section:ProjectPageSection,registration:String,folder:UUID)->Bool {
        !(projectHiddenSections?[registration]?[folder.uuidString] ?? []).contains(section.rawValue)
    }
    mutating func setProjectSection(_ section:ProjectPageSection,visible:Bool,registration:String,folder:UUID) {
        var accounts=projectHiddenSections ?? [:]
        var folders=accounts[registration] ?? [:]
        var hidden=Set(folders[folder.uuidString] ?? [])
        if visible {hidden.remove(section.rawValue)} else {hidden.insert(section.rawValue)}
        folders[folder.uuidString]=hidden.sorted();accounts[registration]=folders;projectHiddenSections=accounts
    }
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
    var displayIcon: String { symbol ?? (!widgets.isEmpty && Set(widgets.map(\.kindRaw)).count == 1 ? widgets[0].kind?.icon ?? "square" : "square.grid.2x2") }

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
        let width = kind.defaultColumns
        let height = kind.defaultRows
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
        firstFree(columns:kind.defaultColumns,rows:kind.defaultRows,in:placements,rowLimit:rows)
    }
    static func firstFree(columns width: Int, rows height: Int, in placements: [WidgetPlacement], rowLimit rows: Int) -> GridRect? {
        guard rows >= height, width <= columns else { return nil }
        for y in 0...(rows-height) {
            for x in 0...(columns-width) {
                let candidate = GridRect(x:x,y:y,w:width,h:height)
                if valid(candidate,among:placements,rowLimit:rows) { return candidate }
            }
        }
        return nil
    }
    /// A preset applied to a placed widget: in place, nudged left or up only as far as the page
    /// edge needs, otherwise the first free spot on the page; nil when the page has no room.
    static func resized(_ widget: WidgetPlacement, to size: WidgetSize, among placements: [WidgetPlacement], rows: Int) -> GridRect? {
        let others = placements.filter { $0.id != widget.id }
        let here = GridRect(x:min(widget.rect.x,columns-size.columns),y:max(0,min(widget.rect.y,rows-size.rows)),w:size.columns,h:size.rows)
        if valid(here,among:others,rowLimit:rows) { return here }
        return firstFree(columns:size.columns,rows:size.rows,in:others,rowLimit:rows)
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
