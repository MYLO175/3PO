#if DEBUG
import SwiftUI

/// Fictional UI/transport checks return before all source startup and use disposable storage.
struct MemoryInspectionPreview:View {
    var model:DashboardModel
    @State private var ready=false
    @State private var capture:PAContextCapture?
    @ViewBuilder
    var body:some View {
        if ProcessInfo.processInfo.arguments.contains("--context-pages") {
            ContextPagesView(model: model).task {
                guard !ready else { return }; ready = true
                try? Self.seedContextPages(model)
            }
        } else {
        VStack {
            Button("Preview reply context") {
                let selection=model.assistant.memory.selection("fictional",includeTopics:true,query:"Orion",focus:[.projects])
                let notes=PAContextCapture.notebookIDs(model.assistant.memory.notebook("fictional",includeTopics:true).context(query:"Orion",focus:[.projects]))
                capture=PAContextCapture(model:"Fictional model",focusAreas:[.projects],memoryIDs:selection.records.compactMap{$0["id"].flatMap(UUID.init(uuidString:))},eligibleMemoryCount:selection.eligibleCount,notebookMemoryIDs:notes.memories,workspaceIDs:notes.workspace,historyTurnIDs:[],excerptedHistoryIDs:[],sourceSnapshotIncluded:false,sourceSnapshotBytes:0,profileSetup:false)
            }
            PAMemoryView(memory:model.assistant.memory,registration:"fictional",focusAreas:[.projects])
        }.task { guard !ready else { return };ready=true;Self.seed(model,registration:"fictional") }
            .sheet(item:$capture) { capture in PAContextCaptureView(capture:capture,model:model,registration:"fictional") }
        }
    }
    @MainActor private static func seedContextPages(_ model: DashboardModel) throws {
        let owner = model.chatGPT.activeID
        guard !owner.isEmpty else { throw ContextPageFailure.unavailable }
        let project = LifeItem(registration: owner, kind: .space, title: "Fictional Lark optics", notes: "Compare two camera-calibration methods.")
        _ = try model.assistant.projects.create([project], receipt: .init(id: "fictional-context-preview", registration: owner, result: "Fictional context preview prepared"))
        let overview = ContextPage(registration: owner, kind: .overview, key: "everyday", owner: .human, title: "Everyday context", markdown: "# My everyday context\n\nThis is a fictional engineering project preview. I prefer short, practical plans and clear uncertainty.\n\n## Where to look\n\nThe Lark optics project explains the current camera experiment.")
        let saved = try model.contextPages.save(overview, expectedRevision: nil)
        var revised = saved; revised.markdown += "\n\nKeep original evidence available when a plan changes."
        _ = try model.contextPages.save(revised, expectedRevision: saved.revision)
        let purpose = ContextPage(registration: owner, kind: .note, key: "project-purpose:" + project.id.uuidString, owner: .human, title: "Purpose of Fictional Lark optics", markdown: "Compare two camera-calibration methods on the same small optics rig. The next decision is which method is stable enough for repeated measurements.", references: [model.contextProjectIdentity(project)])
        _ = try model.contextPages.save(purpose, expectedRevision: nil)
        let records = model.contextKnowledge(registration: owner).filter { $0.projectID == project.id && $0.reference.kind != "projectIdentity" }
        if !records.isEmpty {
            var summary = ContextPage(registration: owner, kind: .project, key: project.id.uuidString, owner: .generated, title: project.title, synopsis: "Calibration comparison and next decision", markdown: "# Lark optics\n\nCompare two camera-calibration methods on the same rig. The next decision is which method supports repeatable measurements.\n\nNo completed experiment or attendance has been verified.", references: records.map(\.reference))
            summary.evidenceQuotes = records.map { .init(referenceID: $0.reference.id, quote: String($0.text.prefix(160))) }
            _ = try model.contextPages.save(summary, expectedRevision: nil)
        }
    }
    @MainActor static func seed(_ model:DashboardModel,registration:String) {
        let store=model.assistant.memory,now=Date.now
        var preference=PAMemory(registration:registration,text:"I prefer short practical plans.",kind:.preference,provenance:"Fictional human statement",evidence:"I prefer short practical plans.",certainty:.stated,durability:.stable)
        preference.organisation = .init(areas:[.about],connections:[])
        _=store.put(preference)
        _=store.put(.init(registration:registration,text:"My temporary Orion reading group is no longer relevant.",kind:.context,provenance:"Fictional retired human context",retiredAt:now,evidence:"My temporary Orion reading group is no longer relevant.",certainty:.stated,durability:.situational))
        let old=PAMemory(registration:registration,text:"I study the Orion course.",kind:.context,provenance:"Fictional human statement",evidence:"I study the Orion course.",certainty:.stated,durability:.stable)
        _=store.put(old)
        var revised=old;revised.id=UUID();revised.text="I now study the Lyra course.";revised.evidence=revised.text
        _=store.correct(old.id,with:revised)
        let resolved=PAMemory(registration:registration,text:"Prepare the Orion study plan.",kind:.commitment,provenance:"Fictional resolved memory",resolved:now)
        _=store.put(resolved)
        let identity=MemorySourceIdentity(kind:.whatsapp,accountID:"fictional-linked",containerID:"orion",itemID:"fictional-message",linkedIdentity:"fictional-linked")
        let evidence=MemorySourceEvidence(identity:identity,revision:"fictional-version",label:"Orion team",quote:"The Orion draft is due Monday.",observed:now,sourceDate:now)
        let source=PAMemory(registration:registration,text:"Alex reports the Orion draft is due Monday.",kind:.commitment,explicit:false,provenance:"Fictional source; access not granted",evidence:evidence.quote,certainty:.inferred,durability:.situational,source:evidence,sourceState:.accepted)
        _=store.put(source)
        _=store.put(.init(registration:"different-fictional-account",text:"Private unrelated fact must not appear.",kind:.context,provenance:"Fictional other account"))
    }
    @MainActor static func validate(_ model:DashboardModel) async {
        let registration=model.chatGPT.activeID,selected=model.chatGPT.selectedModel
        var checks:[String:Bool]=[:],report:[String:Any]=["storage":"Fictional input; in-memory store; no source startup","selectedModel":selected]
        guard !registration.isEmpty,model.assistant.memory.enabled,model.chatGPT.inferenceVerified,!model.chatGPT.usagePaused else {
            report["error"]="Existing account/memory access is unavailable. No setting changed and no request made."
            write(report);return
        }
        // The first Core Location delegate callback can revise authorised-access status.
        // Let that local status settle before capturing ownership; never bypass the live guard.
        _=model.weather.scope
        try? await Task.sleep(for:.milliseconds(350))
        seed(model,registration:registration)
        let selection=model.assistant.memory.selection(registration,includeTopics:true,query:"Orion",focus:[])
        let expected=Set(selection.records.compactMap{$0["id"].flatMap(UUID.init(uuidString:))})
        model.assistant.draft="What is my preference for plans? Use saved memory and keep the answer short."
        model.assistant.send(context:nil,model:model)
        checks["accepted"]=model.assistant.busy
        let deadline=Date.now.addingTimeInterval(150)
        while model.assistant.busy && Date.now < deadline { try? await Task.sleep(for:.milliseconds(200)) }
        if model.assistant.busy { model.assistant.cancel() }
        let turn=model.assistant.feed?.turns.last(where:{$0.role == "assistant"})
        checks["completed"]=turn?.completed == true
        checks["capture saved"]=turn?.contextCapture != nil
        if let capture=turn?.contextCapture {
            checks["exact initial selection"]=Set(capture.memoryIDs) == expected
            checks["no cached source snapshot"] = !capture.sourceSnapshotIncluded && capture.sourceSnapshotBytes == 0
            checks["preserved model"]=capture.model == selected && model.chatGPT.selectedModel == selected
            checks["no other-account or unavailable source fact"]=capture.memoryIDs.allSatisfy{id in model.assistant.memory.records.contains{$0.id == id && $0.registration == registration && $0.source == nil && MemoryRules.usable($0,registration:registration)}}
            checks["current human replayed"]=capture.historyTurnIDs.contains{ id in model.assistant.feed?.turns.contains{$0.id == id && $0.role == "user"} == true }
            if let data=try? JSONEncoder().encode(turn),let restored=try? JSONDecoder().decode(AssistantTurn?.self,from:data) { checks["capture round trip"]=restored.contextCapture == capture }
            report["attemptedTools"]=capture.attemptedTools
        }
        report["checks"]=checks;report["passed"]=checks.values.filter{$0}.count;report["total"]=checks.count;report["error"]=model.assistant.error as Any? ?? NSNull()
        write(report)
    }
    private static func write(_ report:[String:Any]) {
        if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-memory-inspection-evaluation.json"),options:.atomic)}
    }
}
#endif
