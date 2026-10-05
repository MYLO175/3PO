import Foundation
import SwiftData

@main struct Checks {
    @MainActor static func main() throws {
        let container = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LifeWorkspaceStore(container: container)
        func rejects(_ body: () throws -> Void) { var rejected = false; do { try body() } catch { rejected = true }; precondition(rejected) }
        let root = try store.save(LifeItem(registration: "fictional-a", kind: .organisation, title: "Example university"), expected: nil)
        let course = try store.save(LifeItem(registration: "fictional-a", kind: .course, title: "Engineering", parentID: root.id), expected: nil)
        let task = try store.save(LifeItem(registration: "fictional-a", kind: .task, title: "Read paper", parentID: course.id, due: "2026-10-10", estimateMinutes: 45), expected: nil)
        precondition(LifeWorkspaceRules.descendants(root.id, in: store.state.items) == [course.id, task.id])
        let reloaded = LifeWorkspaceStore(container: container)
        precondition(reloaded.state == store.state && reloaded.items("fictional-b").isEmpty)
        var moved = root; moved.parentID = task.id
        rejects { _ = try store.save(moved, expected: root.revision) }
        precondition(store.state == reloaded.state, "Cycle rejection is atomic")
        var other = LifeItem(registration: "fictional-b", kind: .project, title: "Private project", parentID: root.id)
        rejects { _ = try store.save(other, expected: nil) }; other.parentID = nil; _ = try store.save(other, expected: nil)
        let scoped = LifeItem(registration: "fictional-a", conversationID: UUID(), kind: .project, title: "Legacy scope")
        _ = try store.save(scoped, expected: nil)
        precondition(!store.items("fictional-a").contains(where: { $0.id == scoped.id }))
        precondition(store.items("fictional-a", includeTopics: true).contains(where: { $0.id == scoped.id }))
        var revised = task; revised.title = "Read two papers"; revised.status = .active
        let saved = try store.save(revised, expected: task.revision)
        rejects { _ = try store.save(revised, expected: task.revision) }
        precondition(saved.id == task.id && saved.revision != task.revision)
        precondition(store.undoDate("fictional-a") != nil && store.undoDate("fictional-b") == nil)
        precondition(LifeItemQuery(root: course.id, query: "Engineering", unfinished: true, dueBefore: "2026-10-12", maxMinutes: 60).matching(store.items("fictional-a")).map(\.id) == [task.id])
        precondition(LifeItemQuery(root: course.id, query: "", dueBefore: "2026-10-09").matching(store.items("fictional-a")).isEmpty)
        precondition(LifeItemQuery.path(saved, in: store.items("fictional-a")).map(\.id) == [root.id, course.id, task.id])
        var bad = saved; bad.due = "2026-02-30"; rejects { _ = try store.save(bad, expected: saved.revision) }
        bad.due = "2026-10-10T10:00:00Z"; rejects { _ = try store.save(bad, expected: saved.revision) }
        precondition(LifeWorkspaceRules.dateValid("2028-02-29") && !LifeWorkspaceRules.dateValid("2026-2-1"))
        let dependency = LifeItemLink(registration: "fictional-a", from: course.id, relation: .dependsOn, target: .init(kind: .item, id: saved.id.uuidString))
        _ = try store.link(dependency, expected: course.revision)
        rejects { _ = try store.link(.init(registration: "fictional-a", from: saved.id, relation: .dependsOn, target: .init(kind: .item, id: course.id.uuidString)), expected: saved.revision) }
        rejects { _ = try store.link(.init(registration: "fictional-a", from: root.id, relation: .partOf, target: .init(kind: .item, id: saved.id.uuidString)), expected: root.revision) }
        rejects { _ = try store.link(.init(registration: "fictional-a", from: course.id, relation: .related, target: .init(kind: .item, id: other.id.uuidString)), expected: course.revision) }
        let missing = LifeWorkspaceStore(container: nil); rejects { _ = try missing.save(root, expected: nil) }; precondition(missing.state.items.isEmpty)
        let batchParent = LifeItem(registration: "fictional-a", kind: .project, title: "Batch project")
        let batchChild = LifeItem(registration: "fictional-a", kind: .section, title: "Research", parentID: batchParent.id)
        let receipt = LifeWorkspaceReceipt(id: "fictional-operation", registration: "fictional-a", result: "Created two items", itemID: batchParent.id)
        _ = try store.create([batchParent, batchChild], receipt: receipt)
        let count = store.state.items.count
        rejects { _ = try store.create([batchParent, batchChild], receipt: receipt) }
        precondition(store.state.items.count == count && LifeWorkspaceStore(container: container).receipt(receipt.id, registration: "fictional-a") != nil)
        let invalidChild = LifeItem(registration: "fictional-a", kind: .task, title: "Bad child", parentID: UUID())
        rejects { _ = try store.create([LifeItem(registration: "fictional-a", kind: .project, title: "Should not remain"), invalidChild], receipt: .init(id: "invalid", registration: "fictional-a", result: "", itemID: nil)) }
        precondition(store.state.items.count == count, "Invalid batch saves nothing")
        let stale = store.revision
        _ = try store.save(LifeItem(registration: "fictional-a", kind: .resource, title: "Reference"), expected: nil)
        rejects { try store.unlink(dependency.id, registration: "fictional-a", expectedRevision: stale) }
        try store.unlink(dependency.id, registration: "fictional-a", expectedRevision: store.revision)
        precondition(!store.state.links.contains(where: { $0.id == dependency.id }))
        var renamed = saved; renamed.title = "Changed for Undo"
        _ = try store.save(renamed, expected:saved.revision)
        try store.undo("fictional-a")
        precondition(store.state.items.first(where: { $0.id == saved.id })?.title == saved.title && store.undoDate("fictional-a") == nil)
        rejects { try store.undo("fictional-a") }
        precondition(LifeWorkspaceStore(container:container).undoDate("fictional-a") == nil, "Project Undo is session-only")
        // Corrupt/unsupported storage stays intact and cannot be replaced by an empty state.
        let broken = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let bytes = Data("{\"version\":99,\"items\":[],\"links\":[],\"receipts\":[]}".utf8)
        broken.mainContext.insert(CachedDashboard(key: "lifeWorkspace", data: bytes)); try broken.mainContext.save()
        let unavailable = LifeWorkspaceStore(container: broken)
        rejects { _ = try unavailable.save(root, expected: nil) }
        let preserved = try broken.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first!.data
        precondition(preserved == bytes)
        print("PASS: project persistence, identity, scope, dates, optimistic edits, hierarchy/dependency cycles, atomic batches, saved receipts and corrupt-store preservation")
    }
}
