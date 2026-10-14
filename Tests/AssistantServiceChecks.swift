import Foundation
import SwiftData
import Observation

private final class ObservationCounter:@unchecked Sendable {
    private let lock=NSLock()
    private var count=0
    var value:Int {lock.withLock{count}}
    func increment() {lock.withLock{count += 1}}
}

@MainActor private final class FictionalInference: PAInferenceConnection {
    var activeID = "fictional-owner"
    var selectedModel = "fictional-model"
    var busy = false
    var usagePaused = false
    var inferenceVerified = true
    var hasSession = true
    var replies: [PAResponse] = []
    var holdNext = false
    var deltas=["Fictional partial"]
    var afterDelta:(@MainActor ()->Void)?
    private var held: CheckedContinuation<Void, Never>?
    private(set) var inputs: [[[String: Any]]] = []
    private(set) var instructions: [String] = []
    private(set) var purposes: [AIRequestPurpose] = []
    var waiting: Bool { held != nil }
    func release() { let value = held; held = nil; value?.resume() }
    func streamResponse(input: [[String: String]], instructions: String, model: String?, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> String {
        preconditionFailure("These assistant fixtures must use completed tool transport.")
    }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        inputs.append(input); self.instructions.append(instructions); purposes.append(purpose)
        for text in deltas {onDelta(text);afterDelta?()}
        if holdNext {
            holdNext = false
            await withCheckedContinuation { held = $0 }
        }
        try Task.checkCancellation()
        precondition(!replies.isEmpty, "Missing fictional response")
        return replies.removeFirst()
    }
}

@MainActor private final class FictionalMailCursor: AssistantMailCursor {
    var status = "Fictional bounded mail search"
    var results: [MailMessage] = []
    var hasMore = false
    var hasUnavailable = false
}

@MainActor private final class FictionalTools: AssistantToolSession {
    var calendar = CalendarSnapshot(sources: [], events: [])
    var reminders = ReminderSnapshot(sources: [], reminders: [])
    var itemDetails: [String: NativeEditDetails] = [:]
    var consultedMemory: Set<UUID> = []
    var receipts: [String] = []
    private(set) var actionCountReads=0
    var confirmedActionCount:Int {actionCountReads += 1;return receipts.count}
    var pendingNativeActionCount=0
    var actionReceiptsReadable=true
    var memoryNotes: [String] = []
    var clarification: (String, [String])?
    let mailCursor: any AssistantMailCursor = FictionalMailCursor()
    var executeBody: ((PAFunctionCall, FictionalTools) throws -> String)?
    private(set) var calls: [String] = []
    func execute(_ call: PAFunctionCall, valid: @escaping NativeWriteValidity) async throws -> String {
        try Task.checkCancellation()
        guard valid() else { throw ActionFailure.message("Fictional owned context changed") }
        calls.append(call.name)
        if call.name == "ask_clarification" { clarification = ("Which fictional option?", ["First", "Second"]) }
        return try executeBody?(call, self) ?? "{\"verified\":true}"
    }
}

@MainActor private final class FictionalContext {
    let now = Date.now.addingTimeInterval(3600)
    var state = AssistantRuntimeState(attentionPreferencesReadable: true, acknowledgementRevision: "ack-1", resolutionRevision: "resolution-1", acknowledgements: [], whatsappScope: .init(registration: "fictional-owner", linkedIdentity: "fictional-device", revision: UUID()), weatherScope: "fictional-weather")
    var sourceCalls = 0
    var afterCalls = 0
    var requests: [AssistantToolRequest] = []
    var sessions: [FictionalTools] = []
    var configure: ((FictionalTools, AssistantToolRequest) -> Void)?
    func runtime() -> AssistantRuntime {
        .init(clock: { self.now }, state: { self.state }, sourceSnapshot: { self.sourceCalls += 1; return "Fictional cached context" }, deliveryAvailable: { $0.deliveryID != "fictional-withdrawn" }, tools: { request in
            let session = FictionalTools()
            self.configure?(session, request)
            self.requests.append(request); self.sessions.append(session)
            return session
        }, afterTurn: { self.afterCalls += 1 })
    }
}

@main struct AssistantServiceChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ value: Bool, _ message: String) { count += 1; precondition(value, message) }
        func until(_ condition: () -> Bool) async {
            for _ in 0..<20_000 { if condition() { return }; await Task.yield() }
            preconditionFailure("Fictional assistant did not settle")
        }
        func final(_ text: String) -> PAResponse { .init(text: text, output: [], calls: []) }
        func tools(_ names: [String]) -> PAResponse {
            let calls = names.enumerated().map { PAFunctionCall(id: "fictional-\($0.offset)-\(UUID().uuidString)", name: $0.element, namespace: "pa", arguments: "{}") }
            return .init(text: "", output: [["type": "reasoning", "encrypted_content": "fictional-reasoning"]] + calls.map { ["type": "function_call", "call_id": $0.id, "name": $0.name, "arguments": $0.arguments] }, calls: calls)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("3po-assistant-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "3po-assistant-fixture-" + UUID().uuidString
        let settings = UserDefaults(suiteName: suite)!
        defer { settings.removePersistentDomain(forName: suite) }
        settings.set(true, forKey: "assistantContextEnabled")
        settings.set(true, forKey: "paMemoryEnabled")
        settings.set(true, forKey: "paMemoryLearningEnabled")
        func open(_ name: String) throws -> ModelContainer {
            try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(url: directory.appendingPathComponent(name + ".store"), cloudKitDatabase: .none))
        }
        func service(_ provider: FictionalInference, _ container: ModelContainer) -> AssistantService {
            AssistantService(connection: provider, container: container, settings: settings, imageDirectory: directory.appendingPathComponent("images"))
        }

        do {
            let question=AssistantTurn(role:"assistant",content:"Which time?",completed:true,created:.now)
            var conversation=AssistantConversation(accountID:"fixture",title:"Reply metadata",turns:[question])
            check(AssistantActivityContext(conversation).repliesAfter[question.id] == nil,"An unanswered action question remains pending")
            let reply=AssistantTurn(role:"user",content:"Use noon",completed:true,created:.distantPast)
            conversation.turns.append(reply)
            let answered=AssistantActivityContext(conversation)
            check(answered.repliesAfter[question.id] == reply.id,"Accepted later transcript replies resolve questions even with earlier queued timestamps")
            conversation.turns[0].content="A streamed partial variant"
            check(AssistantActivityContext(conversation) == answered,"Question resolution metadata never observes streamed prose")
            conversation.turns[1].contextID=UUID()
            check(AssistantActivityContext(conversation).repliesAfter[question.id] == nil,"Replies in another captured conversation scope do not resolve a question")
            conversation.turns[1].contextID=nil;conversation.turns[1].deliveryID="background-delivery"
            check(AssistantActivityContext(conversation).repliesAfter[question.id] == nil,"Imported deliveries are not human answers")
        }
        let streamProvider=FictionalInference(),streamContext=FictionalContext()
        let streamService=service(streamProvider,try open("stream-observation"))
        let streamID=streamService.openPA()!
        streamProvider.deltas=(1...200).map{"Fictional streamed response \($0)"}
        streamProvider.replies=[final("Completed fictional streaming response")]
        check(streamService.send(runtime:streamContext.runtime(),topicID:nil,prompt:"Fictional streaming request"),"Streaming fixture starts the actual assistant service")
        let transcriptChanges=ObservationCounter(),activityChanges=ObservationCounter()
        @MainActor func observeStreaming() {
            withObservationTracking({_ = streamService.conversation(streamID)},onChange:{transcriptChanges.increment()})
            withObservationTracking({_ = streamService.activityContext(streamID)},onChange:{activityChanges.increment()})
        }
        observeStreaming();streamProvider.afterDelta=observeStreaming
        await until{!streamService.busy}
        check(transcriptChanges.value >= 200,"Each real streamed delta updates the displayed transcript")
        check(activityChanges.value == 0,"Streamed prose never invalidates Activity metadata")
        check(streamService.feed?.turns.last?.content == "Completed fictional streaming response","Removing Activity observation retains the full final response")
        streamProvider.activeID="different-fictional-account"
        check(streamService.activityContext(streamID) == nil && streamService.conversation(streamID) == nil,"Exact context lookup still excludes other accounts")
        print("Streaming observation:200 deltas; transcript invalidations \(transcriptChanges.value); Activity invalidations \(activityChanges.value)")

        let provider = FictionalInference(), context = FictionalContext(), container = try open("normal")
        let preferencesBeforeConstruction = NSDictionary(dictionary:settings.persistentDomain(forName:suite) ?? [:])
        let assistant = service(provider, container)
        check(preferencesBeforeConstruction.isEqual(to:settings.persistentDomain(forName:suite) ?? [:]), "Constructing the assistant must not persist fallback preferences or source selections")
        let fact = PAMemory(registration: provider.activeID, text: "My AI coursework is a current study priority.", kind: .context, explicit: true, provenance: "Fictional human")
        check(assistant.memory.put(fact), "Fixture memory must save in disposable storage.")
        let widget = UUID()
        assistant.drafts.set("Retained fictional unsent draft", registration: provider.activeID, widget: widget, conversation: nil)
        assistant.drafts.flush()
        context.configure = { session, request in
            session.executeBody = { call, session in
                if call.name == "read_memory" { session.consultedMemory.insert(fact.id) }
                if call.name == "remember_context" {
                    let entry = PAMemory(registration: request.registration, text: "I prefer a short coursework plan.", kind: .preference, explicit: true, provenance: "Fictional current request", sourceTurnID: request.turnID.uuidString)
                    guard assistant.memory.put(entry) else { throw ActionFailure.message("Fixture memory save failed") }
                    session.receipts.append("Fictional memory saved and verified")
                }
                return "{\"verified\":true}"
            }
        }
        provider.replies = [tools(["read_memory", "remember_context"]), final("Completed fictional coursework plan")]
        assistant.draft = "Keep the visible fixture draft"
        check(assistant.send(runtime: context.runtime(), topicID: nil, prompt: "Help with my AI coursework; remember that I prefer a short plan.", focusAreas: [.studies]), "Actual service must accept a normal request.")
        check(assistant.busy && assistant.draft == "Keep the visible fixture draft", "Preparation must preserve the caller's draft and mark only its reply busy.")
        await until { !assistant.busy }
        let reply = assistant.feed!.turns.last!
        check(reply.completed && reply.content == "Completed fictional coursework plan", "Completed transport must supersede partial text and receipts.")
        check(reply.contextCapture?.memoryIDs.contains(fact.id) == true && reply.contextCapture?.consultedMemoryIDs == [fact.id], "Actual preparation must retain selected and successfully read memory identities separately.")
        check(reply.contextCapture?.attemptedTools == ["read_memory", "remember_context"] && reply.focusAreas == [.studies], "Actual execution traces and captured Focus must stay on the response.")
        check(reply.created == context.now && reply.contextCapture?.captured == context.now, "Preparation and trace dates must use the injected clock.")
        check(context.sessions.first?.receipts == ["Fictional memory saved and verified"] && context.afterCalls == 1, "Verified receipts must persist across rounds and finish once.")
        check(provider.inputs.last?.contains(where: { $0["encrypted_content"] as? String == "fictional-reasoning" }) == true, "Actual service must replay completed reasoning output.")
        check(provider.instructions.first?.contains(DateRules.localTimestamp(context.now)) == true, "Inference instructions must use the captured fictional clock.")
        let originalIDs = assistant.feed!.turns.map(\.id)
        let reopened = service(FictionalInference(), try open("normal"))
        check(reopened.feed?.turns.map(\.id) == originalIDs && reopened.feed?.turns.last?.contextCapture == reply.contextCapture, "Reopening must preserve turn identities, completed replies and exact traces.")
        check(reopened.memory.records.contains(where: { $0.text == "I prefer a short coursework plan." }), "Verified memory changes must survive reopening.")
        check(reopened.drafts.text(registration: provider.activeID, widget: widget, conversation: nil) == "Retained fictional unsent draft", "Unrelated unsent drafts must survive the conversation run.")

        let history = AssistantConversation(accountID: provider.activeID, title: "Fictional history", turns: [
            .init(role: "user", content: "Retained fictional human turn", completed: true, created: context.now),
            .init(role: "assistant", content: "Withdrawn fictional source advice", completed: true, deliveryID: "fictional-withdrawn", created: context.now)
        ], isPrimary: true)
        check(assistant.sourceSafeHistory(runtime: context.runtime(), feed: history, topic: nil).map(\.content) == ["Retained fictional human turn"], "Injected delivery support must withdraw stale source advice without discarding human history.")

        let imageProvider = FictionalInference(), imageContext = FictionalContext()
        let imageAssistant = service(imageProvider, try open("images"))
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jD1sAAAAASUVORK5CYII=")!
        let attachment = try imageAssistant.images.add(png, registration: imageProvider.activeID)
        imageProvider.replies = [final("Fictional image described")]
        check(imageAssistant.send(runtime: imageContext.runtime(), topicID: nil, prompt: "Describe this fictional image", images: [attachment]), "Actual service must accept an owned stored image.")
        await until { !imageAssistant.busy }
        let imageTurn = imageAssistant.feed!.turns.first!
        let inputContent = imageProvider.inputs.first?.first?["content"] as? [[String: Any]] ?? []
        check(imageTurn.images == [attachment] && inputContent.contains(where: { $0["type"] as? String == "input_image" }), "Actual image preparation must preserve attachment identity and include the bounded payload.")
        let imageReopened = service(FictionalInference(), try open("images"))
        check(imageReopened.feed?.turns.first?.images == [attachment] && (try? imageReopened.images.data(attachment, registration: imageProvider.activeID)) != nil, "Owned image metadata and bytes must remain usable after reopening.")

        let setupProvider = FictionalInference(), setupContext = FictionalContext()
        let setup = service(setupProvider, try open("setup"))
        setupProvider.replies = [final("{\"question\":\"What is taking up most of your time?\"}")]
        check(setup.beginSetup(runtime: setupContext.runtime(), topic: nil), "Explicit setup Start must use the real service.")
        await until { !setup.busy }
        check(setupContext.sourceCalls == 0 && setup.feed?.turns.last?.content == "What is taking up most of your time?", "Setup must avoid cached source snapshots and show one completed question.")
        check(setup.feed?.turns.first?.profileControl == true && setup.learningTurns().isEmpty, "Setup controls must not become learning evidence.")
        check(setup.feed?.turns.last?.contextCapture?.profileSetup == true && setup.feed?.turns.last?.contextCapture?.sourceSnapshotIncluded == false, "Setup must retain its memory-only capture.")
        setupProvider.replies = [tools(["change_calendar"])]
        check(setup.sendProfile(runtime: setupContext.runtime(), topic: nil, answer: "For this fictional example, I study engineering."), "Setup must save the current human answer before inference.")
        await until { !setup.busy }
        check(setup.error?.contains("memory setup") == true && setupContext.sessions.last?.calls.isEmpty == true, "Setup restrictions must stop unsupported execution in the actual service.")
        check(setup.learningTurns().count == 1, "Human setup answers remain available while controls remain excluded.")

        for change in ["Stop", "account", "model", "source", "memory"] {
            let p = FictionalInference(), c = FictionalContext(), store = try open("ownership-" + change)
            let value = service(p, store)
            p.holdNext = true; p.replies = [tools(["read_memory"])]
            check(value.send(runtime: c.runtime(), topicID: nil, prompt: "Fictional owned request"), "Fixture owned request must prepare.")
            await until { p.waiting }
            switch change {
            case "Stop": value.cancel()
            case "account": p.activeID = "another-fictional-owner"
            case "model": p.selectedModel = "another-fictional-model"
            case "source": c.state.weatherScope = "changed-fictional-weather"
            default: _ = value.memory.put(PAMemory(registration: p.activeID, text: "A newly revised fictional fact", kind: .context, explicit: true, provenance: "Fictional human"))
            }
            p.release()
            await until { !value.busy }
            check(c.sessions.first?.calls.isEmpty == true && value.error != nil, "\(change) must reject late tools and retain a visible stop/failure.")
            let saved = try ConversationRepository(container: try open("ownership-" + change)).load()
            check(saved.first?.turns.contains(where: { $0.role == "user" && $0.content == "Fictional owned request" }) == true, "\(change) must retain the prepared human request after reopen.")
        }

        let queuedProvider = FictionalInference(), queuedContext = FictionalContext()
        let queued = service(queuedProvider, try open("queue"))
        queuedProvider.holdNext = true
        queuedProvider.replies = [final("First fictional response"), final("Second fictional response")]
        check(queued.send(runtime: queuedContext.runtime(), topicID: nil, prompt: "First fictional request"), "First queue fixture request must prepare.")
        await until { queuedProvider.waiting }
        check(queued.send(runtime: queuedContext.runtime(), topicID: nil, prompt: "Second fictional request", focusAreas: [.career]), "Explicit request during a busy turn must enqueue.")
        check(queued.queue.items.first?.state == .waiting && queued.queue.items.first?.focusAreas == [.career], "Enqueued work must capture Focus and wait serially.")
        queuedProvider.release()
        await until { queued.queue.items.first?.state == .completed && !queued.busy }
        check(queued.feed?.turns.last?.content == "Second fictional response" && queued.feed?.turns.last?.focusAreas == [.career], "Queue delivery must use the captured request and Focus.")
        let queueReopened = service(FictionalInference(), try open("queue"))
        check(queueReopened.queue.items.first?.state == .completed && queueReopened.feed?.turns.map(\.id) == queued.feed?.turns.map(\.id), "Completed queued receipts and identities must survive reopening.")

        let questionProvider = FictionalInference(), questionContext = FictionalContext()
        let question = service(questionProvider, try open("question-queue"))
        questionProvider.holdNext = true; questionProvider.replies = [final("First complete"), tools(["ask_clarification"])]
        _ = question.send(runtime: questionContext.runtime(), topicID: nil, prompt: "First question fixture request")
        await until { questionProvider.waiting }
        _ = question.send(runtime: questionContext.runtime(), topicID: nil, prompt: "Request needing an answer")
        _ = question.send(runtime: questionContext.runtime(), topicID: nil, prompt: "Later request must wait")
        questionProvider.release()
        await until { question.queue.items.first?.state == .needsAnswer && !question.busy }
        check(question.queue.items.last?.state == .waiting && questionProvider.inputs.count == 2, "Needs-answer must stop automatic queue advancement.")
        check(question.feed?.turns.last?.completed == true && question.feed?.turns.last?.choices == ["First", "Second"], "The captured clarification bubble must retain exact answer choices.")
        let questionReopenedProvider = FictionalInference()
        let questionReopened = service(questionReopenedProvider, try open("question-queue"))
        await Task.yield()
        check(questionReopened.queue.items.first?.state == .needsAnswer && questionReopened.queue.items.last?.state == .waiting && questionReopenedProvider.inputs.isEmpty, "Reopening must not replay a paused needs-answer queue.")

        let interruptedProvider = FictionalInference(), interruptedContext = FictionalContext()
        let interrupted = service(interruptedProvider, try open("interrupted-queue"))
        interruptedProvider.holdNext = true; interruptedProvider.replies = [final("Initial completed response"), final("Cancelled response must not appear")]
        _ = interrupted.send(runtime: interruptedContext.runtime(), topicID: nil, prompt: "Initial interruption fixture request")
        await until { interruptedProvider.waiting }
        _ = interrupted.send(runtime: interruptedContext.runtime(), topicID: nil, prompt: "Queued request to stop")
        _ = interrupted.send(runtime: interruptedContext.runtime(), topicID: nil, prompt: "Later request must remain waiting")
        interruptedProvider.holdNext = true; interruptedProvider.release()
        await until { interruptedProvider.inputs.count == 2 && interruptedProvider.waiting }
        interrupted.cancel(); interruptedProvider.release()
        await until { interrupted.queue.items.first?.state == .interrupted && !interrupted.busy }
        check(interrupted.queue.items.last?.state == .waiting && interruptedProvider.inputs.count == 2, "Stopping queued inference must preserve interruption and pause later work.")
        let interruptedReopenedProvider = FictionalInference()
        let interruptedReopened = service(interruptedReopenedProvider, try open("interrupted-queue"))
        await Task.yield()
        check(interruptedReopened.queue.items.first?.state == .interrupted && interruptedReopened.queue.items.last?.state == .waiting && interruptedReopenedProvider.inputs.isEmpty, "Reopening must not replay interrupted foreground requests.")

        func nativeCall(_ name:String,operation:String = "create",target:String? = nil,destination:String? = nil,scope:String? = nil)->PAFunctionCall {
            var fields:[String:Any]=["operation":operation,"target":target as Any? ?? NSNull(),"destination":destination as Any? ?? NSNull(),"title":"Fictional weekend","notes":NSNull(),"scope":scope as Any? ?? NSNull(),"options":NSNull(),"authorization":"Yes, all weekend"]
            if name == "change_calendar" {fields.merge(["location":NSNull(),"start":"2026-10-24","end":"2026-10-26","allDay":true]){_,new in new}}
            else {fields.merge(["due":"2026-10-24","hasTime":false]){_,new in new}}
            return .init(id:UUID().uuidString,name:name,namespace:"pa",arguments:String(decoding:try! JSONSerialization.data(withJSONObject:fields,options:[.sortedKeys]),as:UTF8.self))
        }
        func response(_ calls:[PAFunctionCall])->PAResponse {
            .init(text:"",output:calls.map{["type":"function_call","call_id":$0.id,"name":$0.name,"arguments":$0.arguments]},calls:calls)
        }
        let destination=SourceOption(id:"fictional-destination",title:"Fictional destination",account:"Fictional",writable:true)
        for name in ["change_calendar","change_reminder"] {
            for explicit in [false,true] {
                let p=FictionalInference(),c=FictionalContext()
                settings.set(true,forKey:"assistantContextEnabled")
                let value=service(p,try open("recovery-"+name+String(explicit))),original=nativeCall(name,destination:explicit ? destination.id : nil)
                var writes=0,mutations:[PAFunctionCall]=[]
                c.configure={session,_ in session.executeBody={call,session in
                    if call.name == "read_calendar" {session.calendar.sources=[destination];return "{\"sources\":[\"fictional-destination\"]}"}
                    if call.name == "read_reminders" {session.reminders.sources=[destination];return "{\"sources\":[\"fictional-destination\"]}"}
                    mutations.append(call)
                    try PAToolProtocol.nativeReadPreflight(call.name,operation:"create",hasSources:!(name == "change_calendar" ? session.calendar.sources : session.reminders.sources).isEmpty,hasDetails:false)
                    writes += 1;session.receipts.append("Fictional creation saved and verified")
                    return "{\"verified\":true}"
                }}
                p.replies=[response([original]),final("Fictional creation completed")]
                check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Yes, all weekend"),"A confirmed creation must start without another human message")
                await until{!value.busy}
                check(c.sessions[0].calls == [name,name == "change_calendar" ? "read_calendar" : "read_reminders",name] && writes == 1,"Missing destinations must cause one internal read and one actual creation")
                check(mutations.count == 2 && mutations.allSatisfy{$0.id == original.id && $0.arguments == original.arguments},"Preparation must preserve exact mutation identity, dates, explicit/default destination and authority")
                check(value.error == nil && value.feed?.turns.last?.content == "Fictional creation completed" && value.feed?.turns.filter{$0.role == "user"}.count == 1,"The same foreground request must finish without asking the human to repeat")
                check(value.feed?.turns.last?.unresolvedToolErrors?.isEmpty == true && value.feed?.turns.last?.contextCapture?.attemptedTools.contains(name == "change_calendar" ? "read_calendar" : "read_reminders") == true,"Internal preparation must be traced without a false visible save failure")
                let saved=try ConversationRepository(container:try open("recovery-"+name+String(explicit))).load()
                check(saved.first?.turns.last?.content == "Fictional creation completed","Recovered creation reply must survive reopening")
            }
        }
        for interruption in ["Stop","account","model","permission","filters","context"] {
            let p=FictionalInference(),c=FictionalContext()
            settings.set(true,forKey:"assistantContextEnabled")
            let value=service(p,try open("preparation-interruption-"+interruption))
            var writes=0
            c.configure={session,_ in session.executeBody={call,session in
                if call.name == "read_calendar" {
                    session.calendar.sources=[destination]
                    switch interruption {
                    case "Stop":value.cancel()
                    case "account":p.activeID="changed-owner"
                    case "model":p.selectedModel="changed-model"
                    case "permission":value.contextEnabled=false
                    case "filters":value.excludedCalendars.insert(destination.id)
                    default:c.state.weatherScope="changed-context"
                    }
                    return "{}"
                }
                try PAToolProtocol.nativeReadPreflight(call.name,operation:"create",hasSources:!session.calendar.sources.isEmpty,hasDetails:false)
                writes += 1;return "{}"
            }}
            p.replies=[response([nativeCall("change_calendar")])]
            _=value.send(runtime:c.runtime(),topicID:nil,prompt:"Yes, all weekend")
            await until{!value.busy}
            check(writes == 0 && c.sessions[0].calls == ["change_calendar","read_calendar"],"\(interruption) during preparation must block the original mutation")
            check(value.error != nil && p.inputs.count == 1,"\(interruption) must stop the captured turn without fresh inference or retargeting")
        }
        for name in ["change_calendar","change_reminder"] {
            for operation in ["edit","delete"] {
                let p=FictionalInference(),c=FictionalContext()
                settings.set(true,forKey:"assistantContextEnabled")
                let value=service(p,try open("details-"+name+operation)),target="issued-occurrence",original=nativeCall(name,operation:operation,target:target,scope:name == "change_calendar" ? "occurrence" : "reminderSeries")
                var writes=0,mutations:[PAFunctionCall]=[]
                c.configure={session,_ in
                    if name == "change_calendar" {session.calendar = .init(sources:[destination],events:[.init(id:target,calendarID:destination.id,title:"Fictional event",start:c.now,end:c.now.addingTimeInterval(3600),allDay:false,location:"",sourceLabel:"Fictional")])}
                    else {session.reminders = .init(sources:[destination],reminders:[.init(id:target,listID:destination.id,title:"Fictional reminder",due:nil,hasTime:false,sourceLabel:"Fictional",writable:true,recurring:true)])}
                    session.executeBody={call,session in
                        if call.name == "read_item_details" {
                            let args=try PAToolProtocol.arguments(call)
                            check(args["id"] as? String == target && args["kind"] as? String == (name == "change_calendar" ? "event" : "reminder"),"Internal detail read preserves exact occurrence and native kind")
                            session.itemDetails[target] = .init(kind:name == "change_calendar" ? .event : .reminder,itemID:"fictional-item",occurrenceID:target,sourceID:destination.id,title:"Fictional",notes:"",recurring:true,writable:true)
                            return "{}"
                        }
                        mutations.append(call)
                        try PAToolProtocol.nativeReadPreflight(call.name,operation:operation,hasSources:true,hasDetails:session.itemDetails[target] != nil,target:target)
                        writes += 1;session.receipts.append("Fictional exact operation verified");return "{\"verified\":true}"
                    }
                }
                p.replies=[response([original]),final("Fictional exact operation completed")]
                _=value.send(runtime:c.runtime(),topicID:nil,prompt:"Yes, all weekend")
                await until{!value.busy}
                check(writes == 1 && mutations.count == 2 && mutations.allSatisfy{$0.id == original.id && $0.arguments == original.arguments},"Detail preparation cannot change occurrence, recurring scope or authorisation")
                check(c.sessions[0].calls == [name,"read_item_details",name] && value.error == nil,"An already issued edit/delete target is prepared once in the same turn")
            }
        }
        for name in ["change_calendar","change_reminder"] {
            for sibling in [false,true] {
                let p=FictionalInference(),c=FictionalContext()
                let value=service(p,try open("late-issued-"+name+String(sibling))),target="later-issued",other="sibling-issued"
                let original=nativeCall(name,operation:"edit",target:target),unresolved=nativeCall(name,operation:"edit",target:other)
                let readName=name == "change_calendar" ? "read_calendar" : "read_reminders"
                let read=PAFunctionCall(id:UUID().uuidString,name:readName,namespace:"pa",arguments:readName == "read_calendar" ? "{\"start\":\"2026-10-24\",\"end\":\"2026-10-25\"}" : "{}")
                var writes=0
                c.configure={session,_ in session.executeBody={call,session in
                    if call.name == readName {
                        if name == "change_calendar" {session.calendar = .init(sources:[destination],events:[target,other].map{.init(id:$0,calendarID:destination.id,title:"Fictional event",start:c.now,end:c.now.addingTimeInterval(3600),allDay:false,location:"",sourceLabel:"Fictional")})}
                        else {session.reminders = .init(sources:[destination],reminders:[target,other].map{.init(id:$0,listID:destination.id,title:"Fictional reminder",due:nil,hasTime:false,sourceLabel:"Fictional",writable:true,recurring:false)})}
                        return "{}"
                    }
                    if call.name == "read_item_details" {
                        let args=try PAToolProtocol.arguments(call)
                        check(args["id"] as? String == target,"Internal recovery must resolve only its exact target")
                        session.itemDetails[target] = .init(kind:name == "change_calendar" ? .event : .reminder,itemID:"fictional-item",occurrenceID:target,sourceID:destination.id,title:"Fictional",notes:"",recurring:false,writable:true)
                        return "{}"
                    }
                    let args=try PAToolProtocol.arguments(call),id=args["target"] as? String
                    try PAToolProtocol.nativeReadPreflight(call.name,operation:"edit",hasSources:false,hasDetails:id.flatMap{session.itemDetails[$0]} != nil,target:id)
                    writes += 1;session.receipts.append("Fictional later-issued edit verified");return "{\"verified\":true}"
                }}
                // A newly issued transport call may retry the unchanged operation;
                // the engine must still reject reuse of a completed call ID.
                var retry=original;retry.id=UUID().uuidString
                p.replies=[response(sibling ? [original,unresolved] : [original]),response([read]),response([retry]),final("Fictional later-issued edit completed")]
                _=value.send(runtime:c.runtime(),topicID:nil,prompt:"Edit the exact previously discussed item")
                await until{!value.busy}
                check(writes == 1 && value.error == nil,"A freshly issued target can complete after exact internal details preparation")
                check(value.feed?.turns.last?.toolErrors?.contains(PAReadPrerequisite.details) == true,"Resolved prerequisite history must remain saved")
                check(value.feed?.turns.last?.unresolvedToolErrors?.isEmpty == !sibling,"Resolve the recovered target while retaining any sibling prerequisite")
                check(c.sessions[0].itemDetails[other] == nil,"Recovery must not read or edit the sibling target")
            }
        }
        for failure in ["empty","read-error","uncertain-save","repeated-prerequisite","disabled-destination","read-only"] {
            let p=FictionalInference(),c=FictionalContext()
            settings.set(true,forKey:"assistantContextEnabled")
            let value=service(p,try open("preparation-failure-"+failure))
            var writes=0
            c.configure={session,_ in session.executeBody={call,session in
                if call.name == "read_calendar" {
                    if failure == "read-error" {throw ActionFailure.message("Fictional source unavailable")}
                    var source=destination;if failure == "read-only" {source.writable=false}
                    session.calendar.sources=failure == "empty" ? [] : [source]
                    return "{}"
                }
                if failure == "uncertain-save" {writes += 1;throw ActionFailure.message("Fictional attempted save has an uncertain outcome")}
                try PAToolProtocol.nativeReadPreflight(call.name,operation:"create",hasSources:!session.calendar.sources.isEmpty,hasDetails:false)
                if failure == "repeated-prerequisite" {throw PAReadPrerequisite(readTool:"read_calendar",reason:PAReadPrerequisite.destinations)}
                if failure == "disabled-destination" {throw NativePreSaveFailure(message:"The explicitly selected fictional destination is unavailable")}
                if failure == "read-only" {throw NativePreSaveFailure(message:"The fictional destination is read-only")}
                writes += 1;return "{}"
            }}
            p.replies=[response([nativeCall("change_calendar",destination:failure == "disabled-destination" ? "excluded-destination" : nil)]),final("Fictional limitation reported")]
            _=value.send(runtime:c.runtime(),topicID:nil,prompt:"Yes, all weekend")
            await until{!value.busy}
            let calls=c.sessions[0].calls
            check(writes == (failure == "uncertain-save" ? 1 : 0),"\(failure) must not replay or substitute a native write")
            check(calls.filter{$0 == "read_calendar"}.count == (failure == "uncertain-save" ? 0 : 1) && calls.filter{$0 == "change_calendar"}.count <= 2,"\(failure) must have bounded known-prerequisite recovery only")
            check(value.feed?.turns.last?.unresolvedToolErrors?.isEmpty == false,"\(failure) must retain its genuine unresolved limitation")
            if ["empty","read-error"].contains(failure) {
                let output=p.inputs[1].first{$0["type"] as? String == "function_call_output"}?["output"] as? String
                let detail=try output.flatMap{try JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:Any]}
                check(detail?["nativeSaveAttempted"] as? Bool == false && detail?["stage"] as? String == "read_preparation","A failed preparatory read must not be described as an uncertain native save")
            }
        }
        let batchProvider=FictionalInference(),batchContext=FictionalContext()
        settings.set(true,forKey:"assistantContextEnabled")
        let batchService=service(batchProvider,try open("preparation-partial-batch")),creation=nativeCall("change_calendar")
        let memoryCall=PAFunctionCall(id:UUID().uuidString,name:"save_memory",namespace:"pa",arguments:"{}")
        var batchWrites=0
        batchContext.configure={session,request in session.executeBody={call,session in
            if call.name == "save_memory" {
                guard batchService.memory.put(.init(registration:request.registration,text:"Fictional preference",kind:.preference,explicit:true,provenance:"Fictional human",sourceTurnID:request.turnID.uuidString)) else {throw ActionFailure.message("Fixture memory save failed")}
                session.receipts.append("Fictional earlier memory verified");return "{\"verified\":true}"
            }
            if call.name == "read_calendar" {session.calendar.sources=[destination];return "{}"}
            try PAToolProtocol.nativeReadPreflight(call.name,operation:"create",hasSources:!session.calendar.sources.isEmpty,hasDetails:false)
            batchWrites += 1;session.receipts.append("Fictional later event verified");return "{\"verified\":true}"
        }}
        batchProvider.replies=[response([memoryCall,creation]),final("Fictional batch completed")]
        _=batchService.send(runtime:batchContext.runtime(),topicID:nil,prompt:"Remember my fictional preference and add the fictional event")
        await until{!batchService.busy}
        check(batchWrites == 1 && batchContext.sessions[0].receipts.count == 2 && batchService.error == nil,"A recovered later operation preserves earlier verified receipts and self-authored memory revision")
        let replayed=batchProvider.inputs[1].filter{$0["type"] as? String == "function_call_output"}.compactMap{$0["call_id"] as? String}
        check(replayed == [memoryCall.id,creation.id],"Internal reads do not fabricate completed transport calls or duplicate the original operation")
        let readOnlyProvider=FictionalInference(),readOnlyContext=FictionalContext()
        let readOnlyService=service(readOnlyProvider,try open("readonly-receipts-unavailable"))
        var readOnlyOutcomes:[AssistantTurnOutcome]=[]
        var readOnlyRuntime=readOnlyContext.runtime();readOnlyRuntime.finished={readOnlyOutcomes.append($0)}
        var readOnlyProgress:[AssistantTurnOutcome]=[]
        readOnlyRuntime.working={readOnlyProgress.append($0)}
        readOnlyContext.configure={session,_ in session.actionReceiptsReadable=false}
        readOnlyProvider.replies=[final("Supported fictional read-only answer")]
        _=readOnlyService.send(runtime:readOnlyRuntime,topicID:nil,prompt:"Explain this fictional project")
        await until{!readOnlyService.busy}
        check(readOnlyOutcomes.last?.phase == "completed" && readOnlyOutcomes.last?.unconfirmedActions == 0,"Unavailable historical action receipts cannot invent uncertainty for a read-only answer")
        check(readOnlyProgress.isEmpty && readOnlyOutcomes.last?.attemptedTools.isEmpty == true,"A conversation-only answer emits no work progress or invented tool attempts")

        let uncertainProvider=FictionalInference(),uncertainContext=FictionalContext()
        let uncertainService=service(uncertainProvider,try open("uncertain-turn"))
        var uncertainOutcomes:[AssistantTurnOutcome]=[]
        var uncertainRuntime=uncertainContext.runtime();uncertainRuntime.finished={uncertainOutcomes.append($0)}
        var workingOutcomes:[AssistantTurnOutcome]=[]
        uncertainRuntime.working={outcome in
            check(uncertainContext.sessions[0].calls.isEmpty,"Work progress is emitted before the tool can attempt a save")
            check(uncertainContext.sessions[0].actionCountReads == 0,"Progress metadata never reads the durable action ledger")
            workingOutcomes.append(outcome)
        }
        uncertainContext.configure={session,_ in session.executeBody={_,session in
            session.pendingNativeActionCount=1
            throw PANativeActionUncertainty(operationKey:"fictional-durable-claim",nativeReadbackVerified:true,message:"Fictional save receipt is unconfirmed")
        }}
        uncertainProvider.replies=[response([nativeCall("change_calendar")]),final("This unsupported success must never be requested")]
        _=uncertainService.send(runtime:uncertainRuntime,topicID:nil,prompt:"Add the fictional event")
        await until{!uncertainService.busy}
        check(uncertainProvider.inputs.count == 1 && uncertainProvider.replies.count == 1,"Native uncertainty stops the real engine before another inference or save")
        check(uncertainOutcomes.count == 1 && uncertainOutcomes[0].phase == "uncertain" && uncertainOutcomes[0].unconfirmedActions == 1,"Fluent output cannot hide an unconfirmed native operation")
        check(workingOutcomes.count == 1 && workingOutcomes[0].attemptedTools == ["change_calendar"] && uncertainOutcomes[0].attemptedTools == ["change_calendar"],"Running and uncertain outcomes retain the same typed work")
        check(uncertainService.activityContext(uncertainOutcomes[0].conversationID)?.attemptedTools[uncertainOutcomes[0].responseTurnID] == ["change_calendar"],"Activity metadata publishes completed tool traces while retaining uncertain outcomes")

        let reviewProvider=FictionalInference(),reviewContext=FictionalContext()
        let reviewContainer=try open("review-handover"),reviewService=service(reviewProvider,reviewContainer)
        let primaryID=reviewService.openPA()!,humanID=UUID(),responseID=UUID()
        let reviewID=reviewService.openReview(key:"mail:fictional-source",title:"Fictional engineering milestones",sourceKind:"mail",accountID:"fictional-mail",messageID:"fictional-source",identity:nil,chatID:nil,seeds:[.init(role:"assistant",content:"Fictional source plan only",completed:true)])!
        check(reviewService.activityContext(reviewID)?.reviewMessageID == "fictional-source","Stable Activity context retains exact Review source ownership")
        check(reviewService.activeID == primaryID && reviewService.feed?.turns.isEmpty == true,"Opening Review retains general feed and selection without inference")
        check(reviewService.topics.isEmpty,"Dedicated Review is excluded from legacy topics")
        reviewService.draft="Retained general draft"
        var reviewValid=true,reviewFinished:[AssistantTurnOutcome]=[],normalFinished:[AssistantTurnOutcome]=[]
        var reviewRuntime=reviewContext.runtime();reviewRuntime.finished={reviewFinished.append($0)}
        var normalRuntime=reviewContext.runtime();normalRuntime.finished={normalFinished.append($0)}
        reviewProvider.holdNext=true
        let submitted=Date.now.addingTimeInterval(-120)
        check(reviewService.sendReview(runtime:reviewRuntime,conversationID:reviewID,prompt:"Please explain the fictional dates",humanTurnID:humanID,responseTurnID:responseID,query:"engineering milestones",sourceContext:"fictional-source",selectionContext:"Only selected fictional project tasks; unselected Calendar proposals are excluded.",submitted:submitted,focusAreas:[.studies],valid:{reviewValid}),"Real Review uses the shared engine")
        await until{reviewProvider.waiting}
        check(reviewContext.requests.last?.history.contains{$0["content"]?.contains("unselected Calendar proposals are excluded") == true} == true && String(describing:reviewProvider.inputs[0]).contains("unselected Calendar proposals are excluded"),"The inference and intent ports capture the displayed checkbox selection")
        check(reviewService.activeID == primaryID && reviewService.draft == "Retained general draft" && reviewService.feed?.turns.isEmpty == true,"A held Review keeps general selection, draft and history")
        check(reviewService.conversation(reviewID)?.turns.contains{$0.id == humanID && $0.created == submitted} == true,"Review retains captured human ID and submission time")
        check(reviewService.send(runtime:normalRuntime,topicID:nil,prompt:"A separate foreground request",focusAreas:[.career]),"Explicit foreground request queues while Review unwinds")
        reviewValid=false;reviewService.cancel();reviewProvider.replies=[final("Separate foreground result")];reviewProvider.release()
        await until{!reviewService.busy}
        check(reviewFinished.count == 1 && reviewFinished[0].responseTurnID == responseID && normalFinished.isEmpty,"Review completion fires once and does not run a general job through its continuation")
        reviewService.continueForegroundAfterReview(runtime:normalRuntime)
        await until{!reviewService.busy && normalFinished.count == 1}
        check(reviewFinished.count == 1 && reviewService.feed?.turns.last?.content == "Separate foreground result","Normal handover retains its own finished callback and result")
        let normalInput=String(describing:reviewProvider.inputs.last!)
        check(!normalInput.contains("Fictional source plan only") && !normalInput.contains("Please explain the fictional dates"),"General inference never receives isolated Review history")
        check(reviewService.draft == "Retained general draft","Normal handover preserves unsent general draft")
        let reopenedReview=service(reviewProvider,reviewContainer)
        check(reopenedReview.conversation(reviewID)?.reviewKey == "mail:fictional-source" && reopenedReview.feed?.id == primaryID,"Reopening preserves Review identity separately from the primary feed")

        // The real AssistantService and PAMemoryStore share a current native
        // snapshot only within each synchronous ownership decision. There is
        // no provider, source collection, native write or personal state here.
        for revokeSource in [false,true] {
            let projectionProvider=FictionalInference(),projectionContext=FictionalContext()
            let projectionService=service(projectionProvider,try open(revokeSource ? "stream-source-withdrawal" : "stream-source-batching"))
            let sourceIdentity=MemorySourceIdentity(kind:.calendar,accountID:"fictional-provider",containerID:"fictional-calendar",itemID:"fictional-stream-item")
            let sourceQuote="Prepare the fictional Orion prototype."
            let sourceItem=NativeLearningItem(identity:sourceIdentity,revision:"fictional-current-v1",label:"Fictional Studies",text:sourceQuote,date:projectionContext.now,changed:Date.now)
            let sourceEvidence=MemorySourceEvidence(identity:sourceIdentity,revision:sourceItem.revision,label:sourceItem.label,quote:sourceQuote,observed:Date.now,sourceDate:sourceItem.date)
            let sourceFact=PAMemory(registration:projectionProvider.activeID,text:"A Calendar entry requests the fictional Orion prototype.",kind:.commitment,explicit:false,provenance:"Fictional Calendar source",evidence:sourceQuote,certainty:.inferred,durability:.situational,source:sourceEvidence,sourceState:.proposed)
            check(projectionService.memory.putSources([sourceFact],evidenceTexts:[sourceIdentity:sourceQuote],expectedRevision:projectionService.memory.revision),"Streaming batching fixture saves exact source evidence in disposable storage")
            let validation=NativeLearningValidationBatch()
            var sourceAvailable=true,validationDecisions=0,nativeQueries=0,nativeBuilds=0,withdrawnBuilds=0
            @MainActor func currentItems()->[NativeLearningItem]? {
                nativeQueries += 1
                return validation.items(.calendar) {
                    nativeBuilds += 1
                    if !sourceAvailable {withdrawnBuilds += 1;return nil}
                    return [sourceItem]
                }
            }
            projectionService.memory.sourcePermissionProjection={
                guard let items=currentItems() else {return []}
                return Set(projectionService.memory.records.filter{NativeLearningRules.permitted($0,items:items)}.map(\.id))
            }
            var projectionRuntime=projectionContext.runtime()
            projectionRuntime.state={
                // A current runtime acknowledgement can depend on the same
                // native kind as the independent source-memory ownership guard.
                _=currentItems()
                return projectionContext.state
            }
            projectionRuntime.withValidation={body in
                validationDecisions += 1
                return validation.withSnapshot(body)
            }
            projectionProvider.deltas=(1...200).map{"Fictional streamed token \($0). "}
            projectionProvider.replies=[final("Completed fictional current-source response")]
            var emittedDeltas=0,partialAtWithdrawal=""
            projectionProvider.afterDelta={
                emittedDeltas += 1
                if revokeSource && emittedDeltas == 50 {
                    partialAtWithdrawal=projectionService.feed?.turns.last?.content ?? ""
                    sourceAvailable=false
                }
            }
            let clock=ContinuousClock(),began=clock.now
            check(projectionService.send(runtime:projectionRuntime,topicID:nil,prompt:"Explain the fictional Orion prototype"),"Current-source streaming fixture starts the actual assistant service")
            // Preparation has separate current decisions; isolate the engine's
            // callback counts before its task first runs on the main actor.
            validationDecisions=0;nativeQueries=0;nativeBuilds=0;withdrawnBuilds=0
            await until{!projectionService.busy}
            let localElapsed=began.duration(to:clock.now)
            check(validationDecisions >= 202,"All 200 partial callbacks, preflight and completed response retain a fresh full ownership decision")
            check(nativeQueries == validationDecisions*2 && nativeBuilds == validationDecisions,"Runtime and source-memory consumers share one current snapshot per callback, with no cross-callback reuse")
            if revokeSource {
                check(withdrawnBuilds > 0 && projectionService.error != nil,"The callback after access withdrawal freshly checks the unavailable native source")
                check(!partialAtWithdrawal.isEmpty && projectionService.feed?.turns.last?.content == partialAtWithdrawal && projectionService.feed?.turns.last?.completed == false,"Source withdrawal stops later partials and rejects completed output while retaining earlier historical text")
            } else {
                check(projectionService.feed?.turns.last?.content == "Completed fictional current-source response" && projectionService.feed?.turns.last?.completed == true && projectionService.error == nil,"Batching retains authoritative completed text and ordinary chat behaviour")
            }
            check(projectionContext.sessions.allSatisfy{$0.calls.isEmpty},"Streaming validation never invokes tools or performs a save")
            print("Local current-source streaming:200 deltas; revoke=\(revokeSource); decisions \(validationDecisions); queries \(nativeQueries); builds \(nativeBuilds); elapsed \(localElapsed)")
        }
        do {
            let definitions=ReviewPlanTools.tools.first?["tools"] as? [[String:Any]] ?? []
            let normal=PAToolProtocol.tools.first?["tools"] as? [[String:Any]] ?? []
            check(definitions.contains{$0["name"] as? String == "prepare_review_actions"} && !normal.contains{$0["name"] as? String == "prepare_review_actions"},"Only Review inference receives the draft proposal tool")
            check(ReviewPlanTools.tools.count == 1 && ReviewPlanTools.tools[0]["name"] as? String == "pa", "Draft preparation retains the local pa tool namespace")
            let input=ReviewPlanTools.Input(revision:UUID(),actions:[.init(existingID:"issued-action",selected:false)])
            let args=String(decoding:try JSONEncoder().encode(input),as:UTF8.self)
            let call=PAFunctionCall(id:"draft",name:"prepare_review_actions",namespace:"pa",arguments:args)
            let parsed=try ReviewPlanTools.input(call)
            check(parsed.revision == input.revision && parsed.actions[0].existingID == "issued-action" && !parsed.actions[0].selected,"Typed plan requests preserve exact revision and unticked action identity")
            var foreign=call;foreign.namespace="foreign"
            do {_=try ReviewPlanTools.input(foreign);check(false,"Foreign namespace cannot prepare a Review plan")} catch {check(true,"Foreign namespace cannot prepare a Review plan")}
            var object=try JSONSerialization.jsonObject(with:Data(args.utf8)) as! [String:Any]
            var rows=object["actions"] as! [[String:Any]];rows[0]["nativeSave"]="attempted";object["actions"]=rows
            var unknown=call;unknown.arguments=String(decoding:try JSONSerialization.data(withJSONObject:object),as:UTF8.self)
            do {_=try ReviewPlanTools.input(unknown);check(false,"Unknown concrete fields cannot slip into a draft tool")} catch {check(true,"Unknown concrete fields cannot slip into a draft tool")}
        }
        do {
            let provider=FictionalInference(),context=FictionalContext(),store=try open("review-canonical-actions"),service=service(provider,store)
            let id=service.openReview(key:"mail:canonical",title:"Fictional actions",sourceKind:"mail",accountID:"mail",messageID:"canonical",identity:nil,chatID:nil,seeds:[])!
            var outcomes:[AssistantTurnOutcome]=[],executions=0
            var runtime=context.runtime();runtime.prepareReviewActions={_,_ in "{}"}
            runtime.executeReviewActions={_,valid,refresh in
                precondition(valid());executions += 1
                for name in ["A","B"] {
                    precondition(valid(),"The previous verified save must not invalidate this batch")
                    let item=LifeItem(registration:service.connection.activeID,kind:.space,title:name)
                    _=try service.projects.create([item],receipt:.init(id:"review-"+name,registration:item.registration,result:"Created "+name,itemID:item.id))
                    refresh(true)
                    precondition(valid(),"Only the self-authored project revision is adopted")
                }
                return .init(output:"{\"verified\":true}",confirmed:["a":"Created A","b":"Created B"])
            }
            runtime.finished={outcomes.append($0)}
            provider.replies=[response([nativeCall("execute_review_actions")]),final("Two actions completed")]
            check(service.sendReview(runtime:runtime,conversationID:id,prompt:"Add both",humanTurnID:UUID(),responseTurnID:UUID(),query:"Add both",sourceContext:"{}",selectionContext:"Issued exact actions",submitted:context.now,focusAreas:[],valid:{true}),"Review accepts canonical execution through its isolated conversation")
            await until{!service.busy}
            check(executions == 1 && context.sessions.first?.calls.isEmpty == true,"Prepared execution uses its canonical callback rather than generic native creation")
            check(outcomes.first?.confirmedActions == 2 && outcomes.first?.receipts == ["Created A","Created B"] && outcomes.first?.phase == "completed","Canonical execution contributes exact confirmed receipts and honest completion")
        }
        print("PASS \(count) actual assistant service contracts: persisted preparation/send/reopen, exact traces/receipts, setup, ownership cancellation, serial queues and bounded native-read recovery; fictional providers/storage/settings only, no dashboard or Keychain.")
    }
}
