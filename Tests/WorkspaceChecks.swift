import Foundation
import CoreGraphics

@main
struct WorkspaceChecks {
    static func main() throws {
        let defaults = WidgetConfiguration()
        assert(defaults.sourceExclusions.isEmpty)
        assert(defaults.calendarMode == "agenda" && defaults.reminderGrouping == "lists")
        assert(defaults.conversationID == nil)

        let base = WidgetPlacement(kind: .calendar, rect: GridRect(x: 0, y: 0, w: 4, h: 5))
        assert(GridRules.valid(GridRect(x: 4, y: 0, w: 4, h: 5), among: [base]), "Edge touching is allowed")
        assert(!GridRules.valid(GridRect(x: 3, y: 0, w: 4, h: 5), among: [base]), "Horizontal overlap is rejected")
        assert(!GridRules.valid(GridRect(x: 0, y: 4, w: 4, h: 5), among: [base]), "Vertical overlap is rejected")
        assert(!GridRules.valid(GridRect(x: 10, y: 0, w: 3, h: 4), among: []), "Right overflow is rejected")
        assert(!GridRules.valid(GridRect(x: 0, y: -1, w: 1, h: 1), among: []), "Negative rows are rejected")
        assert(!GridRules.valid(GridRect(x: 0, y: 0, w: 0, h: 1), among: []), "Empty dimensions are rejected")
        assert(GridRules.valid(base.rect, among: [base], excluding: base.id), "The edited placement can be excluded")

        let unknown = WidgetPlacement(kindRaw: "futureWidget", rect: GridRect(x: 0, y: 0, w: 4, h: 4))
        assert(unknown.kind == nil)
        let unknownRoundTrip = try JSONDecoder().decode(WidgetPlacement.self, from: JSONEncoder().encode(unknown))
        assert(unknownRoundTrip == unknown && unknownRoundTrip.kindRaw == "futureWidget")

        var configuration = WidgetConfiguration()
        configuration.sourceExclusions = ["source-a", "source-b"]
        configuration.calendarMode = "week"
        configuration.reminderGrouping = "dueDate"
        configuration.conversationID = UUID()
        configuration.conversationSelections = ["account-one":UUID(),"account-two":UUID()]
        configuration.paTopicSelections = ["account-one":"","account-two":UUID().uuidString]
        configuration.colourProfiles = ["light":["widget":"#FFEEEE"],"dark":["widget":"#332222","text":"#FFFFFF"]]
        var legacyConfiguration = try JSONSerialization.jsonObject(with:JSONEncoder().encode(configuration)) as! [String:Any]
        legacyConfiguration.removeValue(forKey:"colourProfiles")
        let migratedColours = try JSONDecoder().decode(WidgetConfiguration.self,from:JSONSerialization.data(withJSONObject:legacyConfiguration))
        assert(migratedColours.colourProfiles == nil && migratedColours.paTopicSelections == configuration.paTopicSelections,"Old layouts inherit theme and retain topic selections")
        let state = GridRules.defaults()
        let stateRoundTrip = try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(state))
        assert(stateRoundTrip == state, "Workspace state survives JSON encoding")
        assert(state.schemaVersion == 1 && state.pages.map(\.title) == ["Today", "Planning", "Sources"])
        assert(state.selectedPageID == state.pages[0].id)
        assert(state.pages[0].widgets.map(\.rect) == [
            GridRect(x: 0, y: 0, w: 4, h: 7),
            GridRect(x: 4, y: 0, w: 3, h: 7),
            GridRect(x: 7, y: 0, w: 5, h: 7)
        ])

        let configuredPlacement = WidgetPlacement(kind: .conversation, rect: GridRect(x: 0, y: 0, w: 4, h: 5), configuration: configuration)
        let placementRoundTrip = try JSONDecoder().decode(WidgetPlacement.self, from: JSONEncoder().encode(configuredPlacement))
        assert(placementRoundTrip == configuredPlacement)

        let row = (0..<GridRules.columns).map { column in
            WidgetPlacement(kind: .overview, rect: GridRect(x: column, y: 0, w: 1, h: 1))
        }
        let next = GridRules.firstFree(kind: .calendar, in: row)
        assert(next == GridRect(x: 0, y: 1, w: 4, h: 5), "Search advances to the first free row")
        assert(GridRules.firstFree(kind: .mail, in: []) == GridRect(x: 0, y: 0, w: 4, h: 4))
        assert(
            GridRules.firstFree(kind: .calendar, in: [base]) == GridRect(x: 4, y: 0, w: 4, h: 5),
            "Search checks columns from left to right before advancing rows"
        )

        let orderedWidgets = [
            WidgetPlacement(kind: .mail, rect: GridRect(x: 0, y: 0, w: 4, h: 4)),
            WidgetPlacement(kindRaw: "futureWidget", rect: GridRect(x: 4, y: 0, w: 4, h: 4)),
            WidgetPlacement(kind: .calendar, rect: GridRect(x: 8, y: 0, w: 4, h: 5))
        ]
        let orderedPage = DashboardPage(title: "Order", widgets: orderedWidgets)
        let orderedPageRoundTrip = try JSONDecoder().decode(DashboardPage.self, from: JSONEncoder().encode(orderedPage))
        assert(orderedPageRoundTrip.widgets == orderedWidgets, "Placement order survives JSON encoding")

        assert(GridRules.valid(GridRect(x:0,y:3,w:4,h:5),among:[],rowLimit:8))
        assert(!GridRules.valid(GridRect(x:0,y:4,w:4,h:5),among:[],rowLimit:8),"Canvas bottom is bounded")
        let filled = [WidgetPlacement(kind:.calendar,rect:GridRect(x:0,y:0,w:12,h:8))]
        assert(GridRules.firstFree(kind:.reminders,in:filled,rows:8) == nil,"Full pages cannot grow downward")
        let legacy = try JSONDecoder().decode(DashboardPage.self,from:Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"title\":\"Legacy\",\"widgets\":[]}".utf8))
        assert(legacy.canvasRows == nil && GridRules.rows(legacy) == 8)
        let tall = DashboardPage(title:"Legacy tall",widgets:[WidgetPlacement(kind:.calendar,rect:GridRect(x:0,y:3,w:12,h:15))])
        assert(GridRules.rows(tall) == 18,"Existing extents are preserved rather than cropped")
        for size in [(1100.0,600.0),(750.0,430.0),(1600.0,1000.0)] {
            let geometry = WorkspaceGeometry(width:size.0,height:size.1,rows:8)
            let full = geometry.frame(GridRect(x:0,y:0,w:12,h:8))
            assert(abs(full.width-size.0) < 0.001 && abs(full.height-size.1) < 0.001)
            let origin = GridRect(x:1,y:1,w:4,h:5)
            let before = geometry.frame(origin)
            let smooth = geometry.preview(origin:origin,dx:7,dy:9,resizing:false,minimumColumns:4,minimumRows:5)
            assert(abs(smooth.minX-before.minX-7) < 0.001 && abs(smooth.minY-before.minY-9) < 0.001,"Preview tracks pixel movement before snapping")
            let moved = geometry.target(origin:origin,dx:geometry.xStep*2,dy:geometry.yStep,resizing:false,minimumColumns:4,minimumRows:5)
            assert(moved == GridRect(x:3,y:2,w:4,h:5),"Movement is measured against the immutable gesture origin")
            let edge = geometry.target(origin:origin,dx:10000,dy:10000,resizing:false,minimumColumns:4,minimumRows:5)
            assert(edge == GridRect(x:8,y:3,w:4,h:5))
            let resized = geometry.target(origin:origin,dx:10000,dy:10000,resizing:true,minimumColumns:4,minimumRows:5)
            assert(resized == GridRect(x:1,y:1,w:11,h:7),"Resize clamps at canvas edges")
            let minimum = geometry.target(origin:origin,dx:-10000,dy:-10000,resizing:true,minimumColumns:4,minimumRows:5)
            assert(minimum == origin)
            let pointerSize = geometry.preview(origin:origin,dx:5,dy:7,resizing:true,minimumColumns:4,minimumRows:5)
            assert(abs(pointerSize.width-before.width-5) < 0.001 && abs(pointerSize.height-before.height-7) < 0.001)
        }

        let earlier = Date(timeIntervalSince1970:100), later = earlier.addingTimeInterval(1)
        assert(UndoOrder.latest(layout:earlier,completion:later,edit:nil) == "completion")
        assert(UndoOrder.latest(layout:later,completion:earlier,edit:nil) == "layout")
        assert(UndoOrder.latest(layout:earlier,completion:nil,edit:later) == "edit")
        assert(UndoOrder.latest(layout:nil,completion:nil,edit:nil) == nil)
        assert(UndoOrder.latest(layout:earlier,completion:earlier,edit:nil,email:later) == "email")
        assert(UndoOrder.latest(layout:later,completion:nil,edit:nil,discovery:earlier) == "layout")
        assert(UndoOrder.latest(layout:nil,completion:earlier,edit:nil,question:later) == "question")
        assert(UndoOrder.latest(layout:nil,completion:nil,edit:nil,discovery:later) == "discovery")
        let hidden = ToolbarRules.setting(.date,visible:false,hidden:"future-control")
        assert(!ToolbarRules.visible(.date,hidden:hidden) && ToolbarRules.visible(.refresh,hidden:hidden))
        assert(ToolbarRules.setting(.date,visible:true,hidden:hidden) == "future-control")
        var clock = WidgetConfiguration(); clock.clockShowsTime = false; clock.clockShowsSeconds = true
        let clockData = try JSONEncoder().encode(clock), restoredClock = try JSONDecoder().decode(WidgetConfiguration.self,from:clockData)
        assert(restoredClock.clockShowsTime == false && restoredClock.clockShowsSeconds == true)
        assert(WidgetKind.clock.minimumRows == 2 && WidgetKind.clock.minimumColumns == 3)
        print("PASS: fixed viewport geometry, continuous previews, workspace persistence, clock preferences, toolbar preservation and latest-supported Undo ordering")
    }
}
