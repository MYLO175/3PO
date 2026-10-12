import Foundation

extension EmailSummaryService {
    @discardableResult func submitReviewFeedback(_ source:ReviewFeedbackEmail,words:String,about:String,model:DashboardModel)->Bool {
        guard feedbackSourceCurrent(source.message,summary:source.summary,model:model),model.assistant.memory.canSaveReviewPreference,let body=source.summary.bodyFingerprint else {feedback.error="The email or account changed. Your words are still here; reopen Feedback before saving.";return false}
        let job=ReviewFeedbackJob(registration:model.chatGPT.activeID,messageID:source.message.id,accountID:source.message.accountID,headerFingerprint:source.summary.fingerprint,bodyFingerprint:body,assessmentVersion:ReviewAcknowledgementRules.emailVersion(source.message,source.summary),model:model.chatGPT.selectedModel,sourceRevision:model.sourceRevision,words:words,about:about)
        if let previous=feedback.latest(job.registration,messageID:job.messageID),previous.pending,feedbackMemory(previous,model:model) != nil {guard feedback.markSaved(previous.id) else {return false}}
        guard feedback.submit(job) else {return false}
        runFeedback(model)
        return true
    }
    private func feedbackSource(_ job:ReviewFeedbackJob,model:DashboardModel)->ReviewFeedbackEmail? {
        guard job.registration == model.chatGPT.activeID,job.model == model.chatGPT.selectedModel,job.sourceRevision == model.sourceRevision,let message=model.mailData.messages.first(where:{$0.id == job.messageID && $0.accountID == job.accountID}),let summary=current(message,model:model),summary.fingerprint == job.headerFingerprint,summary.bodyFingerprint == job.bodyFingerprint,ReviewAcknowledgementRules.emailVersion(message,summary) == job.assessmentVersion,feedbackSourceCurrent(message,summary:summary,model:model) else {return nil}
        return .init(message:message,summary:summary)
    }
    func feedbackMemory(_ job:ReviewFeedbackJob,model:DashboardModel)->PAMemory? {
        guard job.registration == model.chatGPT.activeID else {return nil}
        return model.assistant.memory.records.first{$0.id == job.memoryID && $0.registration == job.registration && $0.reviewPreference == true && $0.reviewFeedback == job.words.trimmingCharacters(in:.whitespacesAndNewlines)}
    }
    @discardableResult func retryFeedback(_ job:ReviewFeedbackJob,model:DashboardModel)->Bool {
        guard feedback.activeID != job.id,feedback.records.first(where:{$0.id == job.id}) == job,job.registration == model.chatGPT.activeID,!job.pending else {return false}
        if feedbackMemory(job,model:model) != nil {return feedback.markSaved(job.id)}
        var retry=job;retry.model=model.chatGPT.selectedModel;retry.sourceRevision=model.sourceRevision;retry.state = .queued;retry.error=nil
        guard feedbackSource(retry,model:model) != nil else {feedback.error="This email changed or is unavailable. Your feedback is retained; submit new feedback from its current review.";return false}
        guard feedback.replaceForRetry(retry) else {return false}
        runFeedback(model)
        return true
    }
    @discardableResult func saveFeedbackWords(_ job:ReviewFeedbackJob,model:DashboardModel)->Bool {
        guard feedback.activeID != job.id,feedback.records.first(where:{$0.id == job.id}) == job,job.registration == model.chatGPT.activeID,!job.pending,job.state != .saved else {return false}
        if feedbackMemory(job,model:model) != nil {return feedback.markSaved(job.id)}
        guard model.assistant.memory.saveReviewPreference(job.words,registration:job.registration,about:job.about,id:job.memoryID) else {feedback.error=model.assistant.memory.error;return false}
        return feedback.markSaved(job.id)
    }
    private func runFeedback(_ model:DashboardModel) {
        var completionGuard:(id:UUID,memory:UUID,generation:Int)?
        feedback.start(validate:{job in self.feedbackSource(job,model:model) != nil},ready:{
            model.heartbeat.deviceAvailable && !self.busy && !model.chatGPT.busy && !model.assistant.busy && !model.writing && !model.heartbeat.busy && !model.proactive.busy && !model.briefings.busy && !model.memoryLearning.busy && !model.sourceLearning.busy && !model.nativeSourceLearning.busy && !model.memoryMaintenance.busy && !model.projectPlacement.busy && !model.lifeOrganisation.busy
        },prepare:{job in
            guard let source=self.feedbackSource(job,model:model) else {throw ReviewFeedbackFailure.message("The email changed. Your feedback is retained.")}
            completionGuard=(job.id,model.assistant.memory.revision,self.reviewFeedbackGeneration)
            return try await self.interpretReviewFeedback(source,words:job.words,about:job.about,model:model,isCurrent:{self.feedbackSource(job,model:model) != nil})
        },commit:{job,interpretation in
            #if DEBUG
            let fictional=ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") && ProcessInfo.processInfo.arguments.contains("--feedback-preview")
            #else
            let fictional=false
            #endif
            guard completionGuard?.id == job.id,completionGuard?.memory == model.assistant.memory.revision,completionGuard?.generation == self.reviewFeedbackGeneration,!model.assistant.busy,!model.writing,model.heartbeat.deviceAvailable,(fictional || model.chatGPT.inferenceVerified),!model.chatGPT.usagePaused else {throw ReviewFeedbackFailure.message("Foreground work or memory changed. No preference was saved; your feedback is retained.")}
            guard model.assistant.memory.saveReviewPreference(job.words,registration:job.registration,about:job.about,interpretation:interpretation,id:job.memoryID) else {throw ReviewFeedbackFailure.message(model.assistant.memory.error ?? "The preference could not be saved. Your feedback is retained.")}
            guard self.feedbackMemory(job,model:model)?.reviewInterpretation == interpretation else {throw ReviewFeedbackFailure.message("The saved preference could not be verified. Inspect memory before retrying.")}
        },alreadySaved:{job in self.feedbackMemory(job,model:model) != nil})
    }
}
