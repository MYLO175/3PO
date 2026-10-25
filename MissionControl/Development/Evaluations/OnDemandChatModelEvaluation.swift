#if DEBUG
import Foundation
import SwiftData

/// The real foreground prompt/engine with invented history and read-only ports.
/// No personal sources, mutation ports, retries or normal app startup are available.
@MainActor enum OnDemandChatModelEvaluation {
    static func run(_ model: DashboardModel) async throws -> [String:Any] {
        let provider = BoundedChatInference(model.inference)
        guard provider.hasSession, provider.inferenceVerified, !provider.usagePaused else { throw IntegrationError.verification }
        let suite="3PO.on-demand-chat."+UUID().uuidString
        guard let settings=UserDefaults(suiteName:suite) else {throw IntegrationError.verification}
        let images=FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {settings.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:images)}
        settings.set(true,forKey:"paMemoryEnabled");settings.set(true,forKey:"assistantContextEnabled")
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        var old=AssistantConversation(accountID:provider.activeID,title:"Fictional earlier chat",isPrimary:true)
        old.turns=[.init(role:"user",content:"For our fictional launch, we chose the codename Kestrel Finch.",completed:true,created:Date.now.addingTimeInterval(-40_000)),
                   .init(role:"assistant",content:"Our fictional launch codename is Kestrel Finch.",completed:true,created:Date.now.addingTimeInterval(-39_990))]
        try ConversationRepository(container:container).save([old])
        let assistant=AssistantService(connection:provider,container:container,settings:settings,imageDirectory:images)
        // Only the directory/policy adapter uses this isolated model. Tools below
        // cannot reach DashboardModel or its source and action services.
        model.assistant=assistant
        let scope=WhatsAppSourceScope(registration:provider.activeID,linkedIdentity:"fictional-unused",revision:UUID())
        var broadReads=0, sessions:[OnDemandChatTools]=[]
        var runtime=AssistantRuntime(clock:{.now},state:{.init(attentionPreferencesReadable:true,resolvedRequests:[],whatsappScope:scope,weatherScope:"fictional-unused",weatherSupplied:false)},sourceSnapshot:{broadReads += 1;return nil},deliveryAvailable:{_ in true},tools:{request in
            let session=OnDemandChatTools(history:request.historyLookup);sessions.append(session);return session
        },afterTurn:{})
        runtime.conversationDirectory={model.conversationContextDirectory(registration:$0)}
        runtime.pageKnowledgeAvailable={model.contextKnowledgeAvailable(registration:$0,versions:$1)}
        let scenarios=[("self-contained","What does HTTP stand for? Answer in one short sentence."),
                       ("past-chat","What codename did we choose for our fictional launch in an earlier chat? Look it up in earlier chat."),
                       ("saved-page","What is the purpose of my fictional Orion rig project?")]
        var checks:[String:Bool]=[:],rows:[[String:Any]]=[]
        for (id,human) in scenarios {
            guard assistant.newChat(),assistant.send(runtime:runtime,topicID:nil,prompt:human,focusAreas:[]) else {throw IntegrationError.verification}
            while assistant.busy {try await Task.sleep(for:.milliseconds(50))}
            let reply=assistant.feed?.turns.last, names=sessions.last?.names ?? []
            checks[id+" completes using production foreground preparation"] = assistant.error == nil && reply?.completed == true
            if id == "self-contained" {checks["self-contained answer performs no lookup"] = names.isEmpty && reply?.content.lowercased().contains("hypertext transfer protocol") == true}
            if id == "past-chat" {checks["past-chat answer retrieves earlier discussion on demand"] = names.contains("search_chat_history") && reply?.content.contains("Kestrel Finch") == true}
            if id == "saved-page" {checks["personal question reads a relevant page on demand"] = names.contains("read_context_page") && reply?.content.lowercased().contains("alignment") == true}
            checks[id+" receives no old chat or personal records by default"] = reply?.contextCapture?.historyTurnIDs.count == 1 && reply?.contextCapture?.sourceSnapshotIncluded == false && reply?.contextCapture?.memoryIDs.isEmpty == true
            rows.append(["id":id,"tools":names,"reply":reply?.content ?? "","error":assistant.error ?? ""])
        }
        checks["no broad source projection or nonfixture tool execution"] = broadReads == 0 && sessions.allSatisfy{$0.unavailable == 0}
        return ["completed":Date.now.ISO8601Format(),"model":provider.selectedModel,"requests":provider.requests,"passed":checks.values.filter{$0}.count,"total":checks.count,"checks":checks,"scenarios":rows,"boundary":"Actual foreground preparation and configured subscription model over invented local history and static directory. Read-only fictional tools, no personal source access or mutation ports. At most eight requests, no retry."]
    }
}

@MainActor private final class BoundedChatInference: PAInferenceConnection {
    let base:any PAInferenceConnection
    private(set) var requests=0
    init(_ base:any PAInferenceConnection) {self.base=base}
    var activeID:String {base.activeID};var selectedModel:String {base.selectedModel}
    var busy:Bool {base.busy};var usagePaused:Bool {base.usagePaused}
    var inferenceVerified:Bool {base.inferenceVerified};var hasSession:Bool {base.hasSession}
    func streamResponse(input:[[String:String]],instructions:String,model:String?,effort:String,purpose:AIRequestPurpose,onDelta:@escaping(String)->Void) async throws -> String {throw IntegrationError.verification}
    func toolResponse(input:[[String:Any]],instructions:String,tools:[[String:Any]],model:String,purpose:AIRequestPurpose,onDelta:@escaping(String)->Void) async throws -> PAResponse {
        guard requests < 8 else {throw ActionFailure.message("Fictional model evaluation request limit reached; no retry.")}
        requests += 1
        return try await base.toolResponse(input:input,instructions:instructions,tools:tools,model:model,effort:"medium",purpose:.diagnostic,onDelta:onDelta)
    }
}

@MainActor private final class OnDemandChatTools: AssistantToolSession {
    var calendar=CalendarSnapshot(sources:[],events:[]),reminders=ReminderSnapshot(sources:[],reminders:[])
    var itemDetails:[String:NativeEditDetails]=[:],consultedMemory=Set<UUID>(),receipts:[String]=[],memoryNotes:[String]=[]
    var clarification:(String,[String])?;let mailCursor:any AssistantMailCursor=OnDemandMailCursor()
    let history:(String?,String?)->AssistantPageContext
    var names:[String]=[],captures:[AssistantPageContext]=[],unavailable=0
    var pageContextAvailable:Bool {captures.allSatisfy{$0.current()}}
    init(history:@escaping(String?,String?)->AssistantPageContext) {self.history=history}
    func execute(_ call:PAFunctionCall,valid:@escaping NativeWriteValidity) async throws -> String {
        guard valid() else {throw IntegrationError.verification}
        let args=try PAToolProtocol.arguments(call);names.append(call.name)
        if call.name == "search_chat_history" || call.name == "read_chat_history" {
            let capture=history(args["query"] as? String,args["id"] as? String);captures.append(capture);return capture.text
        }
        if call.name == "read_context_page" {return "{\"pages\":[{\"id\":\"fictional-orion\",\"title\":\"Orion rig\",\"markdown\":\"The fictional Orion rig measures camera alignment using repeatable photographs.\"}]}"}
        unavailable += 1
        throw ActionFailure.message("This evaluation has only read-only fictional history and page tools. No source or mutation was attempted.")
    }
}
@MainActor private final class OnDemandMailCursor:AssistantMailCursor {
    let status="Fictional, unused",results:[MailMessage]=[],hasMore=false,hasUnavailable=false
}
#endif
