import Foundation

/// One authenticated MCP connection owns its issued identities. Host-approved
/// mutations reuse the app's canonical stores; this layer never starts inference.
@MainActor final class MCPAppToolSession {
    let model: DashboardModel
    let tools: PAToolSession
    let registration: String
    private var memories: [UUID: PAMemory] = [:]
    private var pages: [String: ContextPage] = [:]
    private var projectNotes: [UUID: LifeItem] = [:]
    private var instructionReads: [String: Instruction] = [:]
    private var reviewReads: [String: String] = [:]
    private struct Instruction {
        var revision: String
        var text: String
        var page: ContextPage?
        var candidate: ContextPage?
        var brief: BriefWritingPrompt?
        var review: ReviewPolicyCapture?
    }
    init(model: DashboardModel) {
        self.model = model; registration = model.inference.activeID
        tools = PAToolSession(model: model, human: MCPBridgeContract.hostProvenance,
                              humanContext: "External MCP host session", topicID: nil, turnID: UUID(), focusAreas: [])
    }
    static func permissionScope(_ model: DashboardModel) -> String {
        let access = model.whatsapp.access(for: model.inference.activeID)
        return [model.inference.activeID, model.reviewStorageIdentity, String(model.assistant.contextEnabled),
                String(model.assistant.memory.enabled), model.assistant.excludedCalendars.sorted().joined(separator: "\n"),
                model.assistant.excludedLists.sorted().joined(separator: "\n"), model.assistant.excludedAccounts.sorted().joined(separator: "\n"),
                model.whatsapp.linkedIdentity, String(access.enabled), String(access.includeInSuggestions == true), access.chats.sorted().joined(separator: "\n")].joined(separator: "\u{0}")
    }
    private func json(_ value: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self) }
    private func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
    private func version<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return ContextKnowledgeRules.fingerprint(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
    private func result(_ message: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        extra.merging(["saved": true, "result": message]) { _, new in new }
    }
    func execute(_ call: PAFunctionCall, requestID: UUID?, valid: @escaping NativeWriteValidity) async throws -> String {
        var mutationStarted = false
        do { return try await executeApp(call, requestID: requestID, valid: valid, willMutate: { mutationStarted = true }) }
        catch {
            if MCPBridgeContract.customWrites.contains(call.name), !mutationStarted { throw MCPPreSaveFailure(message: error.localizedDescription) }
            throw error
        }
    }
    private func executeApp(_ call: PAFunctionCall, requestID: UUID?, valid: @escaping NativeWriteValidity, willMutate: () -> Void) async throws -> String {
        guard registration == model.inference.activeID, valid() else { throw ActionFailure.message("The external account or source access changed.") }
        let args = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as! [String: Any]
        func text(_ key: String) -> String? { args[key] as? String }
        if MCPBridgeContract.nativeReads.contains(call.name) || MCPBridgeContract.nativeWrites.contains(call.name) {
            let output = try await tools.executeMCP(call, requestID: requestID, valid: valid)
            if ["read_memory", "read_life_notebook"].contains(call.name) {
                let value = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any] ?? [:]
                var returned = Set((value["records"] as? [[String: String]] ?? []).compactMap { $0["id"].flatMap(UUID.init(uuidString:)) })
                let notebook = value["notes"] as? [String: Any] ?? [:]
                for area in notebook["areas"] as? [[String: Any]] ?? [] {
                    returned.formUnion((area["facts"] as? [[String: String]] ?? []).compactMap { $0["id"].flatMap(UUID.init(uuidString:)) })
                }
                for record in model.assistant.memory.permittedRecords where returned.contains(record.id) { memories[record.id] = record }
            }
            return output
        }
        let memory = model.assistant.memory
        switch call.name {
        case "about_3po":
            let items = model.assistant.projects.items(registration, includeTopics: true)
            let records = model.contextKnowledge(registration: registration, includeTopics: true, purpose: .conversation)
            let guide = model.contextNavigationGuide(registration: registration, items: items, records: records)
            return try json(["app": "3PO", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
                "purpose": "Your local macOS personal assistant: personal context and instructions, nested Projects with tasks and notes, Apple Calendar and Reminders, a daily Brief and saved Review inbox.",
                "guide": guide.text, "instructions": MCPBridgeContract.instructions,
                "permissions": ["approvalLocation": "The connected assistant's tool permission UI", "sourceContextEnabled": model.assistant.contextEnabled,
                    "memoryEnabled": memory.enabled, "excludedCalendarCount": model.assistant.excludedCalendars.count,
                    "excludedReminderListCount": model.assistant.excludedLists.count, "excludedEmailAccountCount": model.assistant.excludedAccounts.count],
                "tools": MCPBridgeContract.definitions.map { $0["name"] as! String },
                "limits": "Mac and 3PO must be running. Current account only. Source choices and native OS permissions still apply. Email and WhatsApp are read-only; no sending, provider credentials or arbitrary file/shell access. Maintained pages are read-only; edit human notes, instructions or underlying facts. No background AI work is started by these tools."])
        case "read_instructions":
            guard let target = text("target") else {
                return try json(["targets": ["assistant", "projects", "reminders", "brief", "review"],
                    "additionalScopes": "calendar:<ID from read_calendar>, space:<UUID from read_life_items>, topic:<area key>",
                    "topics": LifeArea.allCases.map(\.rawValue) + ["recent"], "note": "Read the applicable target before changing guidance. Read instructions:calendars via read_context_page for the calendar-purpose directory."])
            }
            let value = try instruction(target)
            instructionReads[target] = value
            if target == "review" {
                return try json(["target": target, "revision": value.revision, "text": value.text,
                                 "ownership": "One complete editable Review guide, incorporating learned preferences during heartbeats. Original feedback is retained in memory history. This guidance grants no source access or action approval."])
            }
            let learned = instructionMemories(target)
            for record in learned { memories[record.id] = record }
            return try json(["target": target, "revision": value.revision, "text": value.text,
                             "learnedGuidance": learned.map { ["id": $0.id.uuidString, "text": $0.text, "instructionScope": $0.effectiveInstructionScope ?? ""] },
                             "ownership": "text is the explicit editable policy. Learned guidance is separate saved memory; use change_memory to correct/forget an issued learned rule. Explicit instructions take priority. Neither grants source access or action approval."])
        case "change_instructions":
            let target = text("target")!, expected = text("revision")!, value = text("text")!
            guard let captured = instructionReads[target], captured.revision == expected,
                  try instruction(target).revision == expected,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ActionFailure.message("Read the current instructions before replacing them. Empty guidance is not saved.") }
            guard captured.brief == nil || value.count <= 8000,
                  captured.review == nil || value.count <= ReviewPolicyRules.textLimit,
                  captured.page == nil && captured.candidate == nil || value.utf8.count <= ContextPageLimits.maximumMarkdownBytes else { throw ActionFailure.message("The instruction text exceeds this editor's size limit.") }
            willMutate()
            if let brief = captured.brief { try model.briefings.saveWritingPrompt(value, expected: brief, model: model) }
            else if let review = captured.review {
                guard model.emailSummaries.savePolicy(value, registration: registration, expected: review) else { throw ActionFailure.message(model.emailSummaries.reviewPolicies.error ?? "Review guidance could not be saved.") }
            } else {
                guard var page = captured.page ?? captured.candidate else { throw ActionFailure.message("This instruction target is unavailable.") }
                page.markdown = value; page.synopsis = ""
                _ = try model.contextPages.save(page, expectedRevision: captured.page?.revision)
            }
            let saved = try instruction(target)
            guard saved.text == value || saved.text == value.trimmingCharacters(in: .whitespacesAndNewlines) else { throw ActionFailure.message("The instruction save could not be verified. Read it before continuing.") }
            instructionReads.removeValue(forKey: target)
            return try json(result("Updated 3PO instructions: " + target, ["target": target, "revision": saved.revision]))
        case "read_context_notes":
            guard model.contextPages.isReadable else { throw ContextPageFailure.unavailable }
            let records = model.contextKnowledge(registration: registration, includeTopics: true, purpose: .inspection)
            if let id = text("id") {
                guard let page = model.contextPages.page(id: id, registration: registration), eligible(page, records: records) else { throw ActionFailure.message("That context page is unavailable under the current source choices.") }
                pages[id] = page
                return try json(["page": try object(page), "editable": page.owner == .human && page.kind != .instruction && page.kind != .calendarPurpose])
            }
            let available = model.contextPages.pages(registration: registration).filter { eligible($0, records: records) }
            return try json(["pages": available.prefix(100).map { ["id": $0.id, "title": $0.title, "kind": $0.kind.rawValue, "revision": $0.revision.uuidString, "editable": $0.owner == .human && $0.kind != .instruction && $0.kind != .calendarPurpose] as [String: Any] }, "omitted": max(0, available.count - 100)])
        case "change_context_note":
            let operation = text("operation")!
            let page: ContextPage
            if operation == "create" {
                guard text("id") == nil, text("revision") == nil, let title = text("title"), let markdown = text("markdown") else { throw ActionFailure.message("A new note needs a title and Markdown; id and revision must be null.") }
                page = ContextPage(registration: registration, kind: .note, key: "external-note:" + requestID!.uuidString, owner: .human, title: title, markdown: markdown)
            } else {
                guard let id = text("id"), let prior = pages[id], prior.owner == .human,
                      ![ContextPage.Kind.instruction, .calendarPurpose].contains(prior.kind),
                      text("revision") == prior.revision.uuidString,
                      model.contextPages.page(id: id, registration: registration) == prior,
                      eligible(prior, records: model.contextKnowledge(registration: registration, includeTopics: true, purpose: .inspection)) else { throw ActionFailure.message("Read the current human-owned note and revision before changing it.") }
                page = prior
            }
            if operation == "forget" {
                guard text("title") == nil, text("markdown") == nil else { throw ActionFailure.message("Forget requires null title and Markdown.") }
                willMutate()
                try model.contextPages.forget(id: page.id, registration: registration, expectedRevision: page.revision)
                guard model.contextPages.page(id: page.id, registration: registration) == nil else { throw ActionFailure.message("The note removal could not be verified.") }
                pages.removeValue(forKey: page.id)
                return try json(result("Forgot human context note and its history.", ["id": page.id]))
            }
            guard let title = text("title"), let markdown = text("markdown"), !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ActionFailure.message("Supply a title and nonempty Markdown.") }
            var edited = page; edited.title = title; edited.markdown = markdown; edited.synopsis = ""
            willMutate()
            let saved = try model.contextPages.save(edited, expectedRevision: operation == "create" ? nil : page.revision)
            guard model.contextPages.page(id: saved.id, registration: registration) == saved else { throw ActionFailure.message("The note save could not be verified.") }
            var acknowledgement: String?
            do { _ = try model.acknowledgeProjectPurpose(saved) } catch { acknowledgement = "Note saved; its matching question could not be acknowledged. Read Review inbox before retrying only the acknowledgement." }
            pages.removeValue(forKey: saved.id)
            var extra: [String: Any] = ["id": saved.id, "revision": saved.revision.uuidString]
            if let acknowledgement { extra["notice"] = acknowledgement }
            return try json(result("Saved human context note.", extra))
        case "read_memory_records":
            guard memory.enabled, let offset = args["offset"] as? Int, (0...1_000_000).contains(offset) else { throw ActionFailure.message("Enable memory use and supply a nonnegative offset.") }
            let state = text("state")!, query = text("query")?.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init) ?? []
            let available = memory.permittedRecords.filter { record in
                guard record.registration == registration, record.supersededBy == nil, record.sourceInvalidation == nil else { return false }
                let matches = query.allSatisfy { record.text.lowercased().contains($0) }
                let included = state == "all" || (state == "resolved" ? record.resolved != nil : state == "retired" ? record.retiredAt != nil : record.resolved == nil && record.retiredAt == nil)
                return matches && included
            }.sorted { $0.id.uuidString < $1.id.uuidString }
            let selected = Array(available.dropFirst(offset).prefix(60))
            for record in selected { memories[record.id] = record }
            return try json(["records": selected.map { record in
                ["id": record.id.uuidString, "text": record.text, "kind": record.kind.rawValue, "evidence": record.evidence ?? "", "provenance": record.provenance,
                 "resolved": record.resolved != nil, "retired": record.retiredAt != nil, "scope": record.conversationID?.uuidString ?? "shared", "reviewPreference": record.reviewPreference == true, "instructionScope": record.effectiveInstructionScope as Any? ?? NSNull()] as [String: Any]
            }, "total": available.count, "nextOffset": offset + selected.count < available.count ? (offset + selected.count) as Any : NSNull(), "coverage": "Current saved versions only; forgotten records and inaccessible source content are withheld."])
        case "save_memory":
            guard memory.enabled, let value = text("text"), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let evidence = text("evidence"), !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ActionFailure.message("Memory use must be enabled; supply a supported fact and its human evidence.") }
            let record = PAMemory(registration: registration, text: value, kind: MemoryKind(rawValue: text("kind")!)!, explicit: true,
                provenance: "Saved through an external MCP assistant; human evidence supplied by that assistant", sourceTurnID: requestID!.uuidString,
                evidence: evidence, sourceDate: .now, certainty: .stated, durability: .stable)
            willMutate()
            guard memory.put(record), memory.permittedRecords.contains(where: { $0.id == record.id && $0.text == value }) else { throw ActionFailure.message(memory.error ?? "Memory save could not be verified.") }
            return try json(result("Saved shared 3PO memory.", ["id": record.id.uuidString]))
        case "change_memory":
            guard memory.enabled, let id = text("id").flatMap(UUID.init(uuidString:)), let prior = memories[id],
                  memory.permittedRecords.contains(prior), prior.registration == registration, prior.supersededBy == nil, prior.sourceInvalidation == nil,
                  let evidence = text("evidence"), !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ActionFailure.message("Read the current permitted memory before changing it, and supply the current human request.") }
            let operation = text("operation")!
            var resultID = id
            let success: Bool
            switch operation {
            case "forget": willMutate(); success = memory.forget(id)
            case "resolve": willMutate(); success = memory.resolve(id)
            case "reopen": willMutate(); success = memory.reopen(id)
            default:
                guard let value = text("text"), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 2000 else { throw ActionFailure.message("Supply the corrected fact, up to 2000 characters.") }
                var revised = prior; revised.id = UUID(); revised.text = value; revised.explicit = true
                revised.evidence = evidence; revised.sourceTurnID = requestID!.uuidString; revised.sourceDate = .now
                revised.provenance = "Corrected through an external MCP assistant; human evidence supplied by that assistant"
                revised.connections = nil; revised.organisation = nil; revised.certainty = .stated; revised.durability = nil
                revised.source = nil; revised.supportingSources = nil; revised.sourceState = nil; revised.sourceInvalidation = nil
                willMutate()
                success = memory.correct(id, with: revised); resultID = revised.id
            }
            guard success else { throw ActionFailure.message(memory.error ?? "Memory change could not be saved.") }
            guard operation == "forget" ? !memory.permittedRecords.contains(where: { $0.id == id }) : memory.records.contains(where: { $0.id == resultID && (operation == "correct" ? $0.text == text("text") : operation == "resolve" ? $0.resolved != nil : $0.resolved == nil) }) else { throw ActionFailure.message("The memory outcome could not be verified.") }
            memories.removeValue(forKey: id)
            return try json(result("Saved 3PO memory change: " + operation, ["id": resultID.uuidString]))
        case "read_review_inbox":
            guard let offset = args["offset"] as? Int, (0...1_000_000).contains(offset) else { throw ActionFailure.message("Supply a nonnegative Review offset, starting at zero.") }
            let rows = try reviewRows()
            var selected: [[String: Any]] = [], bytes = 0
            for row in rows.dropFirst(offset).prefix(40) {
                let count = try JSONSerialization.data(withJSONObject: row).count
                guard bytes + count <= 240_000 else { break }
                selected.append(row); bytes += count
            }
            for row in selected { reviewReads[row["id"] as! String] = row["revision"] as? String }
            let next = offset + selected.count
            return try json(["items": selected, "total": rows.count, "nextOffset": next < rows.count ? next as Any : NSNull(), "pendingCount": model.reviewInbox.pendingCount,
                             "coverage": "Saved Review presentation only. Suggestions are proposals, not approvals or proof of current native state. Use source reads and separate change tools for requested work."])
        case "dismiss_review_item":
            let id = text("id")!, revision = text("revision")!
            guard reviewReads[id] == revision, try reviewRows().contains(where: { $0["id"] as? String == id && $0["revision"] as? String == revision }) else { throw ActionFailure.message("This Review item changed. Read its current version before acknowledging it.") }
            let inbox = model.reviewInbox
            willMutate()
            if id.hasPrefix("email:"), let card = inbox.emailCards.first(where: { "email:" + $0.id == id }) {
                let version = ReviewAcknowledgementRules.emailVersion(card.message, card.summary)
                model.emailSummaries.dismiss(card.id, model: model, expectedRegistration: registration, expectedVersion: version)
                guard model.emailSummaries.records.contains(where: { $0.id == card.id && $0.registration == registration && $0.dismissed == true && $0.dismissedSourceVersion == version }) else { throw ActionFailure.message("Email acknowledgement could not be saved.") }
            } else if id.hasPrefix("discovery:"), let record = inbox.discoveries.first(where: { "discovery:" + $0.id == id }) {
                model.proactive.dismiss(record, model: model)
                guard model.proactive.state.records.contains(where: { $0.id == record.id && $0.registration == registration && $0.dismissed }) else { throw ActionFailure.message("Suggestion acknowledgement could not be saved.") }
            } else if id.hasPrefix("brief:"), let question = inbox.questions.first(where: { "brief:" + $0.id == id }) {
                guard model.briefings.resolveQuestion(question, model: model, answered: false) else { throw ActionFailure.message("Question acknowledgement could not be saved.") }
            } else if id.hasPrefix("memory:"), let question = inbox.learningQuestions.first(where: { "memory:" + $0.id == id }) {
                model.memoryLearning.dismiss(question)
                guard model.memoryLearning.state.questions?.contains(where: { $0.id == question.id && $0.dismissed }) == true else { throw ActionFailure.message("Question acknowledgement could not be saved.") }
            } else if id.hasPrefix("project:"), let question = inbox.contextQuestions.first(where: { "project:" + $0.id == id }) {
                _ = try model.contextQuestions.dismiss(id: question.id, registration: registration, expectedRevision: question.revision)
            } else { throw ActionFailure.message("This Review item cannot be dismissed with this tool.") }
            reviewReads.removeValue(forKey: id)
            return try json(result("Acknowledged Review item; no proposed action or task was completed.", ["id": id, "completed": false]))
        case "read_project_notes":
            guard let id = text("id").flatMap(UUID.init(uuidString:)) else { throw ActionFailure.message("Use an issued project UUID.") }
            let item = try tools.mcpProjectItem(id)
            projectNotes[id] = item
            return try json(["id": id.uuidString, "title": item.title, "revision": item.revision.uuidString, "notes": try object(item.noteCards)])
        case "change_project_note":
            guard let id = text("id").flatMap(UUID.init(uuidString:)), let captured = projectNotes[id], text("revision") == captured.revision.uuidString,
                  let current = model.assistant.projects.items(registration, includeTopics: true).first(where: { $0.id == id }), current == captured else { throw ActionFailure.message("Read the current project note cards before editing them.") }
            var edited = current
            let value = text("text")!
            if let noteID = text("noteID") {
                guard let note = UUID(uuidString: noteID), current.noteCards.contains(where: { $0.id == note }) else { throw ActionFailure.message("Use an exact issued note card UUID.") }
                if note == current.id { edited.notes = value; edited.notesFormatting = nil }
                else if let index = edited.additionalNotes?.firstIndex(where: { $0.id == note }) {
                    if value.isEmpty { edited.additionalNotes?.remove(at: index) }
                    else { edited.additionalNotes?[index].text = value; edited.additionalNotes?[index].formatting = nil }
                }
            } else {
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ActionFailure.message("A new note cannot be empty.") }
                edited.additionalNotes = (edited.additionalNotes ?? []) + [LifeNote(id: requestID!, text: value)]
            }
            willMutate()
            let saved = try model.assistant.projects.save(edited, expected: current.revision)
            guard model.assistant.projects.items(registration, includeTopics: true).contains(saved) else { throw ActionFailure.message("The project note save could not be verified.") }
            projectNotes.removeValue(forKey: id)
            return try json(result("Saved project note card.", ["id": id.uuidString, "revision": saved.revision.uuidString]))
        default: throw ActionFailure.message("Unsupported external tool.")
        }
    }
    private func instructionMemories(_ target: String) -> [PAMemory] {
        var scope = target
        if target.hasPrefix("calendar:") {
            guard let source = tools.calendar.sources.first(where: { "calendar:" + $0.id == target && !model.assistant.excludedCalendars.contains($0.id) }) else { return [] }
            scope = "calendar:" + model.calendarPageKey(source)
        }
        return model.assistant.memory.instructionPreferences(scope, registration: registration)
    }
    private func instruction(_ target: String) throws -> Instruction {
        var value = try baseInstruction(target)
        if target == "review" { return value }
        let learned = instructionMemories(target)
        if !learned.isEmpty { value.revision += ":" + (try version(learned)) }
        return value
    }
    private func baseInstruction(_ target: String) throws -> Instruction {
        if target == "brief" {
            guard model.briefings.writingPromptReadable else { throw ActionFailure.message("Saved brief instructions are unavailable.") }
            let value = model.briefings.writingPrompt(registration)
            return Instruction(revision: value.revision?.uuidString ?? "default", text: value.text, brief: value)
        }
        if target == "review" {
            guard model.emailSummaries.reviewPolicies.readable else { throw ActionFailure.message("Saved Review guidance is unavailable.") }
            let value = model.emailSummaries.policy(registration)
            return Instruction(revision: value.revision, text: value.text, review: value)
        }
        guard model.contextPages.isReadable else { throw ContextPageFailure.unavailable }
        let candidate: ContextPage
        var defaultText = ""
        if let feature = ContextFeature(rawValue: target) {
            defaultText = feature == .assistant ? model.assistant.preferences : feature.defaultText
            candidate = .init(registration: registration, kind: .instruction, key: target, owner: .human, title: feature.title, markdown: defaultText)
        } else if target.hasPrefix("calendar:") {
            let id = String(target.dropFirst(9))
            guard let source = tools.calendar.sources.first(where: { $0.id == id && !model.assistant.excludedCalendars.contains(id) }) else { throw ActionFailure.message("Read the permitted calendar before editing its purpose.") }
            candidate = .init(registration: registration, kind: .calendarPurpose, key: model.calendarPageKey(source), owner: .human, title: "Calendar purpose", markdown: "")
        } else if let scope = ContextInstructionScope(key: target) {
            candidate = .init(registration: registration, kind: .instruction, key: scope.key, owner: .human, title: "Instructions for " + target, markdown: "")
        } else { throw ActionFailure.message("Unknown instruction target. Read the instruction directory.") }
        var scoped = candidate
        if case .space(let id) = ContextInstructionScope(key: target) {
            let item = try tools.mcpProjectItem(id)
            guard !item.kind.isWork else { throw ActionFailure.message("Scoped instructions belong to a project space.") }
            scoped.title = "Instructions for " + item.title
            scoped.references = [projectIdentity(item)]
        }
        guard model.contextPages.identityStatus(id: scoped.id, registration: registration) != .preserved else { throw ContextPageFailure.unsupportedPage }
        let saved = model.contextPages.page(id: scoped.id, registration: registration)
        guard saved == nil || (saved!.owner == .human && saved!.references == scoped.references) else { throw ActionFailure.message("Saved guidance has a different owner or scope. Reopen it in 3PO.") }
        return Instruction(revision: saved?.revision.uuidString ?? "new:" + ContextKnowledgeRules.fingerprint(target + registration), text: saved?.markdown ?? defaultText, page: saved, candidate: scoped)
    }
    private func projectIdentity(_ item: LifeItem) -> ContextPageReference {
        .init(kind: "projectIdentity", key: item.id.uuidString, revision: ContextKnowledgeRules.fingerprint(item.registration + ":" + item.id.uuidString + ":" + (item.conversationID?.uuidString ?? "shared")))
    }
    private func eligible(_ page: ContextPage, records: [ContextKnowledgeRecord]) -> Bool {
        guard page.registration == registration else { return false }
        if page.kind == .calendarPurpose {
            return page.owner == .human && tools.calendar.sources.contains { !model.assistant.excludedCalendars.contains($0.id) && model.calendarPageKey($0) == page.key }
        }
        if page.owner == .human {
            if page.references.isEmpty { return true }
            if page.references.count == 1, let reference = page.references.first, reference.kind == "projectIdentity",
               let item = model.assistant.projects.items(registration, includeTopics: true).first(where: { $0.id.uuidString == reference.key && !$0.kind.isWork }) { return reference == projectIdentity(item) }
        }
        return model.assistant.memory.enabled && model.contextPageEligible(page, records: records)
    }
    private func reviewRows() throws -> [[String: Any]] {
        let inbox = model.reviewInbox
        var rows: [[String: Any]] = []
        func row<T: Encodable>(_ prefix: String, _ id: String, _ value: T, title: String) throws {
            let data = try object(value)
            let encoded = try json(data)
            rows.append(["id": prefix + id, "revision": try version(value), "title": String(title.prefix(1000)),
                         "data": encoded.utf8.count <= 20_000 ? data : String(encoded.prefix(10_000)), "dataTruncated": encoded.utf8.count > 20_000])
        }
        for card in inbox.emailCards { try row("email:", card.id, card.summary, title: card.message.subject) }
        for discovery in inbox.discoveries { try row("discovery:", discovery.id, discovery, title: discovery.message) }
        for question in inbox.questions { try row("brief:", question.id, question, title: question.question) }
        for question in inbox.learningQuestions { try row("memory:", question.id, question, title: question.text) }
        for question in inbox.contextQuestions { try row("project:", question.id, question, title: question.question) }
        return rows
    }
}
