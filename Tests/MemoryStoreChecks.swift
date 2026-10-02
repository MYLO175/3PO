import Foundation
import SwiftData
@main struct Checks {
    @MainActor static func main() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly:true)
        let container = try ModelContainer(for:CachedDashboard.self,configurations:configuration)
        let store = PAMemoryStore(container:container)
        let learned = LearnedMemory(turnID:"one",text:"Needs two weeks notice",kind:.preference,evidence:"I need two weeks notice")
        let messageDate = Date(timeIntervalSince1970:1_790_000_000)
        precondition(store.merge([learned],registration:"account",sourceDates:["one":messageDate]))
        precondition(store.records.count == 1 && store.records[0].explicit == false && store.records[0].sourceTurnID == "one")
        precondition(store.records[0].sourceDate == messageDate && store.records[0].evidence == learned.evidence)
        var duplicate = learned; duplicate.text = "NEEDS  TWO WEEKS NOTICE"
        precondition(store.merge([duplicate],registration:"account") && store.records.count == 1)
        let saved = store.records[0]
        precondition(store.accept(saved.id) && store.records[0].explicit)
        let reload = PAMemoryStore(container:container)
        precondition(reload.records[0].explicit && reload.records[0].sourceDate == messageDate)
        precondition(reload.forget(saved.id) && reload.records.isEmpty && reload.suppressed("account") == ["one"])
        let forgotten = PAMemoryStore(container:container)
        precondition(forgotten.records.isEmpty && forgotten.suppressed("account") == ["one"])
        precondition(forgotten.merge([learned],registration:"account") && forgotten.records.isEmpty)
        precondition(forgotten.put(saved) && forgotten.records.count == 1)
        precondition(forgotten.resolve(saved.id) && forgotten.context("account").isEmpty)
        precondition(forgotten.reopen(saved.id) && forgotten.context("account").count == 1)
        let undated = LearnedMemory(turnID:"legacy",text:"Uses a separate project list",kind:.context,evidence:"I use a separate project list")
        precondition(forgotten.merge([undated],registration:"account"))
        precondition(forgotten.records.first(where:{ $0.sourceTurnID == "legacy" })?.sourceDate == nil)
        let unavailable = PAMemoryStore(container:nil)
        precondition(!unavailable.put(saved) && unavailable.records.isEmpty)
        let topic = UUID(), otherTopic = UUID()
        let topicEntry = PAMemory(registration:"scope-account",text:"My fictional study project is optics",kind:.context,provenance:"Test",conversationID:topic)
        let sharedEntry = PAMemory(registration:"scope-account",text:"I prefer short answers",kind:.preference,provenance:"Test")
        precondition(store.put(topicEntry) && store.put(sharedEntry))
        precondition(store.context("scope-account").count == 1)
        precondition(store.context("scope-account",conversationID:topic).count == 2)
        precondition(store.context("scope-account",conversationID:otherTopic).count == 1)
        precondition(store.context("scope-account",includeTopics:true).count == 2)
        print("PASS: atomic learned merge/dedup, confirmation, reload, Forget suppression across reload, Undo restore, resolve/reopen and unavailable storage")
    }
}
