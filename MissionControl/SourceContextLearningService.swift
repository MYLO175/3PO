import Foundation
import Observation
import SwiftData

@MainActor @Observable final class SourceContextLearningService {
    private(set) var busy=false
    private(set) var error:String?
    private var task:Task<Void,Never>?
    private var state=SourceContextState()
    private let container:ModelContainer?
    private var readable=true
    init(container:ModelContainer?) {
        self.container=container
        do {
            if let saved=try container?.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first(where:{$0.key == "paSourceContextLearning"}) {
                state=try JSONDecoder().decode(SourceContextState.self,from:saved.data)
                guard state.version == 1 else { throw MemoryLearningFailure.invalid }
            }
        } catch { readable=false;self.error="Source-learning progress could not be read; its saved record is preserved." }
    }
    private func key(_ scope:WhatsAppSourceScope)->String { scope.registration+":"+scope.linkedIdentity }
    func status(_ model:DashboardModel)->String {
        if busy { return "Learning from a small recent WhatsApp batch…" }
        let scope=model.whatsapp.scope(for:model.chatGPT.activeID),access=model.whatsapp.access(for:scope.registration)
        if !access.enabled || access.learnContext != true { return "WhatsApp context learning is off. Enable it separately in WhatsApp → PA chat access." }
        if state.scopes[key(scope)]?.paused == true { return "Source learning paused after an interrupted or failed attempt. Check recent context resumes once." }
        return "Selected chats only · last 48 hours · up to 8 messages per pass · shared learning budget: 4 automatic passes/day"
    }
    func check(_ model:DashboardModel,manual:Bool=false) {
        let assistant=model.assistant,memory=assistant.memory,registration=model.chatGPT.activeID
        let scope=model.whatsapp.scope(for:registration),access=model.whatsapp.access(for:registration)
        guard readable,!busy,access.enabled,access.learnContext == true,!scope.linkedIdentity.isEmpty,!access.chats.isEmpty,
              memory.enabled,memory.learningEnabled,assistant.contextEnabled,!assistant.busy,!assistant.hasDraft,!model.writing,
              !model.chatGPT.busy,!model.chatGPT.usagePaused,model.chatGPT.inferenceVerified,!model.memoryLearning.busy,
              !model.lifeOrganisation.busy,!model.proactive.busy,!model.briefings.busy,!model.emailSummaries.busy else { return }
        let scopeKey=key(scope),progress=state.scopes[scopeKey] ?? .init()
        guard manual || !progress.paused else { return }
        let recent=SourceContextRules.recent(model.whatsapp.messages,chats:model.whatsapp.chats,allowed:access.chats,now:.now)
        let batch=SourceContextRules.batch(recent,progress:progress)
        guard !batch.isEmpty,model.learningBudget.claim(registration,manual:manual) else { return }
        let previous=state
        var claim=progress;claim.paused=true;state.scopes[scopeKey]=claim
        do { try save() } catch { state=previous;self.error=error.localizedDescription;return }
        let memoryRevision=memory.revision,selectedModel=model.chatGPT.selectedModel
        let sourcesEnabled=assistant.contextEnabled
        let existing=memory.context(registration,query:batch.map(\.text).joined(separator:" ")).prefix(12).map{["text":String(($0["text"] ?? "").prefix(500)),"certainty":$0["certainty"] ?? "unknown"]}
        busy=true;error=nil
        task=Task {
            defer { busy=false }
            do {
                try Task.checkCancellation()
                guard scope == model.whatsapp.scope(for:model.chatGPT.activeID),registration == model.chatGPT.activeID,memoryRevision == memory.revision,
                      selectedModel == model.chatGPT.selectedModel,memory.enabled,memory.learningEnabled,assistant.contextEnabled,!assistant.busy,!assistant.hasDraft,!model.writing else { throw MemoryLearningFailure.changed }
                let input=try SourceContextRules.input(batch,existing:existing)
                let output=try await model.chatGPT.streamResponse(input:[["role":"user","content":input]],instructions:SourceContextRules.instructions,model:selectedModel) { _ in }
                try Task.checkCancellation()
                guard scope == model.whatsapp.scope(for:model.chatGPT.activeID),registration == model.chatGPT.activeID,
                      selectedModel == model.chatGPT.selectedModel,memoryRevision == memory.revision,memory.enabled,memory.learningEnabled,
                      sourcesEnabled == assistant.contextEnabled,assistant.contextEnabled,!assistant.busy,!assistant.hasDraft,!model.writing else { throw MemoryLearningFailure.changed }
                let fresh=SourceContextRules.recent(model.whatsapp.messages,chats:model.whatsapp.chats,allowed:access.chats,now:.now)
                guard batch.allSatisfy({item in fresh.contains(where:{$0 == item})}),
                      let facts=SourceContextRules.decode(output,messages:batch,registration:registration,linkedIdentity:scope.linkedIdentity,now:.now) else { throw MemoryLearningFailure.invalid }
                let quotes=Dictionary(facts.compactMap{fact in batch.first(where:{$0.itemID == fact.source?.identity.itemID && $0.chatID == fact.source?.identity.containerID}).map{(fact.id,$0.text)}},uniquingKeysWith:{first,_ in first})
                guard memory.putSources(facts,sourceTexts:quotes,expectedRevision:memoryRevision) else { throw MemoryLearningFailure.storage }
                let old=state
                var complete=progress
                if !complete.oriented { for item in recent { complete.seen[item.id]=item.revision };complete.oriented=true }
                for item in batch { complete.seen[item.id]=item.revision }
                // Keep only bounded recent cursor identities; message text lives in the encrypted source cache.
                let recentIDs=Set(recent.map(\.id));complete.seen=complete.seen.filter{recentIDs.contains($0.key)}
                complete.paused=false;state.scopes[scopeKey]=complete
                do { try save() } catch { state=old;throw error }
            } catch { self.error=error.localizedDescription }
        }
    }
    func cancel() { task?.cancel() }
    private func save() throws {
        guard let container else { throw MemoryLearningFailure.storage }
        let context=container.mainContext,data=try JSONEncoder().encode(state)
        if let saved=try context.fetch(FetchDescriptor<CachedDashboard>()).first(where:{$0.key == "paSourceContextLearning"}) { saved.data=data;saved.updated = .now }
        else { context.insert(CachedDashboard(key:"paSourceContextLearning",data:data)) }
        do { try context.save() } catch { context.rollback();throw error }
    }
}
