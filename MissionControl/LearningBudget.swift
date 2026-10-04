import Foundation
import Observation
import SwiftData

struct LearningBudgetProgress:Codable {
    var day=""
    var attempts=0
    var lastAttempt:Date?
}
enum LearningBudgetRules {
    static func allowed(_ progress:LearningBudgetProgress,now:Date)->Bool {
        (progress.day != BriefingRules.day(now) || progress.attempts < 4) && now.timeIntervalSince(progress.lastAttempt ?? .distantPast) >= 1800
    }
}
/// Shared across conversation learning, notebook organisation and optional source learning.
/// Foreground requests, briefs and proactive suggestions keep their own existing bounds.
@MainActor @Observable final class LearningBudget {
    private var accounts:[String:LearningBudgetProgress]=[:]
    private let container:ModelContainer?
    private var readable=true
    init(container:ModelContainer?) {
        self.container=container
        do {
            if let saved=try container?.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first(where:{$0.key == "paCombinedLearningBudget"}) { accounts=try JSONDecoder().decode([String:LearningBudgetProgress].self,from:saved.data) }
        } catch { readable=false }
    }
    func claim(_ registration:String,manual:Bool,now:Date = .now)->Bool {
        guard readable,!registration.isEmpty else { return false }
        if manual { return true }
        let prior=accounts
        var value=accounts[registration] ?? .init()
        guard LearningBudgetRules.allowed(value,now:now),let container else { return false }
        if value.day != BriefingRules.day(now) { value.day=BriefingRules.day(now);value.attempts=0 }
        value.attempts += 1;value.lastAttempt=now;accounts[registration]=value
        do {
            let context=container.mainContext,data=try JSONEncoder().encode(accounts)
            if let saved=try context.fetch(FetchDescriptor<CachedDashboard>()).first(where:{$0.key == "paCombinedLearningBudget"}) { saved.data=data;saved.updated=now }
            else { context.insert(CachedDashboard(key:"paCombinedLearningBudget",data:data)) }
            try context.save();return true
        } catch { accounts=prior;container.mainContext.rollback();return false }
    }
}
