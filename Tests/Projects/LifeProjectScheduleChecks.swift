import Foundation
import SwiftData

/// Typed deadline phrases, relative wording, project-only Due soon and board moves
/// for tasks gathered from subprojects, all on fictional data at a fixed date.
enum LifeProjectScheduleChecks {
    @MainActor static func run() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12))! // a Thursday
        func parse(_ text: String) -> (String, String?) { let value = LifeDueParser.parse(text, now: now, calendar: calendar); return (value.title, value.due) }
        let cases: [(String, String, String?)] = [
            ("Lab report fri", "Lab report", "2026-10-30"),
            ("Essay thursday", "Essay", "2026-11-05"),
            ("Read paper tomorrow", "Read paper", "2026-10-30"),
            ("Call the lab today", "Call the lab", "2026-10-29"),
            ("Draft next week", "Draft", "2026-11-05"),
            ("Revise in 3 days", "Revise", "2026-11-01"),
            ("Revise in 2 weeks", "Revise", "2026-11-12"),
            ("Submit by 14 nov", "Submit", "2026-11-14"),
            ("Submit Nov 14", "Submit", "2026-11-14"),
            ("Pay rent 1/10", "Pay rent", "2027-10-01"),
            ("Meet on next mon", "Meet", "2026-11-02"),
            ("Fri", "Fri", nil),
            ("Buy 3 apples", "Buy 3 apples", nil),
            ("Book 31 feb", "Book 31 feb", nil),
            ("Plan may", "Plan may", nil),
        ]
        for (text, title, due) in cases {
            let value = parse(text)
            precondition(value.0 == title && value.1 == due, "Parsed \(text) as \(value)")
        }
        let labels: [(String, String, LifeDueUrgency)] = [
            ("2026-10-27", "2 days late", .late), ("2026-10-28", "1 day late", .late), ("2026-10-29", "Today", .soon),
            ("2026-10-30", "Tomorrow", .soon), ("2026-11-01", "Sun", .soon), ("2026-11-02", "Mon", .later),
            ("2026-11-12", "12 Nov", .later), ("2027-01-05", "5 Jan 2027", .later)
        ]
        for (due, text, urgency) in labels {
            let value = LifeDue.label(due, now: now, calendar: calendar)
            precondition(value?.text == text && value?.urgency == urgency, "Labelled \(due) as \(String(describing: value))")
        }
        precondition(LifeDue.label("2026-02-30", now: now, calendar: calendar) == nil && LifeDue.date("26-10-29", calendar: calendar) == nil, "Invalid dates have no label")

        let registration = "fictional-schedule"
        let root = LifeItem(registration: registration, kind: .space, title: "Final-year project")
        let nested = LifeItem(registration: registration, kind: .space, title: "Experiments", parentID: root.id)
        let other = LifeItem(registration: registration, kind: .space, title: "Moving out")
        let late = LifeItem(registration: registration, kind: .task, title: "Outline", parentID: root.id, due: "2026-10-27")
        let deep = LifeItem(registration: registration, kind: .task, title: "Wire the rig", parentID: nested.id, status: .active, due: "2026-11-04")
        let undated = LifeItem(registration: registration, kind: .task, title: "Order sensors", parentID: nested.id, status: .waiting)
        let finished = LifeItem(registration: registration, kind: .task, title: "Risk assessment", parentID: nested.id, status: .done, due: "2026-10-20")
        let archived = LifeItem(registration: registration, kind: .task, title: "Old rig", parentID: nested.id, status: .archived, due: "2026-10-30")
        let distant = LifeItem(registration: registration, kind: .task, title: "Book a van", parentID: other.id, due: "2026-11-20")
        let index = LifeProjectIndex([root, nested, other, late, deep, undated, finished, archived, distant])
        precondition(index.tasks(under: root.id).map(\.id) == [deep.id, undated.id, finished.id, late.id], "Subtree tasks follow the outline order and leave out archived work")
        precondition(index.tasks(under: nil).count == 5 && index.open(under: root.id).count == 3)
        precondition(index.lateCount(under: root.id, now: now) == 1 && index.lateCount(under: other.id, now: now) == 0)
        precondition(index.nextDue(under: root.id)?.id == late.id && index.nextDue(under: nested.id)?.id == deep.id, "Late work counts as the next deadline")
        precondition(index.dueSoon(under: nil, now: now).map(\.id) == [late.id, deep.id], "Due soon is unfinished project work that is late or due within two weeks")
        precondition(LifeDue.ordered([undated, deep, late]).map(\.id) == [late.id, deep.id, undated.id])

        let container = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LifeWorkspaceStore(container: container)
        _ = try store.create([root, nested, late, deep], receipt: .init(id: "schedule-board", registration: registration, result: "Fictional board", itemID: root.id))
        func rejects(_ body: () throws -> Void) { var rejected = false; do { try body() } catch { rejected = true }; precondition(rejected) }
        rejects { try LifeTaskStageChange.applyDrag(deep.id, stage: .done, taskParent: root.id, capturedParent: root.id, currentParent: root.id, registration: registration, activeRegistration: registration, capturedIDs: [deep.id], currentIDs: [deep.id], expectedRevision: store.revision, store: store) }
        rejects { try LifeTaskStageChange.applyDrag(deep.id, stage: .done, taskParent: nested.id, capturedParent: root.id, currentParent: nested.id, registration: registration, activeRegistration: registration, capturedIDs: [deep.id], currentIDs: [deep.id], expectedRevision: store.revision, store: store) }
        try LifeTaskStageChange.applyDrag(deep.id, stage: .done, taskParent: nested.id, capturedParent: root.id, currentParent: root.id, registration: registration, activeRegistration: registration, capturedIDs: [deep.id], currentIDs: [deep.id], expectedRevision: store.revision, store: store)
        precondition(store.items(registration).first { $0.id == deep.id }?.status == .done, "A subproject task moves on its parent's board at its own captured folder")
        print("PASS: deadline phrases and invalid dates; relative wording; subtree tasks, late counts, next deadline and Due soon; subproject board moves keep page and task-folder guards")
    }
}
