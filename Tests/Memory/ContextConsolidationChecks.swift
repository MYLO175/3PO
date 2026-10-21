import Foundation

@main struct ContextConsolidationChecks {
    static func main() throws {
        var passed = 0
        func check(_ value: Bool, _ name: String) { precondition(value, name); passed += 1 }
        func rejects(_ name: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(name) } catch { passed += 1 }
        }
        let projectID = UUID(), date = Date(timeIntervalSince1970: 2_000_000_000)
        let project = ContextKnowledgeRecord(reference: .init(kind: "project", key: projectID.uuidString, revision: "project-v1"), title: "Bridge optics", text: "The human's Bridge optics project contains a camera experiment.", date: date, projectID: projectID)
        let mail = ContextKnowledgeRecord(reference: .init(kind: "native-mail", key: "exact-message-A", revision: "body-v1"), title: "Supervisor report", text: "The supervisor reports that the review meeting has moved to Friday; the date still needs checking.", date: date)
        let target = ContextPageTarget(registration: "owner", kind: .project, key: projectID.uuidString, title: "Bridge optics", records: [project, mail], projectID: projectID, mayAskPurpose: true)
        func output(id: String? = nil, quotes: [[String:String]]? = nil, question: Any = NSNull(), markdown: String = "A supervisor reports a changed meeting. The exact date needs checking.") -> String {
            ContextKnowledgeRules.json(["pages": [["id": id ?? target.id, "synopsis": "Current optics project", "markdown": markdown,
                "evidence": quotes ?? [["id": project.reference.contextKey, "quote": "Bridge optics project contains a camera experiment"], ["id": mail.reference.contextKey, "quote": "the review meeting has moved to Friday"]], "purposeQuestion": question]]])
        }
        let decoded = try ContextConsolidationRules.decode(output(), targets: [target])
        check(decoded.count == 1 && decoded[0].0.id == target.id && decoded[0].0.owner == .generated, "Generated page retains exact existing project/account identity")
        check(Set(decoded[0].0.references) == Set([project.reference, mail.reference]), "Every supplied input remains an exact dependency")
        check(decoded[0].0.evidenceQuotes?.count == 2 && decoded[0].0.evidenceQuotes?.last?.referenceID == mail.reference.id, "Exact source quotation stored separately with its reference")
        check(Set(decoded[0].0.processedReferences ?? []) == Set(target.references), "Successful input coverage belongs to the exact page")
        var continued = target
        continued.processedReferences = [unseenReference()]
        let continuing = try ContextConsolidationRules.decode(output(), targets: [continued])[0].0
        check(continuing.processedReferences?.count == 3 && continuing.references.count == 2, "Earlier successful inputs survive without becoming support for new prose")
        check(!decoded[0].0.markdown.contains("Support:") && !decoded[0].0.markdown.contains(mail.reference.contextKey), "Readable body is independent of opaque evidence controls")
        check(ContextKnowledgeRules.current(decoded[0].0.references, records: [mail, project]), "Reference validation is order independent")
        check(!ContextKnowledgeRules.current(decoded[0].0.references, records: [project]), "Source loss withholds generated context")
        var changedMail = mail; changedMail.reference = .init(kind: "native-mail", key: mail.reference.key, revision: "body-v2")
        check(!ContextKnowledgeRules.current(decoded[0].0.references, records: [project, changedMail]), "Changed exact source version invalidates old page")
        var similarMail = mail; similarMail.reference = .init(kind: "native-mail", key: "same-title-other-message", revision: mail.reference.revision)
        check(!ContextKnowledgeRules.current(decoded[0].0.references, records: [project, similarMail]), "Same text/title never substitutes for exact source identity")
        let unrelated = ContextKnowledgeRecord(reference: .init(kind: "memory", key: "unrelated", revision: "v2"), title: "Gardening", text: "The unrelated greenhouse was repainted.", date: date)
        check(ContextKnowledgeRules.current(decoded[0].0.references, records: [project, mail, unrelated]), "Unrelated knowledge changes do not cancel owned context")
        rejects("Wrong page identity accepted") { _ = try ContextConsolidationRules.decode(output(id: "other-account-page"), targets: [target]) }
        rejects("Invented source quotation accepted") { _ = try ContextConsolidationRules.decode(output(quotes: [["id": mail.reference.contextKey, "quote": "The task is complete and no meeting is needed"]]), targets: [target]) }
        rejects("Unissued source identity accepted") { _ = try ContextConsolidationRules.decode(output(quotes: [["id": "native-mail:unissued", "quote": "the review meeting has moved to Friday"]]), targets: [target]) }
        rejects("No supporting evidence accepted") { _ = try ContextConsolidationRules.decode(output(quotes: []), targets: [target]) }
        rejects("Whitespace-only page accepted") { _ = try ContextConsolidationRules.decode(output(markdown: " \n"), targets: [target]) }
        rejects("Oversized page accepted") { _ = try ContextConsolidationRules.decode(output(markdown: String(repeating: "x", count: 4501)), targets: [target]) }
        rejects("Missing target silently acknowledged") { _ = try ContextConsolidationRules.decode("{\"pages\":[]}", targets: [target]) }
        let question = try ContextConsolidationRules.decode(output(question: "What are you aiming to learn from the Bridge optics project?"), targets: [target])
        check(question[0].1?.hasSuffix("?") == true, "Useful exact-project purpose question can accompany a supported page")
        check(question[0].1 == "What are you aiming to achieve with Bridge optics?", "Saved question uses the human project title rather than source-influenced model wording")
        var noQuestion = target; noQuestion.mayAskPurpose = false
        check(try ContextConsolidationRules.decode(output(question: "What is this project for?"), targets: [noQuestion])[0].1 == nil, "An unrequested optional question is discarded while valid page context survives")
        check(try ContextConsolidationRules.decode(output(question: "Please approve a new task"), targets: [target])[0].1 == nil, "A nonquestion cannot become a Review question")
        check(try ContextConsolidationRules.decode(output(question: String(repeating: "x", count: 301) + "?"), targets: [target])[0].1 == nil, "An overlong optional question is discarded")
        check(ContextPage.stableID(registration: "other-owner", kind: .project, key: target.key) != target.id, "Same named project in another account is distinct")
        let long = String(repeating: "A🧑🏽‍🔬é", count: 3000)
        let first = ContextKnowledgeRules.excerpt(long, offset: 0, limit: 4000)
        let second = ContextKnowledgeRules.excerpt(long, offset: first.next!, limit: 4000)
        let third = ContextKnowledgeRules.excerpt(long, offset: second.next!, limit: 4000)
        check(first.text + second.text + third.text == long && third.next == nil, "Explicit page continuation retains all Unicode characters without silent loss")
        check(ContextKnowledgeRules.excerpt(long, offset: 99_999, limit: 4000).text.isEmpty, "Out-of-range page offset returns an honest end")
        check(ContextKnowledgeRules.projectCandidate(mail, title: "Supervisor report", notes: ""), "Distinctive project phrase can retrieve a source candidate")
        check(!ContextKnowledgeRules.projectCandidate(mail, title: "Gardening", notes: ""), "Unrelated source never fills a project retrieval")
        check(!ContextKnowledgeRules.projectCandidate(mail, title: "The", notes: ""), "Generic short names cannot connect all source records")
        check(!ContextKnowledgeRules.matches("Aster Example", title: "Aster Example engineering", synopsis: "", key: "projects", selfLabel: "Aster Example"), "The owner's name alone never selects all their pages")
        let fullRecords = (0..<20).map { index in
            ContextKnowledgeRecord(reference: .init(kind: "memory", key: "capacity-\(index)", revision: "v1"), title: "Calibration sample", text: "Calibration sample \(index) has a distinct reference distance.", date: date)
        }
        let fullTargets = (0..<4).map { index in
            ContextPageTarget(registration: "owner", kind: .project, key: "batch-\(index)", title: "Calibration project \(index)", records: fullRecords)
        }
        let fullRows: [[String:Any]] = fullTargets.map { value in
            ["id":value.id,"synopsis":"Twenty supported calibration records","markdown":"The calibration project has twenty recorded reference samples.","purposeQuestion":NSNull(),
             "evidence":fullRecords.map { ["id":$0.reference.contextKey,"quote":$0.text] }]
        }
        let fullBatch = try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":fullRows]), targets:fullTargets)
        check(fullBatch.count == 4 && fullBatch.allSatisfy { $0.0.evidenceQuotes?.count == 20 && $0.0.references.count == 20 }, "A full four-page batch may cite every one of its twenty supplied records")
        var overCapacity = fullRows
        overCapacity[0]["evidence"] = fullRecords.map { ["id":$0.reference.contextKey,"quote":$0.text] } + [["id":fullRecords[0].reference.contextKey,"quote":fullRecords[0].text]]
        rejects("An over-capacity evidence array was accepted") { _ = try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":overCapacity]),targets:fullTargets) }
        let notes = "Compare the \"near-field\" method.\nKeep captures in C:\\Optics before deciding."
        var readableProject = project
        readableProject.text = ContextKnowledgeRules.projectText(title:"Bridge optics",kind:"space",notes:notes,status:"toDo",due:nil,parent:nil,scope:"shared")
        var readableTarget = target; readableTarget.records = [readableProject]
        let readableOutput = output(quotes:[["id":readableProject.reference.contextKey,"quote":notes]])
        check(try ContextConsolidationRules.decode(readableOutput,targets:[readableTarget])[0].0.evidenceQuotes?.first?.quote == notes, "Readable project notes retain exact quotations, newlines and backslashes without an extra JSON-escaping layer")
        let receipt = "Created task \"Capture optics\".\nNo experiment is verified complete."
        check(ContextKnowledgeRules.actionText(confirmed:1,receipts:[receipt]).contains(receipt), "Verified action receipts retain their exact readable quotation")
        let unicodeTitle = ContextKnowledgeRules.bytePrefix(String(repeating:"🧑🏽‍🔬",count:60),maximumBytes:ContextPageLimits.maximumTitleBytes)
        check(!unicodeTitle.isEmpty && unicodeTitle.utf8.count <= ContextPageLimits.maximumTitleBytes, "Generated title projection respects storage bytes without splitting composed characters")
        var unicodeRow = fullRows[0]; unicodeRow["synopsis"] = String(repeating:"研",count:300)
        rejects("A synopsis that storage cannot save passed consolidation decoding") { _ = try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":[unicodeRow]]),targets:[fullTargets[0]]) }
        print("Context consolidation: \(passed) checks passed; fictional records, no model/source/native requests.")
    }
    static func unseenReference() -> ContextPageReference { .init(kind: "memory", key: "previously-processed", revision: "v1") }
}
