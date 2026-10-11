import Foundation
import SwiftData

@main struct LocalRecordChecks {
    @MainActor static func main() throws {
        enum Injected: Error { case failed }
        func check(_ value: Bool, _ message: String = "Storage contract failed") { precondition(value, message) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("3po-storage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fictional.store")
        func open() throws -> ModelContainer {
            try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        }
        let container = try open(), records = LocalRecordRepository(container: container)
        let original = Data("original receipt".utf8), revised = Data("pending receipt".utf8)
        try records.write(["action": original, "sources": original, "cursor": original, "legacy": Data([0,1,2])])
        let unrelated = CachedDashboard(key: "other-owner", data: original)
        container.mainContext.insert(unrelated)
        let failing = LocalRecordRepository(container: container) { _ in throw Injected.failed }
        do { try failing.write(["action": revised, "new-action": revised, "cursor": revised], removing: ["legacy"]); fatalError("Expected injected failure") }
        catch Injected.failed { }
        try check(records.read("action") == original)
        try check(records.read("new-action") == nil)
        try check(records.read("cursor") == original)
        try check(records.read("legacy") == Data([0,1,2]))
        precondition(container.mainContext.hasChanges, "Other owner must retain unsaved work")
        try check(records.read("other-owner") == nil, "Save must not commit another owner")
        try container.mainContext.save()
        try records.write(["unrelated-later-save": revised])
        let reopened = LocalRecordRepository(container: try open())
        try check(reopened.read("action") == original)
        try check(reopened.read("new-action") == nil, "Later saves cannot resurrect failed claims")
        try check(reopened.read("other-owner") == original)
        try records.write(["sources": revised, "cursor": revised], removing: ["unrelated-later-save"])
        try check(reopened.read("sources") == revised && reopened.read("cursor") == revised)
        try check(reopened.read("unrelated-later-save") == nil)
        do { let _: [String] = try records.decode("legacy")!; fatalError("Expected unreadable original") }
        catch is DecodingError { }
        try check(records.read("legacy") == Data([0,1,2]), "Decode must preserve unreadable original")
        print("Local record checks passed: failed updates/inserts/deletes, later save and reopen, atomic related records, other-owner isolation and unreadable legacy preservation.")
    }
}
