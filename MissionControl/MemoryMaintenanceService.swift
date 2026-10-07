import Foundation
import SwiftData
import Observation

/// Semantic maintenance only proposes human review; it never executes memory edits.
@MainActor @Observable final class MemoryMaintenanceService {
    private var state=MemoryReviewState()
    private var readable=true
    private let container:ModelContainer?
    private var task:Task<Void,Never>?
    private(set) var busy=false
    private(set) var error:String?
    private(set) var status="Review useful human facts for possible duplicates, conflicts or obsolete provisional context."
    private var revision=UUID()
    private var undoID:String?
    private var dismissalDate:Date?
    func undoDate(_ registration:String)->Date? { state.proposals.contains{$0.id == undoID && $0.registration == registration && $0.dismissed} ? dismissalDate : nil }
    init(container:ModelContainer?) {
        self.container=container
        do {
            if let saved=try container?.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first(where:{$0.key == "paMemoryReview"}) {
                state=try JSONDecoder().decode(MemoryReviewState.self,from:saved.data)
                guard state.version == 1 else { throw MemoryLearningFailure.invalid }
            }
        } catch { readable=false;self.error="Saved review data is unreadable and has been preserved." }
    }
    func automatic(_ registration:String)->Bool { readable && state.accounts[registration]?.automatic == true }
    func setAutomatic(_ value:Bool,registration:String) {
        guard readable,!registration.isEmpty else { return }
        let prior=state;state.accounts[registration,default:.init()].automatic=value
        do { try save();revision=UUID();if !value { cancel() } } catch { state=prior;self.error=error.localizedDescription }
    }
    func proposals(_ memory:PAMemoryStore,registration:String)->[MemoryReviewProposal] {
        state.proposals.filter{!$0.dismissed && MemoryReviewRules.current($0,records:memory.records,registration:registration)}.sorted{$0.created > $1.created}
    }
    func dismiss(_ id:String,registration:String) {
        guard let index=state.proposals.firstIndex(where:{$0.id == id && $0.registration == registration}) else { return }
        let prior=state;state.proposals[index].dismissed=true
        do { try save();revision=UUID();undoID=id;dismissalDate = .now } catch { state=prior;self.error=error.localizedDescription }
    }
    func undo(_ registration:String) {
        guard let index=state.proposals.firstIndex(where:{$0.id == undoID && $0.registration == registration && $0.dismissed}) else { return }
        let prior=state;state.proposals[index].dismissed=false
        do { try save();revision=UUID();undoID=nil;dismissalDate=nil } catch { state=prior;self.error=error.localizedDescription }
    }
    func paused(_ registration:String)->Bool { state.accounts[registration]?.paused == true }
    func check(_ model:DashboardModel,manual:Bool=false) {
        let memory=model.assistant.memory,registration=model.chatGPT.activeID,progress=state.accounts[registration] ?? .init()
        guard readable,!busy,!registration.isEmpty,manual || (progress.automatic && !progress.paused && Date.now.timeIntervalSince(progress.lastAttempt ?? .distantPast) >= 7*86400),
              memory.enabled,memory.learningEnabled,!model.assistant.busy,!model.assistant.hasDraft,!model.chatGPT.busy,!model.chatGPT.usagePaused,model.chatGPT.inferenceVerified,!model.writing,
              !model.heartbeat.busy,!model.projectPlacement.busy,!model.briefings.busy,!model.proactive.busy,!model.emailSummaries.busy,!model.memoryLearning.busy,!model.sourceLearning.busy,!model.nativeSourceLearning.busy,!model.lifeOrganisation.busy else { return }
        let now=Date.now,records=MemoryReviewRules.batch(memory.records,registration:registration,progress:progress,manual:manual,now:now)
        guard !records.isEmpty,let input=try? MemoryReviewRules.input(records,now:now),model.learningBudget.claim(registration,manual:manual) else { return }
        let prior=state;state.accounts[registration,default:.init()].paused=true;state.accounts[registration]?.lastAttempt=now
        do { try save() } catch { state=prior;self.error=error.localizedDescription;return }
        let captured=revision,memoryRevision=memory.revision,selectedModel=model.chatGPT.selectedModel
        busy=true;error=nil;status="Reviewing \(records.count) human facts; no edits will be made…"
        task=Task {
            defer { busy=false }
            do {
                try Task.checkCancellation()
                guard registration == model.chatGPT.activeID,captured == revision,memoryRevision == memory.revision,selectedModel == model.chatGPT.selectedModel,memory.enabled,memory.learningEnabled,!model.assistant.busy,!model.assistant.hasDraft,!model.writing else { throw MemoryLearningFailure.changed }
                let output=try await model.chatGPT.streamResponse(input:[["role":"user","content":input]],instructions:MemoryReviewRules.instructions,model:selectedModel,purpose:.organisation) { _ in }
                try Task.checkCancellation()
                guard registration == model.chatGPT.activeID,captured == revision,memoryRevision == memory.revision,selectedModel == model.chatGPT.selectedModel,memory.enabled,memory.learningEnabled,!model.assistant.busy,!model.assistant.hasDraft,!model.writing else { throw MemoryLearningFailure.changed }
                guard let proposals=MemoryReviewRules.decode(output,records:records,registration:registration,now:now) else { throw MemoryLearningFailure.invalid }
                let beforeSave=state
                for proposal in proposals where !state.proposals.contains(where:{$0.id == proposal.id}) { state.proposals.append(proposal) }
                for record in records { state.accounts[registration,default:.init()].inspected[record.id]=MemoryReviewRules.fingerprint(record) }
                let currentIDs=Set(memory.records.filter{$0.registration == registration}.map(\.id))
                state.accounts[registration]?.inspected=state.accounts[registration]?.inspected.filter{currentIDs.contains($0.key)} ?? [:]
                let retained=Array(state.proposals.filter{$0.registration == registration}.sorted{$0.created > $1.created}.prefix(200))
                state.proposals=state.proposals.filter{$0.registration != registration}+retained
                state.accounts[registration]?.paused=false
                do { try save() } catch { state=beforeSave;throw error }
                status="Reviewed \(records.count) facts; \(proposals.count) possible improvements. Check the evidence before changing a fact."
            } catch { self.error=error.localizedDescription;status="Review paused. Review now explicitly resumes; completed suggestions remain saved." }
        }
    }
    func cancel() { task?.cancel() }
    #if DEBUG
    func seedPreview(_ proposals:[MemoryReviewProposal]) {
        state.proposals=proposals
        do { try save() } catch { self.error=error.localizedDescription }
    }
    #endif
    private func save()throws {
        guard let container else { throw MemoryLearningFailure.storage }
        let data=try JSONEncoder().encode(state),context=container.mainContext
        if let saved=try context.fetch(FetchDescriptor<CachedDashboard>()).first(where:{$0.key == "paMemoryReview"}) { saved.data=data;saved.updated = .now }
        else { context.insert(CachedDashboard(key:"paMemoryReview",data:data)) }
        do { try context.save() } catch { context.rollback();throw error }
    }
}
