import Foundation
import Observation

struct ReviewFeedbackJob:Codable,Identifiable,Equatable {
    enum State:String,Codable {case queued,learning,saving,saved,failed,stopped,interrupted}
    var id=UUID()
    var memoryID=UUID()
    var registration:String
    var messageID:String
    var accountID:String
    var headerFingerprint:String
    var bodyFingerprint:String
    var assessmentVersion:String
    var model:String
    var sourceRevision:Int
    var words:String
    var about:String
    var created=Date.now
    var state=State.queued
    var error:String?
    var pending:Bool {state == .queued || state == .learning || state == .saving}
    var status:String {
        switch state {
        case .queued:"Feedback queued"
        case .learning,.saving:"Learning your preference…"
        case .saved:"Preference saved"
        case .failed:"Feedback needs attention"
        case .stopped:"Feedback stopped"
        case .interrupted:"Feedback interrupted"
        }
    }
}

/// Explicit submissions only. Navigation never owns or cancels these tasks.
/// Retained jobs are not recall facts and never replay after reopening.
@MainActor @Observable final class ReviewFeedbackJobs {
    private(set) var records:[ReviewFeedbackJob]=[]
    private(set) var readable=true
    var error:String?
    @ObservationIgnored private let persist:([ReviewFeedbackJob])throws->Void
    @ObservationIgnored private var task:Task<Void,Never>?
    @ObservationIgnored private var operation:Task<ReviewFeedbackInterpretation,Error>?
    @ObservationIgnored private var restart:(()->Void)?
    private(set) var activeID:UUID?

    init(load:()throws->[ReviewFeedbackJob],persist:@escaping ([ReviewFeedbackJob])throws->Void) {
        self.persist=persist
        do {
            let saved=try load()
            guard Set(saved.map(\.id)).count == saved.count,Set(saved.map(\.memoryID)).count == saved.count else {throw ReviewFeedbackFailure.message("Invalid feedback identities")}
            records=saved.map {value in
                var job=value
                if job.pending {job.state = .interrupted;job.error="The app closed before feedback finished. Your words are retained; retry when ready."}
                return job
            }
            if records != saved {try persist(records)}
        } catch {readable=false;self.error="Saved feedback is unavailable. Its storage is preserved; new submissions are disabled."}
    }
    func items(_ registration:String)->[ReviewFeedbackJob] {records.filter{$0.registration == registration}.sorted{$0.created > $1.created}}
    func latest(_ registration:String,messageID:String)->ReviewFeedbackJob? {items(registration).first{$0.messageID == messageID}}
    @discardableResult func submit(_ job:ReviewFeedbackJob)->Bool {
        guard readable,!job.words.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,job.words.count <= 2000,job.about.count <= 300,!job.registration.isEmpty,!job.messageID.isEmpty,!records.contains(where:{$0.id == job.id || $0.memoryID == job.memoryID || ($0.registration == job.registration && $0.messageID == job.messageID && $0.pending)}) else {error="Check your feedback or wait for its existing submission.";return false}
        return change { $0.append(job) }
    }
    @discardableResult func replaceForRetry(_ job:ReviewFeedbackJob)->Bool {
        guard readable,activeID != job.id,let previous=records.first(where:{$0.id == job.id}),!previous.pending,previous.state != .saved,previous.memoryID == job.memoryID,previous.registration == job.registration,previous.words == job.words,previous.about == job.about else {return false}
        return update(job.id) {$0=job}
    }
    func stop(_ id:UUID) {
        guard records.first(where:{$0.id == id})?.pending == true else {return}
        if activeID == id {operation?.cancel()}
        _=update(id) {$0.state = .stopped;$0.error="Stopped. Your feedback is retained; no new preference will be saved."}
    }
    func interruptActive() {
        task?.cancel();operation?.cancel()
        guard records.contains(where:{$0.pending}) else {return}
        // Capture cancellation now. Later human submissions belong to a fresh owner.
        if !change({values in
            for i in values.indices where values[i].pending {
                values[i].state = values[i].id == activeID ? .stopped : .interrupted
                values[i].error="Foreground work interrupted feedback. Your words are retained; retry when ready."
            }
        }) {readable=false}
    }
    @discardableResult func markSaved(_ id:UUID)->Bool {update(id) {$0.state = .saved;$0.error=nil}}
    /// The owner supplies exact source/ownership guards and the bounded inference.
    /// The commit is synchronous: cancellation cannot cross a save boundary.
    func start(validate:@escaping (ReviewFeedbackJob)->Bool,ready:@escaping ()->Bool,prepare:@escaping (ReviewFeedbackJob)async throws->ReviewFeedbackInterpretation,commit:@escaping (ReviewFeedbackJob,ReviewFeedbackInterpretation)throws->Void,alreadySaved:@escaping (ReviewFeedbackJob)->Bool) {
        guard readable,records.contains(where:{$0.state == .queued}) else {return}
        if task != nil {
            restart={ [weak self] in self?.start(validate:validate,ready:ready,prepare:prepare,commit:commit,alreadySaved:alreadySaved) }
            return
        }
        task=Task { @MainActor in
            defer {
                self.task=nil;self.operation=nil;self.activeID=nil
                let restart=self.restart;self.restart=nil
                if self.readable,self.records.contains(where:{$0.state == .queued}) {restart?()}
            }
            while let job=self.records.first(where:{$0.state == .queued}) {
                self.activeID=job.id
                do {
                    while !ready() {
                        try Task.checkCancellation()
                        guard self.records.first(where:{$0.id == job.id})?.state == .queued else {throw CancellationError()}
                        guard validate(job) else {throw ReviewFeedbackFailure.message("The email, account or settings changed. Your feedback is retained; reopen it before retrying.")}
                        try await Task.sleep(for:.milliseconds(500))
                    }
                    try Task.checkCancellation()
                    guard self.records.first(where:{$0.id == job.id})?.state == .queued else {throw CancellationError()}
                    guard validate(job) else {throw ReviewFeedbackFailure.message("The email, account or settings changed. Your feedback is retained; reopen it before retrying.")}
                    if alreadySaved(job) {guard self.markSaved(job.id) else {return};continue}
                    guard self.update(job.id,{$0.state = .learning;$0.error=nil}) else {return}
                    let operation=Task {let result=try await prepare(job);try Task.checkCancellation();return result}
                    self.operation=operation
                    let interpretation=try await withTaskCancellationHandler(operation:{try await operation.value},onCancel:{operation.cancel()})
                    self.operation=nil
                    try Task.checkCancellation()
                    guard validate(job),self.records.first(where:{$0.id == job.id})?.state == .learning else {throw ReviewFeedbackFailure.message("The email, account or settings changed. No preference was saved; your feedback is retained.")}
                    guard self.update(job.id,{$0.state = .saving}) else {return}
                    try commit(job,interpretation)
                    // A failed receipt save cannot cause the same memory to be saved twice.
                    guard self.markSaved(job.id) else {return}
                } catch {
                    self.operation=nil
                    if self.records.first(where:{$0.id == job.id})?.state != .stopped {
                        guard self.update(job.id,{$0.state = error is CancellationError ? .stopped : .failed;$0.error=error is CancellationError ? "Interrupted by foreground work. Your feedback is retained; retry when ready." : error.localizedDescription}) else {return}
                    }
                    // Other explicit submissions remain queued; never retry this one.
                    if Task.isCancelled {return}
                }
            }
        }
    }
    @discardableResult private func update(_ id:UUID,_ mutation:(inout ReviewFeedbackJob)->Void)->Bool {
        change {values in if let i=values.firstIndex(where:{$0.id == id}) {mutation(&values[i])}}
    }
    private func change(_ mutation:(inout [ReviewFeedbackJob])->Void)->Bool {
        guard readable else {return false}
        var next=records;mutation(&next)
        do {try persist(next);records=next;error=nil;return true}
        catch {self.error="Feedback progress could not be saved. Your retained feedback has not been discarded.";return false}
    }
}
