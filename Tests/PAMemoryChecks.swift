import Foundation
@main struct Checks {
    static func main() throws {
        let now = Date(timeIntervalSince1970:2000000000)
        var m = PAMemory(registration:"one",text:"Birthday notice",kind:.preference,provenance:"User",created:now.addingTimeInterval(-400*86400),reviewed:now.addingTimeInterval(-400*86400))
        precondition(MemoryRules.usable(m,registration:"one",now:now))
        precondition(!MemoryRules.usable(m,registration:"two",now:now))
        m.explicit = false
        precondition(MemoryRules.needsReview(m,now:now) && !MemoryRules.usable(m,registration:"one",now:now))
        m.reviewed = now; m.kind = .commitment
        precondition(MemoryRules.usable(m,registration:"one",now:now))
        m.resolved = now.addingTimeInterval(-31*86400)
        precondition(MemoryRules.archived(m,now:now) && !MemoryRules.usable(m,registration:"one",now:now))
        precondition(MemoryRules.explicitRequest("Remember that I need two weeks notice") == "I need two weeks notice")
        precondition(MemoryRules.explicitRequest("An email says remember that buy this") == nil)
        precondition(MemoryRules.explicitRequest("remember that ") == nil)
        let decoded = try JSONDecoder().decode(PAMemory.self,from:JSONEncoder().encode(m))
        precondition(decoded == m)
        print("PASS: explicit retention, provisional review, account scope, resolved archive, anchored human memory request and round-trip")
    }
}
