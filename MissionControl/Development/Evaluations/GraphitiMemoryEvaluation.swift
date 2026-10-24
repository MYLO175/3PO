#if DEBUG
import Foundation
import SwiftData

/// Live subscription + real local Graphiti; no personal database or native startup.
@MainActor enum GraphitiMemoryEvaluation {
    static func run(_ model: DashboardModel) async throws -> [String: Any] {
        let registration = model.chatGPT.activeID
        guard !registration.isEmpty, model.chatGPT.inferenceVerified, !model.chatGPT.usagePaused else {
            throw ActionFailure.message("A verified subscription connection is required for the fictional check.")
        }
        let root = EvaluationOutput.url("/tmp/graphiti-live-" + UUID().uuidString)
        let suite = "3po-graphiti-fictional-" + UUID().uuidString
        let settings = UserDefaults(suiteName: suite)!
        settings.set(true, forKey: "paMemoryEnabled")
        settings.set(true, forKey: "paMemoryLearningEnabled")
        settings.set(false, forKey: "assistantContextEnabled")
        defer { settings.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        model.assistant = AssistantService(connection: model.chatGPT, container: model.container, settings: settings, imageDirectory: root.appendingPathComponent("images"))
        model.graphiti = GraphitiMemoryService(container: model.container, root: root)
        var checks: [String: Bool] = [:]
        var timings: [String: Double] = [:]
        var correctedEvidence: String = ""
        let fact = PAMemory(registration: registration,
            text: "My name is Alex. I am building the Orion river monitoring prototype with Mira. The Orion prototype uses two sensors. Mira is my project collaborator.",
            kind: .context, explicit: true, provenance: "Fictional human statement", created: .now.addingTimeInterval(-172800),
            evidence: "My name is Alex. I am building the Orion river monitoring prototype with Mira. The Orion prototype uses two sensors. Mira is my project collaborator.", certainty: .stated, durability: .stable)
        checks["fictional original saved"] = model.assistant.memory.put(fact)
        func original(_ text: String, daysAgo: Double) -> PAMemory {
            .init(registration: registration, text: text, kind: .context, explicit: true,
                  provenance: "Fictional human statement", created: .now.addingTimeInterval(-daysAgo * 86400),
                  evidence: text, certainty: .stated, durability: .stable)
        }
        let purpose = original("The Orion prototype is my practical portfolio project for environmental engineering roles. Orion measures river water quality.", daysAgo: 1.5)
        let motivation = original("I want an environmental engineering role because protecting rivers matters to me. I am Alex, the person building Orion.", daysAgo: 1)
        checks["separate purpose and motivation saved"] = model.assistant.memory.put(purpose) && model.assistant.memory.put(motivation)
        let buildStarted = Date.now
        let first = try await model.graphiti.synchronize(model, registration: registration, explicit: true)
        guard first.failure == nil, model.graphiti.settings(registration).indexedCount == 3 else {
            throw ActionFailure.message(first.failure ?? first.detail)
        }
        checks["live extraction indexed original"] = true
        timings["initialThreeEpisodeBuildSeconds"] = Date.now.timeIntervalSince(buildStarted)
        let unchanged = try await model.graphiti.synchronize(model, registration: registration, explicit: true)
        checks["unchanged snapshot skips extraction"] = unchanged.skipped
        let capture = try await model.graphiti.search("Who works with Alex on the river monitoring project?", model: model, registration: registration)
        checks["semantic lookup finds collaborator"] = capture.text.contains("Mira") && capture.memoryIDs.contains(fact.id)
        func citedMemoryIDs(_ capture: AssistantPageContext) -> Set<String> {
            let payload = (try? JSONSerialization.jsonObject(with: Data(capture.text.utf8))) as? [String: Any]
            let facts = payload?["facts"] as? [[String: Any]] ?? []
            return Set(facts.flatMap { $0["sources"] as? [[String: String]] ?? [] }.compactMap { $0["reference"] })
        }
        let connected = try await model.graphiti.search("How does Orion relate to Alex's career direction and what motivates that direction?", model: model, registration: registration)
        let focusedMotivation = try await model.graphiti.search("Why does Alex want an environmental engineering role? Protecting rivers motivation.", model: model, registration: registration)
        checks["focused retrieval finds original motivation"] = focusedMotivation.text.lowercased().contains("river") && citedMemoryIDs(focusedMotivation).contains("memory:" + motivation.id.uuidString)
        checks["retrieval connects separately learned project and motivation"] = connected.text.lowercased().contains("environmental") && connected.text.lowercased().contains("river") && citedMemoryIDs(connected).isSuperset(of: ["memory:" + purpose.id.uuidString, "memory:" + motivation.id.uuidString])
        model.graphiti.configure(registration, mode: .graphiti)
        let runtime = model.assistantRuntime()
        let initial = runtime.contextPages(registration, "Orion", nil, false, true)
        checks["graph mode omits factual page prose"] = !initial.text.contains("two sensors") && initial.memoryIDs.isEmpty && initial.referenceVersions.isEmpty
        // Actual assistant preparation, model-selected tool, PAToolSession and final synthesis.
        checks["assistant request accepted"] = model.assistant.send(runtime: runtime, topicID: nil,
            prompt: "Using Graphiti memory, who is my collaborator on Orion, and how does this project relate to my career direction and motivation? Search the graph before answering. Do not save or change anything.")
        let deadline = Date.now.addingTimeInterval(180)
        while model.assistant.busy, Date.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        guard !model.assistant.busy else { model.assistant.cancel(); throw ActionFailure.message("Fictional assistant check timed out.") }
        let reply = model.assistant.feed?.turns.last
        checks["assistant used Graphiti tool"] = reply?.contextCapture?.attemptedTools.contains("search_graph_memory") == true
        checks["assistant answered from graph"] = reply?.completed == true && reply?.content.contains("Mira") == true && reply?.contextCapture?.memoryBackend == "graphiti"
        checks["graph search retained provenance"] = reply?.contextCapture?.consultedMemoryIDs.contains(fact.id) == true
        checks["assistant connects career purpose"] = reply?.content.lowercased().contains("environmental") == true
        checks["assistant explains personal motivation"] = reply?.content.lowercased().contains("protect") == true
        let beforeCorrection = try await model.graphiti.search("Orion collaborator", model: model, registration: registration)
        let replacement = original("My name is Alex. I am building the Orion river monitoring prototype with Tomas. The Orion prototype now uses four sensors. Tomas is my current project collaborator.", daysAgo: 0)
        checks["canonical correction saved"] = model.assistant.memory.correct(fact.id, with: replacement)
        checks["correction invalidates old graph capture"] = !beforeCorrection.current()
        let rebuildStarted = Date.now
        let rebuilt = try await model.graphiti.synchronize(model, registration: registration, explicit: true)
        guard rebuilt.failure == nil else { throw ActionFailure.message(rebuilt.failure!) }
        timings["correctionRebuildSeconds"] = Date.now.timeIntervalSince(rebuildStarted)
        let after = try await model.graphiti.search("Who is Alex's current Orion collaborator and how many sensors does the prototype use?", model: model, registration: registration)
        correctedEvidence = after.text
        checks["corrected retrieval replaces old collaborator"] = after.text.contains("Tomas") && !after.text.contains("Mira")
        checks["corrected retrieval replaces old sensor count"] = (after.text.lowercased().contains("four") || after.text.contains("4 sensors")) && !after.text.lowercased().contains("two sensors")
        let preserved = try await model.graphiti.search("Why does Alex want environmental engineering work?", model: model, registration: registration)
        checks["correction preserves unrelated motivation"] = preserved.text.lowercased().contains("river") && citedMemoryIDs(preserved).contains("memory:" + motivation.id.uuidString)
        checks["forget original saved"] = model.assistant.memory.forget(replacement.id)
        checks["forget invalidates captured graph result"] = !after.current()
        do {
            _ = try await model.graphiti.search("Orion collaborator", model: model, registration: registration)
            checks["withdrawn generation refuses new retrieval"] = false
        } catch { checks["withdrawn generation refuses new retrieval"] = true }
        await model.graphiti.clear(model)
        checks["clear returns to pages without removing conversation"] = model.graphiti.settings(registration).mode == .pages && model.assistant.feed?.turns.isEmpty == false
        return ["checks": checks, "passed": checks.values.filter { $0 }.count, "total": checks.count,
                "timings": timings, "initialConnectedEvidence": connected.text,
                "initialFocusedMotivationEvidence": focusedMotivation.text, "correctedEvidence": correctedEvidence,
                "assistantAnswer": reply?.content ?? "", "assistantError": model.assistant.error ?? "",
                "model": model.chatGPT.selectedModel,
                "storage": "Fictional original, in-memory app storage and temporary graph deleted after check; no native sources started. Cross-episode and correction acceptance, not evidence of superiority over context pages."]
    }
}
#endif
