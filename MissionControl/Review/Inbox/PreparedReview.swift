import Foundation
import Observation

/// Saved presentation is separate from evidence used to generate new AI advice.
/// These checks use only ownership and explicit access choices, never content revisions.
struct PreparedReviewAccess {
    var registration:String
    var enabled:Bool
    var mailEnabled:Bool
    var mailAccounts:Set<String>
    var excludedMail:Set<String>
    var mailAccountByMessage:[String:String]
    var acknowledgedMail:Set<String>
    var whatsappEnabled:Bool
    var whatsappIdentity:String
    var whatsappChats:Set<String>
    @MainActor init(_ model:DashboardModel) {
        registration=model.inference.activeID;enabled=model.assistant.contextEnabled
        mailEnabled=model.emailSummaries.enabled
        mailAccounts=Set(model.mailData.accounts.map(\.id));excludedMail=model.assistant.excludedAccounts
        mailAccountByMessage=[:];acknowledgedMail=[]
        for summary in model.emailSummaries.records where summary.registration == registration {
            if summary.dismissed == true {acknowledgedMail.insert(summary.id)}
            if let message=summary.message {mailAccountByMessage[summary.id]=message.accountID}
        }
        for message in model.mailData.messages where mailAccountByMessage[message.id] == nil {mailAccountByMessage[message.id]=message.accountID}
        let access=model.whatsapp.access(for:registration)
        whatsappEnabled=access.enabled && access.includeInSuggestions == true
        whatsappIdentity=model.whatsapp.linkedIdentity;whatsappChats=Set(access.chats)
    }
    func permits(_ record:PADiscovery)->Bool {
        guard enabled,record.registration == registration else {return false}
        if record.sourceKind == "whatsapp" {
            return whatsappEnabled && record.sourceIdentity == whatsappIdentity && record.sourceChatID.map{whatsappChats.contains($0)} == true
        }
        return mailEnabled && !acknowledgedMail.contains(record.mailID) && mailAccountByMessage[record.mailID].map{mailAccounts.contains($0) && !excludedMail.contains($0)} == true
    }
}

@MainActor extension ProactiveService {
    func preparedReviewAvailable(_ record:PADiscovery,model:DashboardModel,access:PreparedReviewAccess? = nil)->Bool {
        !record.dismissed && record.reviewState != "approved" && record.supersededBy == nil && record.retiredAt == nil && (access ?? PreparedReviewAccess(model)).permits(record)
    }
}

/// Every observed dependency is main-actor owned. Invalidate synchronously on
/// mutation, so account/permission changes can never return an earlier snapshot.
/// Native freshness and memory revisions are deliberately not dependencies.
@MainActor @Observable final class PreparedReviewStore {
    @ObservationIgnored private var cached:ReviewInboxProjection?
    private(set) var revision=0
    #if DEBUG
    @ObservationIgnored private(set) var builds=0
    #endif
    func value(_ model:DashboardModel)->ReviewInboxProjection {
        _=revision
        if let cached {return cached}
        let value=withObservationTracking {model.buildPreparedReview()} onChange: { [weak self] in
            MainActor.assumeIsolated {self?.cached=nil;self?.revision += 1}
        }
        cached=value
        scheduleExpiry(value.expiresAt)
        #if DEBUG
        builds += 1
        #endif
        return value
    }
    /// One local wakeup when the next reading card's week ends. No source read or inference.
    @ObservationIgnored private var expiry:Task<Void,Never>?
    private func scheduleExpiry(_ date:Date?) {
        expiry?.cancel();expiry=nil
        guard let date else {return}
        expiry=Task { @MainActor [weak self] in
            try? await Task.sleep(for:.seconds(max(1,date.timeIntervalSinceNow)))
            guard !Task.isCancelled,let self else {return}
            self.cached=nil;self.revision += 1
        }
    }
}

@MainActor extension DashboardModel {
    func buildPreparedReview(now:Date = .now)->ReviewInboxProjection {
        let owner=inference.activeID,access=PreparedReviewAccess(self)
        let questions=briefings.preparedQuestions(self)
        let learning=(memoryLearning.state.questions ?? []).filter{memoryLearning.visible($0,assistant:assistant)}
        let projectQuestions = visibleContextProjectQuestions()
        let currentMessages=Dictionary(mailData.messages.map{($0.id,$0)},uniquingKeysWith:{first,_ in first})
        let saved:[(MailMessage,EmailSummary)]=emailSummaries.records.compactMap {summary in
            guard access.enabled,access.mailEnabled,summary.registration == owner,
                  let message=summary.message ?? currentMessages[summary.id],access.mailAccounts.contains(message.accountID),!access.excludedMail.contains(message.accountID) else {return nil}
            return (message,summary)
        }
        let highlights=saved.filter{$0.1.dismissed != true && ($0.1.attention || $0.1.followUpDate != nil || $0.1.worthReading == true || $0.1.keepInReview == true)}.sorted {
            let a=EmailHighlightRules.rank($0.1,replied:$0.0.replied),b=EmailHighlightRules.rank($1.1,replied:$1.0.replied)
            return a != b ? a < b : $0.0.received != $1.0.received ? $0.0.received > $1.0.received : $0.0.id < $1.0.id
        }
        func handled(_ summary:EmailSummary)->EmailHandling? {summary.keepInReview == true ? nil : summary.handling}
        func resolved(_ summary:EmailSummary)->EmailResolution? {summary.keepInReview == true ? nil : summary.resolution}
        let admitted=Set(highlights.filter{EmailHighlightRules.needsReview($0.1,replied:$0.0.replied,now:now)}.map{$0.0.id})
        // Mail suggestions follow their email's current verdict and stay saved while hidden.
        // Proposed changes to an existing Calendar or Reminders item always concern the human.
        let discoveries=proactive.state.records.filter{!reviewDiscoveryCompleted($0) && proactive.preparedReviewAvailable($0,model:self,access:access) && ($0.sourceKind == "whatsapp" || $0.nativeTarget != nil || admitted.contains($0.mailID))}.map(ProactiveRules.reviewProjection)
        let emails=highlights.filter{admitted.contains($0.0.id) && handled($0.1) == nil && resolved($0.1) == nil}
        let actionable=Set(emails.map{$0.0.id})
        let grouped=Dictionary(grouping:discoveries.filter{$0.sourceKind != "whatsapp"},by:{$0.mailID})
        var attachedIDs=Set<String>()
        let cards=highlights.compactMap {message,summary -> ReviewInboxEmailCard? in
            let attached=grouped[message.id] ?? []
            guard actionable.contains(message.id) || !attached.isEmpty else {return nil}
            attachedIDs.formUnion(attached.map(\.id))
            return .init(message:message,summary:summary,discoveries:attached,handling:handled(summary),needsReview:true)
        }
        let standalone=discoveries.filter{!attachedIDs.contains($0.id)}
        let cardIDs=Set(cards.map(\.id))
        let history=saved.compactMap {message,summary in !cardIDs.contains(message.id) ? handled(summary).map{(message,summary,$0)} : nil}
        let resolutions=saved.compactMap {message,summary in !cardIDs.contains(message.id) ? resolved(summary).map{(message,summary,$0)} : nil}
        let pending=PAQueueRules.handoffs(assistant.queue.items,registration:owner)
        let count=questions.count+learning.count+projectQuestions.count+standalone.count+cards.count+pending.filter{$0.state == .needsAnswer || $0.state == .interrupted}.count
        let expiresAt=highlights.filter{EmailHighlightRules.readingAdmitted($0.1,now:now)}.map{EmailHighlightRules.readingExpiry($0.1)}.min()
        return .init(questions:questions,learningQuestions:learning,discoveries:discoveries,emails:emails,highlights:highlights,emailCards:cards,standaloneDiscoveries:standalone,handled:history,resolved:resolutions,pending:pending,pendingCount:count,contextQuestions:projectQuestions,expiresAt:expiresAt)
    }
}

@MainActor extension DashboardModel {
    func preparedFeedbackEmail(_ record:PADiscovery)->ReviewFeedbackEmail? {
        guard record.sourceKind != "whatsapp",let pair=reviewInbox.highlights.first(where:{$0.0.id == record.mailID && $0.1.registration == record.registration}) else {return nil}
        return .init(message:pair.0,summary:pair.1)
    }
    func preparedSourceDetails(_ record:PADiscovery)->ReviewSourceDetails? {
        if let email=preparedFeedbackEmail(record) {return .email(email.message)}
        return nil
    }
}
