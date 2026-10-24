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
        let fact = PAMemory(registration: registration,
            text: "My name is Alex. I am building the Orion river monitoring prototype with Mira. The Orion prototype uses two sensors. Mira is my project collaborator.",
            kind: .context, explicit: true, provenance: "Fictional human statement", created: .now.addingTimeInterval(-172800),
            evidence: "My name is Alex. I am building the Orion river monitoring prototype with Mira. The Orion prototype uses two sensors. Mira is my project collaborator.", certainty: .stated, durability: .stable)
        checks["fictional original saved"] = model.assistant.memory.put(fact)
        let first = try await model.graphiti.synchronize(model, registration: registration, explicit: true)
        guard first.failure == nil, model.graphiti.settings(registration).indexedCount == 1 else {
            throw ActionFailure.message(first.failure ?? first.detail)
        }
        checks["live extraction indexed original"] = true
        let unchanged = try await model.graphiti.synchronize(model, registration: registration, explicit: true)
        checks["unchanged snapshot skips extraction"] = unchanged.skipped
        let capture = try await model.graphiti.search("Who works with Alex on the river monitoring project?", model: model, registration: registration)
        checks["semantic lookup finds collaborator"] = capture.text.contains("Mira") && capture.memoryIDs.contains(fact.id)
        model.graphiti.configure(registration, mode: .graphiti)
        let runtime = model.assistantRuntime()
        let initial = runtime.contextPages(registration, "Orion", nil, false, true)
        checks["graph mode omits factual page prose"] = !initial.text.contains("two sensors") && initial.memoryIDs.isEmpty && initial.referenceVersions.isEmpty
        // Actual assistant preparation, model-selected tool, PAToolSession and final synthesis.
        checks["assistant request accepted"] = model.assistant.send(runtime: runtime, topicID: nil,
            prompt: "Using Graphiti memory, who is my collaborator on Orion, and what is the project about? Search the graph before answering. Do not save or change anything.")
        let deadline = Date.now.addingTimeInterval(180)
        while model.assistant.busy, Date.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        guard !model.assistant.busy else { model.assistant.cancel(); throw ActionFailure.message("Fictional assistant check timed out.") }
        let reply = model.assistant.feed?.turns.last
        checks["assistant used Graphiti tool"] = reply?.contextCapture?.attemptedTools.contains("search_graph_memory") == true
        checks["assistant answered from graph"] = reply?.completed == true && reply?.content.contains("Mira") == true && reply?.contextCapture?.memoryBackend == "graphiti"
        checks["graph search retained provenance"] = reply?.contextCapture?.consultedMemoryIDs.contains(fact.id) == true
        let after = try await model.graphiti.search("Orion collaborator", model: model, registration: registration)
        checks["forget original saved"] = model.assistant.memory.forget(fact.id)
        checks["forget invalidates captured graph result"] = !after.current()
        do {
            _ = try await model.graphiti.search("Orion collaborator", model: model, registration: registration)
            checks["withdrawn generation refuses new retrieval"] = false
        } catch { checks["withdrawn generation refuses new retrieval"] = true }
        await model.graphiti.clear(model)
        checks["clear returns to pages without removing conversation"] = model.graphiti.settings(registration).mode == .pages && model.assistant.feed?.turns.isEmpty == false
        return ["checks": checks, "passed": checks.values.filter { $0 }.count, "total": checks.count,
                "assistantAnswer": reply?.content ?? "", "assistantError": model.assistant.error ?? "",
                "model": model.chatGPT.selectedModel,
                "storage": "Fictional original, in-memory app storage and temporary graph deleted after check; no native sources started. A plumbing acceptance check, not evidence of superiority over context pages."]
    }
}
#endif
