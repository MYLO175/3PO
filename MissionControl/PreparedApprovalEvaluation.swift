#if DEBUG
import Foundation

/// Actual saved-proposal authority and project persistence, using disposable app storage.
@MainActor enum PreparedApprovalEvaluation {
    static func run() throws -> [String:Bool] {
        guard ProcessInfo.processInfo.arguments.contains("--validate-review-inbox") else {throw IntegrationError.verification}
        let arguments=UserDefaults.standard.volatileDomain(forName:NSArgumentDomain)
        var fixtureArguments=arguments;fixtureArguments["assistantContextEnabled"]=true;fixtureArguments["automaticEmailSummaries"]=true
        UserDefaults.standard.setVolatileDomain(fixtureArguments,forName:NSArgumentDomain)
        defer {UserDefaults.standard.setVolatileDomain(arguments,forName:NSArgumentDomain)}
        let model=DashboardModel(),original=try ReviewInboxEvaluation.seed(model)
        var record=original;record.kind="reminder";record.proposedChange=nil;record.sourceTitle="Submit Orion report"
        try model.proactive.seedAdviceFixture([record],model:model)
        record=model.proactive.state.records[0]
        var checks:[String:Bool]=[:]
        model.reviewDiscovery(record)
        if case .create(let request)=model.editTarget {
            checks["native form captures exact displayed proposal"]=request.discoveryApproval == model.preparedApprovalSnapshot(record) && request.id.uuidString == record.id
        } else {checks["native form captures exact displayed proposal"]=false}
        let snapshot=model.preparedApprovalSnapshot(record)
        let fact=PAMemory(registration:model.chatGPT.activeID,text:"The fictional report is for a different supervisor now.",kind:.context,provenance:"Fictional human",evidence:"The fictional report is for a different supervisor now.")
        guard model.assistant.memory.put(fact) else {throw SummaryFailure.invalid}
        var summary=model.emailSummaries.records[0];summary.bodyFingerprint="changed-after-preparation"
        try model.emailSummaries.seedAdviceFixture([summary])
        model.mailData.messages=[]
        try model.validatePreparedApproval(record)
        checks["changed memory and source body do not block a concrete approval"]=model.preparedApprovalSnapshot(record) == snapshot && model.currentPreparedApproval(record)
        var changed=record;changed.sourceTitle="Different action"
        try model.proactive.seedAdviceFixture([changed],model:model)
        checks["changed displayed payload rejects the old approval"] = !model.currentPreparedApproval(record)
        try model.proactive.seedAdviceFixture([record],model:model)
        var wrongAccount=record;wrongAccount.registration="another-registration"
        checks["approval cannot cross account"] = !model.currentPreparedApproval(wrongAccount)
        try model.proactive.beginReview(record.id,model:model)
        checks["pending receipt blocks a second review but preserves in-flight validity"] = !model.proactive.canReview(record.id,model:model) && model.currentPreparedApproval(record)
        try model.proactive.abortReview(record.id,registration:record.registration)
        try model.proactive.beginReview(record.id,model:model);try model.proactive.finishReview(record.id,registration:record.registration)
        checks["completed receipt prevents replay"] = !model.currentPreparedApproval(record) && !model.proactive.canReview(record.id,model:model)

        var parent=LifeItem(registration:record.registration,kind:.space,title:"Fictional engineering project")
        parent=try model.assistant.projects.save(parent,expected:nil)
        var proposal=record;proposal.id=UUID().uuidString;proposal.kind="projectTask"
        proposal.proposedProjectTask = .init(target:.init(id:parent.id,revision:parent.revision,title:parent.title),connection:"Existing project")
        try model.proactive.seedAdviceFixture([proposal],model:model)
        var revised=parent;revised.notes="A corrected project description"
        revised=try model.assistant.projects.save(revised,expected:parent.revision)
        let item=LifeItem(registration:record.registration,kind:.task,title:"Submit fictional report",parentID:parent.id,notes:record.evidence)
        try model.savePreparedProjectItem(item,proposal:proposal)
        checks["project description revision does not block task approval"]=model.assistant.projects.items(record.registration,includeTopics:true).contains{$0.id == item.id && $0.parentID == parent.id}
        do {try model.savePreparedProjectItem(item,proposal:proposal);checks["project receipt prevents approval replay"]=false}
        catch {checks["project receipt prevents approval replay"]=true}
        var unavailable=proposal;unavailable.id=UUID().uuidString
        try model.proactive.seedAdviceFixture([unavailable],model:model)
        var invalidDestination=item;invalidDestination.id=UUID();invalidDestination.title="Second fictional report";invalidDestination.parentID=UUID()
        do {try model.savePreparedProjectItem(invalidDestination,proposal:unavailable);checks["missing exact project destination blocks creation"]=false}
        catch {checks["missing exact project destination blocks creation"]=true}
        var archived=revised;archived.status = .archived
        _ = try model.assistant.projects.save(archived,expected:revised.revision)
        invalidDestination.parentID=parent.id
        do {try model.savePreparedProjectItem(invalidDestination,proposal:unavailable);checks["archived project destination blocks creation"]=false}
        catch {checks["archived project destination blocks creation"]=true}
        checks["project failures leave no task and no receipt"] = !model.assistant.projects.items(record.registration,includeTopics:true).contains{$0.id == invalidDestination.id} && model.assistant.projects.receipt("project-suggestion:"+unavailable.id,registration:record.registration) == nil
        return checks
    }
}
#endif
