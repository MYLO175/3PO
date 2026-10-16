import Foundation
import SwiftData

@main struct LocalRecordChecks {
    @MainActor static func main() throws {
        if let index=CommandLine.arguments.firstIndex(of:"--lease-probe"),CommandLine.arguments.indices.contains(index+1) {
            do { let lease=try LocalRecordFileLease(url:URL(fileURLWithPath:CommandLine.arguments[index+1]));withExtendedLifetime(lease) {};exit(0) }
            catch {exit(23)}
        }
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
        // The expected bytes are compared under the write lease; a stale owner
        // cannot erase a later transaction, including an absent->present race.
        let captured=try records.read("action")
        try records.write(["action":revised],expected:["action":LocalRecordVersion(captured)])
        do { try reopened.write(["action":original,"must-not-save":original],expected:["action":LocalRecordVersion(captured)]);fatalError("Stale write accepted") }
        catch LocalRecordFailure.changed {}
        try check(records.read("action") == revised && records.read("must-not-save") == nil)
        try records.write(["claimed":original],expected:["claimed":.missing])
        do {try reopened.write(["claimed":revised],expected:["claimed":.missing]);fatalError("Duplicate claim accepted")}
        catch LocalRecordFailure.changed {}
        let lockURL=directory.appendingPathComponent("process.lock")
        var lease:LocalRecordFileLease?=try LocalRecordFileLease(url:lockURL)
        func probe()->Int32 {
            let child=Process();child.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]);child.arguments=["--lease-probe",lockURL.path]
            do {try child.run();child.waitUntilExit();return child.terminationStatus} catch {fatalError("Probe failed")}
        }
        check(probe() == 23,"A second process cannot acquire the personal-store lease")
        withExtendedLifetime(lease) {};lease=nil
        check(probe() == 0,"Exit/release permits a subsequent owner without deleting the lock inode")
        print("Local record checks passed: failed updates/inserts/deletes, later save and reopen, atomic related records, other-owner isolation and unreadable legacy preservation.")
    }
}
