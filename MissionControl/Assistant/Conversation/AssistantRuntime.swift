import Foundation

/// Preserve developer authority while separating reusable policy from changing request data.
/// An actual human message ends the initial developer block, giving implicit caching
/// a reusable boundary without unsupported explicit markers or synthetic human evidence.
struct AssistantRequestPrompt {
    var stable: String
    var current: String
    func input(around history: [[String: Any]]) -> [[String: Any]] {
        let policy: [String: Any] = ["role": "developer", "content": [["type": "input_text", "text": stable]]]
        let context: [String: Any] = ["role": "developer", "content": [["type": "input_text", "text": current]]]
        guard let firstHuman = history.firstIndex(where: { $0["role"] as? String == "user" }) else {
            return [policy, context] + history
        }
        return [policy] + Array(history[...firstHuman]) + [context] + Array(history.dropFirst(firstHuman + 1))
    }
}

/// Current context authority needed by a foreground request. These are purpose
/// specific receipts and projections, not references to the application's services.
struct AssistantRuntimeState {
    var attentionPreferencesReadable: Bool
    /// All current exact confirmations; presentation caps must not evict an owned receipt.
    var resolvedRequests: [[String:String]]
    var whatsappScope: WhatsAppSourceScope
    var weatherScope: String
    /// No weather permission dependency exists when no forecast was supplied.
    var weatherSupplied:Bool = true
}

/// Permission/ownership metadata only; reading this must never project sources,
/// memory, context pages, historical receipts or native items.
struct AssistantStreamingState {
    var storageCurrent: Bool
    var whatsappScope: WhatsAppSourceScope
    var weatherScope: String
}

struct AssistantToolRequest {
    var registration: String
    var human: String
    var humanContext: String
    var topicID: UUID?
    var turnID: UUID
    var mail: (any AssistantMailCursor)?
    var history: [[String: String]]
    var focusAreas: [LifeArea]?
    var inferenceModel:String? = nil
    var memoryBackend: String = "pages"
    /// Explicit historical reads return data and receipts, never human authority.
    var historyLookup: (String?, String?) -> AssistantPageContext = { _,_ in .init(text: "{\"available\":false}") }
}

/// Bounded page prose plus exact supporting identities captured before yielding.
/// The callback checks only supplied knowledge and permission, never whole-store churn.
@MainActor struct AssistantPageContext {
    var text = "{}"
    var pageIDs: [String] = []
    var memoryIDs: Set<UUID> = []
    var workspaceIDs: Set<UUID> = []
    var referenceVersions: [String: String] = [:]
    var sourceAccessFingerprints: [String:String] = [:]
    /// Stable ordinary-chat orientation, placed before clocks, snapshots and request-local facts.
    var guideText: String = ""
    var guideFingerprint: String? = nil
    var validate: (Set<String>) -> Bool = { _ in true }
    func current(ignoring: Set<String> = []) -> Bool { validate(ignoring) }
    func including(_ guidance: AssistantPageContext, as key: String) -> AssistantPageContext {
        let base = self
        var value = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        value[key] = (try? JSONSerialization.jsonObject(with: Data(guidance.text.utf8))) as? [String: Any] ?? [:]
        let encoded = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return .init(text: encoded, pageIDs: Array(Set(pageIDs + guidance.pageIDs)).sorted(),
                     memoryIDs: memoryIDs.union(guidance.memoryIDs), workspaceIDs: workspaceIDs.union(guidance.workspaceIDs),
                     referenceVersions: referenceVersions.merging(guidance.referenceVersions) { first, _ in first },
                     sourceAccessFingerprints: sourceAccessFingerprints.merging(guidance.sourceAccessFingerprints) { first,_ in first },
                     guideText: guideText,
                     guideFingerprint: guideFingerprint,
                     validate: { base.current(ignoring: $0) && guidance.current(ignoring: $0) })
    }
}

/// Read-only cursor presentation. Source searching remains inside the turn's tool
/// session; the assistant retains its identity without constructing a Mail reader.
@MainActor protocol AssistantMailCursor: AnyObject {
    var status: String { get }
    var results: [MailMessage] { get }
    var hasMore: Bool { get }
    var hasUnavailable: Bool { get }
    var searchTerms: [String] { get }
}
extension AssistantMailCursor { var searchTerms: [String] { [] } }

/// A session owns exact issued IDs, bounded source cursors and durable receipts
/// for one turn. Production execution and fictional execution use the same boundary.
@MainActor protocol AssistantToolSession: AnyObject {
    var calendar: CalendarSnapshot { get }
    var reminders: ReminderSnapshot { get }
    var itemDetails: [String: NativeEditDetails] { get }
    var consultedMemory: Set<UUID> { get }
    var consultedWorkspace: Set<UUID> { get }
    var suppliedWeatherScope:String? {get}
    var suppliedWhatsAppScope:WhatsAppSourceScope? {get}
    var pageContextAvailable: Bool { get }
    var consultedContextVersions: [String: String] { get }
    var suppliedSourceAccessFingerprints: [String:String] { get }
    func adoptContextChanges(_ keys: Set<String>)
    var receipts: [String] { get }
    var confirmedActionCount:Int {get}
    var pendingNativeActionCount:Int {get}
    var actionReceiptsReadable:Bool {get}
    var memoryNotes: [String] { get set }
    var clarification: (String, [String])? { get }
    var mailCursor: any AssistantMailCursor { get }
    func execute(_ call: PAFunctionCall, valid: @escaping NativeWriteValidity) async throws -> String
}

/// The desktop adapter supplies source/review projections and tool creation. The
/// assistant owns conversation state, preparation, inference, queues and storage.
@MainActor struct AssistantRuntime {
    var clock: () -> Date
    var state: () -> AssistantRuntimeState?
    var sourceSnapshot: () -> String?
    var deliveryAvailable: (AssistantTurn) -> Bool
    var tools: (AssistantToolRequest) -> any AssistantToolSession
    var afterTurn: () -> Void
    var streamingState: (() -> AssistantStreamingState?)? = nil
    /// Ordinary chat does not project Review attention until it actually reads it.
    var requestState: ((Bool) -> AssistantRuntimeState?)? = nil
    var conversationDirectory: (String) -> AssistantPageContext = { _ in .init() }
    func snapshot(includeAttention: Bool) -> AssistantRuntimeState? {
        if let requestState { return requestState(includeAttention) }
        return state()
    }
    func historicalAccessAvailable(_ turn: AssistantTurn) -> Bool {
        guard turn.role == "assistant" else { return true }
        if let captured = turn.sourceAccessFingerprints, !captured.isEmpty {
            return captured.allSatisfy { lookupAccess($0.key) == $0.value }
        }
        guard let capture = turn.contextCapture else { return true }
        if capture.sourceSnapshotIncluded {
            guard let access = capture.retrievalAccess, lookupAccess("read_context_page") == access else { return false }
        }
        let reads = (capture.lookups ?? []).filter { Self.sourceReadTools.contains($0.tool) && $0.status == "completed" }
        let attempted = Set(capture.attemptedTools).intersection(Self.sourceReadTools)
        guard attempted.isSubset(of:Set(reads.map(\.tool))) else { return false }
        return reads.allSatisfy { row in row.accessFingerprint.map { lookupAccess(row.tool) == $0 } ?? false }
    }
    func historicalSourceAccess(_ turn: AssistantTurn) -> [String:String] {
        if let captured=turn.sourceAccessFingerprints, !captured.isEmpty { return captured }
        var access: [String:String] = [:]
        for row in turn.contextCapture?.lookups ?? [] where Self.sourceReadTools.contains(row.tool) && row.status == "completed" {
            if let fingerprint=row.accessFingerprint {access[row.tool]=fingerprint}
        }
        if turn.contextCapture?.sourceSnapshotIncluded == true, let fingerprint=turn.contextCapture?.retrievalAccess {access["read_context_page"]=fingerprint}
        return access
    }
    static let sourceReadTools: Set<String> = ["read_calendar", "read_reminders", "read_item_details", "search_mail", "continue_mail", "read_email", "list_whatsapp_chats", "search_whatsapp", "read_weather", "read_attention"]
    /// Lookup metadata is recorded only at tool boundaries, never per text fragment.
    var lookupAccess: (String) -> String? = { _ in nil }
    var contextPages: (String, String?, UUID?, Bool, Bool) -> AssistantPageContext = { _,_,_,_,_ in .init() }
    var memoryBackend: String = "pages"
    var memoryBackendCurrent: () -> Bool = { true }
    var memoryBackendInstructions: String = ""
    var profileContextPages: (String, UUID?) -> AssistantPageContext = { _,_ in .init() }
    var pageKnowledgeAvailable: (String, [String: String]) -> Bool = { _,_ in true }
    /// One fresh synchronous projection for a bounded history selection; no result
    /// is retained across an await or another validation decision.
    var pageKnowledgeAvailability: ((String, [[String: String]]) -> [Bool])?
    var ownedPageKnowledgeAvailable: ((String, [String: String], Set<String>) -> Bool)?
    var ownedContextReferences: (String, Set<String>) -> Set<String> = { _, keys in keys }
    /// Exact dependencies a supported memory mutation may retire, captured before it removes its lineage.
    var memoryMutationReferences: (String, PAFunctionCall) -> Set<String> = { _, _ in [] }
    var started:(AssistantTurnOutcome)->Void = {_ in}
    var working:(AssistantTurnOutcome)->Void = {_ in}
    var finished:(AssistantTurnOutcome)->Void = {_ in}
    /// Share current source projections only within one synchronous ownership decision.
    var withValidation:(() -> Bool)->Bool = {$0()}
    /// Review-only drafts. Produces selectable proposals, never native/project writes.
    var prepareReviewActions:((PAFunctionCall,@escaping NativeWriteValidity) async throws -> String)?
    var executeReviewActions:((PAFunctionCall,@escaping NativeWriteValidity,@escaping @MainActor (Bool)->Void) async throws -> ReviewActionExecution)?
    var reviewCreationGuard:((PAFunctionCall)throws->Void)?
    var approvalAvailable:((AssistantActionProposal)->Bool)?
    /// Executes the exact displayed payload with human authority and no inference.
    var approveAction:((AssistantActionProposal,@escaping NativeWriteValidity) async throws -> String)?
}
struct ReviewActionExecution {
    var output:String
    var confirmed:[String:String]
    var uncertain:Int=0
    var failure:String?
}

@MainActor extension AssistantToolSession {
    var consultedWorkspace:Set<UUID> { [] }
    var confirmedActionCount:Int {receipts.count}
    var pendingNativeActionCount:Int {0}
    var actionReceiptsReadable:Bool {true}
    var suppliedWeatherScope:String? {nil}
    var suppliedWhatsAppScope:WhatsAppSourceScope? {nil}
    var pageContextAvailable: Bool { true }
    var consultedContextVersions: [String: String] { [:] }
    var suppliedSourceAccessFingerprints: [String:String] { [:] }
    func adoptContextChanges(_ keys: Set<String>) {}
}

struct AssistantTurnOutcome {
    var registration:String
    var conversationID:UUID
    var humanTurnID:UUID
    var responseTurnID:UUID
    var phase:String
    var message:String
    var receipts:[String]
    var errors:[String]
    var confirmedActions:Int = 0
    var unconfirmedActions:Int = 0
    var attemptedTools:[String] = []
}
