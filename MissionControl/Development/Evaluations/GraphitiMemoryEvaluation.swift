#if DEBUG
import Foundation
import SwiftData

/// Live subscription + real local Graphiti; no personal database or native startup.
@MainActor enum GraphitiMemoryEvaluation {
    static func run(_ model: DashboardModel) async throws -> [String: Any] {
        let registration = model.chatGPT.activeID
        guard !registration.isEmpty, model.chatGPT.inferenceVerified, !model.chatGPT.usagePaused else {
            throw ActionFailure.message("A verified subscription connection is required for the fictional check (selected: \(!registration.isEmpty), session: \(model.chatGPT.hasSession), verified: \(model.chatGPT.inferenceVerified), usage paused: \(model.chatGPT.usagePaused), saved accounts: \(model.chatGPT.accounts.count), initialization: \(model.chatGPT.message)).")
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
        var extractionResults: [[String: Any]] = []
        model.graphiti.extractionObserver = { name, result in
            extractionResults.append(["schema": name, "result": result])
            try? JSONSerialization.data(withJSONObject: extractionResults, options: [.prettyPrinted, .sortedKeys]).write(to: EvaluationOutput.url("/tmp/graphiti-fictional-extraction.json"), options: .atomic)
        }
        var checks: [String: Bool] = [:]
        var timings: [String: Double] = [:]
        var correctedEvidence: String = ""
        let fact = PAMemory(registration: registration,
            text: "My name is Alex. I am building the Orion river monitoring prototype with Mira. The Orion prototype uses two sensors. Mira is my project collaborator and academic supervisor. Meet Mira at 14:00 tomorrow. Finish the worksheet tonight.",
            kind: .context, explicit: true, provenance: "Fictional human statement", created: .now.addingTimeInterval(-172800),
            evidence: "My name is Alex. I am building the Orion river monitoring prototype with Mira. The Orion prototype uses two sensors. Mira is my project collaborator and academic supervisor. Meet Mira at 14:00 tomorrow. Finish the worksheet tonight.", certainty: .stated, durability: .stable)
        checks["fictional original saved"] = model.assistant.memory.put(fact)
        func original(_ text: String, daysAgo: Double) -> PAMemory {
            .init(registration: registration, text: text, kind: .context, explicit: true,
                  provenance: "Fictional human statement", created: .now.addingTimeInterval(-daysAgo * 86400),
                  evidence: text, certainty: .stated, durability: .stable)
        }
        let purpose = original("The Orion prototype is my practical portfolio project for environmental engineering roles. Orion measures river water quality.", daysAgo: 1.5)
        let motivation = original("I want an environmental engineering role because protecting rivers matters to me. I am Alex, the person building Orion.", daysAgo: 1)
        checks["separate purpose and motivation saved"] = model.assistant.memory.put(purpose) && model.assistant.memory.put(motivation)
        var temporary = original("Attend the laboratory at 14:00 tomorrow.", daysAgo: 0.5)
        temporary.durability = .situational
        var commitment = original("Finish the worksheet tonight.", daysAgo: 0.5)
        commitment.kind = .commitment
        checks["excluded fixture originals saved"] = model.assistant.memory.put(temporary) && model.assistant.memory.put(commitment)
        let admitted = model.graphiti.snapshot(model, registration: registration)
        checks["situational memories and commitments excluded before inference"] = !admitted.records.values.contains { $0.memoryID == temporary.id || $0.memoryID == commitment.id }
        model.assistant.draft = "Fictional unsent draft retained during explicit indexing"
        let buildStarted = Date.now
        let first = try await model.graphiti.synchronize(model, registration: registration, explicit: true)
        guard first.failure == nil, model.graphiti.settings(registration).indexedCount == 3 else {
            throw ActionFailure.message(first.failure ?? first.detail)
        }
        checks["explicit indexing preserves existing draft"] = model.assistant.draft == "Fictional unsent draft retained during explicit indexing"
        model.assistant.draft = ""
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
        checks["focused retrieval finds original motivation"] = focusedMotivation.text.lowercased().contains("protect") && citedMemoryIDs(focusedMotivation).contains("memory:" + motivation.id.uuidString)
        checks["retrieval connects separately learned project and motivation"] = connected.text.lowercased().contains("environmental") && connected.text.lowercased().contains("river") && citedMemoryIDs(connected).isSuperset(of: ["memory:" + purpose.id.uuidString, "memory:" + motivation.id.uuidString])
        model.graphiti.configure(registration, mode: .graphiti)
        let runtime = model.assistantRuntime()
        let initial = runtime.contextPages(registration, "Orion", nil, false, true)
        checks["graph mode omits factual page prose"] = !initial.text.contains("two sensors") && initial.memoryIDs.isEmpty && initial.referenceVersions.isEmpty
        // Actual assistant preparation, model-selected tool, PAToolSession and final synthesis.
        checks["assistant request accepted"] = model.assistant.send(runtime: runtime, topicID: nil,
            prompt: "Who is my collaborator on Orion, and how does this project relate to my career direction and motivation? Do not save or change anything.")
        let deadline = Date.now.addingTimeInterval(180)
        while model.assistant.busy, Date.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        guard !model.assistant.busy else { model.assistant.cancel(); throw ActionFailure.message("Fictional assistant check timed out.") }
        let reply = model.assistant.feed?.turns.last
        checks["assistant used Graphiti tool"] = reply?.contextCapture?.attemptedTools.contains("search_graph_memory") == true
        checks["assistant answered from graph"] = reply?.completed == true && reply?.content.contains("Mira") == true && reply?.contextCapture?.memoryBackend == "graphiti"
        checks["graph search retained provenance"] = reply?.contextCapture?.consultedMemoryIDs.contains(fact.id) == true
        checks["assistant connects career purpose"] = reply?.content.lowercased().contains("environmental") == true
        checks["assistant explains personal motivation"] = reply?.content.lowercased().contains("protect") == true
        let background = try await model.graphiti.search("Saved background", model: model, registration: registration, browse: true)
        checks["transient details excluded from graph"] = !background.text.contains("14:00") && !background.text.lowercased().contains("worksheet")
        // Production gathering instructions and conversation loop, with real graph retrieval
        // and explicitly fictional current-source ports; no EventKit or mail access.
        let allowed: Set<String> = ["search_graph_memory", "read_calendar", "read_life_items"]
        var used: Set<String> = [], sourceAnswer = "", requests = 0
        let definitions = (PAToolProtocol.tools.first?["tools"] as? [[String: Any]] ?? []).filter { allowed.contains($0["name"] as? String ?? "") }
        let tools: [[String: Any]] = [["type": "namespace", "name": "pa", "description": "Read-only fictional sources and real experimental graph", "tools": definitions]]
        let outcome = try await PAConversationEngine().run(base: [["role": "user", "content": "What should I prepare for my meeting tomorrow? Check what I am currently working on and tell me when the meeting is. Do not change anything."]], allowedTools: allowed, valid: { true }, receipts: { [] }, infer: { input, delta in
            requests += 1
            guard requests <= 8 else { throw ActionFailure.message("Source integration diagnostic exceeded its budget.") }
            return try await model.chatGPT.toolResponse(input: input, instructions: "You are 3PO. Today is 24 October 2026 in Europe/London. Calendar and Projects are available through the supplied tools. Do not invent their contents. " + runtime.memoryBackendInstructions, tools: tools, model: model.chatGPT.selectedModel, purpose: .diagnostic, onDelta: delta)
        }, execute: { call in
            let arguments = try PAToolProtocol.arguments(call)
            used.insert(call.name)
            switch call.name {
            case "search_graph_memory":
                let capture = try await model.graphiti.search(arguments["query"] as? String ?? "Mira", model: model, registration: registration)
                return .output(capture.text, succeeded: capture.current())
            case "read_calendar":
                return .output(GraphitiMemoryRules.json(["timeZone": "Europe/London", "timeInterpretation": "Timed event timestamps are already local with the offset for that event date. Use that offset; do not apply today’s daylight-saving offset again.", "events": [["title": "Meeting with Mira", "start": "2026-10-25T15:30:00+00:00", "end": "2026-10-25T16:00:00+00:00"]], "coverage": "Current fictional Calendar snapshot for tomorrow; read-only."]), succeeded: true)
            case "read_life_items":
                return .output(GraphitiMemoryRules.json(["items": [["title": "Orion river monitoring", "notes": "Current work: investigate calibration drift before the next supervisor meeting. Bring the comparison plot; the latest trial disagreed with the reference probe."]], "coverage": "Current fictional project notes; read-only."]), succeeded: true)
            default: throw ActionFailure.message("Unavailable fictional tool.")
            }
        }, progress: { _ in }, partial: { _ in }, toolRound: {}, attempted: { _ in }, toolFinished: {})
        if case .completed(let text) = outcome { sourceAnswer = text }
        checks["meeting preparation consults graph and actual source ports"] = used.isSuperset(of: allowed)
        checks["meeting preparation uses current project issue"] = sourceAnswer.lowercased().contains("drift")
        checks["meeting preparation uses source time not old memory"] = (sourceAnswer.contains("15:30") || sourceAnswer.contains("3:30")) && !sourceAnswer.contains("14:00") && !sourceAnswer.contains("16:30") && !sourceAnswer.contains("4:30")
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
        checks["operational sensor details excluded"] = !after.text.lowercased().contains("four sensors") && !after.text.lowercased().contains("two sensors")
        let preserved = try await model.graphiti.search("Why does Alex want environmental engineering work?", model: model, registration: registration)
        checks["correction preserves unrelated motivation"] = preserved.text.lowercased().contains("protect") && citedMemoryIDs(preserved).contains("memory:" + motivation.id.uuidString)
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
                "extractionResults": extractionResults, "sourcePreparationAnswer": sourceAnswer, "sourcePreparationTools": used.sorted(), "backgroundEvidence": background.text,
                "assistantAnswer": reply?.content ?? "", "assistantError": model.assistant.error ?? "",
                "model": model.chatGPT.selectedModel,
                "storage": "Fictional original, in-memory app storage and temporary graph deleted after check; no native sources started. Cross-episode and correction acceptance, not evidence of superiority over context pages."]
    }
}
#endif
