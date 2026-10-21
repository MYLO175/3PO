import Foundation
import Observation

@MainActor @Observable final class ContextConsolidationService {
    private(set) var busy = false
    private(set) var ownedHeartbeatRunID: String?
    private(set) var error: String?
    private(set) var status = "Context pages update during a heartbeat when relevant information changes."

    private func mayOfferQuestion(_ model: DashboardModel, registration: String, now: Date = .now) -> Bool {
        guard model.memoryLearning.questionsEnabled, model.contextQuestions.canSave,
              model.contextQuestions.questions(registration: registration).isEmpty,
              !model.memoryLearning.offeredQuestion(registration: registration, on: now) else { return false }
        return !model.contextQuestions.questions(registration: registration, includeFinished: true).contains { BriefingRules.day($0.created) == BriefingRules.day(now) }
    }

    func targets(_ model: DashboardModel, registration: String) -> [ContextPageTarget] {
        let records = model.contextKnowledge(registration: registration)
        let memory = model.assistant.memory.permittedRecords.filter { MemoryRules.usable($0, registration: registration) }
        let humanMemory = Set(memory.filter { $0.source == nil }.map(\.id))
        let everyday = Set(memory.filter { $0.source == nil && $0.reviewPreference != true && $0.conversationID == nil &&
            ($0.kind == .preference || $0.organisation?.areas.contains(.about) == true) }.map(\.id))
        var result: [ContextPageTarget] = []
        func append(kind: ContextPage.Kind, key: String, title: String, candidates: [ContextKnowledgeRecord], projectID: UUID? = nil, mayAskPurpose: Bool = false) {
            guard !candidates.isEmpty else { return }
            let id = ContextPage.stableID(registration: registration, kind: kind, key: key)
            let old = model.contextPages.page(id: id, registration: registration)
            let current = Dictionary(candidates.map { ($0.reference.contextKey, $0.reference) }, uniquingKeysWith: { first, _ in first })
            let processed = (old?.processedReferences ?? old?.references ?? []).filter { current[$0.contextKey]?.revision == $0.revision }
            let acknowledged = Dictionary(processed.map { ($0.contextKey, $0.revision) }, uniquingKeysWith: { first, _ in first })
            func pending(_ record: ContextKnowledgeRecord) -> Bool { acknowledged[record.reference.contextKey] != record.reference.revision }
            let oldSupport = Set(old?.references.map(\.contextKey) ?? [])
            let ordered = candidates.sorted { lhs, rhs in
                if pending(lhs) != pending(rhs) { return pending(lhs) }
                if oldSupport.contains(lhs.reference.contextKey) != oldSupport.contains(rhs.reference.contextKey) { return oldSupport.contains(lhs.reference.contextKey) }
                return lhs.date == rhs.date ? lhs.reference.contextKey < rhs.reference.contextKey : lhs.date < rhs.date
            }
            var bounded = Array(ordered.prefix(20))
            let boundedTitle = ContextKnowledgeRules.bytePrefix(String(title.prefix(60)), maximumBytes: ContextPageLimits.maximumTitleBytes)
            var target = ContextPageTarget(registration: registration, kind: kind, key: key, title: boundedTitle.isEmpty ? "Project context" : boundedTitle, records: bounded,
                projectID: projectID, mayAskPurpose: mayAskPurpose, hasPendingChanges: candidates.contains(where: pending), processedReferences: processed)
            while ContextKnowledgeRules.json(target.input).utf8.count > 20_000 && bounded.count > 1 {
                bounded.removeLast(); target.records = bounded
            }
            result.append(target)
        }
        let overview = records.filter { $0.memoryID.map(everyday.contains) == true }
        append(kind: .overview, key: "maintained", title: "Everyday overview", candidates: overview)
        for area in LifeArea.allCases {
            let selected = records.filter { $0.reference.kind == "memory" && $0.areas.contains(area) }
            append(kind: .topic, key: area.rawValue, title: area.title, candidates: selected)
        }
        let notebook = model.assistant.memory.notebook(registration, includeTopics: true)
        let items = model.assistant.projects.items(registration, includeTopics: true)
        for item in items where !item.kind.isWork {
            let linked = notebook.anchors.first { $0.id == "life:" + item.id.uuidString }?.memoryIDs ?? []
            let children = Set(items.filter { $0.parentID == item.id }.map(\.id)).union([item.id])
            var selected = records.filter { $0.reference.kind == "project" && $0.projectID.map(children.contains) == true }
            selected += records.filter { $0.reference.kind == "page" && $0.projectID == item.id }
            selected += records.filter { $0.memoryID.map(linked.contains) == true }
            selected += records.filter { ContextKnowledgeRules.projectCandidate($0, title: item.title, notes: item.searchableNotes, selfLabel: notebook.selfLabel) }.map {
                var candidate = $0
                candidate.relevance = "Lexically retrieved candidate for this existing project. Verify relevance from its text; a similar name is not a confirmed relationship. Omit unrelated material."
                return candidate
            }
            guard !selected.isEmpty else { continue }
            let hasPurpose = !item.searchableNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selected.contains { $0.reference.kind == "page" } || !linked.intersection(humanMemory).isEmpty
            let meaningfulProject = item.kind == .project || (!items.filter { $0.parentID == item.id && $0.kind.isWork }.isEmpty)
            append(kind: .project, key: item.id.uuidString, title: item.title, candidates: selected,
                projectID: item.id, mayAskPurpose: mayOfferQuestion(model, registration: registration) && !hasPurpose && meaningfulProject)
        }
        let updates = records.filter { $0.reference.kind != "projectIdentity" }
        append(kind: .topic, key: "recent", title: "Recent context and recorded changes", candidates: updates)
        return result.filter { target in
            let current = model.contextPages.page(id: target.id, registration: registration)
            guard current?.owner != .human else { return false }
            return current == nil || target.hasPendingChanges || !ContextKnowledgeRules.current(current!.references, records: records)
        }.sorted { lhs, rhs in
            let a = model.contextPages.page(id: lhs.id, registration: registration)?.updated ?? .distantPast
            let b = model.contextPages.page(id: rhs.id, registration: registration)?.updated ?? .distantPast
            if a != b { return a < b }
            if (lhs.kind == .overview) != (rhs.kind == .overview) { return lhs.kind == .overview }
            return lhs.id < rhs.id
        }
    }

    /// One synthesis per owned heartbeat; all provider calls use that run's persisted allowance.
    /// Existing source-learning quotas/failed claims are unchanged.
    func run(_ model: DashboardModel, request: HeartbeatChildRequest) async throws -> HeartbeatLearningResult {
        try request.validate()
        guard model.contextPages.canSave else {
            return .init(failure: model.contextPages.error ?? "Context-page storage is unavailable.", detail: "Saved context is preserved; maintenance could not start.", skipped: false)
        }
        guard !busy, model.assistant.memory.enabled, model.assistant.memory.learningEnabled,
              !model.assistant.hasDraft, !model.assistant.busy else {
            return .init(detail: "Context-page maintenance is waiting for idle permitted memory.", skipped: true)
        }
        let registration = request.registration
        let all = targets(model, registration: registration)
        let capturedRecords = model.contextKnowledge(registration: registration)
        let checkpoint = model.contextPages.checkpoint(registration: registration)
        guard !all.isEmpty else {
            let current = Dictionary(capturedRecords.map { ($0.reference.contextKey, $0.reference) }, uniquingKeysWith: { first, _ in first })
            let retained = (checkpoint?.references ?? []).filter { current[$0.contextKey]?.revision == $0.revision }
            if retained != checkpoint?.references {
                try model.contextPages.saveBatch([], checkpoint: .init(registration: registration, references: retained), expectedCheckpointRevision: checkpoint?.revision)
            }
            status = "Context pages are current; no AI update was needed."
            return .init(detail: status, skipped: true)
        }
        var selected: [ContextPageTarget] = []
        for target in all {
            guard selected.count < 4 else { break }
            guard ContextKnowledgeRules.json(["targets": (selected + [target]).map(\.input)]).utf8.count <= 30_000 else { continue }
            selected.append(target)
        }
        guard !selected.isEmpty else { return .init(failure: "A context page exceeded its bounded input; its changes remain pending.", detail: "Context input remains pending.", skipped: false) }
        let selectedModel = model.chatGPT.selectedModel
        let memoryPermission = model.assistant.memory.useRevision
        let learningPermission = model.assistant.memory.controlsRevision
        let expected = Dictionary(selected.compactMap { target in model.contextPages.page(id: target.id, registration: registration).map { (target.id, $0.revision) } }, uniquingKeysWith: { first, _ in first })
        let input = ContextKnowledgeRules.json(["targets": selected.map(\.input), "now": Date.now.ISO8601Format(), "timezone": TimeZone.current.identifier])
        busy = true; ownedHeartbeatRunID = request.runID; error = nil; status = "Updating relevant context pages…"
        defer { busy = false; ownedHeartbeatRunID = nil }
        do {
            try request.validate(); try request.claim()
            let text = try await model.chatGPT.streamResponse(input: [["role": "user", "content": input]], instructions: ContextConsolidationRules.instructions, model: selectedModel, purpose: .learning) { _ in }
            try Task.checkCancellation(); try request.validate()
            guard registration == model.chatGPT.activeID, model.assistant.memory.enabled, model.assistant.memory.learningEnabled,
                  memoryPermission == model.assistant.memory.useRevision, learningPermission == model.assistant.memory.controlsRevision else { throw MemoryLearningFailure.changed }
            let current = model.contextKnowledge(registration: registration, retainingReferences: Dictionary(selected.flatMap(\.references).map { ($0.contextKey, $0.revision) }, uniquingKeysWith: { first, _ in first }))
            guard selected.allSatisfy({ ContextKnowledgeRules.current($0.references, records: current) }) else { throw ContextPageFailure.invalid("changed supporting records") }
            let decoded = try ContextConsolidationRules.decode(text, targets: selected)
            // Never acknowledge unprocessed targets or changes that arrived while this call yielded.
            let remaining = Set(all.map(\.id)).subtracting(selected.map(\.id))
            let currentByKey = Dictionary(current.map { ($0.reference.contextKey, $0.reference) }, uniquingKeysWith: { first, _ in first })
            var acknowledged = Dictionary((checkpoint?.references ?? []).filter { currentByKey[$0.contextKey]?.revision == $0.revision }.map { ($0.contextKey, $0) }, uniquingKeysWith: { first, _ in first })
            for reference in selected.flatMap(\.references) { acknowledged[reference.contextKey] = reference }
            let newCheckpoint = ContextPageCheckpoint(registration: registration, references: Array(acknowledged.values))
            let saved = try model.contextPages.saveBatch(decoded.map { $0.0 }, expectedRevisions: expected, checkpoint: newCheckpoint,
                expectedCheckpointRevision: checkpoint?.revision)
            var offered = false
            for (page, question) in decoded where !offered {
                guard mayOfferQuestion(model, registration: registration), let question, let target = selected.first(where: { $0.id == page.id }), let projectID = target.projectID,
                      let identity = current.first(where: { $0.reference.kind == "projectIdentity" && $0.reference.key == projectID.uuidString })?.reference,
                      !model.contextPages.pages(registration: registration).contains(where: { $0.kind == .note && $0.key == "project-purpose:" + projectID.uuidString }) else { continue }
                offered = try model.contextQuestions.offer(registration: registration, projectID: projectID, identity: identity, question: question) != nil
            }
            status = "Updated \(saved.count) context page\(saved.count == 1 ? "" : "s")\(remaining.isEmpty ? "." : "; other changes remain pending.")"
            return .init(detail: status, skipped: false)
        } catch {
            self.error = error.localizedDescription
            status = "Context-page update did not finish. Saved pages and pending changes are retained."
            if error is CancellationError { throw error }
            return .init(failure: self.error, detail: status, skipped: false)
        }
    }
}
