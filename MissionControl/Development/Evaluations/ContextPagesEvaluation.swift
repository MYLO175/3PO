#if DEBUG
import Foundation
import SwiftData

/// Fictional storage and completed transport only; every selection, page read,
/// consolidation receipt and foreground ownership decision uses production code.
@MainActor enum ContextPagesEvaluation {
    static func run() async throws -> [String: Bool] {
        guard ProcessInfo.processInfo.arguments.contains("--validate-advice-context") else { throw IntegrationError.verification }
        var checks = try consolidationChecks()
        checks.merge(try humanEvidenceChecks(), uniquingKeysWith: { $1 })
        checks.merge(try await pageReadChecks(), uniquingKeysWith: { $1 })
        checks.merge(try instructionChecks(), uniquingKeysWith: { $1 })
        checks.merge(try emailPageChecks(), uniquingKeysWith: { $1 })
        checks.merge(try await ownedMutationChecks(), uniquingKeysWith: { $1 })
        return checks
    }

    /// Produces supported fictional provider output; no selection algorithm lives here.
    @discardableResult private static func consolidate(_ target: ContextPageTarget, in fixture: ContextPagesFixture,
                                                       checkpoint: Bool = false) throws -> ContextPage {
        guard let evidence = target.records.first else { throw IntegrationError.verification }
        let output: [String: Any] = ["pages": [["id": target.id, "synopsis": "Fictional supported context",
            "markdown": "# Fictional context\n\n" + evidence.text,
            "evidence": [["id": evidence.reference.contextKey, "quote": String(evidence.text.prefix(80))]]]]]
        let decoded = try ContextConsolidationRules.decode(ContextKnowledgeRules.json(output), targets: [target])
        guard let page = decoded.first?.0 else { throw IntegrationError.verification }
        let store = fixture.model.contextPages, previous = store.page(id: target.id, registration: fixture.registration)
        var expected: [String: UUID] = [:]
        if let previous { expected[page.id] = previous.revision }
        let oldCheckpoint = store.checkpoint(registration: fixture.registration)
        let refs = Array(Dictionary(((oldCheckpoint?.references ?? []) + target.references).map { ($0.contextKey, $0) }, uniquingKeysWith: { _, new in new }).values)
        let saved = try store.saveBatch([page], expectedRevisions: expected,
            checkpoint: checkpoint ? .init(registration: fixture.registration, references: refs) : nil,
            expectedCheckpointRevision: checkpoint ? oldCheckpoint?.revision : nil)
        guard let result = saved.first else { throw IntegrationError.verification }
        return result
    }

    private static func consolidationChecks() throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let fixture = try ContextPagesFixture()
        defer { fixture.clean() }
        let model = fixture.model, registration = fixture.registration
        var facts: [PAMemory] = []
        for index in 0..<27 {
            let fact = PAMemory(registration: registration, text: "Fictional cobalt study fact \(index) concerns a distinct engineering exercise.",
                kind: .context, provenance: "Fictional human fixture", created: Date(timeIntervalSince1970: Double(1_700_000_000 + index)),
                organisation: .init(areas: [.studies], connections: []))
            guard model.assistant.memory.put(fact) else { throw IntegrationError.verification }
            facts.append(fact)
        }
        guard let first = model.contextConsolidation.targets(model, registration: registration).first(where: { $0.kind == .topic && $0.key == LifeArea.studies.rawValue }) else { throw IntegrationError.verification }
        let firstPage = try consolidate(first, in: fixture, checkpoint: true)
        let firstIDs = Set(first.references.map(\.contextKey))
        let overflow = Set(facts.map { "memory:" + $0.id.uuidString }).subtracting(firstIDs)
        checks["Context pages bound first target and leave record 21 onward unprocessed"] = first.records.count == 20 && overflow.count == 7 && firstPage.processedReferences?.count == 20
        checks["Context pages checkpoint acknowledges only supplied batch records"] = Set(model.contextPages.checkpoint(registration: registration)?.references.map(\.contextKey) ?? []).isDisjoint(with: overflow)
        let working = model.captureContextPages(registration: registration, query: "cobalt study")
        let workingRows = try object(working.text)["workingChanges"] as? [[String: String]] ?? []
        checks["Context pages overflow stays available as working context before consolidation"] = overflow.isSubset(of: Set(workingRows.compactMap { $0["id"] }))
        guard let second = model.contextConsolidation.targets(model, registration: registration).first(where: { $0.id == first.id }) else { throw IntegrationError.verification }
        checks["Context pages next target prioritises all independently pending overflow"] = second.hasPendingChanges && overflow.isSubset(of: Set(second.references.map(\.contextKey)))
        let secondPage = try consolidate(second, in: fixture, checkpoint: true)
        checks["Context pages accumulate per-page progress beyond one twenty-record window"] = Set(secondPage.processedReferences?.map(\.contextKey) ?? []) == Set(facts.map { "memory:" + $0.id.uuidString })
        checks["Context pages quiet target stops after every current version was processed"] = !model.contextConsolidation.targets(model, registration: registration).contains(where: { $0.id == first.id })
        checks["Context pages progress survives reopening actual storage"] = ContextPageStore(container: model.container).page(id: secondPage.id, registration: registration)?.processedReferences == secondPage.processedReferences

        let shared = try ContextPagesFixture()
        defer { shared.clean() }
        let sharedFact = PAMemory(registration: shared.registration, text: "Fictional cobalt study preference is to compare worked engineering examples.", kind: .preference,
            provenance: "Fictional human fixture", organisation: .init(areas: [.about, .studies], connections: []))
        guard shared.model.assistant.memory.put(sharedFact) else { throw IntegrationError.verification }
        let targets = shared.model.contextConsolidation.targets(shared.model, registration: shared.registration)
        guard let overview = targets.first(where: { $0.kind == .overview }), let topic = targets.first(where: { $0.kind == .topic && $0.key == LifeArea.studies.rawValue }) else { throw IntegrationError.verification }
        _ = try consolidate(overview, in: shared, checkpoint: true)
        let after = shared.model.contextConsolidation.targets(shared.model, registration: shared.registration)
        checks["Context pages shared fact global acknowledgement cannot consume another target"] = after.contains { $0.id == topic.id && $0.hasPendingChanges && $0.references.contains { $0.key == sharedFact.id.uuidString } }
        checks["Context pages completed overview remains quiet while sibling target is pending"] = !after.contains(where: { $0.id == overview.id })
        _ = try consolidate(topic, in: shared)
        checks["Context pages sibling target quiets only after its own successful batch"] = !shared.model.contextConsolidation.targets(shared.model, registration: shared.registration).contains(where: { $0.id == topic.id })
        checks["Context pages fixture makes no real inference requests"] = fixture.provider.calls == 0 && shared.provider.calls == 0 && fixture.sources.reads == 0 && shared.sources.reads == 0 && model.aiUsage.state.records.isEmpty
        let questionProject = try shared.model.assistant.projects.save(.init(registration: shared.registration, kind: .space, title: "Fictional purpose question"), expected: nil)
        _ = try shared.model.contextQuestions.offer(registration: shared.registration, projectID: questionProject.id, identity: shared.model.contextProjectIdentity(questionProject), question: "What are you aiming to achieve with this fictional project?")
        checks["Context questions share the existing daily allowance with conversation learning"] = !shared.model.learningRuntime().canOfferQuestion(shared.registration, .now)
        checks["Context questions pending clarification suppresses more project-purpose offers"] = shared.model.contextConsolidation.targets(shared.model, registration: shared.registration).allSatisfy { !$0.mayAskPurpose }
        if let pending = shared.model.contextQuestions.questions(registration: shared.registration).first {
            _ = try shared.model.contextQuestions.dismiss(id: pending.id, registration: shared.registration, expectedRevision: pending.revision)
        }
        checks["Context question dismissal does not reopen the same day's question allowance"] = !shared.model.learningRuntime().canOfferQuestion(shared.registration, .now)
        checks["Context questions leave the next day's learning allowance available"] = shared.model.learningRuntime().canOfferQuestion(shared.registration, Date.now.addingTimeInterval(86400))
        return checks
    }

    private static func emailPageChecks() throws -> [String: Bool] {
        let fixture = try ContextPagesFixture()
        defer { fixture.clean() }
        let model = fixture.model, registration = fixture.registration
        let project = try model.assistant.projects.save(.init(registration: registration, kind: .space, title: "Fictional workshop"), expected: nil)
        let purpose = try model.contextPages.save(.init(registration: registration, kind: .note, key: "project-purpose:" + project.id.uuidString, owner: .human, title: "Purpose of fictional workshop", markdown: "Compare cobalt spectroscopy calibration methods using a small optical rig.", references: [model.contextProjectIdentity(project)]), expectedRevision: nil)
        _ = try model.contextPages.save(.init(registration: registration, kind: .overview, key: "everyday", owner: .human, title: "Everyday orientation", markdown: "Fictional cobalt interests and unrelated personal background."), expectedRevision: nil)
        let raw: [String: Any] = ["id": "fictional-cobalt-email", "accountID": "fictional-mail", "account": "Fictional Mail", "messageID": 1, "internetMessageID": "cobalt@example.invalid", "sender": "Dr Kestrel", "subject": "Cobalt spectroscopy calibration guide", "received": Date.now.ISO8601Format(), "unread": true, "replied": false, "flagged": false]
        let message = try JSONDecoder().decode(MailMessage.self, from: JSONSerialization.data(withJSONObject: raw))
        let body = "The cobalt spectroscopy calibration guide compares practical optical methods."
        let captured = model.emailSummaries.relevanceContext(message, model: model, body: body)
        let header = model.emailSummaries.relevanceContext(message, model: model, header: true)
        let stamp = model.emailSummaries.reviewPreferenceStamp(message, model: model, evidence: body)
        var checks: [String: Bool] = [:]
        checks["Context email purpose-only discovery selects the exact active human project"] = captured.memories.isEmpty && captured.workspace.contains { $0["id"] == "life:" + project.id.uuidString } && captured.contextPages.contains { $0["id"] == purpose.id }
        checks["Context email excludes everyday orientation and raw working changes"] = captured.contextPages.allSatisfy { $0["id"] == purpose.id } && captured.input["workingChanges"] == nil
        let bodyBytes = try JSONSerialization.data(withJSONObject: EmailRelevanceRules.pageInput(captured.contextPages)).count
        let headerBytes = try JSONSerialization.data(withJSONObject: EmailRelevanceRules.pageInput(header.contextPages)).count
        checks["Context email body and header page payloads obey encoded bounds"] = bodyBytes <= 3500 && headerBytes <= 1200
        checks["Context email exact current page dependencies are available"] = captured.contextPageDependencies?["page:" + purpose.id] == purpose.revision.uuidString && model.emailSummaries.relevanceContextAvailable(captured, model: model)
        let unrelated = try model.contextPages.save(.init(registration: registration, kind: .note, key: "unrelated-fern", owner: .human, title: "Gardening", markdown: "Keep the fictional fern in indirect light."), expectedRevision: nil)
        checks["Context email unrelated human notes do not trigger reclassification"] = stamp == model.emailSummaries.reviewPreferenceStamp(message, model: model, evidence: body) && model.emailSummaries.relevanceContextAvailable(captured, model: model)
        var revised = purpose; revised.markdown += "\nThe comparison now focuses on repeatable optical measurements."
        let updated = try model.contextPages.save(revised, expectedRevision: purpose.revision)
        checks["Context email changed human purpose rejects stale classification and changes discovery"] = !model.emailSummaries.relevanceContextAvailable(captured, model: model) && stamp != model.emailSummaries.reviewPreferenceStamp(message, model: model, evidence: body)
        let current = model.emailSummaries.relevanceContext(message, model: model, body: body)
        let currentStamp = model.emailSummaries.reviewPreferenceStamp(message, model: model, evidence: body)
        var generated = ContextPage(registration: registration, kind: .topic, key: "cobalt", owner: .generated, title: "Cobalt calibration", markdown: "A short generated synopsis of the human's optical comparison.", references: [.init(kind: "page", key: updated.id, revision: updated.revision.uuidString)])
        let first = try model.contextPages.save(generated, expectedRevision: nil)
        generated.markdown += "\nThe original purpose stays authoritative."
        _ = try model.contextPages.save(generated, expectedRevision: first.revision)
        checks["Context email generated rephrasing alone does not trigger another assessment"] = currentStamp == model.emailSummaries.reviewPreferenceStamp(message, model: model, evidence: body)
        try model.contextPages.forget(id: unrelated.id, registration: registration, expectedRevision: unrelated.revision)
        model.assistant.memory.enabled = false
        checks["Context email paused memory withdraws prior page-backed input"] = !model.emailSummaries.relevanceContextAvailable(current, model: model) && model.emailSummaries.relevanceContext(message, model: model, body: body).contextPages.isEmpty
        checks["Context email fixtures make no source or subscription requests"] = fixture.sources.reads == 0 && fixture.provider.calls == 0 && model.aiUsage.state.records.isEmpty
        return checks
    }

    private static func humanEvidenceChecks() throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        for operation in ["forget", "correct"] {
            let fixture = try ContextPagesFixture()
            defer { fixture.clean() }
            let model = fixture.model, registration = fixture.registration, turnID = UUID()
            let oldWords = "Fictional cobalt workshop is my current research project."
            try fixture.human(oldWords, id: turnID)
            let fact = PAMemory(registration: registration, text: oldWords, kind: .context, provenance: "Fictional human fixture", sourceTurnID: turnID.uuidString,
                evidence: oldWords, organisation: .init(areas: [.studies], connections: []))
            guard model.assistant.memory.put(fact) else { throw IntegrationError.verification }
            let records = model.contextKnowledge(registration: registration)
            let refs = records.filter { $0.memoryID == fact.id || $0.reference.kind == "human" && $0.reference.key == turnID.uuidString }.map(\.reference)
            let page = try model.contextPages.save(.init(registration: registration, kind: .topic, key: "fictional-" + operation, owner: .generated,
                title: "Cobalt workshop", synopsis: "Fictional research context", markdown: oldWords, references: refs), expectedRevision: nil)
            let humanPage = try model.contextPages.save(.init(registration: registration, kind: .note, key: "fictional-human-" + operation, owner: .human,
                title: "Cobalt human context", markdown: oldWords, references: refs), expectedRevision: nil)
            let humanVersion = ContextPageReference(kind: "page", key: humanPage.id, revision: humanPage.revision.uuidString)
            let indirectPage = try model.contextPages.save(.init(registration: registration, kind: .topic, key: "fictional-indirect-" + operation, owner: .generated,
                title: "Cobalt indirect context", markdown: oldWords, references: [humanVersion]), expectedRevision: nil)
            let minimalVersions = [humanVersion.contextKey: humanVersion.revision]
            checks["Context pages \(operation) initially validates transitive human-page support"] = model.contextKnowledgeAvailable(registration: registration, versions: minimalVersions) && model.contextPageEligible(indirectPage, records: model.contextKnowledge(registration: registration))
            let captured = model.captureContextPages(registration: registration, query: "cobalt workshop", pageID: page.id)
            checks["Context pages \(operation) initially captures canonical fact and original human turn"] = captured.current() && refs.count == 2 && captured.referenceVersions["human:" + turnID.uuidString] != nil && captured.pageIDs == [page.id]
            var replacementID: UUID?
            if operation == "forget" {
                guard model.assistant.memory.forget(fact.id) else { throw IntegrationError.verification }
            } else {
                let replacementTurn = UUID(), words = "Fictional cobalt workshop is complete; my current research project is the amber laboratory."
                try fixture.human(words, id: replacementTurn)
                let replacement = PAMemory(registration: registration, text: words, kind: .context, provenance: "Fictional human correction", sourceTurnID: replacementTurn.uuidString,
                    evidence: words, organisation: .init(areas: [.studies], connections: []))
                guard model.assistant.memory.correct(fact.id, with: replacement) else { throw IntegrationError.verification }
                replacementID = replacement.id
            }
            let current = model.contextKnowledge(registration: registration)
            let fresh = model.captureContextPages(registration: registration, query: "cobalt workshop", pageID: page.id)
            checks["Context pages \(operation) suppresses the old human turn as well as its old fact"] = !current.contains { $0.reference.key == turnID.uuidString || $0.memoryID == fact.id }
            checks["Context pages \(operation) invalidates previously supplied generated prose"] = !captured.current() && !fresh.pageIDs.contains(page.id) && !model.contextKnowledgeAvailable(registration: registration, versions: captured.referenceVersions)
            checks["Context pages \(operation) invalidates transitive human-page receipts without copied source bodies"] = !model.contextKnowledgeAvailable(registration: registration, versions: minimalVersions) && !model.contextPageEligible(indirectPage, records: current)
            checks["Context pages \(operation) preserves saved page and immutable history"] = model.contextPages.page(id: page.id, registration: registration) == page && model.contextPages.history(id: page.id, registration: registration).count == 1
            if let replacementID {
                checks["Context pages correction keeps the current replacement available"] = current.contains { $0.memoryID == replacementID && $0.text.contains("amber laboratory") }
                checks["Context pages correction preserves original canonical lineage"] = model.assistant.memory.records.first(where: { $0.id == fact.id })?.supersededBy == replacementID
            }
            fixture.model.chatGPT.activeID = "fictional-other-account"
            checks["Context pages \(operation) cannot retrieve another account's facts or pages"] = model.contextKnowledge(registration: registration).isEmpty && model.captureContextPages(registration: registration, query: nil).text == "{}"
        }
        return checks
    }

    private static func pageReadChecks() async throws -> [String: Bool] {
        let fixture = try ContextPagesFixture()
        defer { fixture.clean() }
        let model = fixture.model, registration = fixture.registration
        // Escaping, Unicode and >12 KB exercise the final JSON byte bound as well as character offsets.
        let body = String(repeating: "ab\"\\🌱", count: 2500)
        let page = try model.contextPages.save(.init(registration: registration, kind: .note, key: "fictional-long-read", owner: .human,
            title: "Cobalt long read", markdown: body), expectedRevision: nil)
        let tools = PAToolSession(model: model, human: "Read the cobalt long read", humanContext: "Read the cobalt long read", topicID: nil,
            turnID: UUID(), evaluationMemory: model.assistant.memory, evaluationProjects: model.assistant.projects, inferenceModel: fixture.provider.selectedModel)
        var restored = "", offset = 0, bounds = true, offsets = true, chunks = 0, complete = false
        for index in 0..<16 {
            let call = PAFunctionCall(id: "fictional-page-chunk-\(index)", name: "read_context_page", namespace: "pa",
                arguments: ContextKnowledgeRules.json(["id": page.id, "query": NSNull(), "offset": String(offset)]))
            let text = try await tools.execute(call, valid: { true })
            bounds = bounds && text.utf8.count <= 32_000
            let payload = try object(text)
            guard let row = (payload["pages"] as? [[String: String]])?.first, let excerpt = row["markdown"], let next = row["nextOffset"] else { break }
            offsets = offsets && row["offset"] == String(offset) && row["totalCharacters"] == String(body.count)
            restored += excerpt; chunks += 1
            if next == "end" { complete = true; break }
            guard let number = Int(next), number > offset else { offsets = false; break }
            offset = number
        }
        var checks: [String: Bool] = [:]
        checks["Context pages real tool continuation reads every stored long-page character"] = body.utf8.count > 12_000 && complete && chunks > 1 && restored == body
        checks["Context pages real tool continuation uses exact increasing character offsets"] = offsets
        checks["Context pages every encoded continuation stays within final payload bytes"] = bounds
        checks["Context pages real tool records the exact human-page version"] = tools.consultedContextVersions["page:" + page.id] == page.revision.uuidString && tools.pageContextAvailable
        for index in 0..<38 {
            _ = try model.contextPages.save(.init(registration: registration, kind: .note, key: "fictional-directory-\(index)", owner: .human,
                title: "Cobalt note \(index)", synopsis: "Fictional context", markdown: String(repeating: "\"\\🌱", count: 600)), expectedRevision: nil)
        }
        for index in 0..<22 {
            guard model.assistant.memory.put(.init(registration: registration, text: "Cobalt pending fact \(index): " + String(repeating: "\"\\🌱", count: 300), kind: .context, provenance: "Fictional fixture")) else { throw IntegrationError.verification }
        }
        let broad = model.captureContextPages(registration: registration, query: nil, everyday: true)
        let broadObject = try object(broad.text)
        let directory = broadObject["directory"] as? [[String: String]] ?? []
        checks["Context pages ordinary whole payload stays bounded with directory and pending changes"] = broad.text.utf8.count <= 20_000 && broadObject["unavailable"] == nil && !directory.isEmpty
        checks["Context pages directory reports stored pages omitted by its input bound"] = (broadObject["directoryCount"] as? Int ?? 0) > directory.count
        var edited = page; edited.markdown += "\nIndependent human edit"
        _ = try model.contextPages.save(edited, expectedRevision: page.revision)
        checks["Context pages actual read tool rejects later human-page edit"] = !tools.pageContextAvailable
        checks["Context pages read and directory operations make zero inference calls"] = fixture.provider.calls == 0 && fixture.sources.reads == 0 && model.aiUsage.state.records.isEmpty
        return checks
    }

    private static func instructionChecks() throws -> [String: Bool] {
        let fixture = try ContextPagesFixture()
        defer { fixture.clean() }
        let model = fixture.model, registration = fixture.registration
        var checks: [String: Bool] = [:]
        let prompt = model.briefings.writingPrompt(registration)
        let briefWords = "Prioritise fictional cobalt laboratory commitments. " + String(repeating: "\"\\🌱", count: 1800)
        try model.briefings.saveWritingPrompt(briefWords, expected: prompt, model: model)
        let brief = model.captureContextPages(registration: registration, query: nil, pageID: "instructions:brief")
        let briefObject = try object(brief.text)
        checks["Context pages brief instructions carry exact bounded versioned text"] = brief.current() && brief.text.utf8.count <= 32_000 && (briefObject["instructions"] as? [String: String])?["nextOffset"] != "end" && brief.referenceVersions["instruction:brief"] != nil
        try model.briefings.saveWritingPrompt("Use the revised fictional cobalt brief preferences.", expected: model.briefings.writingPrompt(registration), model: model)
        checks["Context pages brief edit invalidates exact prior instruction capture"] = !brief.current() && !model.contextKnowledgeAvailable(registration: registration, versions: brief.referenceVersions)
        let policy = model.emailSummaries.policy(registration)
        guard model.emailSummaries.savePolicy("Only surface meaningful fictional cobalt changes. " + String(repeating: "\"\\🌱", count: 1700), registration: registration, expected: policy) else { throw IntegrationError.verification }
        for index in 0..<18 {
            guard model.assistant.memory.saveReviewPreference("Fictional cobalt feedback \(index): " + String(repeating: "\"\\🌱", count: 400), registration: registration, about: String(repeating: "f", count: 280)) else { throw IntegrationError.verification }
        }
        let review = model.captureContextPages(registration: registration, query: nil, pageID: "instructions:review")
        let reviewObject = try object(review.text), feedback = reviewObject["feedback"] as? [[String: String]] ?? []
        checks["Context pages Review policy and feedback obey one final payload bound"] = review.current() && review.text.utf8.count <= 32_000 && reviewObject["unavailable"] == nil && !feedback.isEmpty && (reviewObject["feedbackCount"] as? Int) == 18
        checks["Context pages Review policy capture retains canonical feedback receipts"] = review.referenceVersions["instruction:review"] != nil && review.referenceVersions.keys.filter { $0.hasPrefix("memory:") }.count == feedback.count
        guard model.emailSummaries.savePolicy("Only surface meaningful revised fictional cobalt changes.", registration: registration, expected: model.emailSummaries.policy(registration)) else { throw IntegrationError.verification }
        checks["Context pages Review edit invalidates exact prior policy capture"] = !review.current() && !model.contextKnowledgeAvailable(registration: registration, versions: review.referenceVersions)
        checks["Context pages feature instructions share existing saved authorities"] = model.contextPages.pages(registration: registration).isEmpty
        let currentBrief = model.captureContextPages(registration: registration, query: nil, pageID: "instructions:brief")
        let currentReview = model.captureContextPages(registration: registration, query: nil, pageID: "instructions:review")
        model.chatGPT.activeID = "fictional-other-account"
        checks["Context pages feature instruction captures reject account changes"] = !currentBrief.current() && !currentReview.current() && model.captureContextPages(registration: registration, query: nil, pageID: "instructions:brief").text == "{}" && model.captureContextPages(registration: registration, query: nil, pageID: "instructions:review").text == "{}"
        model.chatGPT.activeID = registration

        model.contextCalendarAccess = { true }
        let calendars = (0..<80).map { SourceOption(id: "fictional-calendar-\($0)", title: "Calendar \($0)", account: "Fictional calendar account", writable: true, providerID: "fictional-provider-\($0)") }
        model.calendarData = .init(sources: calendars, events: [])
        var purposes: [String: ContextPage] = [:]
        for source in calendars {
            let page = try model.contextPages.save(.init(registration: registration, kind: .calendarPurpose, key: model.calendarPageKey(source), owner: .human,
                title: "Calendar purpose", markdown: "Fictional cobalt appointments only. " + String(repeating: "\"\\🌱", count: 650)), expectedRevision: nil)
            purposes[source.id] = page
        }
        let guide = model.captureContextPages(registration: registration, query: nil, pageID: "instructions:calendars")
        let guideObject = try object(guide.text), rows = guideObject["calendars"] as? [[String: Any]] ?? []
        checks["Context pages calendar guide bounds encoded purposes and reports omitted sources"] = guide.current() && guide.text.utf8.count <= 20_000 && !rows.isEmpty && (guideObject["omittedCount"] as? Int) == calendars.count - rows.count && rows.count < calendars.count && rows.allSatisfy { $0["purposeTruncated"] as? Bool == true }
        guard let firstID = rows.first?["id"] as? String, var purpose = purposes[firstID] else { throw IntegrationError.verification }
        purpose.markdown += "\nRevised human purpose"
        _ = try model.contextPages.save(purpose, expectedRevision: purpose.revision)
        checks["Context pages calendar purpose edit invalidates prior guide capture"] = !guide.current() && !model.contextKnowledgeAvailable(registration: registration, versions: guide.referenceVersions)
        let exact = model.calendarPurposeCapture(sources: [calendars[0]], registration: registration)
        var renamed = calendars[0]; renamed.account = "Renamed account label"; renamed.title = "Renamed calendar label"
        let renamedGuide = model.calendarPurposeCapture(sources: [renamed], registration: registration)
        let renamedRows = try object(renamedGuide.text)["calendars"] as? [[String: Any]]
        checks["Context pages calendar guide retains human writing after cosmetic labels change"] = model.calendarPageKey(renamed) == model.calendarPageKey(calendars[0]) && renamedRows?.first?["purpose"] as? String != "Not described"
        var changed = calendars[0]; changed.providerID = "different-fictional-provider"; changed.account = "Different fictional account"
        model.calendarData = .init(sources: [changed] + Array(calendars.dropFirst()), events: [])
        let retargeted = model.calendarPurposeCapture(sources: [changed], registration: registration)
        let retargetedRows = try object(retargeted.text)["calendars"] as? [[String: Any]]
        checks["Context pages calendar purpose cannot follow reused label or source ID across provider accounts"] = !exact.current() && retargetedRows?.first?["purpose"] as? String == "Not described"
        model.calendarData = .init(sources: calendars, events: [])
        let permitted = model.calendarPurposeCapture(sources: [calendars[0]], registration: registration)
        model.assistant.excludedCalendars.insert(calendars[0].id)
        let excludedRows = try object(model.calendarPurposeCapture(sources: [calendars[0]], registration: registration).text)["calendars"] as? [[String: Any]]
        checks["Context pages calendar exclusion revokes supplied guidance"] = !permitted.current() && excludedRows?.isEmpty == true
        model.assistant.excludedCalendars.remove(calendars[0].id)
        let owned = model.calendarPurposeCapture(sources: [calendars[0]], registration: registration)
        model.chatGPT.activeID = "fictional-other-account"
        checks["Context pages calendar guide rejects a changed connected account"] = !owned.current() && model.calendarPurposeCapture(sources: calendars, registration: registration).text == "{}"
        model.chatGPT.activeID = registration
        model.contextCalendarAccess = { false }
        checks["Context pages calendar permission withdrawal revokes guidance without OS reads"] = !owned.current() && model.calendarPurposeCapture(sources: calendars, registration: registration).text == "{}"
        checks["Context pages instruction fixtures make zero inference requests"] = fixture.provider.calls == 0 && fixture.sources.reads == 0 && model.aiUsage.state.records.isEmpty
        return checks
    }

    private static func ownedMutationChecks() async throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        for kind in ["memory", "project"] {
            for independentEdit in [false, true] {
                let fixture = try ContextPagesFixture()
                defer { fixture.clean() }
                let model = fixture.model, registration = fixture.registration, sourceTurn = UUID()
                let words = "Fictional cobalt workshop has a human-approved research purpose."
                try fixture.human(words, id: sourceTurn)
                let fact = PAMemory(registration: registration, text: words, kind: .context, provenance: "Fictional human fixture", sourceTurnID: sourceTurn.uuidString,
                    evidence: words, organisation: .init(areas: [.projects], connections: []))
                guard model.assistant.memory.put(fact) else { throw IntegrationError.verification }
                var project: LifeItem?
                if kind == "project" {
                    project = try model.assistant.projects.save(.init(registration: registration, kind: .space, title: "Cobalt workshop"), expected: nil)
                }
                let knowledge = model.contextKnowledge(registration: registration)
                let support = knowledge.filter { record in
                    if let project { return record.reference.kind == "projectIdentity" && record.reference.key == project.id.uuidString }
                    return record.memoryID == fact.id || record.reference.kind == "human" && record.reference.key == sourceTurn.uuidString
                }.map(\.reference)
                let page = try model.contextPages.save(.init(registration: registration, kind: .note, key: "fictional-owned-purpose", owner: .human,
                    title: "Cobalt workshop purpose", markdown: words, references: support), expectedRevision: nil)
                let prompt = kind == "memory" ? "Forget my cobalt workshop memory and report the saved result." : "Delete the cobalt workshop project and report the saved result."
                let tools = ContextPagesMutationTools(model: model, memoryID: fact.id, projectID: project?.id)
                let args: [String: Any] = kind == "memory" ? ["operation": "forget", "id": fact.id.uuidString, "text": NSNull(), "authorization": prompt] : ["id": project!.id.uuidString, "keepChildren": false, "authorization": prompt]
                fixture.provider.responseCall = .init(id: "fictional-owned-" + kind, name: kind == "memory" ? "change_memory" : "delete_life_item", namespace: "pa", arguments: ContextKnowledgeRules.json(args))
                fixture.provider.holdFinal = true
                var runtime = model.assistantRuntime(), capturedReferences: [String: String] = [:]
                let capture = runtime.contextPages
                runtime.contextPages = { registration, query, topic, includeTopics, everyday in
                    let value = capture(registration, query, topic, includeTopics, everyday)
                    capturedReferences = value.referenceVersions
                    return value
                }
                runtime.tools = { _ in tools }
                runtime.sourceSnapshot = { nil }
                let whatsapp = WhatsAppSourceScope(registration: registration, linkedIdentity: "fictional-unused", revision: UUID())
                runtime.state = { .init(attentionPreferencesReadable: true, resolvedRequests: [], whatsappScope: whatsapp, weatherScope: "fictional-unused", weatherSupplied: false) }
                runtime.afterTurn = {}; runtime.started = { _ in }; runtime.working = { _ in }; runtime.finished = { _ in }
                let conversation = model.assistant.openPA()
                let started = model.assistant.send(runtime: runtime, topicID: nil, prompt: prompt)
                await waitUntil { fixture.provider.held != nil || !model.assistant.busy }
                let label = "Context pages owned \(kind) \(independentEdit ? "with later edit" : "without later edit")"
                let reachedFinal = fixture.provider.held != nil
                checks[label + " captures the exact human page and source human turn"] = capturedReferences["page:" + page.id] == page.revision.uuidString && capturedReferences["human:" + sourceTurn.uuidString] != nil
                checks[label + " reaches final inference after exactly one real local mutation"] = started && reachedFinal && tools.writes == 1
                let minimalPageVersion = ["page:" + page.id: page.revision.uuidString]
                checks[label + " validates transitive page support using only explicitly owned changes"] = reachedFinal && model.contextKnowledgeAvailable(registration: registration, versions: minimalPageVersion, ignoring: tools.adopted)
                var editedRevision: UUID?
                if independentEdit, reachedFinal {
                    var edited = page; edited.markdown = words + "\nThe human independently revised this purpose while the reply was being prepared."
                    editedRevision = try model.contextPages.save(edited, expectedRevision: page.revision).revision
                }
                fixture.provider.release()
                await waitUntil { !model.assistant.busy }
                let turn = conversation.flatMap { model.assistant.conversation($0)?.turns.last }
                let saved = kind == "memory" ? !model.assistant.memory.records.contains(where: { $0.id == fact.id }) : model.assistant.projects.items(registration, includeTopics: true).isEmpty
                checks[label + " preserves one verified mutation and its receipt"] = saved && tools.writes == 1 && tools.receipts.count == 1 && turn?.actionResult?.confirmedActions == 1
                if independentEdit {
                    checks[label + " refuses final prose after independent human revision"] = reachedFinal && !model.assistant.busy && model.assistant.error != nil && turn?.content.contains(ContextPagesInference.finalText) == false && turn?.actionResult?.phase != "completed"
                    checks[label + " retains the independently saved page version"] = editedRevision != nil && model.contextPages.page(id: page.id, registration: registration)?.revision == editedRevision && !model.contextKnowledgeAvailable(registration: registration, versions: minimalPageVersion, ignoring: tools.adopted)
                } else {
                    checks[label + " completes its authorised turn despite retiring its own context"] = reachedFinal && !model.assistant.busy && model.assistant.error == nil && turn?.content.contains(ContextPagesInference.finalText) == true && turn?.actionResult?.phase == "completed"
                }
                checks[label + " uses completed fictional transport without subscription requests"] = fixture.provider.calls == 2 && fixture.sources.reads == 0 && model.aiUsage.state.records.isEmpty
                if !reachedFinal || (independentEdit == (model.assistant.error == nil)) {
                    let detail = label + ": calls=\(fixture.provider.calls), writes=\(tools.writes), phase=\(turn?.actionResult?.phase ?? "missing"), error=\(model.assistant.error ?? "none")\n"
                    FileHandle.standardError.write(Data(detail.utf8))
                }
                if model.assistant.busy { model.assistant.cancel(); await waitUntil { !model.assistant.busy } }
            }
        }
        return checks
    }

    private static func object(_ text: String) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw IntegrationError.verification }
        return value
    }
    private static func waitUntil(_ finished: @MainActor () -> Bool) async {
        for _ in 0..<40_000 { if finished() { return }; await Task.yield() }
    }
}

@MainActor private final class ContextPagesFixture {
    let model: DashboardModel
    let sources: ContextPagesNativeFixture
    let provider = ContextPagesInference()
    let settings: UserDefaults
    let suite: String
    let images: URL
    var registration: String { provider.activeID }
    init() throws {
        guard ProcessInfo.processInfo.arguments.contains("--validate-advice-context") else { throw IntegrationError.verification }
        let sourcePort = ContextPagesNativeFixture(); sources = sourcePort
        model = DashboardModel(nativeSources: sourcePort)
        guard let container = model.container else { throw IntegrationError.verification }
        suite = "3PO.context-pages-fixture." + UUID().uuidString
        guard let settings = UserDefaults(suiteName: suite) else { throw IntegrationError.verification }
        self.settings = settings
        images = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        settings.set(true, forKey: "assistantContextEnabled"); settings.set(true, forKey: "paMemoryEnabled")
        model.assistant = AssistantService(connection: provider, container: container, settings: settings, imageDirectory: images)
        model.chatGPT.activeID = provider.activeID
        model.contextCalendarAccess = { false }
    }
    func clean() { provider.release(); settings.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: images) }
    func human(_ words: String, id: UUID) throws {
        guard model.assistant.openReview(key: "fictional-context-human-" + id.uuidString, title: "Fictional context", sourceKind: "fictional", accountID: nil, messageID: nil, identity: nil, chatID: nil,
            seeds: [.init(id: id, role: "user", content: words, completed: true)]) != nil else { throw IntegrationError.verification }
    }
}

@MainActor private final class ContextPagesNativeFixture: NativeSourceReading {
    private(set) var reads = 0
    func calendar(from: Date, to: Date) async throws -> CalendarSnapshot { reads += 1; return .init(sources: [], events: []) }
    func reminders() async throws -> ReminderSnapshot { reads += 1; return .init(sources: [], reminders: []) }
    func completedReminders(excluded: Set<String>, now: Date) async throws -> [CompletedReminder] { reads += 1; return [] }
}

@MainActor private final class ContextPagesInference: PAInferenceConnection {
    static let finalText = "Fictional owned context change completed and verified."
    var activeID = "fictional-context-pages-owner", selectedModel = "fictional-model"
    var busy = false, usagePaused = false, inferenceVerified = true, hasSession = true
    var calls = 0, responseCall: PAFunctionCall?, holdFinal = false
    var held: CheckedContinuation<Void, Never>?
    func streamResponse(input: [[String: String]], instructions: String, model: String?, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> String {
        throw ActionFailure.message("Context-page fixture requires completed fictional transport.")
    }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        calls += 1
        if calls == 1, let responseCall {
            return .init(text: "", output: [["type": "function_call", "call_id": responseCall.id, "name": responseCall.name, "arguments": responseCall.arguments]], calls: [responseCall])
        }
        if holdFinal { await withCheckedContinuation { held = $0 } }
        return .init(text: Self.finalText, output: [], calls: [])
    }
    func release() { let continuation = held; held = nil; continuation?.resume() }
}

@MainActor private final class ContextPagesMutationCursor: AssistantMailCursor {
    var status = "Fictional fixture has no Mail search", results: [MailMessage] = [], hasMore = false, hasUnavailable = false
}

/// Only the final local action boundary is replaced. Actual stores mutate and the
/// real assistant must decide whether its captured context can be adopted.
@MainActor private final class ContextPagesMutationTools: AssistantToolSession {
    let model: DashboardModel
    let memoryID: UUID
    let projectID: UUID?
    let calendar = CalendarSnapshot(sources: [], events: []), reminders = ReminderSnapshot(sources: [], reminders: [])
    var itemDetails: [String: NativeEditDetails] = [:]
    var consultedMemory: Set<UUID>
    var consultedWorkspace: Set<UUID>
    var receipts: [String] = [], memoryNotes: [String] = []
    var clarification: (String, [String])?
    var mailCursor: any AssistantMailCursor = ContextPagesMutationCursor()
    private(set) var writes = 0, adopted = Set<String>()
    func adoptContextChanges(_ keys: Set<String>) { adopted.formUnion(keys) }
    init(model: DashboardModel, memoryID: UUID, projectID: UUID?) {
        self.model = model; self.memoryID = memoryID; self.projectID = projectID
        consultedMemory = [memoryID]; consultedWorkspace = projectID.map { [$0] } ?? []
    }
    func execute(_ call: PAFunctionCall, valid: @escaping NativeWriteValidity) async throws -> String {
        guard valid(), writes == 0 else { throw IntegrationError.verification }
        if let projectID {
            guard call.name == "delete_life_item" else { throw IntegrationError.verification }
            try model.assistant.projects.trash(projectID, registration: model.chatGPT.activeID, keepChildren: false, expectedRevision: model.assistant.projects.revision)
        } else {
            guard call.name == "change_memory", model.assistant.memory.forget(memoryID) else { throw IntegrationError.verification }
        }
        writes += 1
        receipts.append("Fictional \(projectID == nil ? "memory forgotten" : "project moved to Recently deleted") and verified")
        return ContextKnowledgeRules.json(["verified": true, "id": (projectID ?? memoryID).uuidString])
    }
}
#endif
