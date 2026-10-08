#if DEBUG
import Foundation
import SwiftUI
import SwiftData

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
        let summary=EmailSummary(id:message.id,registration:registration,fingerprint:EmailSummary.fingerprint(message),summary:"Orion preparation requested.",attention:true,reason:"Prepare the prototype",evidence:quote,bodyFingerprint:"fictional-body-v1",message:message,worthReading:true,needsReply:false)
        try model.emailSummaries.seedAdviceFixture([summary])
        checks["brief input includes exact current email assessment"] = model.briefings.currentEmails(model).count == 1
        var renamedJSON=json;renamedJSON["sender"]="Updated fictional contact name"
        let renamedSender=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:renamedJSON))
        model.mailData = .init(messages:[renamedSender],accounts:model.mailData.accounts,errors:[])
        checks["stale sender metadata withholds old assessment before brief inference"] = model.briefings.currentEmails(model).isEmpty
        checks["withholding a stale assessment preserves saved history"] = model.emailSummaries.records.count == 1 && model.emailSummaries.records[0].fingerprint == summary.fingerprint
        model.mailData = .init(messages:[message],accounts:model.mailData.accounts,errors:[])
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
        let study=PAMemory(registration:registration,text:"Alex is entering fourth year of Cambridge Engineering.",kind:.context,provenance:"Fictional human",evidence:"Alex is entering fourth year of Cambridge Engineering.",organisation:.init(areas:[.studies],connections:[],selfName:"Alex"))
        let weather=PAMemory(registration:registration,text:"Include the weather forecast in today's brief.",kind:.preference,provenance:"Fictional human")
        let family=PAMemory(registration:registration,text:"My family live in Newbury.",kind:.context,provenance:"Fictional human")
        checks["relevance fixtures save without replacing existing memory"]=store.put(study) && store.put(weather) && store.put(family)
        let securityQuery=MemoryRetrieval.emailQuery(subject:"Security alert",sender:"Google",body:"Alex: We noticed a new sign-in to your Google Account on a Mac OS device. If this was you, you don't need to do anything. If not, we'll help you secure your account.")
        let securityMemory=model.automaticMemory(.heartbeatSuggestions,query:securityQuery)
        checks["actual automatic security context omits unrelated biography and preferences"]=securityMemory.records.isEmpty && securityMemory.dependencies.isEmpty
        checks["actual email classification context omits unrelated human facts"]=store.context(registration,query:securityQuery,includeSources:false).isEmpty
        checks["actual notebook security input supplies no facts"]=PAContextCapture.notebookIDs(store.notebook(registration).context(query:securityQuery,selectedMemoryIDs:[])).memories.isEmpty
        let university=model.automaticMemory(.heartbeatSuggestions,query:"Cambridge Engineering module selection")
        checks["actual university context keeps the study fact only"]=university.records.map{$0["id"]} == [study.id.uuidString]
        checks["source assessment without a query does not supply a biography"]=model.automaticMemory(.heartbeatSuggestions).records.isEmpty
        checks["broad day planning remains available without editing saved memory"]=model.automaticMemory(.brief).records.contains{$0["id"] == weather.id.uuidString} && store.records.contains{$0.id == family.id && $0.text == family.text}
        checks["fixture uses only its account and starts no native write"]=store.records.allSatisfy{$0.registration == registration} && model.writing == false
        model.mailData = .init(messages:[message],accounts:model.mailData.accounts,errors:[])
        try model.emailSummaries.seedAdviceFixture([summary])
        let acknowledgement=PADiscovery(id:"fictional-ack",registration:registration,mailID:message.id,kind:"reminder",message:"Review the Orion preparation request.",evidence:quote,created:now,scope:"fictional",sourceRevision:summary.fingerprint,sourceAssessmentRevision:summary.adviceRevision(replied:message.replied))
        try model.proactive.seedAdviceFixture([acknowledgement],model:model)
        let beforeAcknowledgement=model.reviewAcknowledgementRevision,nativeBefore=DiscoveryNativeTarget.fingerprint(model.reminderData),memoryBefore=store.revision
        model.proactive.dismiss(model.proactive.state.records[0],model:model)
        checks["Dismiss counts as exact acknowledgement without native or memory changes"] = model.reviewAcknowledgementRevision != beforeAcknowledgement && !model.acknowledgedEmail(message,summary) && DiscoveryNativeTarget.fingerprint(model.reminderData) == nativeBefore && store.revision == memoryBefore
        checks["dismissing one proposal preserves independent actions in the same source"] = model.briefings.currentEmails(model).count == 1 && model.proactive.emailReviewCandidates(model,heartbeat:true,mailReview:nil,whatsappReady:false,now:now).count == 1
        let ackRows=model.reviewAcknowledgements()
        let snapshot=model.assistant.snapshot(model).flatMap{try? JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:Any]}
        checks["foreground source context knows the acknowledged concern"] = ackRows.contains{$0.id == "discovery:fictional-ack"} && (snapshot?["reviewAcknowledgements"] as? [[String:Any]])?.contains{$0["id"] as? String == "discovery:fictional-ack"} == true && (snapshot?["savedEmailSummaries"] as? [[String:Any]])?.count == 1
        checks["actual dismissal survives reopening its cache"] = model.proactive.reopenedAcknowledgementFixture().first?.dismissed == true && model.proactive.reopenedAcknowledgementFixture().first?.dismissedSourceVersion != nil
        checks["unavailable Mail lanes supply no acknowledged source prose"] = model.reviewAcknowledgements(use:.brief,mailAccounts:[],whatsappReady:false).isEmpty
        let acknowledgedBrief=DailyBriefing(id:"fictional-ack-brief",registration:registration,day:BriefingRules.day(now),created:now,items:[],sources:[],coverage:"Fictional",message:"The dismissed concern has been seen.",reviewAcknowledgementRevision:model.reviewAcknowledgementRevision,reviewAcknowledgementReceipts:ackRows.map(ReviewAcknowledgementReceipt.init))
        try model.briefings.seedAdviceFixture(acknowledgedBrief,model:model)
        checks["saved brief keeps current acknowledgement support"] = model.briefings.current(model)?.id == acknowledgedBrief.id
        var changedAssessment=summary;changedAssessment.bodyFingerprint="fictional-body-v2"
        try model.emailSummaries.seedAdviceFixture([changedAssessment])
        checks["changed negative-context source withholds saved advice but keeps history"] = model.briefings.current(model) == nil && model.briefings.savedToday(model)?.id == acknowledgedBrief.id && model.reviewAcknowledgements().isEmpty
        try model.emailSummaries.seedAdviceFixture([summary])
        model.proactive.undo(model)
        checks["Undo restores concern and original human-choice revision"] = !model.acknowledgedEmail(message,summary) && model.reviewAcknowledgementRevision == beforeAcknowledgement && model.briefings.currentEmails(model).count == 1
        model.emailSummaries.dismiss(message.id,model:model,expectedRegistration:summary.registration,expectedVersion:ReviewAcknowledgementRules.emailVersion(message,summary))
        checks["email-work dismissal is acknowledged across contexts"] = model.acknowledgedEmail(message,model.emailSummaries.records[0]) && model.reviewAcknowledgements().contains{$0.id == "email:"+message.id} && model.briefings.currentEmails(model).isEmpty
        model.emailSummaries.undoDismiss(model)
        checks["email-work Undo restores source attention"] = model.briefings.currentEmails(model).count == 1 && model.reviewAcknowledgementRevision == beforeAcknowledgement
        model.emailSummaries.dismiss(message.id,model:model,expectedRegistration:"fictional-other-registration",expectedVersion:ReviewAcknowledgementRules.emailVersion(message,summary))
        checks["stale registration cannot acknowledge another account's email"] = model.emailSummaries.records[0].dismissed != true
        try model.emailSummaries.seedAdviceFixture([changedAssessment])
        model.emailSummaries.dismiss(message.id,model:model,expectedRegistration:registration,expectedVersion:ReviewAcknowledgementRules.emailVersion(message,summary))
        checks["stale email card cannot acknowledge changed content"] = model.emailSummaries.records[0].dismissed != true
        let oldProposal=model.proactive.state.records[0]
        model.proactive.dismiss(oldProposal,model:model)
        checks["stale proposal dismissal does not acknowledge newer source content"] = model.proactive.state.records[0].dismissedSourceVersion == nil && model.reviewAcknowledgements().isEmpty

        try model.emailSummaries.seedAdviceFixture([summary])
        checks["feedback accepts only exact current permitted email"] = model.emailSummaries.feedbackSourceCurrent(message,summary:summary,model:model)
        model.mailData = .init(messages:[renamedSender],accounts:model.mailData.accounts,errors:[])
        checks["feedback rejects live header change"] = !model.emailSummaries.feedbackSourceCurrent(message,summary:summary,model:model)
        model.mailData = .init(messages:[message],accounts:[],errors:[])
        checks["feedback rejects removed Mail account"] = !model.emailSummaries.feedbackSourceCurrent(message,summary:summary,model:model)
        model.mailData = .init(messages:[message],accounts:[.init(id:message.accountID,title:message.account)],errors:[])
        let project=try model.assistant.projects.save(LifeItem(registration:registration,kind:.space,title:"Orion prototype",status:.active),expected:nil)
        let projectContext=model.emailSummaries.relevanceContext(message,model:model)
        checks["header relevance retrieves current project even without matching human facts"] = projectContext.workspace.contains{$0["id"] == "life:"+project.id.uuidString} && projectContext.memories.isEmpty
        let relevantHuman=PAMemory(registration:registration,text:"I am building the Orion prototype this term.",kind:.context,provenance:"Fictional human",evidence:"I am building the Orion prototype this term.")
        guard store.put(relevantHuman) else {throw SummaryFailure.invalid}
        let relevanceContext=model.emailSummaries.relevanceContext(message,model:model,body:quote)
        checks["email life context selects matching human facts without source facts or biography"] = relevanceContext.memories.contains{$0["id"] == relevantHuman.id.uuidString} && !relevanceContext.memories.contains{$0["id"] == fact.id.uuidString || $0["id"] == human.id.uuidString}
        let supported=try EmailRelevanceRules.validated(.init(reason:"Matches current Orion work",evidence:quote,memoryIDs:[relevantHuman.id.uuidString],workspaceIDs:["life:"+project.id.uuidString],preferenceIDs:[]),context:relevanceContext,message:message,body:quote)
        checks["supported life relevance remains currently usable"] = model.emailSummaries.relevanceAvailable(supported,model:model)
        var newerJSON=json;newerJSON["id"]="fictional-unrelated";newerJSON["received"]=now.addingTimeInterval(60).ISO8601Format()
        let newer=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:newerJSON))
        var taskJSON=newerJSON;taskJSON["id"]="fictional-task"
        let taskMail=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:taskJSON))
        var reading=summary;reading.attention=false;reading.personalRelevance=supported
        var unrelated=summary;unrelated.id=newer.id;unrelated.fingerprint=EmailSummary.fingerprint(newer);unrelated.message=newer;unrelated.attention=false
        var actualTask=summary;actualTask.id=taskMail.id;actualTask.fingerprint=EmailSummary.fingerprint(taskMail);actualTask.message=taskMail
        actualTask.personalRelevance=supported;actualTask.followUpEvidence="Wednesday of week one"
        model.mailData = .init(messages:[message,newer,taskMail],accounts:model.mailData.accounts,errors:[])
        try model.emailSummaries.seedAdviceFixture([reading,unrelated,actualTask])
        checks["current relevance ranks useful reading above newer routine reading while actual tasks stay first"] = model.emailSummaries.highlights(model).map{$0.0.id} == [taskMail.id,message.id,newer.id]
        let taskAssessment=model.emailSummaries.highlights(model).first{$0.0.id == taskMail.id}!.1.adviceRevision(replied:false)
        var renamedProject=project;renamedProject.title="Orion renamed"
        _ = try model.assistant.projects.save(renamedProject,expected:project.revision)
        checks["project change withdraws saved relevance boost"] = !model.emailSummaries.relevanceAvailable(supported,model:model)
        checks["stale life-only reading is withheld from current brief input"] = !model.briefings.currentEmails(model).contains{$0.0.id == message.id}
        checks["date-clarified actionable assessment also invalidates withdrawn life relevance"] = model.emailSummaries.highlights(model).first{$0.0.id == taskMail.id}!.1.adviceRevision(replied:false) != taskAssessment
        model.mailData = .init(messages:[message],accounts:model.mailData.accounts,errors:[])
        try model.emailSummaries.seedAdviceFixture([summary])
        let beforePreference=model.reviewAcknowledgementRevision
        let preference=ReviewRelevancePreference(registration:registration,topic:"Orion prototype",direction:"more")
        try model.emailSummaries.savePreference(preference,expected:nil,model:model)
        let savedPreference=model.emailSummaries.relevancePreferences.first{$0.id == preference.id}!
        checks["explicit relevance preference changes advice context and matches its topic"] = model.reviewAcknowledgementRevision != beforePreference && model.emailSummaries.preferences(registration,query:"Orion update").count == 1 && model.emailSummaries.preferences(registration,query:"Unrelated shopping discount").isEmpty
        var outdatedPreference=savedPreference;outdatedPreference.topic="Earlier overwrite"
        do {try model.emailSummaries.savePreference(outdatedPreference,expected:preference,model:model);checks["stale preference editor cannot overwrite current receipt"]=false} catch {checks["stale preference editor cannot overwrite current receipt"]=true}
        var anotherOwner=ReviewRelevancePreference(registration:"fictional-other",topic:"Private",direction:"less")
        do {try model.emailSummaries.savePreference(anotherOwner,expected:nil,model:model);checks["preference account ownership is captured"]=false} catch {checks["preference account ownership is captured"]=true}
        anotherOwner.registration=registration
        try model.emailSummaries.undoPreference(model)
        checks["preference Undo restores original attention and human-choice stamp"] = model.emailSummaries.preferences(registration).isEmpty && model.reviewAcknowledgementRevision == beforePreference
        let isolated=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let preferenceStore=EmailSummaryService(container:isolated)
        try preferenceStore.savePreference(preference,expected:nil,model:model)
        let reopened=EmailSummaryService(container:isolated)
        checks["explicit preferences reopen from independent saved storage"] = reopened.preferences(registration).map(\.topic) == [preference.topic]
        let maximum=(0..<40).map{ReviewRelevancePreference(registration:registration,topic:"Fictional topic \($0)",direction:"less")}
        var inactive=preference;inactive.inactive=true
        let cache=try isolated.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first{$0.key == "reviewRelevancePreferences"}!
        cache.data=try JSONEncoder().encode(maximum+[inactive]);try isolated.mainContext.save()
        let full=EmailSummaryService(container:isolated)
        var restored=inactive;restored.inactive=false
        do {try full.savePreference(restored,expected:inactive,model:model);checks["restoring preference cannot exceed current attention bound"]=false} catch {checks["restoring preference cannot exceed current attention bound"]=full.preferences(registration).count == 40}
        let invalidBytes=try JSONEncoder().encode([preference,preference]);cache.data=invalidBytes;try isolated.mainContext.save()
        let invalid=EmailSummaryService(container:isolated)
        checks["invalid saved preferences are blocked and preserved without exposure"] = !invalid.relevanceReadable && invalid.preferences(registration).isEmpty && cache.data == invalidBytes
        return ["completed":Date.now.ISO8601Format(),"requests":0,"passed":checks.values.filter{$0}.count,"total":checks.count,"checks":checks,"storage":"Fictional claims, messages and outputs in disposable SwiftData before source startup. No inference, native writes, permission changes or personal store writes. This tests actual consumer projections, not scheduler races or real message delivery."]
    }
}
#endif
