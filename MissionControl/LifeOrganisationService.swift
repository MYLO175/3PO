import Foundation
import Observation
import SwiftData

/// Classification of already-saved human facts only. No source scan, fact rewrite or Apple operation.
@MainActor @Observable final class LifeOrganisationService {
    var automatic = UserDefaults.standard.object(forKey:"paNotebookOrganisationEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automatic,forKey:"paNotebookOrganisationEnabled"); if !automatic { cancel() } }
    }
    private(set) var busy=false
    private(set) var error:String?
    private(set) var status=""
    private var task:Task<Void,Never>?
    private var state=LifeOrganisationState()
    private let container:ModelContainer?
    private var readable=true
    init(container:ModelContainer?) {
        self.container=container
        do {
            if let record=try container?.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first(where:{$0.key == "paLifeOrganisation"}) {
                state=try JSONDecoder().decode(LifeOrganisationState.self,from:record.data)
                guard state.version == 1 else { throw MemoryLearningFailure.invalid }
            }
        } catch { readable=false; self.error="Notebook organisation progress could not be read. Its saved record is preserved." }
    }
    func summary(_ model:DashboardModel)->String {
        if busy { return status }
        let registration=model.chatGPT.activeID,records=model.assistant.memory.records.filter{MemoryRules.usable($0,registration:registration)}
        let organised=records.filter{$0.organisation != nil}.count
        if state.accounts[registration]?.paused == true { return "Organisation paused after a stopped or failed attempt. Saved facts are unchanged; Organise memories resumes once." }
        return "\(organised) of \(records.count) saved facts organised · automatic limit: 2 small passes per day"
    }
    func check(_ model:DashboardModel,manual:Bool=false,topic:UUID?=nil) {
        let assistant=model.assistant,memory=assistant.memory,registration=model.chatGPT.activeID
        guard readable,!busy,(manual || automatic),memory.enabled,memory.learningEnabled,!assistant.busy,(manual || !assistant.hasDraft),
              !model.heartbeat.busy,!model.chatGPT.busy,!model.projectPlacement.busy,!model.chatGPT.usagePaused,model.chatGPT.inferenceVerified,!model.writing,
              !model.sourceLearning.busy,!model.memoryLearning.busy,!model.proactive.busy,!model.briefings.busy,!model.emailSummaries.busy,!registration.isEmpty else { return }
        let accountScopes:[UUID?]=[nil]+assistant.topics.sorted{$0.id.uuidString < $1.id.uuidString}.map{Optional($0.id)}
        let requestedScopes:[UUID?]=manual && topic != nil ? [nil,topic] : accountScopes
        let selectedModel=model.chatGPT.selectedModel,capturedTopics=Set(assistant.topics.map(\.id)),enabledAtStart=automatic
        if manual {
            let old=state
            for scope in requestedScopes {
                let key=LifeOrganisationBatch.scope(registration,scope)
                for record in memory.records where record.registration == registration && record.conversationID == scope && record.organisation == nil { state.scopes[key]?.inspected.removeValue(forKey:record.id) }
            }
            do { try save() } catch { state=old;self.error=error.localizedDescription;return }
        }
        guard LifeOrganisationBatch.allowed(state.accounts[registration] ?? .init(),now:.now,manual:manual) else { return }
        guard requestedScopes.contains(where:{ !batch(memory,registration:registration,topic:$0).isEmpty }) else { return }
        guard model.learningBudget.claim(registration,manual:manual) else { return }
        busy=true;error=nil
        task=Task {
            defer { busy=false }
            do {
                var total=0,passes=0
                for _ in 0..<(manual ? 4 : 1) {
                    try Task.checkCancellation()
                    guard memory.enabled,memory.learningEnabled,registration == model.chatGPT.activeID,selectedModel == model.chatGPT.selectedModel,
                          (manual || automatic == enabledAtStart),Set(assistant.topics.map(\.id)) == capturedTopics,!assistant.busy,!model.writing,(manual || !assistant.hasDraft) else { throw MemoryLearningFailure.changed }
                    guard let scope=requestedScopes.first(where:{ !batch(memory,registration:registration,topic:$0).isEmpty }) else { break }
                    let records=batch(memory,registration:registration,topic:scope),revision=memory.revision
                    let key=LifeOrganisationBatch.scope(registration,scope),now=Date.now,old=state
                    var progress=state.accounts[registration] ?? .init()
                    if progress.day != LifeOrganisationBatch.day(now) { progress.day=LifeOrganisationBatch.day(now);progress.attempts=0 }
                    progress.attempts += 1;progress.lastAttempt=now;progress.paused=true;state.accounts[registration]=progress
                    do { try save() } catch { state=old;throw error }
                    status="Organising \(records.count) saved facts…"
                    let output=try await model.chatGPT.streamResponse(input:[["role":"user","content":LifeOrganisationRules.input(records)]],instructions:LifeOrganisationRules.instructions,model:selectedModel,purpose:.organisation) { _ in }
                    try Task.checkCancellation()
                    guard revision == memory.revision,memory.enabled,memory.learningEnabled,registration == model.chatGPT.activeID,selectedModel == model.chatGPT.selectedModel,
                          (manual || automatic == enabledAtStart),Set(assistant.topics.map(\.id)) == capturedTopics,!assistant.busy,!model.writing,(manual || !assistant.hasDraft) else { throw MemoryLearningFailure.changed }
                    guard let entries=LifeOrganisationRules.decode(output,records:records) else { throw MemoryLearningFailure.invalid }
                    guard memory.organise(entries,expectedRevision:revision) else { throw MemoryLearningFailure.storage }
                    let before=state
                    for record in records { state.scopes[key,default:.init()].inspected[record.id]=record.reviewed }
                    state.accounts[registration]?.paused=false
                    do { try save() } catch { state=before;throw error }
                    total += entries.count;passes += 1
                }
                status="Organised \(total) saved facts in \(passes) small \(passes == 1 ? "pass" : "passes"). Original facts and evidence are preserved."
            } catch is CancellationError { error="Organisation stopped. Completed metadata is kept; the interrupted pass remains paused." }
            catch { self.error=error.localizedDescription }
        }
    }
    func cancel() { task?.cancel() }
    private func batch(_ memory:PAMemoryStore,registration:String,topic:UUID?)->[PAMemory] {
        LifeOrganisationBatch.records(memory.records,registration:registration,topic:topic,progress:state.scopes[LifeOrganisationBatch.scope(registration,topic)] ?? .init())
    }
    private func save() throws {
        guard let container else { throw MemoryLearningFailure.storage }
        let context=container.mainContext,data=try JSONEncoder().encode(state)
        if let record=try context.fetch(FetchDescriptor<CachedDashboard>()).first(where:{$0.key == "paLifeOrganisation"}) { record.data=data;record.updated = .now }
        else { context.insert(CachedDashboard(key:"paLifeOrganisation",data:data)) }
        do { try context.save() } catch { context.rollback();throw error }
    }
}
