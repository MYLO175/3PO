#if DEBUG
import SwiftUI

/// In-memory fictional data for the Projects design lab. Mirrors the real shape
/// (projects nest through `parent`, tasks belong to one project) without touching LifeWorkspaceStore.
struct LabProject: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var icon: String
    var parent: UUID?
}
struct LabTask: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var project: UUID
    var stage: LifeTaskStage
    var due: Date?
    var waiting: String? = nil
    var finished: Date? = nil
}
struct LabNote: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var body: String
}
struct LabGroup { let title: String; let tasks: [LabTask] }

@MainActor @Observable final class LabStore {
    var projects: [LabProject]
    var tasks: [LabTask]
    var notes: [UUID:[LabNote]]
    init(projects: [LabProject], tasks: [LabTask], notes: [UUID:[LabNote]]) { self.projects = projects; self.tasks = tasks; self.notes = notes }

    func project(_ id: UUID) -> LabProject? { projects.first { $0.id == id } }
    func children(of id: UUID?) -> [LabProject] { projects.filter { $0.parent == id } }
    func subtree(_ id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id], frontier = [id]
        while let next = frontier.popLast() { for child in children(of:next) where result.insert(child.id).inserted { frontier.append(child.id) } }
        return result
    }
    /// Every project in outline order, optionally starting at one project.
    func flattened(under id: UUID?) -> [LabProject] {
        var result: [LabProject] = []
        func visit(_ parent: UUID?) { for child in children(of:parent) { result.append(child); visit(child.id) } }
        if let id, let root = project(id) { result.append(root) }
        visit(id); return result
    }
    func tasks(under id: UUID?, deep: Bool = true) -> [LabTask] {
        guard let id else { return tasks }
        if !deep { return tasks.filter { $0.project == id } }
        let ids = subtree(id)
        return tasks.filter { ids.contains($0.project) }
    }
    func progress(_ id: UUID?) -> [Int] {
        let list = tasks(under:id)
        return LifeTaskStage.allCases.map { stage in list.filter { $0.stage == stage }.count }
    }
    func open(under id: UUID?) -> [LabTask] { tasks(under:id).filter { $0.stage != .done }.sorted(by:Self.byDue) }
    func nextDue(_ id: UUID) -> LabTask? { open(under:id).first { $0.due != nil } }
    func lateCount(_ id: UUID?) -> Int { open(under:id).filter { $0.due.map { LabDue.days($0) < 0 } ?? false }.count }
    func path(_ id: UUID?) -> [LabProject] {
        var result: [LabProject] = [], cursor = id
        while let current = cursor, let item = project(current) { result.insert(item,at:0); cursor = item.parent }
        return result
    }
    /// Where a task sits below `scope`, for labelling tasks gathered from subprojects.
    func place(_ task: LabTask, from scope: UUID?) -> String? {
        let full = path(task.project)
        let start = scope.flatMap { id in full.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0
        let rest = full.dropFirst(start)
        return rest.isEmpty ? nil : rest.map(\.title).joined(separator:" › ")
    }
    func toggle(_ id: UUID) { guard let task = tasks.first(where:{ $0.id == id }) else { return }; setStage(id,task.stage == .done ? .todo : .done) }
    func setStage(_ id: UUID, _ stage: LifeTaskStage) {
        guard let index = tasks.firstIndex(where:{ $0.id == id }) else { return }
        tasks[index].stage = stage; tasks[index].finished = stage == .done ? .now : nil
        if stage != .todo { tasks[index].waiting = nil }
    }
    func add(_ title: String, due: Date?, project: UUID, stage: LifeTaskStage = .todo) { tasks.append(LabTask(title:title,project:project,stage:stage,due:due)) }

    static func byDue(_ a: LabTask, _ b: LabTask) -> Bool {
        switch (a.due,b.due) {
        case let (x?,y?): return x == y ? a.title < b.title : x < y
        case (.some,nil): return true
        case (nil,.some): return false
        default: return a.title < b.title
        }
    }
    static func timeGroups(_ open: [LabTask], horizon: Int? = nil) -> [LabGroup] {
        var late: [LabTask] = [], week: [LabTask] = [], next: [LabTask] = [], later: [LabTask] = [], undated: [LabTask] = []
        for task in open {
            guard let due = task.due else { undated.append(task); continue }
            let days = LabDue.days(due)
            if days < 0 { late.append(task) } else if days < 7 { week.append(task) } else if days < 14 { next.append(task) } else { later.append(task) }
        }
        let all = [LabGroup(title:"Late",tasks:late),LabGroup(title:"This week",tasks:week),LabGroup(title:"Next week",tasks:next),LabGroup(title:"Later",tasks:later),LabGroup(title:"No date",tasks:undated)]
        return (horizon == nil ? all : Array(all.prefix(3))).filter { !$0.tasks.isEmpty }
    }

    static func sample() -> LabStore {
        var projects: [LabProject] = [], tasks: [LabTask] = [], notes: [UUID:[LabNote]] = [:]
        func project(_ title: String, _ icon: String, in parent: UUID? = nil) -> UUID {
            let value = LabProject(title:title,icon:icon,parent:parent); projects.append(value); return value.id
        }
        func task(_ title: String, _ project: UUID, _ stage: LifeTaskStage = .todo, due: Int? = nil, waiting: String? = nil, finished: Int? = nil) {
            tasks.append(LabTask(title:title,project:project,stage:stage,due:due.map(LabDue.day),waiting:waiting,finished:finished.map(LabDue.day)))
        }
        let fyp = project("Final-year project","flask")
        let literature = project("Literature review","books.vertical",in:fyp)
        let experiments = project("Experiments","waveform.path.ecg",in:fyp)
        let writeUp = project("Write-up","doc.text",in:fyp)
        task("Interim report outline",fyp,due:-2)
        task("Book lab time",fyp,.inProgress,due:3)
        task("Prepare for supervisor meeting",fyp,due:5)
        task("Read the baseline paper",literature,.done,finished:-6)
        task("Summarise five related papers",literature,.inProgress,due:1)
        task("Draft the literature review",literature,due:9)
        task("Order sensors",experiments,waiting:"supervisor approval")
        task("Wire the test rig",experiments,.inProgress,due:6)
        task("Pilot measurement",experiments,due:13)
        task("Risk assessment",experiments,.done,finished:-9)
        task("Set up the report template",writeUp,.done,finished:-3)
        task("Methods chapter draft",writeUp,due:24)
        notes[fyp] = [
            LabNote(title:"Supervisor meeting · Tuesday",body:"Narrow the scope to two sensors.\nSend the interim outline by Wednesday.\nAsk about booking the lab for the pilot."),
            LabNote(title:"Ideas",body:"Compare against last year's baseline.\nAdd a cost table to the write-up.")
        ]
        notes[experiments] = [LabNote(title:"Rig checklist",body:"Calibrate before every run.\nLog room temperature.")]

        let signals = project("Signals and systems","waveform")
        let coursework = project("Coursework","pencil.and.ruler",in:signals)
        let revision = project("Revision","brain",in:signals)
        task("Problem sheet 4",signals,.inProgress,due:0)
        task("Problem sheet 5",signals,due:7)
        task("Problem sheet 3",signals,.done,finished:-5)
        task("Simulate the filter",coursework,.inProgress,due:4)
        task("Coursework 1 report",coursework,due:11)
        task("Collect the coursework data",coursework,.done,finished:-4)
        task("Past paper 2024",revision)
        task("Summary sheet, chapters 1–3",revision)
        task("Lecture 6 notes",revision,.done,finished:-1)
        notes[signals] = [LabNote(title:"Exam tips",body:"Past papers from 2021 onwards match the current syllabus.")]

        let thermo = project("Thermodynamics","flame")
        task("Coursework 1",thermo,due:4)
        task("Lab write-up",thermo,due:11)
        task("Tutorial sheet 3",thermo,.done,finished:-2)
        task("Revision plan",thermo)

        let applications = project("Graduate applications","briefcase")
        let northwind = project("Northwind Robotics","building.2",in:applications)
        let example = project("Example Engineering","building.2",in:applications)
        task("Cover letter",northwind,.inProgress,due:2)
        task("Online test",northwind,due:13)
        task("Application form",northwind,.done,finished:-5)
        task("First-round interview",example,waiting:"their reply")
        task("Research the team",example,due:16)
        notes[applications] = [LabNote(title:"Talking points",body:"Sensor project, society treasurer, summer placement.")]

        let moving = project("Moving out","shippingbox")
        task("Book a van",moving,due:20)
        task("Deposit return",moving,waiting:"the landlord")
        task("Cancel broadband",moving,.done,finished:-8)
        return LabStore(projects:projects,tasks:tasks,notes:notes)
    }
}

enum LabUrgency {
    case late, soon, later
    var color: Color { switch self { case .late: .red; case .soon: .orange; case .later: .secondary } }
}
enum LabDue {
    static func day(_ offset: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding:.day,value:offset,to:calendar.startOfDay(for:.now)) ?? .now
    }
    static func days(_ due: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day],from:calendar.startOfDay(for:.now),to:calendar.startOfDay(for:due)).day ?? 0
    }
    /// Relative wording: "2 days late", "Today", "Tomorrow", "Fri", then "14 Nov".
    static func label(_ due: Date) -> (text: String, urgency: LabUrgency) {
        let n = days(due)
        switch n {
        case ..<(-1): return ("\(-n) days late",.late)
        case -1: return ("1 day late",.late)
        case 0: return ("Today",.soon)
        case 1: return ("Tomorrow",.soon)
        case 2...6: return (due.formatted(.dateTime.weekday(.abbreviated)),n <= 3 ? .soon : .later)
        default: return (due.formatted(.dateTime.day().month(.abbreviated)),.later)
        }
    }
}

/// Reads a trailing date phrase off a typed task: "today", "tomorrow", "fri", "next week",
/// "in 3 days", "14 nov", "nov 14" or "14/11". Local only; no AI.
enum LabDueParser {
    private static let weekdays: [String:Int] = ["sun":1,"sunday":1,"mon":2,"monday":2,"tue":3,"tues":3,"tuesday":3,"wed":4,"weds":4,"wednesday":4,"thu":5,"thur":5,"thurs":5,"thursday":5,"fri":6,"friday":6,"sat":7,"saturday":7]
    private static let months = ["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"]
    static func parse(_ text: String, now: Date = .now) -> (title: String, due: Date?) {
        let calendar = Calendar.current, today = calendar.startOfDay(for:now)
        var words = text.split(separator:" ").map(String.init)
        let lower = words.map { $0.lowercased().trimmingCharacters(in:.punctuationCharacters) }, n = lower.count
        func day(_ offset: Int) -> Date { calendar.date(byAdding:.day,value:offset,to:today) ?? today }
        func month(_ word: String) -> Int? { word.count >= 3 && word.count <= 9 ? months.firstIndex { word.hasPrefix($0) }.map { $0 + 1 } : nil }
        func date(_ day: Int, _ month: Int) -> Date? {
            var parts = calendar.dateComponents([.year],from:today); parts.month = month; parts.day = day
            guard (1...12).contains(month), (1...31).contains(day), let value = calendar.date(from:parts), calendar.component(.day,from:value) == day else { return nil }
            return value < today ? calendar.date(byAdding:.year,value:1,to:value) : value
        }
        var match: (count: Int, due: Date)?
        if let last = lower.last {
            let slash = last.split(separator:"/")
            if ["today","tonight"].contains(last) { match = (1,day(0)) }
            else if ["tomorrow","tmrw","tmr"].contains(last) { match = (1,day(1)) }
            else if n >= 2, lower[n-2] == "next", last == "week" { match = (2,day(7)) }
            else if n >= 3, lower[n-3] == "in", let amount = Int(lower[n-2]), (1...365).contains(amount), last.hasPrefix("day") || last.hasPrefix("week") {
                match = (3,day(last.hasPrefix("week") ? amount * 7 : amount))
            }
            else if let weekday = weekdays[last] {
                var offset = (weekday - calendar.component(.weekday,from:today) + 7) % 7
                if offset == 0 { offset = 7 }
                match = (n >= 2 && lower[n-2] == "next" ? 2 : 1,day(offset))
            }
            else if n >= 2, let d = Int(lower[n-2]), let m = month(last), let value = date(d,m) { match = (2,value) }
            else if n >= 2, let m = month(lower[n-2]), let d = Int(last), let value = date(d,m) { match = (2,value) }
            else if slash.count == 2, let d = Int(slash[0]), let m = Int(slash[1]), let value = date(d,m) { match = (1,value) }
        }
        guard let match, match.count < n else { return (text.trimmingCharacters(in:.whitespaces),nil) }
        words.removeLast(match.count)
        while words.count > 1, let last = words.last?.lowercased(), ["by","on","due"].contains(last) { words.removeLast() }
        return (words.joined(separator:" "),match.due)
    }
}
#endif
