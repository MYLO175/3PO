import Foundation

/// The learning services consume saved human context, permitted cached source
/// evidence and an inference port. They cannot navigate or start source helpers.
@MainActor protocol LearningAssistantReading: AnyObject {
    var connection: any PAInferenceConnection { get }
    var memory: PAMemoryStore { get }
    var busy: Bool { get }
    var hasDraft: Bool { get }
    var contextEnabled: Bool { get }
    var contextRevision: UUID { get }
    var topics: [AssistantConversation] { get }
    var excludedCalendars: Set<String> { get }
    var excludedLists: Set<String> { get }
    var excludedAccounts: Set<String> { get }
    func learningTurns() -> [MemoryLearningTurn]
    func acknowledgeLearned(_ learned: [LearnedMemory])
}

@MainActor protocol WhatsAppLearningReading: AnyObject {
    var messages: [WhatsAppReadMessage] { get }
    var chats: [WhatsAppChat] { get }
    func scope(for registration: String) -> WhatsAppSourceScope
    func access(for registration: String) -> WhatsAppAccess
}

struct LearningActivity {
    var otherWorkBusy = false
    var lanes: Set<LearningLane> = []
    func blocks(_ lane: LearningLane) -> Bool {
        otherWorkBusy || !lanes.subtracting([lane]).isEmpty
    }
    static var unavailable: Self { .init(otherWorkBusy: true) }
}

@MainActor final class LearningRuntime {
    let assistant: any LearningAssistantReading
    let inference: any PAInferenceConnection
    let learningBudget: LearningBudget
    let whatsapp: any WhatsAppLearningReading
    let now: () -> Date
    private let activity: () -> LearningActivity
    private let isWriting: () -> Bool
    private let revision: () -> Int
    private let cachedNativeItems: (MemorySourceKind, Date) -> [NativeLearningItem]?
    var writing: Bool { isWriting() }
    var sourceRevision: Int { revision() }
    func otherWorkBusy(excluding lane: LearningLane) -> Bool { activity().blocks(lane) }
    func nativeLearningItems(_ kind: MemorySourceKind) -> [NativeLearningItem]? { cachedNativeItems(kind, now()) }
    init(assistant: any LearningAssistantReading, inference: any PAInferenceConnection, learningBudget: LearningBudget, whatsapp: any WhatsAppLearningReading,
         now: @escaping () -> Date = { .now }, activity: @escaping () -> LearningActivity, writing: @escaping () -> Bool,
         sourceRevision: @escaping () -> Int, nativeItems: @escaping (MemorySourceKind, Date) -> [NativeLearningItem]?) {
        self.assistant = assistant; self.inference = inference; self.learningBudget = learningBudget; self.whatsapp = whatsapp
        self.now = now; self.activity = activity; self.isWriting = writing; self.revision = sourceRevision; self.cachedNativeItems = nativeItems
    }
}
