#if DEBUG
import Foundation
import SwiftUI

/// Actual consumer projections, fictional data and disposable storage; zero subscription requests.
@MainActor enum AdviceContextEvaluation {
    static func run(_ model:DashboardModel)throws->[String:Any] {
        guard ProcessInfo.processInfo.arguments.contains("--validate-advice-context"),model.assistant.memory.enabled,model.assistant.contextEnabled else {
            throw ActionFailure.message("This check requires the existing memory/source context settings to be on. No settings were changed.")
        }
        let registration=model.chatGPT.activeID,now=Date.now,store=model.assistant.memory
        let identity=MemorySourceIdentity(kind:.calendar,accountID:"fictional-provider",containerID:"fictional-study",itemID:"fictional-orion")
        let quote="Prepare four sensors for the Orion supervision."
        let source=MemorySourceEvidence(identity:identity,revision:"fictional-v1",label:"Fictional Studies",quote:quote,observed:now,sourceDate:now)
        let fact=PAMemory(registration:registration,text:"A Calendar entry requests a four-sensor Orion prototype.",kind:.commitment,explicit:false,provenance:"Fictional source",evidence:quote,certainty:.inferred,durability:.situational,source:source,sourceState:.proposed)
        let human=PAMemory(registration:registration,text:"I prefer preparing the day before.",kind:.preference,provenance:"Fictional human",evidence:"I prefer preparing the day before.")
        var permitted=true
        store.sourceIsPermitted={_ in permitted}
        store.sourcePermissionProjection={permitted ? [fact.id] : []}
        guard store.putSources([fact],evidenceTexts:[identity:quote],expectedRevision:store.revision),store.put(human) else { throw SummaryFailure.invalid }
        let capture=model.automaticMemory(.brief)
        var checks:[String:Bool]=[:]
        checks["actual capture includes permitted source and human facts"]=capture.records.count == 2 && capture.dependencies.count == 2
        let morning=DailyBriefing(id:"fictional-morning",registration:registration,day:BriefingRules.day(now),created:now,items:[.init(text:"Prepare the Orion prototype.",sourceIDs:["memory_0"])],sources:[.init(id:"memory_0",label:"Fictional memory",kind:"memory",date:nil,originalID:fact.id.uuidString)],coverage:"Fictional",message:"Good morning. Prepare the Orion prototype.",memoryDependencies:capture.dependencies)
        let json:[String:Any]=["id":"fictional-message","accountID":"fictional-mail","account":"Fictional Mail","messageID":1,"internetMessageID":"orion@example.invalid","sender":"Fictional tutor","subject":"Orion preparation","received":now.ISO8601Format(),"unread":true,"replied":false,"flagged":false]
        let message=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:json))
        model.mailData = .init(messages:[message],accounts:[.init(id:message.accountID,title:message.account)],errors:[])
        let summary=EmailSummary(id:message.id,registration:registration,fingerprint:EmailSummary.fingerprint(message),summary:"Orion preparation requested.",attention:true,reason:"Prepare the prototype",evidence:quote,bodyFingerprint:"fictional-body-v1",message:message)
        try model.emailSummaries.seedAdviceFixture([summary])
        let advice=PADiscovery(id:UUID().uuidString,registration:registration,mailID:message.id,kind:"reminder",message:"Would a prototype reminder help?",evidence:quote,created:now,scope:"fixture",sourceRevision:summary.fingerprint,memoryDependencies:capture.dependencies,memoryUse:.manualSuggestions,sourceAssessmentRevision:summary.adviceRevision(replied:false))
        try model.proactive.seedAdviceFixture([advice],model:model)
        try model.briefings.seedAdviceFixture(morning,model:model)
        let savedAdvice=model.proactive.state.records[0],savedMorning=model.briefings.state.records[0]
        let delivery=ConversationRules.morningKey(registration:registration,day:morning.day)
        checks["actual current brief is initially available"]=model.briefings.current(model)?.id == morning.id
        checks["actual Tasks suggestion is initially visible"]=model.proactive.visible(savedAdvice,model:model)
        permitted=false
        checks["revocation rejects captured context before a save"] = !model.memoryDependenciesAvailable(capture.dependencies,use:.brief) && capture != model.automaticMemory(.brief)
        checks["revocation removes current advice"]=model.briefings.current(model) == nil && !model.proactive.visible(savedAdvice,model:model)
        checks["dated morning stays inspectable"]=model.briefings.savedToday(model)?.id == morning.id && model.briefings.savedToday(model)?.message == morning.message
        checks["stale morning leaves future AI history"] = !model.briefings.allowsChatDelivery(delivery,content:BriefingRules.prose(morning),model:model)
        model.reviewDiscovery(savedAdvice)
        checks["stale suggestion cannot open a creation review"]=model.editTarget == nil
        checks["morning completion and notification claims survive"]=BriefingRules.completedDays(records:model.briefings.state.records,registration:registration) == [morning.day] && model.briefings.state.notificationClaims == [morning.day]
        permitted=true
        checks["matching evidence can become usable again"]=model.briefings.current(model)?.id == morning.id && model.proactive.visible(savedAdvice,model:model)
        _=store.put(.init(registration:registration,text:"I enjoy tennis.",kind:.context,provenance:"Unrelated fictional fact"))
        checks["unrelated facts leave persisted advice valid"]=model.briefings.current(model)?.id == morning.id && model.proactive.visible(savedAdvice,model:model)
        let updateOnly=PAMemory(registration:registration,text:"I may need extra Orion preparation.",kind:.context,explicit:false,provenance:"Fictional provisional context",certainty:.inferred,durability:.situational)
        guard store.put(updateOnly) else { throw SummaryFailure.invalid }
        var partialUpdate=morning;partialUpdate.id="fictional-partial-update";partialUpdate.morningID=morning.id;partialUpdate.created=now.addingTimeInterval(0.5);partialUpdate.memoryDependencies=model.automaticMemory(.brief).dependencies
        try model.briefings.seedAdviceFixture(savedMorning,update:partialUpdate,model:model)
        guard store.forget(updateOnly.id) else { throw SummaryFailure.invalid }
        checks["stale update falls back to independently usable morning"]=model.briefings.current(model)?.id == morning.id
        checks["latest stale update stays inspectable with explanation"]=model.briefings.savedToday(model)?.id == partialUpdate.id && model.briefings.freshnessNote(model.briefings.savedToday(model)!,model:model) != nil
        var corrected=human;corrected.id=UUID();corrected.text="I now prefer preparing two days before.";corrected.evidence=corrected.text
        guard store.correct(human.id,with:corrected) else { throw SummaryFailure.invalid }
        checks["human correction sets old advice aside"]=model.briefings.current(model) == nil && !model.proactive.visible(savedAdvice,model:model)
        var update=morning;update.id="fictional-update";update.morningID=morning.id;update.created=now.addingTimeInterval(1);update.message="Updated preparation advice.";update.memoryDependencies=model.automaticMemory(.brief).dependencies
        try model.briefings.seedAdviceFixture(savedMorning,update:update,model:model)
        checks["fresh update uses original morning identity"]=model.briefings.current(model)?.id == update.id && model.briefings.savedMorning(model)?.id == morning.id
        checks["update keeps original morning text and notification claim"]=model.briefings.state.records[0].message == morning.message && model.briefings.state.notificationClaims == [morning.day]
        var legacy=savedAdvice;legacy.memoryDependencies=nil;legacy.memoryUse=nil;legacy.sourceAssessmentRevision=nil
        try model.proactive.seedAdviceFixture([legacy],model:model)
        let savedLegacy=model.proactive.state.records[0]
        checks["legacy advice remains readable without invented receipts"]=model.proactive.visible(savedLegacy,model:model)
        var changedJSON=json;changedJSON["subject"]="Orion preparation cancelled"
        let changed=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:changedJSON))
        model.mailData = .init(messages:[changed],accounts:model.mailData.accounts,errors:[])
        checks["changed header hides an unchanged legacy assessment"] = !model.proactive.visible(savedLegacy,model:model)
        let request=WhatsAppReadMessage(id:"fictional-request",chat:"fictional-study",sender:"Tutor",text:quote,sentByMe:false,time:now.timeIntervalSince1970*1000)
        let cancel=WhatsAppReadMessage(id:"fictional-cancel",chat:request.chat,sender:"Tutor",text:"The supervision has been cancelled.",sentByMe:false,time:request.time+1000)
        checks["later cancellation changes conversation receipt"]=ProactiveRules.whatsappWindow([request],chats:[request.chat],identity:"fictional-link") != ProactiveRules.whatsappWindow([request,cancel],chats:[request.chat],identity:"fictional-link")
        checks["fixture uses only its account and starts no native write"]=store.records.allSatisfy{$0.registration == registration} && model.writing == false
        return ["completed":Date.now.ISO8601Format(),"requests":0,"passed":checks.values.filter{$0}.count,"total":checks.count,"checks":checks,"storage":"Fictional claims, messages and outputs in disposable SwiftData before source startup. No inference, native writes, permission changes or personal store writes. This tests actual consumer projections, not scheduler races or real message delivery."]
    }
}
#endif
