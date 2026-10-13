import Foundation

/// Current context authority needed by a foreground request. These are purpose
/// specific receipts and projections, not references to the application's services.
struct AssistantRuntimeState {
    var attentionPreferencesReadable: Bool
    var acknowledgementRevision: String
    var resolutionRevision: String
    var acknowledgements: [ReviewAcknowledgement]
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
    var started:(AssistantTurnOutcome)->Void = {_ in}
    var finished:(AssistantTurnOutcome)->Void = {_ in}
}

@MainActor extension AssistantToolSession {
    var confirmedActionCount:Int {receipts.count}
    var pendingNativeActionCount:Int {0}
    var actionReceiptsReadable:Bool {true}
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
}
