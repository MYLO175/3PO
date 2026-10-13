import Foundation
import Observation

enum ReviewWorkPhase:String,Codable {case queued,running,completed,partial,failed,uncertain,needsAnswer,stopped,interrupted}
enum ReviewWorkMode:String,Codable {case approval,conversation}
enum ReviewActionPhase:String,Codable {case waiting,working,saved,failed,uncertain}
struct ReviewWorkSource:Codable,Equatable {
    var key:String
    var title:String
    var kind:String
    var accountID:String?
    var messageID:String?
    var identity:String?
    var chatID:String?
}
struct ReviewWorkScope:Codable,Equatable {
    var registration:String
    var model:String
    var sourceChoices:String
    var storage:String
}
struct ReviewWorkAction:Codable,Identifiable,Equatable {
    var id:String
    var title:String
    var destination:String
    /// Typed concrete payload is encoded by the desktop adapter. The queue never
    /// interprets source prose or manufactures an operation from a title.
    var coalescingKey:String?
    var payload:Data
    var phase:ReviewActionPhase = .waiting
    var result:String?
    var itemID:String?
    var location:String?
}
struct ReviewWorkJob:Codable,Identifiable,Equatable {
    var id=UUID()
    var humanTurnID=UUID()
    var responseTurnID=UUID()
    var conversationID:UUID
    var scope:ReviewWorkScope
    var source:ReviewWorkSource
    var mode:ReviewWorkMode
    var human:String
    var humanControl:Bool?
    var selectionActive:Bool?
    var focusAreas:[String]=[]
    var actions:[ReviewWorkAction]=[]
    var phase:ReviewWorkPhase = .queued
    var created=Date.now
    var finished:Date?
    var message:String?
    var error:String?
    var conversationActionCount:Int?
    var savedCount:Int {mode == .approval ? actions.filter{$0.phase == .saved}.count : conversationActionCount ?? 0}
    var pending:Bool {phase == .queued || phase == .running}
}
struct ReviewWorkState:Codable,Equatable {
    var version=1
    var jobs:[ReviewWorkJob]=[]
    var paused:[String:Bool]=[:]
    var drafts:[String:String]=[:]
}
struct ReviewWorkActionResult {
    var phase:ReviewActionPhase
    var message:String
    var itemID:String?
    var location:String?
}
struct ReviewWorkConversationResult {
    var phase:ReviewWorkPhase
    var message:String
    var confirmedActions:Int=0
    var error:String?
}
@MainActor struct ReviewWorkRuntime {
    var scope:()->ReviewWorkScope
    var ready:()->Bool
    var permits:(ReviewWorkSource)->Bool
    var perform:(ReviewWorkJob,ReviewWorkAction,@escaping @MainActor ()->Bool) async throws->ReviewWorkActionResult
    /// Local canonical receipts only; no new inference or native save.
    var inspect:(ReviewWorkJob,ReviewWorkAction)->ReviewWorkActionResult?
    var converse:(ReviewWorkJob,@escaping @MainActor ()->Bool) async->ReviewWorkConversationResult
    var cancelConversation:()->Void
    var changed:(ReviewWorkJob)->Void
}
@MainActor @Observable final class ReviewWorkService {
    private(set) var state=ReviewWorkState()
    private(set) var readable=true
    private(set) var activeID:UUID?
    var error:String?
    @ObservationIgnored private var task:Task<Void,Never>?
    @ObservationIgnored private var activeRuntime:ReviewWorkRuntime?
    @ObservationIgnored private let persist:(Data)throws->Void
    var busy:Bool {activeID != nil}
    init(load:()throws->Data?,persist:@escaping (Data)throws->Void) {
        self.persist=persist
        do {
            guard let bytes=try load() else {return}
            try Self.validateSchema(bytes)
            var value=try JSONDecoder().decode(ReviewWorkState.self,from:bytes)
            guard value.version == 1,Set(value.jobs.map(\.id)).count == value.jobs.count,
                  Set(value.jobs.map(\.humanTurnID)).count == value.jobs.count,
                  value.jobs.allSatisfy({!$0.scope.registration.isEmpty && Set($0.actions.map(\.id)).count == $0.actions.count}) else {throw CocoaError(.fileReadCorruptFile)}
            for index in value.jobs.indices where value.jobs[index].phase == .running {
                value.jobs[index].phase = .interrupted
                value.jobs[index].error="The app closed during this request. Completed receipts are kept; it will not run again automatically."
                value.paused[value.jobs[index].scope.registration]=true
                for action in value.jobs[index].actions.indices where value.jobs[index].actions[action].phase == .working {
                    value.jobs[index].actions[action].phase = .uncertain
                }
            }
            state=value
            if value != (try JSONDecoder().decode(ReviewWorkState.self,from:bytes)) {try persist(Self.encode(value))}
        } catch {readable=false;self.error="Saved Review work is unavailable. Its original storage is preserved; new requests are disabled."}
    }
    /// A future schema is retained verbatim rather than losing unrecognised fields.
    private static func validateSchema(_ bytes:Data)throws {
        guard let root=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],Set(root.keys).isSubset(of:["version","jobs","paused","drafts"]),let jobs=root["jobs"] as? [[String:Any]] else {throw CocoaError(.fileReadCorruptFile)}
        for job in jobs {
            guard Set(job.keys).isSubset(of:["id","humanTurnID","responseTurnID","conversationID","scope","source","mode","human","humanControl","selectionActive","focusAreas","actions","phase","created","finished","message","error","conversationActionCount"]),let scope=job["scope"] as? [String:Any],Set(scope.keys).isSubset(of:["registration","model","sourceChoices","storage"]),let source=job["source"] as? [String:Any],Set(source.keys).isSubset(of:["key","title","kind","accountID","messageID","identity","chatID"]),let actions=job["actions"] as? [[String:Any]],actions.allSatisfy({Set($0.keys).isSubset(of:["id","title","destination","payload","phase","result","itemID","location","coalescingKey"])}) else {throw CocoaError(.fileReadCorruptFile)}
        }
    }
    private static func encode(_ value:ReviewWorkState)throws->Data {let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];return try encoder.encode(value)}
    func jobs(_ registration:String,conversation:UUID?=nil)->[ReviewWorkJob] {state.jobs.filter{$0.scope.registration == registration && (conversation == nil || $0.conversationID == conversation)}.sorted{$0.created < $1.created}}
    func job(_ id:UUID)->ReviewWorkJob? {state.jobs.first{$0.id == id}}
    func waiting(_ registration:String)->Int {state.jobs.filter{$0.scope.registration == registration && $0.phase == .queued}.count}
    func isPaused(_ registration:String)->Bool {state.paused[registration] == true}
    func draft(_ registration:String,conversation:UUID)->String {state.drafts[registration+":"+conversation.uuidString] ?? ""}
    func setDraft(_ text:String,registration:String,conversation:UUID) {_=change{$0.drafts[registration+":"+conversation.uuidString]=String(text.prefix(24_000))}}
    @discardableResult func submit(_ job:ReviewWorkJob)->Bool {
        guard readable,job.phase == .queued,!job.scope.registration.isEmpty,!job.human.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,job.human.count <= 24_000,!state.jobs.contains(where:{$0.id == job.id || $0.humanTurnID == job.humanTurnID}) else {error="Check this reply before submitting. Your draft is retained.";return false}
        if job.mode == .approval {
            guard !job.actions.isEmpty,job.actions.allSatisfy({$0.phase == .waiting && $0.result == nil && $0.itemID == nil}),Set(job.actions.map(\.id)).count == job.actions.count else {error="Choose at least one concrete action.";return false}
            if state.jobs.contains(where:{$0.scope.registration == job.scope.registration && $0.pending && $0.actions.sorted{$0.id < $1.id}.map{$0.coalescingKey ?? $0.payload.base64EncodedString()} == job.actions.sorted{$0.id < $1.id}.map{$0.coalescingKey ?? $0.payload.base64EncodedString()}}) {error="This exact plan is already queued; its existing request is retained.";return false}
        }
        return change {value in value.jobs.append(job);value.drafts[job.scope.registration+":"+job.conversationID.uuidString]=""}
    }
    private func matchesScope(_ job:ReviewWorkJob,_ scope:ReviewWorkScope)->Bool {
        if job.mode == .approval {return job.scope.registration == scope.registration && job.scope.storage == scope.storage}
        return job.scope == scope
    }
    func drive(_ runtime:ReviewWorkRuntime) {
        guard readable,task == nil,activeID == nil,runtime.ready() else {return}
        let scope=runtime.scope()
        guard !isPaused(scope.registration),let job=state.jobs.first(where:{$0.scope.registration == scope.registration && $0.phase == .queued}) else {return}
        guard matchesScope(job,scope),runtime.permits(job.source) else {
            _=update(job.id){$0.phase = .failed;$0.error="The account, model, source choices or storage changed. Reopen this Review conversation before continuing.";$0.finished = .now}
            pause(scope.registration);if let value=self.job(job.id) {runtime.changed(value)};return
        }
        guard update(job.id,{$0.phase = .running;$0.error=nil;$0.finished=nil}) else {return}
        activeID=job.id;activeRuntime=runtime
        if let value=self.job(job.id) {runtime.changed(value)}
        task=Task { @MainActor [self] in
            defer {
                self.task=nil;self.activeID=nil;self.activeRuntime=nil
                if var final=self.job(job.id) {
                    if !self.readable {final.phase = .failed;final.error=self.error;final.message="Review progress could not be saved. Check completed receipts before continuing."}
                    runtime.changed(final)
                }
            }
            let valid: @MainActor ()->Bool = { [weak self] in
                guard let self else {return false}
                return self.readable && !Task.isCancelled && self.activeID == job.id && self.job(job.id)?.phase == .running && self.matchesScope(job,runtime.scope()) && runtime.permits(job.source)
            }
            if job.mode == .conversation {
                guard valid() else {return}
                let result=await runtime.converse(job,valid)
                guard self.readable else {return}
                if self.job(job.id)?.phase == .stopped {
                    _=self.update(job.id){$0.conversationActionCount=result.confirmedActions};return
                }
                guard valid() else {
                    _=self.update(job.id){$0.phase = .failed;$0.message="The request stopped because its account, settings or source access changed.";$0.error=$0.message;$0.conversationActionCount=result.confirmedActions;$0.finished = .now};self.pause(job.scope.registration);return
                }
                let terminal:ReviewWorkPhase = [.completed,.partial,.failed,.uncertain,.needsAnswer,.stopped,.interrupted].contains(result.phase) ? result.phase : .failed
                _=self.update(job.id){$0.phase=terminal;$0.message=terminal == result.phase ? result.message : "The assistant returned an invalid completion state. It will not be replayed.";$0.error=result.error;$0.conversationActionCount=result.confirmedActions;$0.finished = .now}
            } else {
                for original in job.actions {
                    guard valid() else {break}
                    if self.job(job.id)?.actions.first(where:{$0.id == original.id})?.phase == .saved {continue}
                    if let receipt=runtime.inspect(job,original) {
                        self.record(job.id,action:original.id,result:receipt)
                        if receipt.phase != .saved {break}
                        continue
                    }
                    guard self.updateAction(job.id,original.id,{$0.phase = .working}) else {break}
                    do {
                        let returned=try await runtime.perform(job,original,valid)
                        let result:ReviewWorkActionResult
                        if valid() {result=returned}
                        else {result=runtime.inspect(job,original) ?? .init(phase:.failed,message:"The request’s ownership or source access changed; no late result was accepted.")}
                        self.record(job.id,action:original.id,result:result)
                        if result.phase != .saved || !valid() {break}
                    } catch {
                        let receipt=runtime.inspect(job,original) ?? .init(phase:.failed,message:error is CancellationError ? "Stopped before a confirmed save." : error.localizedDescription)
                        self.record(job.id,action:original.id,result:receipt)
                        break
                    }
                    if let value=self.job(job.id) {runtime.changed(value)}
                }
                if let current=self.job(job.id),current.phase == .running {
                    let uncertain=current.actions.contains{$0.phase == .uncertain}
                    let all=current.actions.allSatisfy{$0.phase == .saved}
                    let result:ReviewWorkPhase=all ? .completed : uncertain ? .uncertain : current.savedCount > 0 ? .partial : .failed
                    let failed=current.actions.first{$0.phase == .failed || $0.phase == .uncertain}
                    let detail=failed.map{$0.title+": "+($0.result ?? "This action did not finish.")}
                    _=self.update(job.id){$0.phase=result;$0.message=all ? "\($0.savedCount) actions completed" : "\($0.savedCount) of \($0.actions.count) actions confirmed";$0.error=all ? nil : detail ?? "Remaining work stopped. Reopen this plan before continuing.";$0.finished = .now}
                }
            }
            if let final=self.job(job.id) {
                if final.phase != .completed {self.pause(final.scope.registration)}
            }
        }
    }
    private func record(_ job:UUID,action:String,result:ReviewWorkActionResult) {
        _=updateAction(job,action){$0.phase=result.phase;$0.result=result.message;$0.itemID=result.itemID;$0.location=result.location}
    }
    func stop(_ id:UUID) {
        guard let job=job(id),job.pending else {return}
        if activeID == id {task?.cancel();if job.mode == .conversation {activeRuntime?.cancelConversation()}}
        _=update(id){$0.phase = .stopped;$0.error="Stopped. Confirmed actions are retained; remaining work is paused.";$0.finished = .now}
        pause(job.scope.registration)
        if let value=self.job(id) {activeRuntime?.changed(value)}
    }
    func interruptForForeground(_ registration:String) {
        guard waiting(registration)>0 || activeID.flatMap(job).map({$0.scope.registration == registration}) == true else {return}
        pause(registration);if let id=activeID,job(id)?.scope.registration == registration {stop(id)}
    }
    func continueWaiting(_ registration:String) {_=change{$0.paused[registration]=false}}
    /// Explicit inspection reconciles canonical local receipts; it never performs an operation.
    @discardableResult func reconcile(_ id:UUID,runtime:ReviewWorkRuntime)->Bool {
        guard let original=job(id),!original.pending,original.mode == .approval,original.scope.registration == runtime.scope().registration,original.scope.storage == runtime.scope().storage,runtime.permits(original.source) else {return false}
        for action in original.actions where action.phase != .saved {
            if let result=runtime.inspect(original,action) {record(id,action:action.id,result:result)}
        }
        guard let current=job(id) else {return false}
        if current.actions.allSatisfy({$0.phase == .saved}),current.phase != .stopped {
            _=update(id){$0.phase = .completed;$0.message="\($0.savedCount) actions completed";$0.error=nil;$0.finished = .now}
        }
        if let value=job(id) {runtime.changed(value)}
        return true
    }
    func retry(_ id:UUID)->Bool {
        guard activeID != id,let job=job(id),!job.pending,job.phase != .completed,job.phase != .uncertain,!job.actions.contains(where:{$0.phase == .uncertain || $0.phase == .working}) else {return false}
        return change {value in
            guard let index=value.jobs.firstIndex(where:{$0.id == id}) else {return}
            value.jobs[index].phase = .queued;value.jobs[index].error=nil;value.jobs[index].finished=nil
            value.jobs[index].responseTurnID=UUID()
            for action in value.jobs[index].actions.indices where value.jobs[index].actions[action].phase != .saved {value.jobs[index].actions[action].phase = .waiting}
            value.paused[job.scope.registration]=false
        }
    }
    private func pause(_ registration:String) {_=change{$0.paused[registration]=true}}
    @discardableResult private func update(_ id:UUID,_ mutation:(inout ReviewWorkJob)->Void)->Bool {change {value in if let index=value.jobs.firstIndex(where:{$0.id == id}) {mutation(&value.jobs[index])}}}
    @discardableResult private func updateAction(_ id:UUID,_ action:String,_ mutation:(inout ReviewWorkAction)->Void)->Bool {update(id){job in if let index=job.actions.firstIndex(where:{$0.id == action}) {mutation(&job.actions[index])}}}
    private func change(_ mutation:(inout ReviewWorkState)->Void)->Bool {
        guard readable else {return false}
        var next=state;mutation(&next)
        do {try persist(Self.encode(next));state=next;error=nil;return true}
        catch {readable=false;self.error="Review progress could not be saved. Your retained request and receipts are preserved; remaining work is stopped.";return false}
    }
}
