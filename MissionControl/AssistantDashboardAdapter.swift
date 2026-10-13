import Foundation

extension MailLookup: AssistantMailCursor { }

extension AssistantService {
    @discardableResult func beginSetup(model: DashboardModel, topic: UUID?) -> Bool {
        beginSetup(runtime: model.assistantRuntime(), topic: topic)
    }
    @discardableResult func sendProfile(model: DashboardModel, topic: UUID?, answer: String, control: Bool = false) -> Bool {
        sendProfile(runtime: model.assistantRuntime(), topic: topic, answer: answer, control: control)
    }
    @discardableResult func send(model: DashboardModel, topicID: UUID?, prompt: String, focusAreas: [LifeArea]? = nil, images: [ChatImageAttachment] = []) -> Bool {
        model.reviewWork.interruptForForeground(model.chatGPT.activeID)
        return send(runtime: model.assistantRuntime(), topicID: topicID, prompt: prompt, focusAreas: focusAreas, images: images)
    }
    func send(model: DashboardModel) { model.reviewWork.interruptForForeground(model.chatGPT.activeID);send(runtime: model.assistantRuntime()) }
    func send(context: String?, model: DashboardModel) { model.reviewWork.interruptForForeground(model.chatGPT.activeID);send(context: context, runtime: model.assistantRuntime()) }
    func resumeQueue(model: DashboardModel) { resumeQueue(runtime: model.assistantRuntime()) }
    func sourceSafeHistory(_ model: DashboardModel, feed: AssistantConversation, topic: AssistantConversation?) -> [AssistantTurn] {
        sourceSafeHistory(runtime: model.assistantRuntime(), feed: feed, topic: topic)
    }
    func localDiscoveryReview(_ prompt: String, model: DashboardModel, topicID: UUID?) -> PADiscovery? {
        guard let feed else { return nil }
        let turns = ConversationRules.thread(feed:feed,topic:conversation(topicID)).filter { $0.profileSessionID == nil }
        let records = model.proactive.state.records.filter { $0.registration == connection.activeID && UUID(uuidString:$0.id) != nil && model.proactive.visible($0,model:model) }
        return ProactiveReviewRules.reference(prompt,turns:turns,records:records)
    }
    func snapshot(_ model: DashboardModel) -> String? {
        guard contextEnabled else { return nil }
        let events = model.paOrientation?.events(excluding:excludedCalendars) ?? model.calendarData.events.filter { !excludedCalendars.contains($0.calendarID) }
        let eventCount = model.paOrientation?.calendar.events.filter { !excludedCalendars.contains($0.calendarID) }.count ?? events.count
        let coverage = model.paOrientation?.coverage(limit:200,enabledCount:eventCount) ?? "Fallback: dashboard selected date and following seven days, first 60 events. The PA's 90-day calendar orientation is unavailable."
        let eventLimit = model.paOrientation == nil ? 60 : 200
        let tasks = model.reminderData.reminders.filter { !excludedLists.contains($0.listID) }
        let emails = model.mailData.messages.filter { !excludedAccounts.contains($0.accountID) }.sorted { $0.received > $1.received }
        let summaries = model.emailSummaries.highlights(model).filter{!model.acknowledgedEmail($0.0,$0.1)}.map { message,summary -> [String:Any] in
            ["id":message.id,"account":message.account,"subject":message.subject,"received":message.received.ISO8601Format(),"summary":summary.summary,"attention":EmailHighlightRules.needsAction(summary,replied:message.replied),"replied":message.replied,"assessmentCategory":EmailHighlightRules.category(summary,replied:message.replied),"reason":summary.reason,"evidence":summary.evidence,"followUpDate":summary.followUpDate ?? "none","summarisedAt":summary.created.ISO8601Format()]
        }
        let value: [String:Any] = [
            "now":Date.now.ISO8601Format(), "timezone":TimeZone.current.identifier, "localWeather":model.weather.context(),
            "calendarStatus":model.paOrientation == nil ? model.calendarHealth.detail : model.paOrientationHealth.detail, "calendarCoverage":coverage, "calendarCount":eventCount,
            "events":events.prefix(eventLimit).map { ["id":$0.id, "title":String($0.title.prefix(500)), "start":$0.allDay ? DateRules.localDate($0.start) : DateRules.localTimestamp($0.start), "end":$0.allDay ? DateRules.localDate(PAToolProtocol.exclusiveAllDayEnd($0.end)) : DateRules.localTimestamp($0.end), "allDay":$0.allDay, "source":$0.sourceLabel, "location":String($0.location.prefix(500))] as [String:Any] },
            "reminderStatus":model.reminderHealth.detail, "reminderCount":tasks.count,
            "reminders":tasks.prefix(80).map { ["id":$0.id, "title":String($0.title.prefix(500)), "due":DateRules.reminderDue($0), "hasTime":$0.hasTime, "source":$0.sourceLabel] as [String:Any] },
            "mailStatus":model.mailHealth.detail, "mailCoverage":model.mailCoverage, "mailHeaderCount":emails.count,
            "recentEmailHeaders":emails.prefix(20).map { ["id":$0.id, "sender":String($0.sender.prefix(500)), "subject":String($0.subject.prefix(500)), "received":$0.received.ISO8601Format(), "account":$0.account] },
            "attentionPreferences":model.emailSummaries.preferences(model.chatGPT.activeID).map{["topic":$0.topic,"attention":$0.direction]},
            "reviewAcknowledgements":(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(model.reviewAcknowledgements()))) ?? [],
            "resolvedEmailRequests":model.emailSummaries.resolutionContext(model),
            "savedEmailSummaries":Array(summaries.prefix(20)), "emailSummaryCoverage":model.emailSummaries.coverage(model),
            "limits":"At most \(eventLimit) events, 80 reminders, 20 recent email headers and 20 saved summaries. No full email bodies. Excluded sources are omitted."
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }
}

extension DashboardModel {
    /// Desktop composition only. A foreground turn consumes snapshots and typed
    /// tools; it never receives the dashboard itself.
    func assistantRuntime() -> AssistantRuntime {
        AssistantRuntime(clock: { .now }, state: { [weak self] in
            guard let self else { return nil }
            return nativeLearningValidation.withSnapshot { [self] in
                AssistantRuntimeState(attentionPreferencesReadable: self.emailSummaries.relevanceReadable,
                         acknowledgementRevision: self.reviewAcknowledgementRevision,
                         resolutionRevision: self.emailSummaries.resolutionRevision(self),
                         acknowledgements: self.reviewAcknowledgements(),
                         whatsappScope: self.whatsapp.scope(for: self.chatGPT.activeID), weatherScope: self.weather.scope)
            }
        }, sourceSnapshot: { [weak self] in
            guard let self else { return nil }
            return assistant.snapshot(self)
        }, deliveryAvailable: { [weak self] turn in
            guard let self else { return false }
            guard let delivery = turn.deliveryID else { return true }
            if delivery.hasPrefix("discovery:") {
                guard let record = proactive.record(delivery: delivery, model: self), proactive.visible(record, model: self) else { return false }
                let reviewText=(record.sourceTitle.map{$0+"\n"} ?? "")+record.message
                guard turn.content == record.message || turn.content == reviewText else {return false}
            } else if delivery.hasPrefix("learn-question:") {
                guard let record = memoryLearning.question(delivery: delivery, registration: chatGPT.activeID), memoryLearning.visible(record, assistant: assistant) else { return false }
            } else if delivery.contains(":morning:"), !briefings.allowsChatDelivery(delivery, content: turn.content, model: self) { return false }
            return true
        }, tools: { [self] request in
            PAToolSession(model: self, human: request.human, humanContext: request.humanContext,
                          topicID: request.topicID, turnID: request.turnID, mail: request.mail as? MailLookup,
                          history: request.history, focusAreas: request.focusAreas)
        }, afterTurn: { [weak self] in
            guard let self else { return }
            if !reviewWork.busy {projectPlacement.check(self)}
        },started:{ [weak self] in self?.assistantActivityStarted($0) },working:{ [weak self] in self?.assistantActivityStarted($0) },finished:{ [weak self] in self?.assistantActivityFinished($0) })
    }
}
