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
        let introduction=MemoryLearningTurn(id:"intro",text:"I study Materials Engineering. My family chat is called The Nest.",created:now)
        let parts="{\"memories\":[{\"turnID\":\"intro\",\"text\":\"Studies Materials Engineering\",\"kind\":\"context\",\"evidence\":\"I study Materials Engineering\"},{\"turnID\":\"intro\",\"text\":\"Family chat is The Nest\",\"kind\":\"context\",\"evidence\":\"My family chat is called The Nest\"}]}"
        let multiple=try MemoryLearningRules.decode(parts,turns:[introduction]);precondition(multiple.count == 2 && multiple.allSatisfy{$0.turnID == "intro"})
        func encode(_ values: [LearnedMemory]) throws -> String {
            String(data:try JSONSerialization.data(withJSONObject:["memories":try JSONSerialization.jsonObject(with:JSONEncoder().encode(values))]),encoding:.utf8)!
        }
        var classified=multiple[0];classified.organisation = .init(areas:[.studies],connections:[],selfName:nil)
        let typed=try MemoryLearningRules.decode(encode([classified]),turns:[introduction]);precondition(typed[0].organisation?.areas == [.studies])
        for metadata in [
            LifeMemoryOrganisation(areas:[.studies],connections:[.init(connection:"0",subjectKind:.person,objectKind:.course,subjectIsSelf:true,objectIsSelf:false)],selfName:nil),
            LifeMemoryOrganisation(areas:[.studies],connections:[],selfName:"An invented name"),
            LifeMemoryOrganisation(areas:[.studies],connections:[],selfName:nil,manual:true)
        ] {
            classified.organisation=metadata
            let retained=try MemoryLearningRules.decode(encode([classified]),turns:[introduction])
            precondition(retained.count == 1 && retained[0].text == classified.text && retained[0].evidence == classified.evidence && retained[0].organisation == nil,"Unsupported navigation must not discard a faithful fact")
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
        let old = try MemoryEnvelope.decode(JSONEncoder().encode(MemoryEnvelope(records:[memory])))
        precondition(old.records[0].explicit && old.suppressed.isEmpty)
        var envelope = old; envelope.suppressed["one"] = ["12"]
        let restored = try MemoryEnvelope.decode(JSONEncoder().encode(envelope))
        precondition(restored.suppressed["one"] == ["12"] && restored.records.count == 1)
        do { _ = try MemoryEnvelope.decode(Data("{\"version\":99,\"records\":[],\"suppressed\":{}}".utf8)); fatalError("Accepted unknown version") } catch {}
        let topic = UUID(), otherTopic = UUID()
        let scoped = [MemoryLearningTurn(id:"general",text:"I prefer concise replies",created:now),MemoryLearningTurn(id:"study",text:"My project is about optics",created:now.addingTimeInterval(1),conversationID:topic),MemoryLearningTurn(id:"other",text:"My other project is acoustics",created:now.addingTimeInterval(2),conversationID:otherTopic),MemoryLearningTurn(id:"study-two",text:"I study in the library",created:now.addingTimeInterval(3),conversationID:topic)]
        precondition(MemoryLearningRules.batch(scoped,seen:[],suppressed:[]).map(\.id) == ["general"])
        precondition(MemoryLearningRules.batch(scoped,seen:["general"],suppressed:[]).map(\.id) == ["study","study-two"])
        let questionJSON = "{\"memories\":[],\"question\":{\"turnID\":\"study\",\"text\":\"How much preparation time should I allow for your optics project?\",\"evidence\":\"My project is about optics\"}}"
        let assessment = try MemoryLearningRules.assessment(questionJSON,turns:scoped,questionAllowed:true)
        precondition(assessment.memories.isEmpty && assessment.question?.turnID == "study")
        for (bad,allowed) in [(questionJSON,false),(questionJSON.replacingOccurrences(of:"My project is about optics",with:"Invented quote"),true),(questionJSON.replacingOccurrences(of:"How much preparation time should I allow for your optics project?",with:"Not a question"),true),(questionJSON.replacingOccurrences(of:"\"study\"",with:"\"not-a-turn\""),true)] {
            do { _ = try MemoryLearningRules.assessment(bad,turns:scoped,questionAllowed:allowed); preconditionFailure("Invalid question accepted") } catch {}
        }
        let conflicting = questionJSON.replacingOccurrences(of:"\"memories\":[]",with:"\"memories\":[{\"turnID\":\"study\",\"text\":\"My project is about optics\",\"kind\":\"context\",\"evidence\":\"My project is about optics\"}]")
        do { _ = try MemoryLearningRules.assessment(conflicting,turns:scoped,questionAllowed:true); preconditionFailure("Learned and queried the same fact") } catch {}
        let q = LearningQuestionRules.record(assessment.question!,turns:scoped,prior:[],registration:"one",now:now)!
        precondition(q.conversationID == topic && q.turnID == "study")
        precondition(LearningQuestionRules.record(assessment.question!,turns:scoped,prior:[q],registration:"one",now:now) == nil)
        let today = BriefingRules.day(now)
        precondition(!LearningQuestionRules.allowed(progress:MemoryLearningProgress(),records:[q],registration:"one",day:today))
        precondition(LearningQuestionRules.allowed(progress:MemoryLearningProgress(),records:[q],registration:"two",day:today))
        precondition(LearningQuestionRules.allowed(progress:MemoryLearningProgress(),records:[q],registration:"one",day:"tomorrow"))
        var claimed = MemoryLearningProgress(); claimed.lastQuestionDay = today
        precondition(!LearningQuestionRules.allowed(progress:claimed,records:[],registration:"one",day:today))
        claimed.day = today
        let questionProgress = MemoryLearningRules.progress(turns:[],prior:claimed,suppressed:[],day:"tomorrow")
        precondition(questionProgress.lastQuestionDay == today)
        let legacyProgress = "{\"version\":1,\"accounts\":{\"one\":{\"seen\":[],\"skippedAtOrientation\":0,\"day\":\"today\",\"attempts\":0,\"paused\":false}}}"
        let legacyState = try JSONDecoder().decode(MemoryLearningState.self,from:Data(legacyProgress.utf8))
        precondition(legacyState.questions == nil && legacyState.accounts["one"]?.lastQuestionDay == nil)
        var savedQuestion = q; savedQuestion.dismissed = true
        var questionState = MemoryLearningState(); questionState.questions = [savedQuestion]; questionState.accounts["one"] = claimed
        let questionReload = try JSONDecoder().decode(MemoryLearningState.self,from:JSONEncoder().encode(questionState))
        precondition(questionReload.questions == [savedQuestion] && questionReload.accounts["one"]?.lastQuestionDay == today)
        precondition(!q.deliveryID.hasPrefix("discovery:") && !q.deliveryID.contains(":morning:"))
        var backlog = MemoryLearningProgress()
        let many = (0..<100).map { MemoryLearningTurn(id:"pending-\($0)", text:"A saved message \($0)", created:now.addingTimeInterval(Double($0))) }
        var consumed = Set<String>()
        while true {
            let page = MemoryLearningRules.batch(many.reversed(), seen:backlog.seen, suppressed:[], offsets:backlog.offsets ?? [:])
            if page.isEmpty { break }
            consumed.formUnion(page.map(\.id)); MemoryLearningRules.acknowledge(page, progress:&backlog)
            backlog = try JSONDecoder().decode(MemoryLearningProgress.self, from:JSONEncoder().encode(backlog))
        }
        precondition(consumed.count == 100 && backlog.seen.count == 100, "A busy period or restart must not lose older pending messages")
        let longTurn = MemoryLearningTurn(id:"long", text:String(repeating:"x", count:6200) + " I prefer concise morning briefs.", created:now)
        var longProgress = MemoryLearningProgress(), pieces:[String] = []
        while !longProgress.seen.contains("long") {
            let page = MemoryLearningRules.batch([longTurn], seen:longProgress.seen, suppressed:[], offsets:longProgress.offsets ?? [:])
            precondition(page.count == 1 && page[0].text.count <= 3000)
            pieces.append(page[0].text); MemoryLearningRules.acknowledge(page, progress:&longProgress)
        }
        precondition(pieces.joined() == longTurn.text && longProgress.offsets?.isEmpty == true, "Do not acknowledge an unread tail")
        let target = MemoryInstructionTarget(id:"calendar_0",scope:"calendar:exact-account-provider",title:"Tentative",text:"",revision:"one")
        let guidanceTurn = MemoryLearningTurn(id:"guidance",text:"This calendar is only for tentative plans.",created:now)
        var guidance = LearnedMemory(turnID:"guidance",text:"Use this calendar for tentative plans.",kind:.preference,evidence:guidanceTurn.text,certainty:.stated,durability:.stable,instruction:"calendar_0")
        let routed = try MemoryLearningRules.assessment(encode([guidance]),turns:[guidanceTurn],questionAllowed:false,targets:[target])
        precondition(routed.memories[0].instruction == target.scope)
        guidance.kind = .context
        let calendarContext = try MemoryLearningRules.assessment(encode([guidance]),turns:[guidanceTurn],questionAllowed:false,targets:[target])
        precondition(calendarContext.memories[0].kind == .context && calendarContext.memories[0].instruction == target.scope,"A stated calendar purpose can remain factual context")
        let instructionResult = "{\"memories\":[],\"instructions\":" + String(data:try JSONEncoder().encode([guidance]),encoding:.utf8)! + "}"
        let separateInstructions = try MemoryLearningRules.assessment(instructionResult,turns:[guidanceTurn],questionAllowed:false,targets:[target])
        precondition(separateInstructions.memories.first?.instruction == target.scope,"Instruction updates use a separate bounded result lane")
        guidance.kind = .preference
        do { _ = try MemoryLearningRules.assessment(encode([guidance]),turns:[guidanceTurn],questionAllowed:false); preconditionFailure("Unissued calendar accepted") } catch {}
        var priorRule = PAMemory(registration:"one",text:"Old guidance",kind:.preference,provenance:"Human")
        priorRule.instructionScope = target.scope
        guidance.replaces = priorRule.id.uuidString
        _ = try MemoryLearningRules.assessment(encode([guidance]),turns:[guidanceTurn],questionAllowed:false,targets:[target],existing:[priorRule])
        guidance.certainty = .inferred
        do { _ = try MemoryLearningRules.assessment(encode([guidance]),turns:[guidanceTurn],questionAllowed:false,targets:[target],existing:[priorRule]); preconditionFailure("Inferred correction accepted") } catch {}
        let action = MemoryLearningTurn(id:"operation",text:"Created a reminder for the optics experiment.",created:now,category:"action")
        var actionMemory = LearnedMemory(turnID:action.id,text:"A reminder was created for the experiment.",kind:.context,evidence:action.text)
        let outcome = try MemoryLearningRules.assessment(encode([actionMemory]),turns:[action],questionAllowed:false)
        precondition(outcome.memories[0].certainty == .inferred && outcome.memories[0].durability == .situational)
        actionMemory.kind = .preference; actionMemory.instruction = "calendar_0"
        do { _ = try MemoryLearningRules.assessment(encode([actionMemory]),turns:[action],questionAllowed:false,targets:[target]); preconditionFailure("App outcome became a policy") } catch {}
        var revisedAction = action; revisedAction.revision = "pending-approval"
        var actionProgress = MemoryLearningProgress()
        MemoryLearningRules.acknowledge([revisedAction],progress:&actionProgress)
        precondition(MemoryLearningRules.batch([revisedAction],seen:actionProgress.seen,suppressed:[],revisions:actionProgress.revisions ?? [:]).isEmpty)
        revisedAction.revision = "verified-approval"
        precondition(MemoryLearningRules.batch([revisedAction],seen:[],suppressed:[],paused:[action.id + ":pending-approval"]).count == 1,"A failed old outcome cannot block a newly verified outcome on the same turn")
        let updatedAction = MemoryLearningRules.batch([revisedAction],seen:actionProgress.seen,suppressed:[],revisions:actionProgress.revisions ?? [:])
        precondition(updatedAction.count == 1 && updatedAction[0].offset == 0,"A later approval on the same response turn must be consolidated")
        actionProgress.offsets = [action.id:12]
        precondition(MemoryLearningRules.batch([revisedAction],seen:actionProgress.seen,suppressed:[],offsets:actionProgress.offsets ?? [:],revisions:actionProgress.revisions ?? [:])[0].offset == 0,"A revised outcome cannot inherit an old chunk cursor")
        print("PASS: durable backlog/restart, complete long-message coverage, exact instruction routing/corrections, action authority, bounded learning and legacy controls")
    }
}
