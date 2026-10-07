import Foundation

struct AutomaticMemoryCapture:Equatable {
    var records:[[String:String]]
    var dependencies:[MemoryDependency]
    var eligibleCount:Int
    var whatsappChats:Set<String> = []
    var context:String {
        let value:[String:Any]=["savedMemory":records,"commitmentReports":CommitmentRules.context(records),"eligibleMemoryCount":eligibleCount,"selectedMemoryCount":records.count,"coverage":"At most 40 usable saved facts and 20KB, with exact evidence and certainty. Partial local retrieval, not a complete life history. Source memories additionally follow this feature's source permissions; learning permission alone never enables WhatsApp briefing or automatic suggestions."]
        return (try? String(data:JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),encoding:.utf8)) ?? "{}"
    }
}
extension DashboardModel {
    func whatsappDependenciesAvailable(_ dependencies:[WhatsAppWindowDependency]?,use:AutomaticMemoryUse)->Bool {
        guard let dependencies,!dependencies.isEmpty else { return true }
        let access=whatsapp.access(for:chatGPT.activeID)
        guard assistant.contextEnabled,use.allowsWhatsApp(enabled:access.enabled,brief:access.briefEnabled,suggestions:access.includeInSuggestions == true,heartbeat:heartbeat.whatsappEnabled),dependencies.count <= MemoryDependencyRules.sourceChatLimit,Set(dependencies.map(\.chatID)).count == dependencies.count else { return false }
        return dependencies.allSatisfy { value in
            !value.linkedIdentity.isEmpty && value.linkedIdentity == whatsapp.linkedIdentity && access.chats.contains(value.chatID) &&
            ProactiveRules.whatsappWindow(whatsapp.messages,chats:[value.chatID],identity:whatsapp.linkedIdentity) == value.fingerprint
        }
    }
    private func automaticMemorySourceAllowed(_ record:PAMemory,use:AutomaticMemoryUse)->Bool {
        record.allSourceEvidence.allSatisfy { source in
            switch source.identity.kind {
            case .calendar,.reminder:return true // Current projection already checks exact native versions and filters.
            case .mail:return emailSummaries.enabled
            case .whatsapp:
                let access=whatsapp.access(for:record.registration)
                return use.allowsWhatsApp(enabled:access.enabled,brief:access.briefEnabled,suggestions:access.includeInSuggestions == true,heartbeat:heartbeat.whatsappEnabled)
            }
        }
    }
    func automaticMemory(_ use:AutomaticMemoryUse,query:String? = nil,mailAccounts:Set<String>? = nil,whatsappReady:Bool = true)->AutomaticMemoryCapture {
        // A source assessment without a retrieval subject must not fall back to a biography.
        // The daily brief remains an explicitly broad day-planning consumer.
        let selection=assistant.memory.selection(chatGPT.activeID,includeTopics:use == .brief,query:query ?? (use == .brief ? nil : ""),sourceFilter:{record in
            self.automaticMemorySourceAllowed(record,use:use) && record.allSourceEvidence.allSatisfy{source in
                (source.identity.kind != .mail || mailAccounts?.contains(source.identity.accountID) ?? true) && (source.identity.kind != .whatsapp || whatsappReady)
            }
        })
        let selected=Set(selection.records.compactMap{$0["id"]})
        let chats=Set(assistant.memory.records.filter{selected.contains($0.id.uuidString)}.flatMap(\.allSourceEvidence).filter{$0.identity.kind == .whatsapp}.map{$0.identity.containerID})
        return .init(records:selection.records,dependencies:MemoryDependencyRules.capture(selection.records),eligibleCount:selection.eligibleCount,whatsappChats:chats)
    }
    func memoryDependenciesAvailable(_ dependencies:[MemoryDependency]?,use:AutomaticMemoryUse)->Bool {
        guard let dependencies,!dependencies.isEmpty else { return true }
        return MemoryDependencyRules.available(dependencies,records:memoryDependencyRecords(dependencies,use:use).map(MemoryRetrieval.record))
    }
    func memoryDependencyRecords(_ dependencies:[MemoryDependency],use:AutomaticMemoryUse)->[PAMemory] {
        let ids=Set(dependencies.map(\.id))
        return assistant.memory.enabled ? assistant.memory.permittedRecords.filter {
            ids.contains($0.id.uuidString) && MemoryRules.usable($0,registration:chatGPT.activeID) &&
            MemoryRules.inScope($0,conversationID:nil,includeTopics:use == .brief) && automaticMemorySourceAllowed($0,use:use)
        } : []
    }
}
