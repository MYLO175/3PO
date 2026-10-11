import Foundation
import SwiftData

@MainActor private final class FictionalHeartbeatWorld {
    var now=ISO8601DateFormatter().date(from:"2026-10-07T12:00:00Z")!
    var device=HeartbeatDeviceState(lidClosed:false,userWake:true)
    var environment=HeartbeatEnvironment(registration:"fictional-owner",model:"fictional-model",sourceSettings:"settings-1",scope:"scope-1",whatsappChoices:UUID(),whatsappIdentity:"fictional-device",contextEnabled:true,inferenceVerified:true,usagePaused:false,workBusy:false,foregroundBusy:false,permitted:true,emailEnabled:true,proposalsEnabled:true,proposalAllowanceReached:false)
    var nativeReady=true
    var wantsWhatsApp=false
    var whatsappReady=false
    var pending=false
    var fingerprint="fingerprint-1"
    var activity=HeartbeatActivity()
    var briefID:String?
    var prepareCount=0
    var stages:[String]=[]
    var claims=0
    var verifiedPersistedClaims=0
    var cancelCount=0
    var holdStage:String?
    var failureStage:String?
    var briefClaims=1
    var fakeBriefID=false
    var nativeFailure=false
    var afterPrepare:(()->Void)?
    var held:CheckedContinuation<Void,Never>?
    var capturedRequest:HeartbeatChildRequest?
    var sourceRequest:HeartbeatSourceRequest?
    var repository:LocalRecordRepository!
    var waiting:Bool {held != nil}
    var mail:MailReviewScope {
        .init(windows:["healthy":.init(start:now.addingTimeInterval(-3600),end:now,checked:now.addingTimeInterval(-300))],issues:["unavailable":"Fictional background collection failure"],usesCollectedMail:true,capturedFailures:["healthy":1])
    }
    var sources:HeartbeatSources {
        .init(mailReview:mail,accounts:[.init(id:"healthy",title:"Fictional healthy"),.init(id:"unavailable",title:"Fictional unavailable")],enabledMail:["healthy","unavailable"],nativeReady:nativeReady,wantsWhatsApp:wantsWhatsApp,whatsappReady:whatsappReady)
    }
    func release() {let continuation=held;held=nil;continuation?.resume()}
    func stage(_ name:String,_ request:HeartbeatChildRequest) async throws->HeartbeatChildResult {
        stages.append(name);capturedRequest=request
        for _ in 0..<(name == "brief" ? briefClaims : 1) {
            try request.claim()
            claims += 1
            let saved:PAHeartbeatState?=try repository.decode("paHeartbeat")
            if saved?.accounts[request.registration]?.calls == claims {verifiedPersistedClaims += 1}
        }
        if holdStage == name {await withCheckedContinuation {held=$0}}
        // These fictional workers deliberately return after cancellation so the
        // real scheduler must still reject the late stage result and continuation.
        if failureStage == name {return .init(failure:"Fictional \(name) interruption")}
        if name == "email" {activity.emailDrafts += 1;activity.handled += 1}
        if name == "suggestions" {activity.preparedItems += 1;activity.whatsappDrafts += 1}
        if name == "brief" {briefID=fakeBriefID ? "older-fictional-run" : request.runID;activity.questions += 1}
        try repository.save(["stage":name,"run":request.runID,"owner":request.registration],key:"fictionalChildReceipt")
        return .init(nativeUnavailable:name == "suggestions" && nativeFailure)
    }
    func runtime()->HeartbeatRuntime {
        .init(environment:{self.environment},prepareSources:{request in
            self.prepareCount += 1;self.sourceRequest=request;try request.validate()
            if self.holdStage == "sources" {await withCheckedContinuation {self.held=$0}}
            try request.validate();self.afterPrepare?();return self.sources
        },currentSources:{_ in self.sources},availableMail:{$0},sourceFingerprint:{_,_,_ in self.fingerprint},mailFingerprints:{_ in ["healthy":self.fingerprint]},pending:{review,_,ready in
            .init(any:self.pending,mailAccounts:self.pending || !ready ? review.accountIDs : [],proposals:self.pending)
        },activity:{_,runID in var value=self.activity;value.briefUpdated=self.briefID == runID;return value},email:{try await self.stage("email",$0)},suggestions:{try await self.stage("suggestions",$0)},brief:{try await self.stage("brief",$0)},cancelChildren:{self.cancelCount += 1})
    }
}

@main struct HeartbeatServiceChecks {
    @MainActor static func main() async throws {
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks += 1;precondition(condition,message)}
        func until(_ condition:()->Bool) async {
            for _ in 0..<20_000 {if condition() {return};await Task.yield()}
            preconditionFailure("Fictional heartbeat did not reach the expected boundary")
        }
        let suite="com.mylomichael.missioncontrol.heartbeat-fixture.\(UUID().uuidString)"
        let settings=UserDefaults(suiteName:suite)!
        defer {settings.removePersistentDomain(forName:suite)}
        let directory=URL(fileURLWithPath:ProcessInfo.processInfo.environment["TMPDIR"]!).appendingPathComponent("heartbeat-fictional-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        var storeNumber=0
        func store() throws->ModelContainer {
            storeNumber += 1
            return try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(url:directory.appendingPathComponent("fixture-\(storeNumber).store")))
        }
        func make(_ world:FictionalHeartbeatWorld,_ container:ModelContainer,repository:LocalRecordRepository? = nil)->HeartbeatService {
            world.repository=LocalRecordRepository(container:container)
            return HeartbeatService(container:container,settings:settings,repository:repository,clock:{world.now},deviceState:{world.device})
        }
        let owner="fictional-owner"
        let world=FictionalHeartbeatWorld(),container=try store()
        let beforeDomain=settings.persistentDomain(forName:suite) ?? [:]
        let service=make(world,container)
        check(NSDictionary(dictionary:beforeDomain).isEqual(to:settings.persistentDomain(forName:suite) ?? [:]),"Construction must not write default controls")
        service.intervalMinutes=30
        check(settings.integer(forKey:"paHeartbeatMinutes") == 30,"Explicit controls use the injected suite")
        service.intervalMinutes=60
        let runtime=world.runtime()
        service.check(runtime:runtime)
        await until{!service.busy}
        let completed=service.state.accounts[owner]!,run=completed.reviews!.last!
        check(world.stages == ["email","suggestions","brief"],"Actual scheduler serially owns the three child stages")
        check(world.claims == 3 && world.verifiedPersistedClaims == 3,"Every child claim is durable before fictional inference")
        check(completed.phase == "idle" && completed.assessed == world.now,"Actual completion uses the injected clock")
        check(run.started == world.now && run.finished == world.now && run.calls == 3,"Run timestamps and call delta use the captured clock")
        check(run.steps?.allSatisfy{$0.status == "done"} == true,"Persisted real stage transitions finish")
        check(run.preparedItems == 1 && run.drafts == 2 && run.handled == 1 && run.questions == 1,"Activity records use child receipt deltas")
        check(run.briefUpdated == true && run.mailCollectionIndependent == true,"Only the exact heartbeat brief receipt marks completion")
        check(run.checkedAccounts == 1 && run.waitingAccounts == 1 && completed.mailLanes?["unavailable"]?.pending == true,"Unavailable Mail coverage is retained independently of usable collected data")
        check(completed.mailLanes?["healthy"]?.fingerprint == world.fingerprint,"Successful Mail assessment persists its exact collected fingerprint")
        let reopened=make(world,container)
        check(reopened.state.accounts[owner]?.reviews?.last?.id == run.id && reopened.state.accounts[owner]?.calls == 3,"Actual disk reopening retains run identity and claims")
        reopened.check(runtime:runtime)
        await Task.yield()
        check(world.prepareCount == 1,"Completed runs cannot immediately repeat")
        world.now=world.now.addingTimeInterval(5*3600);world.fingerprint="after-missed-slots"
        reopened.check(runtime:runtime);await until{!reopened.busy}
        check(world.prepareCount == 2 && reopened.state.accounts[owner]?.reviews?.count == 2,"Five missed ticks catch up in one owned cycle")
        let previousClaims=world.claims
        world.now=world.now.addingTimeInterval(3600)
        reopened.check(runtime:runtime);await until{!reopened.busy}
        check(world.claims == previousClaims+3 && reopened.state.accounts[owner]?.reviews?.last?.briefUpdated == true,"Each due interval still owns a current brief even when source fingerprints are unchanged")
        let oldRequest=world.capturedRequest!
        check(({do{try oldRequest.claim();return false}catch{return true}})(),"A finished run cannot later claim another child call")
        check(({do{try world.sourceRequest!.validate();return false}catch{return true}})(),"A finished source-preparation callback cannot regain ownership")

        let outage=FictionalHeartbeatWorld(),outageStore=try store(),outageService=make(outage,outageStore)
        outage.failureStage="email"
        outageService.check(runtime:outage.runtime());await until{!outageService.busy}
        let failed=outageService.state.accounts[owner]!,failedRun=failed.reviews!.last!
        check(outage.stages == ["email"] && failed.calls == 1,"A child failure preserves claimed work and stops later stages")
        check(failed.retryReason == "failure" && failed.retryAfter == outage.now.addingTimeInterval(3600),"Failure waits for a fresh interval")
        check(failedRun.failure != nil && failedRun.steps?[1].status == "failed","Actual failure history is explicit")
        outage.now=outage.now.addingTimeInterval(30)
        let outageReopened=make(outage,outageStore)
        outageReopened.check(runtime:outage.runtime());await Task.yield()
        check(outage.prepareCount == 1,"Reopening a failure never starts a retry storm")
        outage.now=outage.now.addingTimeInterval(3570);outage.failureStage=nil;outage.fingerprint="fresh-after-failure"
        outageReopened.check(runtime:outage.runtime());await until{!outageReopened.busy}
        check(outage.prepareCount == 2 && outageReopened.state.accounts[owner]?.reviews?.count == 2,"Interval recovery starts a new persisted run")
        check(outageReopened.state.accounts[owner]?.reviews?.first?.id == failedRun.id && outageReopened.state.accounts[owner]?.retryAfter == nil,"Fresh success retains original failure history")

        let sleeping=FictionalHeartbeatWorld(),sleepStore=try store()
        sleeping.repository=LocalRecordRepository(container:sleepStore)
        let dueAnchor=sleeping.now.addingTimeInterval(-7200)
        try sleeping.repository.save(PAHeartbeatState(accounts:[owner:.init(checked:dueAnchor,budgetDay:BriefingRules.day(sleeping.now),calls:0,assessed:dueAnchor)]),key:"paHeartbeat")
        let sleepOwned=make(sleeping,sleepStore)
        sleeping.holdStage="email"
        sleepOwned.check(runtime:sleeping.runtime());await until{sleeping.waiting}
        sleepOwned.willSleep(runtime:sleeping.runtime())
        let immediate=make(sleeping,sleepStore),suspended=immediate.state.accounts[owner]!
        check(sleepOwned.busy && suspended.checked == dueAnchor,"Sleep persists the original due anchor before task unwind")
        check(suspended.calls == 1 && suspended.reviews?.last?.outcome() == "Paused for sleep","Immediate reopen retains claims and sleep history")
        check(PAHeartbeatRules.due(suspended,now:sleeping.now),"Sleep retains an overdue catch-up rather than delaying an hour")
        let sleepClaim=sleeping.capturedRequest!
        check(({do{try sleepClaim.claim();return false}catch{return true}})(),"Suspension refuses late child calls")
        sleeping.release();await until{!sleepOwned.busy}
        check(sleeping.stages == ["email"] && sleepOwned.state.accounts[owner]?.calls == 1,"Late cancelled child output cannot continue the sleeping run")
        sleeping.holdStage=nil;sleepOwned.didWake(runtime:sleeping.runtime());await until{!sleepOwned.busy}
        check(sleeping.prepareCount == 2 && sleepOwned.state.accounts[owner]?.reviews?.count == 2,"Wake catches up once with fresh context and a distinct run")
        check(({do{try sleepClaim.claim();return false}catch{return true}})(),"Old run closure stays expired after same-account recovery")

        for restriction in ["lid","darkWake","context","connection","usage","foreground","preview","emptyOwner"] {
            let restricted=FictionalHeartbeatWorld(),restrictedStore=try store(),restrictedService=make(restricted,restrictedStore)
            switch restriction {
            case "lid":restricted.device.lidClosed=true
            case "darkWake":restricted.device.userWake=false
            case "context":restricted.environment.contextEnabled=false
            case "connection":restricted.environment.inferenceVerified=false
            case "usage":restricted.environment.usagePaused=true
            case "foreground":restricted.environment.workBusy=true;restricted.environment.foregroundBusy=true
            case "preview":restricted.environment.permitted=false
            default:restricted.environment.registration=""
            }
            restrictedService.check(runtime:restricted.runtime());await Task.yield()
            check(restricted.prepareCount == 0 && restrictedService.state.accounts.isEmpty,"Ineligible \(restriction) does not consume a due slot")
        }
        let typing=FictionalHeartbeatWorld(),typingStore=try store(),typingService=make(typing,typingStore)
        typingService.userStartedTyping();typingService.check(runtime:typing.runtime());await Task.yield()
        check(typing.prepareCount == 0,"Foreground typing wins before source preparation")
        typing.now=typing.now.addingTimeInterval(121)
        typingService.check(runtime:typing.runtime());await until{!typingService.busy}
        check(typing.prepareCount == 1,"Idle typing expiry allows a due heartbeat")
        let stopped=FictionalHeartbeatWorld(),stoppedStore=try store(),stoppedService=make(stopped,stoppedStore)
        stopped.holdStage="sources"
        stoppedService.check(runtime:stopped.runtime());await until{stopped.waiting}
        check(stopped.sourceRequest?.registration == owner && stopped.sourceRequest?.clock() == stopped.now,"Source preparation carries the captured owner and clock")
        stoppedService.userStartedTyping();stopped.release();await until{!stoppedService.busy}
        check(stopped.claims == 0 && stopped.stages.isEmpty,"Stop during collection never starts child inference")
        check(stoppedService.state.accounts[owner]?.retryReason == "foreground" && stoppedService.state.accounts[owner]?.retryAfter == stopped.now.addingTimeInterval(60),"A stopped source preparation waits for foreground work without an AI failure interval")
        let unavailable=FictionalHeartbeatWorld(),unavailableStore=try store(),unavailableService=make(unavailable,unavailableStore)
        unavailable.nativeReady=false;unavailable.wantsWhatsApp=true
        unavailableService.check(runtime:unavailable.runtime());await until{!unavailableService.busy}
        let partial=unavailableService.state.accounts[owner]!
        check(unavailable.stages == ["email","brief"] && unavailable.claims == 2,"Native unavailability still allows permitted Mail review and an honest brief")
        check(partial.pending == true && partial.reviews?.last?.steps?[0].status == "waiting" && partial.reviews?.last?.steps?[2].status == "waiting","Unavailable native and WhatsApp comparisons remain pending")
        let lostNative=FictionalHeartbeatWorld(),lostStore=try store(),lostService=make(lostNative,lostStore)
        lostNative.nativeFailure=true
        lostService.check(runtime:lostNative.runtime());await until{!lostService.busy}
        check(lostService.state.accounts[owner]?.pending == true && lostService.state.accounts[owner]?.reviews?.last?.steps?[2].status == "waiting","A child's late native read failure cannot be labelled a completed comparison")

        for change in ["owner","model","scope","controls","midnight","foreground","context","usage"] {
            let late=FictionalHeartbeatWorld(),lateStore=try store(),lateService=make(late,lateStore)
            late.holdStage="email"
            lateService.check(runtime:late.runtime());await until{late.waiting}
            let request=late.capturedRequest!
            switch change {
            case "owner":late.environment.registration="another-fictional-owner"
            case "model":late.environment.model="different-model"
            case "scope":late.environment.scope="changed-permissions"
            case "controls":lateService.notificationsEnabled.toggle()
            case "midnight":late.now=late.now.addingTimeInterval(86400)
            case "foreground":late.environment.foregroundBusy=true
            case "context":late.environment.contextEnabled=false
            default:late.environment.usagePaused=true
            }
            check(({do{try request.claim();return false}catch{return true}})(),"Late \(change) rejects a new call before fictional inference")
            late.release();await until{!lateService.busy}
            check(late.stages == ["email"] && lateService.state.accounts[owner]?.assessed == nil && lateService.state.accounts[owner]?.calls == 1,"Late \(change) cannot complete or continue a captured run")
            check(lateService.state.accounts["another-fictional-owner"] == nil,"Captured work is never retargeted")
        }
        for change in ["settings","choices","knownIdentity","unknownIdentity"] {
            let source=FictionalHeartbeatWorld(),sourceStore=try store(),sourceService=make(source,sourceStore)
            if change == "unknownIdentity" {source.environment.whatsappIdentity=""}
            source.afterPrepare={
                switch change {
                case "settings":source.environment.sourceSettings="new-settings"
                case "choices":source.environment.whatsappChoices=UUID()
                default:source.environment.whatsappIdentity="verified-fictional-device";source.environment.scope="verified-scope"
                }
            }
            sourceService.check(runtime:source.runtime());await until{!sourceService.busy}
            check(source.claims == (change == "unknownIdentity" ? 3 : 0),"Only initial unknown identity may become verified during source preparation")
        }

        var denyClaim=true
        let denied=FictionalHeartbeatWorld(),deniedStore=try store()
        let failingClaim=LocalRecordRepository(container:deniedStore,beforeCommit:{context in
            if denyClaim,let data=try context.fetch(LocalRecordRepository.request("paHeartbeat")).first?.data,let value=try? JSONDecoder().decode(PAHeartbeatState.self,from:data),value.accounts[owner]?.calls == 1 {denyClaim=false;throw ActionFailure.message("Fictional disk failure before claim")}
        })
        let deniedService=make(denied,deniedStore,repository:failingClaim)
        deniedService.check(runtime:denied.runtime());await until{!deniedService.busy}
        check(denied.claims == 0 && deniedService.state.accounts[owner]?.calls == nil,"Failed receipt save refuses inference and rolls back the live call count")
        try denied.repository.save(["fictional":"unrelated successful save"],key:"laterSave")
        let deniedReopened=make(denied,deniedStore)
        check(PAHeartbeatRules.callCount(deniedReopened.state.accounts[owner]!,day:BriefingRules.day(denied.now)) == 0,"Later successful saves and disk reopen cannot resurrect the failed call claim")
        check(deniedReopened.state.accounts[owner]?.retryReason == "failure","Failed claim retains a fresh scheduled recovery")

        var denyCompletion=true
        let completion=FictionalHeartbeatWorld(),completionStore=try store()
        let failingCompletion=LocalRecordRepository(container:completionStore,beforeCommit:{context in
            if denyCompletion,let data=try context.fetch(LocalRecordRepository.request("paHeartbeat")).first?.data,let value=try? JSONDecoder().decode(PAHeartbeatState.self,from:data),value.accounts[owner]?.assessed != nil {denyCompletion=false;throw ActionFailure.message("Fictional disk failure before completion")}
        })
        let completionService=make(completion,completionStore,repository:failingCompletion)
        completionService.check(runtime:completion.runtime());await until{!completionService.busy}
        let completionReopened=make(completion,completionStore),retained=completionReopened.state.accounts[owner]!
        check(retained.assessed == nil && retained.calls == 3 && retained.retryReason == "failure","Failed final save retains child claims without falsely completing the assessment")
        check(retained.reviews?.last?.briefUpdated == true && retained.reviews?.last?.outcome() == "Partly completed","A persisted child brief receipt remains honest when parent completion fails")
        let receipt:[String:String]?=try completion.repository.decode("fictionalChildReceipt")
        check(receipt?["stage"] == "brief","Parent rollback never removes completed child receipts")

        let bounded=FictionalHeartbeatWorld(),boundedStore=try store(),boundedService=make(bounded,boundedStore)
        boundedService.dailyCallLimit=8;bounded.briefClaims=6
        boundedService.check(runtime:bounded.runtime());await until{!boundedService.busy}
        check(bounded.claims == 8 && boundedService.state.accounts[owner]?.calls == 8,"Multiple brief preparations share the parent's whole-run allowance")
        bounded.now=bounded.now.addingTimeInterval(3600);bounded.fingerprint="new-but-exhausted"
        boundedService.check(runtime:bounded.runtime());await until{!boundedService.busy}
        check(bounded.claims == 8 && boundedService.state.accounts[owner]?.retryReason == "allowance","Further due source checks cannot exceed the persisted daily allowance")
        bounded.now=bounded.now.addingTimeInterval(86400);bounded.briefClaims=1
        boundedService.check(runtime:bounded.runtime());await until{!boundedService.busy}
        check(boundedService.state.accounts[owner]?.calls == 3 && boundedService.state.accounts[owner]?.reviews?.count == 3,"A new day grants only its own calls and keeps prior run history")
        boundedService.dailyCallLimit=64
        let overrun=FictionalHeartbeatWorld(),overrunStore=try store(),overrunService=make(overrun,overrunStore)
        overrunService.dailyCallLimit=8;overrun.briefClaims=7
        overrunService.check(runtime:overrun.runtime());await until{!overrunService.busy}
        check(overrun.claims == 8 && overrunService.state.accounts[owner]?.calls == 8 && overrunService.state.accounts[owner]?.retryReason == "allowance","A child cannot exceed the whole-run allowance inside one stage")
        check(overrunService.state.accounts[owner]?.reviews?.last?.briefUpdated == false,"An exhausted preparation cannot claim a saved brief")
        overrunService.dailyCallLimit=64

        let mismatch=FictionalHeartbeatWorld(),mismatchStore=try store(),mismatchService=make(mismatch,mismatchStore)
        mismatch.fakeBriefID=true
        mismatchService.check(runtime:mismatch.runtime());await until{!mismatchService.busy}
        check(mismatchService.state.accounts[owner]?.assessed == nil && mismatchService.state.accounts[owner]?.reviews?.last?.briefUpdated == false,"A stale brief receipt cannot satisfy the captured run")
        let corrupt=FictionalHeartbeatWorld(),corruptStore=try store(),original=Data("fictional-invalid-heartbeat".utf8)
        let corruptRepository=LocalRecordRepository(container:corruptStore);try corruptRepository.write(["paHeartbeat":original])
        let corruptService=make(corrupt,corruptStore)
        corruptService.check(runtime:corrupt.runtime(),manual:true);await Task.yield()
        check(!corruptService.readable && corrupt.prepareCount == 0,"Corrupt saved state fails closed before any source or child work")
        check(try corruptRepository.read("paHeartbeat") == original,"Corrupt original bytes remain intact")
        check(!service.statusFor("another-fictional-owner").contains("Heartbeat completed"),"Another account never displays the previous owner's detail")
        print("HeartbeatService: \(checks) contracts passed; fictional stages/clock/device and private disk storage, no dashboard, native sources or AI.")
    }
}
