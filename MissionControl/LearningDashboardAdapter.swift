import Foundation

extension AssistantService: LearningAssistantReading {}
extension WhatsAppService: WhatsAppLearningReading {}

@MainActor extension DashboardModel {
    func learningRuntime() -> LearningRuntime {
        LearningRuntime(assistant: assistant, inference: chatGPT, learningBudget: learningBudget, whatsapp: whatsapp,
            activity: { [weak self] in
                guard let self else { return .unavailable }
                var lanes = Set<LearningLane>()
                if memoryLearning.busy { lanes.insert(.conversation) }
                if nativeSourceLearning.busy { lanes.insert(.nativeSources) }
                if sourceLearning.busy { lanes.insert(.whatsapp) }
                if lifeOrganisation.busy { lanes.insert(.organisation) }
                if memoryMaintenance.busy { lanes.insert(.maintenance) }
                return LearningActivity(otherWorkBusy: heartbeat.busy || projectPlacement.busy || proactive.busy || briefings.busy || emailSummaries.busy, lanes: lanes)
            }, writing: { [weak self] in self?.writing ?? true },
            sourceRevision: { [weak self] in self?.sourceRevision ?? .min },
            nativeItems: { [weak self] kind, now in self?.nativeLearningItems(kind, now: now) })
    }
}

@MainActor extension MemoryLearningService {
    func check(_ model: DashboardModel, manual: Bool = false) { check(model.learningRuntime(), manual: manual) }
    func recoverDelivery(_ model: DashboardModel) { recoverDelivery(model.learningRuntime()) }
    #if DEBUG
    func validate(_ model: DashboardModel) async throws -> String { try await validate(model.learningRuntime()) }
    #endif
}
@MainActor extension SourceContextLearningService {
    func lastAssessment(_ model: DashboardModel) -> Date { lastAssessment(model.learningRuntime()) }
    func status(_ model: DashboardModel) -> String { status(model.learningRuntime()) }
    func check(_ model: DashboardModel, manual: Bool = false) { check(model.learningRuntime(), manual: manual) }
}
@MainActor extension NativeSourceLearningService {
    func setEnabled(_ value: Bool, kind: MemorySourceKind, model: DashboardModel) { setEnabled(value, kind: kind, model: model.learningRuntime()) }
    func permits(_ record: PAMemory, model: DashboardModel) -> Bool { permits(record, model: model.learningRuntime()) }
    func status(_ kind: MemorySourceKind, model: DashboardModel) -> String { status(kind, model: model.learningRuntime()) }
    func check(_ model: DashboardModel, kind: MemorySourceKind? = nil, manual: Bool = false) { check(model.learningRuntime(), kind: kind, manual: manual) }
}
@MainActor extension LifeOrganisationService {
    func summary(_ model: DashboardModel) -> String { summary(model.learningRuntime()) }
    func check(_ model: DashboardModel, manual: Bool = false, topic: UUID? = nil) { check(model.learningRuntime(), manual: manual, topic: topic) }
}
@MainActor extension MemoryMaintenanceService {
    func check(_ model: DashboardModel, manual: Bool = false) { check(model.learningRuntime(), manual: manual) }
}
