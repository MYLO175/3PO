import Foundation

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
}

/// Bounded page prose plus exact supporting identities captured before yielding.
/// The callback checks only supplied knowledge and permission, never whole-store churn.
@MainActor struct AssistantPageContext {
    var text = "{}"
    var pageIDs: [String] = []
    var memoryIDs: Set<UUID> = []
    var workspaceIDs: Set<UUID> = []
    var referenceVersions: [String: String] = [:]
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
}

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
    var contextPages: (String, String?, UUID?, Bool, Bool) -> AssistantPageContext = { _,_,_,_,_ in .init() }
    var profileContextPages: (String, UUID?) -> AssistantPageContext = { _,_ in .init() }
    var pageKnowledgeAvailable: (String, [String: String]) -> Bool = { _,_ in true }
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
