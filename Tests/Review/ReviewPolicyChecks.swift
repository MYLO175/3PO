import Foundation

/// Fictional storage and completed classifier results; no personal sources or model-quality claim.
enum ReviewPolicyChecks {
    @MainActor static func run() throws {
        var data: Data?
        var writes = 0
        func store() -> ReviewPolicyStore {
            ReviewPolicyStore(load: {data}, persist: {next, expected in
                guard expected == data else {throw SummaryFailure.invalid}
                data = next; writes += 1
            })
        }
        let first = store(), original = first.policy("owner")
        precondition(original.isDefault && original.text == ReviewPolicyRules.defaultText && writes == 0)
        precondition(first.policy("other").registration == "other" && first.history("owner").isEmpty)
        let global = "Only surface direct personal requests, deadlines and changes to existing commitments; routine broadcasts stay quiet."
        precondition(first.save(global, registration: "owner", expected: original))
        let saved = first.policy("owner")
        precondition(saved.text == global && !saved.isDefault && saved.revision != original.revision)
        // Stage policy is present independently of words, examples, facts or source retrieval.
        precondition(saved.input["text"] == global && saved.input["revision"] == saved.revision)
        precondition(!first.save("Stale", registration: "owner", expected: original))
        precondition(!first.save("Other account", registration: "other", expected: saved))
        precondition(!first.save(" ", registration: "owner", expected: saved))
        precondition(!first.save(String(repeating: "a", count: ReviewPolicyRules.textLimit + 1), registration: "owner", expected: saved))
        let reopened = store()
        precondition(reopened.policy("owner") == saved && reopened.policy("other").isDefault)
        precondition(first.reset("owner", expected: saved))
        let reset = first.policy("owner")
        precondition(reset.isDefault && reset.text == original.text && reset.revision != original.revision)
        let earlier = first.history("owner").last!
        precondition(first.restore(earlier, expected: reset))
        let restored = first.policy("owner")
        precondition(restored.text == saved.text && restored.revision != saved.revision && first.history("owner").first?.restoredFrom == earlier.id)
        precondition(first.history("owner").count == 3)
        precondition(!first.restore(earlier, expected: first.policy("other")))
        // Another writer is detected against the exact persisted record before overwrite.
        let independent = store(), beforeIndependent = independent.policy("owner")
        precondition(independent.save("Show robotics results.", registration: "owner", expected: beforeIndependent))
        precondition(!first.save("Do not overwrite newer edits", registration: "owner", expected: restored))
        precondition(first.policy("owner") == independent.policy("owner"))
        let corrupt = Data("{broken legacy state".utf8)
        var corruptWrites = 0
        let blocked = ReviewPolicyStore(load: {corrupt}, persist: {_, _ in corruptWrites += 1})
        precondition(!blocked.readable && !blocked.save(global, registration: "owner", expected: blocked.policy("owner")) && corruptWrites == 0)
        let readOnly = ReviewPolicyStore(load: {nil}, persist: nil)
        precondition(!readOnly.writable && !readOnly.save(global, registration: "owner", expected: readOnly.policy("owner")))
        let failedData: Data? = nil
        let failure = ReviewPolicyStore(load: {failedData}, persist: {_, _ in throw SummaryFailure.invalid})
        precondition(!failure.save(global, registration: "owner", expected: failure.policy("owner")) && failure.history("owner").isEmpty && failedData == nil)
        let mismatch = ReviewPolicyStore(load: {nil}, persist: {_, _ in})
        precondition(!mismatch.save(global, registration: "owner", expected: mismatch.policy("owner")) && !mismatch.readable)

        // The complete guide is global, includes its tail, and never needs original feedback.
        var guideData: Data?
        func guideStore() -> ReviewPolicyStore {
            ReviewPolicyStore(load: {guideData}, persist: {next, expected in
                guard expected == guideData else { throw SummaryFailure.invalid }
                guideData = next
            })
        }
        func rule(_ text: String, id: String = UUID().uuidString) -> ReviewGuidancePreference {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(dependency: .init(id: id, fingerprint: MemoryDependencyRules.fingerprint(["id": id, "text": trimmed])), text: trimmed)
        }
        let guide = guideStore()
        var rules = (0..<18).map { rule("Priority \($0): " + String(repeating: "Keep the distinct fictional topic and its conditions. ", count: 10)) }
        let complete = guide.policy("owner", preferences: rules)
        precondition(complete.text.count > 6000 && rules.allSatisfy { complete.text.contains($0.text) } && !complete.isDefault)
        precondition(guide.needsConsolidation("owner", preferences: rules) && guide.history("owner").isEmpty)
        let merged = "# What matters to me\n\n" + rules.map(\.text).joined(separator: "\n\n")
        precondition(guide.save(merged, registration: "owner", expected: complete, preferences: rules, consolidate: true))
        let synthesised = guide.policy("owner", preferences: rules)
        precondition(synthesised.text == merged && !guide.needsConsolidation("owner", preferences: rules))
        precondition(guideStore().policy("owner", preferences: rules) == synthesised && guide.history("owner").first?.consolidatedFrom?.preferences.count == 18)
        precondition(guide.policy("other", preferences: []).isDefault && guide.policy("owner").isDefault)
        let disabled = guide.policy("owner", preferences: Array(rules.dropLast()))
        precondition(!disabled.text.contains(rules.last!.text) && !guide.matches(synthesised, preferences: Array(rules.dropLast())))
        let originalRule = rules[0]
        rules[0] = rule("A corrected fictional rule replaces the earlier preference.", id: originalRule.dependency.id)
        let correctedGuide = guide.policy("owner", preferences: rules)
        precondition(correctedGuide.text.contains(rules[0].text) && !correctedGuide.text.contains(originalRule.text))
        precondition(!guide.save("Stale synthesis", registration: "owner", expected: synthesised, preferences: rules, consolidate: true))
        let edited = "Show only my explicitly edited fictional priorities."
        precondition(guide.save(edited, registration: "owner", expected: correctedGuide, preferences: rules))
        precondition(guide.policy("owner", preferences: rules).text == edited && !guide.needsConsolidation("owner", preferences: rules))
        let pausedEdit = edited + " Keep the wording concise."
        precondition(guide.save(pausedEdit, registration: "owner", expected: guide.policy("owner")))
        precondition(guide.policy("owner", preferences: rules).text == pausedEdit, "Editing with memory paused cannot resurrect earlier removed rules")
        let hiddenEdit = pausedEdit + " Preserve the specific scope."
        precondition(guide.save(hiddenEdit, registration: "owner", expected: guide.policy("owner", preferences: Array(rules.dropLast())), preferences: Array(rules.dropLast())))
        precondition(guide.policy("owner", preferences: rules).text == hiddenEdit, "Re-enabling a disabled rule cannot undo a deliberate human edit")
        rules.append(rule("Also prioritise the newly learned fictional result."))
        let later = guide.policy("owner", preferences: rules)
        precondition(later.text.contains(hiddenEdit) && later.text.contains(rules.last!.text) && !later.text.contains(rules[1].text))
        precondition(guide.policy("owner").text == hiddenEdit, "Pausing memory keeps explicit human edits")
        let decodedGuide = try ReviewGuidanceRules.decode(String(decoding: JSONSerialization.data(withJSONObject: ["text": merged]), as: UTF8.self))
        precondition(decodedGuide == merged)
        for malformed in ["{}", "{\"text\":\"\"}", "{\"text\":\"ok\",\"other\":true}"] {
            do { _ = try ReviewGuidanceRules.decode(malformed); preconditionFailure("Invalid guidance admitted") } catch {}
        }

        // Negative decisions retain every supplied Review preference, not a generated summary's subset.
        let preference: [String: String] = ["id": UUID().uuidString, "purpose": "review preference", "text": "Routine university broadcasts can stay quiet.", "reviewAbout": "University newsletters"]
        let unrelated: [String: String] = ["id": UUID().uuidString, "text": "I study robotics."]
        let receipt = EmailReviewContextReceipt(policy: saved, memories: [preference, unrelated], discoveryRevision: nil)
        precondition(receipt.preferences == MemoryDependencyRules.capture([preference]))
        precondition(receipt.policy.matches(saved) && !receipt.policy.matches(reset))
        precondition(!ReviewPolicyRules.assessmentContextMatches(nil,policy:saved,discoveryRevision:nil),"Two absent legacy stamps do not prove the global policy actually used")
        precondition(!ReviewPolicyRules.assessmentContextMatches(nil,policy:saved,discoveryRevision:"legacy-feedback"),"Legacy feedback stamps alone cannot make an uncaptured policy current")
        precondition(ReviewPolicyRules.assessmentContextMatches(receipt,policy:saved,discoveryRevision:nil),"A real policy capture remains current with an intentionally empty discovery selection")
        precondition(!ReviewPolicyRules.assessmentContextMatches(receipt,policy:reset,discoveryRevision:nil),"Changed policy invalidates the exact captured assessment context")
        var discovered=receipt;discovered.discoveryRevision="selected-feedback-v1"
        precondition(ReviewPolicyRules.assessmentContextMatches(discovered,policy:saved,discoveryRevision:"selected-feedback-v1"))
        precondition(!ReviewPolicyRules.assessmentContextMatches(discovered,policy:saved,discoveryRevision:"selected-feedback-v2"),"New applicable feedback schedules reconsideration")
        precondition(MemoryDependencyRules.available(receipt.preferences, records: [preference, unrelated]))
        var corrected = preference; corrected["text"] = "Prioritise these broadcasts."
        precondition(!MemoryDependencyRules.available(receipt.preferences, records: [corrected, unrelated]))
        precondition(!MemoryDependencyRules.available(receipt.preferences, records: [unrelated]))
        let negative = EmailHeaderDecision(id: "quiet", registration: "owner", fingerprint: "f", received: .now, readBody: false, reviewContext: receipt)
        let reopenedNegative = try JSONDecoder().decode(EmailHeaderDecision.self, from: JSONEncoder().encode(negative))
        precondition(!reopenedNegative.readBody && reopenedNegative.reviewContext == receipt)

        let fields: [String: Any] = ["id": "fixture", "accountID": "fictional-mail", "account": "Fictional", "messageID": 1, "internetMessageID": "fixture@example.invalid", "sender": "Campus round-up <news@example.invalid>", "subject": "Activities around Cambridge", "received": "2026-10-21T09:00:00Z", "unread": true, "replied": false, "flagged": false]
        let message = try JSONDecoder().decode(MailMessage.self, from: JSONSerialization.data(withJSONObject: fields))
        func assessment(_ quote: String, attention: Bool = false, additional: [String: Any] = [:], context: EmailRelevanceContext = .init(), policy: ReviewPolicyCapture = original) throws -> EmailSummary {
            var output: [String: Any] = ["summary": "Fictional email", "attention": attention, "worthReading": true, "needsReply": false, "reason": attention ? "A direct personal request requires a decision." : "", "evidence": quote]
            output.merge(additional) {_, next in next}
            return try EmailSummary.decode(String(decoding: JSONSerialization.data(withJSONObject: output), as: UTF8.self), message: message, body: quote, registration: "owner", relevanceContext: context, reviewPolicy: policy)
        }
        let broadcast = try assessment("Explore societies, talks and exhibitions this week.")
        let promotion = try assessment("Save 20% before 31 October 2026.", additional: ["followUpDate": "2026-10-31", "followUpEvidence": "31 October 2026"])
        precondition(broadcast.worthReading == false && !EmailHighlightRules.needsReview(broadcast, replied: false))
        precondition(promotion.worthReading == false && promotion.followUpDate == nil && !EmailHighlightRules.visible(promotion))
        let direct = try assessment("Please confirm your interview attendance by 23 October.", attention: true)
        let changed = try assessment("Your booked interview has moved to 24 October.", attention: true)
        precondition(direct.attention && changed.attention && EmailHighlightRules.needsReview(direct, replied: false))
        let projectID = "life:" + UUID().uuidString
        let context = EmailRelevanceContext(workspace: [["id": projectID, "revision": UUID().uuidString, "title": "Robotics project"]])
        let quote = "New robotics dataset and evaluation results are available."
        let relevant = try assessment(quote, additional: ["personalRelevance": ["reason": "Evaluation data for the current robotics project", "evidence": quote, "workspaceIDs": [projectID]]], context: context)
        precondition(relevant.worthReading == true && !relevant.attention && relevant.personalRelevance?.workspace.first?.id == projectID)
        // Reproduce the model fixture's results case: exact source text alone is quiet,
        // while a citation to the supplied canonical feedback supports informational reading.
        let resultsQuote="Your fictional coding assessment results are ready to read."
        let resultsPreference:[String:String]=["id":UUID().uuidString,"purpose":"review preference","text":"Coding assessment results are important to me.","reviewAbout":"Coding assessment stages and results"]
        let resultsContext=EmailRelevanceContext(memories:[resultsPreference],memoryReceipts:MemoryDependencyRules.capture([resultsPreference]))
        var rawPreference = resultsPreference; rawPreference["reviewFeedback"] = "ORIGINAL_FEEDBACK_MARKER"; rawPreference["reviewInterpretation"] = "INTERPRETATION_MARKER"
        let routineInput = String(decoding: try JSONSerialization.data(withJSONObject: EmailRelevanceContext(memories:[rawPreference]).input), as: UTF8.self)
        precondition(!routineInput.contains("ORIGINAL_FEEDBACK_MARKER") && !routineInput.contains("INTERPRETATION_MARKER") && !routineInput.contains(resultsPreference["id"]!))
        let missingCitation=try assessment(resultsQuote,context:resultsContext)
        precondition(missingCitation.worthReading == false && missingCitation.personalRelevance == nil,"An uncited worthReading claim is not admitted just because positive feedback was supplied")
        let resultsRelevance:[String:Any]=["reason":"The human explicitly prioritises assessment results.","evidence":resultsQuote,"memoryIDs":[resultsPreference["id"]!]]
        let citedResults=try assessment(resultsQuote,additional:["personalRelevance":resultsRelevance],context:resultsContext)
        precondition(citedResults.worthReading == true && !citedResults.attention && citedResults.personalRelevance?.memories == resultsContext.memoryReceipts)
        for ids:[String:Any] in [["memoryIDs":[UUID().uuidString]],["preferenceIDs":[resultsPreference["id"]!]],["memoryIDs":[]]] {
            let invalidRelevance:[String:Any]=["reason":"The human explicitly prioritises assessment results.","evidence":resultsQuote].merging(ids){_,next in next}
            do {_ = try assessment(resultsQuote,additional:["personalRelevance":invalidRelevance],context:resultsContext);preconditionFailure("Unsupplied, misclassified or empty feedback citation admitted")}
            catch SummaryFailure.unsupportedEvidence {}
        }
        let humanPolicy = ReviewPolicyCapture(registration: "owner", revision: UUID().uuidString, text: "Show substantive robotics research results even when no action is required.", isDefault: false)
        let policyMatch: [String: Any] = ["reason": "The explicitly prioritised research results arrived.", "policyQuote": humanPolicy.text, "sourceQuote": quote]
        let priority = try assessment(quote, additional: ["policyRelevance": policyMatch], policy: humanPolicy)
        precondition(priority.worthReading == true && priority.policyRelevance?.policy?.matches(humanPolicy) == true && !priority.attention)
        let learnedPolicy = guide.policy("owner", preferences: rules)
        let learnedMatch: [String: Any] = ["reason": "A result explicitly prioritised in the complete guide arrived.", "policyQuote": rules.last!.text, "sourceQuote": resultsQuote]
        let learnedPriority = try assessment(resultsQuote, additional: ["policyRelevance": learnedMatch], policy: learnedPolicy)
        precondition(learnedPriority.worthReading == true && learnedPriority.policyRelevance?.policy?.matches(learnedPolicy) == true)
        var invalid = policyMatch; invalid["policyQuote"] = "Invented sender priority"
        do {_ = try assessment(quote, additional: ["policyRelevance": invalid], policy: humanPolicy); preconditionFailure("Invented policy quote accepted")} catch SummaryFailure.unsupportedEvidence {}
        do {_ = try assessment(quote, additional: ["policyRelevance": policyMatch]); preconditionFailure("Default policy used as a positive personal priority")} catch SummaryFailure.unsupportedEvidence {}
        let foreign = ReviewPolicyCapture(registration: "other", revision: humanPolicy.revision, text: humanPolicy.text, isDefault: false)
        do {_ = try assessment(quote, policy: foreign); preconditionFailure("Foreign policy accepted")} catch SummaryFailure.unsupportedEvidence {}
        // A taste alone cannot admit an email; a life fact, project or explicit priority still can.
        let tasteQuote = "The Lantern Quartet play the Riverside Hall next Saturday at 8pm."
        let taste: [String: String] = ["id": UUID().uuidString, "text": "You enjoy jazz concerts.", "kind": "preference"]
        let course: [String: String] = ["id": UUID().uuidString, "text": "You study geology.", "kind": "context"]
        let tasteContext = EmailRelevanceContext(memories: [taste, course], workspace: context.workspace, memoryReceipts: MemoryDependencyRules.capture([taste, course]))
        func cited(_ ids: [String: Any]) throws -> EmailSummary {
            try assessment(tasteQuote, additional: ["personalRelevance": (["reason": "Matches a stated interest", "evidence": tasteQuote] as [String: Any]).merging(ids) {_, next in next}, "followUpDate": "2026-10-31", "followUpEvidence": "next Saturday at 8pm"], context: tasteContext)
        }
        let tasteOnly = try cited(["memoryIDs": [taste["id"]!]])
        precondition(tasteOnly.worthReading == false && tasteOnly.personalRelevance == nil && tasteOnly.followUpDate == nil && !EmailHighlightRules.visible(tasteOnly), "A taste alone leaves the email quiet without rejecting the assessment")
        let lifeFact = try cited(["memoryIDs": [course["id"]!]]), withProject = try cited(["memoryIDs": [taste["id"]!], "workspaceIDs": [projectID]])
        precondition(lifeFact.worthReading == true, "A life fact remains specific support")
        precondition(withProject.worthReading == true, "A current project remains specific support")
        precondition(citedResults.worthReading == true, "An explicit Review priority is not a taste")
        do {_ = try cited(["memoryIDs": [UUID().uuidString]]); preconditionFailure("Unsupplied memory admitted")} catch SummaryFailure.unsupportedEvidence {}
        // Saved informational cards remain persistent data. Older reading judgements wait for the bounded
        // reassessment lane; current ones stay in Review for one week after receipt.
        let received = message.received
        var previous = broadcast; previous.worthReading = true; previous.reviewPolicyVersion = 2
        let previousData = try JSONEncoder().encode(previous)
        let previousReadback = try JSONDecoder().decode(EmailSummary.self, from: previousData)
        precondition(previousReadback.worthReading == true && previousReadback.reviewPolicyVersion == 2 && !EmailHighlightRules.needsReview(previousReadback, replied: false, now: received))
        precondition(EmailHighlightRules.visible(previousReadback, now: received), "Older reading stays eligible for its reassessment")
        var current = previous; current.reviewPolicyVersion = EmailSummary.reviewPolicyVersion
        precondition(EmailHighlightRules.readingExpiry(current) == received.addingTimeInterval(7*86400))
        precondition(EmailHighlightRules.needsReview(current, replied: false, now: received.addingTimeInterval(6*86400)))
        precondition(!EmailHighlightRules.needsReview(current, replied: false, now: received.addingTimeInterval(7*86400)), "Reading leaves Review after a week")
        var olderAction = direct; olderAction.reviewPolicyVersion = 2
        precondition(EmailHighlightRules.needsReview(olderAction, replied: false, now: received.addingTimeInterval(30*86400)), "Action items never expire and stay until reassessed")
        // Suggestions follow the email's verdict: a date alone never feeds the suggestion pass.
        var datedQuiet = previous; datedQuiet.followUpDate = "2026-10-30"
        precondition(!EmailHighlightRules.suggestionSource(datedQuiet, replied: false, heartbeat: true, now: received))
        var datedCurrent = current; datedCurrent.followUpDate = "2026-10-30"
        precondition(EmailHighlightRules.suggestionSource(datedCurrent, replied: false, heartbeat: false, now: received))
        precondition(EmailHighlightRules.suggestionSource(current, replied: false, heartbeat: true, now: received) && !EmailHighlightRules.suggestionSource(current, replied: false, heartbeat: false, now: received))
        precondition(!EmailHighlightRules.suggestionSource(current, replied: false, heartbeat: true, now: received.addingTimeInterval(8*86400)))
        precondition(EmailHighlightRules.suggestionSource(direct, replied: false, heartbeat: false, now: received))
        var withReceipt = priority; withReceipt.reviewContext = receipt
        let readback = try JSONDecoder().decode(EmailSummary.self, from: JSONEncoder().encode(withReceipt))
        precondition(readback.reviewContext == receipt && readback.policyRelevance == priority.policyRelevance)
        precondition(withReceipt.adviceRevision(replied: false) != priority.adviceRevision(replied: false))
        print("PASS Review policy: account ownership, global capture, persistence/CAS/readback, history/reset/restore, exact policy capture rollout, supplied feedback citation requirements, negative feedback receipts, quiet broadcasts/promotions, taste-only relevance, supported opportunities, direct requests/changes, one-week reading cards, verdict-led suggestion sources and preserved saved cards. No AI or source reads.")
    }
}
