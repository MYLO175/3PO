import Foundation
@main struct Checks {
    static func main() throws {
        let now = Date(timeIntervalSince1970:2000000000)
        let turns = (0..<20).map { MemoryLearningTurn(id:String($0),text:"I prefer at least two weeks of advance notice.",created:now.addingTimeInterval(Double($0))) }
        let progress = MemoryLearningRules.progress(turns:turns.reversed(),prior:nil,suppressed:[],day:"day")
        precondition(progress.skippedAtOrientation == 12)
        let batch = MemoryLearningRules.batch(turns.reversed(),seen:progress.seen,suppressed:[])
        precondition(batch.map(\.id) == (12..<20).map(String.init))
        var next = progress; next.seen.formUnion(batch.map(\.id))
        precondition(MemoryLearningRules.batch(turns,seen:next.seen,suppressed:[]).isEmpty)
        precondition(MemoryLearningRules.batch(turns,seen:progress.seen,suppressed:["19"]).count == 7)
        var unknown = turns[0]; unknown.dateKnown = false
        let input = try MemoryLearningRules.input(turns:[unknown],existing:[],timezone:"Europe/London")
        precondition(input.contains("unknown") && input.contains("dateKnown"))
        let good = "{\"memories\":[{\"turnID\":\"12\",\"text\":\"Prefers two weeks of advance notice.\",\"kind\":\"preference\",\"evidence\":\"two weeks of advance notice\"}]}"
        let valid = try MemoryLearningRules.decode(good,turns:batch); precondition(valid.count == 1)
        func encode(_ values: [LearnedMemory]) throws -> String {
            String(data:try JSONSerialization.data(withJSONObject:["memories":values.map { ["turnID":$0.turnID,"text":$0.text,"kind":$0.kind.rawValue,"evidence":$0.evidence] }]),encoding:.utf8)!
        }
        let excessive = try encode((12..<17).map { LearnedMemory(turnID:String($0),text:"Supported",kind:.preference,evidence:"two weeks of advance notice") })
        let duplicate = try encode([valid[0],valid[0]])
        var long = valid[0]; long.text = String(repeating:"x",count:501)
        for bad in [good.replacingOccurrences(of:"\"12\"",with:"\"999\""),good.replacingOccurrences(of:"two weeks of advance notice\"",with:"invented evidence\""),good.replacingOccurrences(of:"\"preference\"",with:"\"execute\""),excessive,duplicate,try encode([long])] {
            do { _ = try MemoryLearningRules.decode(bad,turns:batch); fatalError("Accepted invalid model data") } catch {}
        }
        let empty = try MemoryLearningRules.decode("{\"memories\":[]}",turns:batch); precondition(empty.isEmpty)
        next.lastAttempt = now; precondition(!MemoryLearningRules.allowed(next,now:now,manual:false))
        next.lastAttempt = now.addingTimeInterval(-901); next.attempts = 4
        precondition(!MemoryLearningRules.allowed(next,now:now,manual:false)); precondition(MemoryLearningRules.allowed(next,now:now,manual:true))
        let tomorrow = MemoryLearningRules.progress(turns:turns,prior:next,suppressed:[],day:"tomorrow")
        precondition(tomorrow.attempts == 0 && tomorrow.seen == next.seen)
        next.paused = true; next.attempts = 0
        precondition(!MemoryLearningRules.allowed(next,now:now,manual:false))
        let memory = PAMemory(registration:"one",text:"Existing explicit",kind:.preference,provenance:"User")
        let old = try MemoryEnvelope.decode(JSONEncoder().encode([memory]))
        precondition(old.records[0].explicit && old.suppressed.isEmpty)
        var envelope = old; envelope.suppressed["one"] = ["12"]
        let restored = try MemoryEnvelope.decode(JSONEncoder().encode(envelope))
        precondition(restored.suppressed["one"] == ["12"] && restored.records.count == 1)
        do { _ = try MemoryEnvelope.decode(Data("{\"version\":99,\"records\":[],\"suppressed\":{}}".utf8)); fatalError("Accepted unknown version") } catch {}
        print("PASS: bounded orientation/batches, evidence and ID validation, daily/interval/pause controls, explicit migration and suppression persistence")
    }
}
