import Foundation

/// One synchronous, read-only pass over many saved items (every email assessment, header
/// decision or pending-source check) reuses identical context projections instead of
/// rebuilding them per item. Rebuilding per item on the main thread stalled the app during
/// heartbeats (1 November). Nothing survives the pass: no await can happen inside it, and
/// the next pass builds from current state again. Do not build an observation-tracked cache
/// (such as the Review inbox projection) inside a pass: a reused value skips the reads that
/// tracking records.
@MainActor final class ContextEvaluationBatch {
    struct KnowledgeRequest: Hashable {
        var registration: String
        var topic: UUID?
        var includeTopics: Bool
        var allowedMemoryIDs: Set<UUID>?
        var includeRecent: Bool
        var retainingReferences: [String: String]
        var retainingReferenceVersions: [String: Set<String>]
        var purpose: ContextKnowledgePurpose
        var mailAccounts: Set<String>?
        var whatsappReady: Bool
    }
    /// A family's receipts are gathered and projected only when the pass first checks one.
    fileprivate final class Pages {
        let family: String
        let registration: String
        private let prepare: () -> (captured: Set<[String: String]>, available: ([String: String]?) -> Bool)
        private lazy var prepared = prepare()
        init(family: String, registration: String, prepare: @escaping () -> (captured: Set<[String: String]>, available: ([String: String]?) -> Bool)) {
            self.family = family; self.registration = registration; self.prepare = prepare
        }
        func availability(_ versions: [String: String]) -> Bool? {
            prepared.captured.contains(versions) ? prepared.available(versions) : nil
        }
    }
    private var values: [AnyHashable: Any]?
    private var pages: Pages?

    fileprivate func withPass<T>(_ body: () -> T) -> T {
        if values != nil { return body() }
        values = [:]; defer { values = nil; pages = nil }
        return body()
    }
    /// Inside a pass an identical request returns the first result; outside one, `build` runs every time.
    func value<T>(_ key: AnyHashable, build: () -> T) -> T {
        guard values != nil else { return build() }
        if let value = values?[key] as? T { return value }
        let value = build(); values?[key] = value; return value
    }
    /// The shared result for a receipt the current page family captured, or nil to check it individually.
    func pageAvailability(_ versions: [String: String]?, registration: String) -> Bool? {
        guard let versions, let pages, pages.registration == registration else { return nil }
        return pages.availability(versions)
    }
    func sharesPages(_ family: String, registration: String) -> Bool {
        pages?.family == family && pages?.registration == registration
    }
    fileprivate func withPages<T>(_ value: Pages, _ body: () -> T) -> T {
        let outer = pages; pages = value; defer { pages = outer }
        return body()
    }
}

extension DashboardModel {
    /// Reuse context projections, native snapshots and the Review policy for one synchronous,
    /// read-only pass. Do not mutate model state inside `body`.
    func withSharedContextEvaluation<T>(_ body: () -> T) -> T {
        nativeLearningValidation.withSnapshot { contextEvaluation.withPass { emailSummaries.withSharedPolicy(body) } }
    }
    /// As above, and every page receipt in the family's `captures` is checked against one projection
    /// per purpose (see `withContextPageAvailability`). Other receipts keep their exact individual
    /// check. A nested pass of the same family reuses the outer projection.
    func withSharedContextPages<T>(_ family: String, registration: String, captures: @escaping () -> [[String: String]], _ body: () -> T) -> T {
        withSharedContextEvaluation {
            guard !contextEvaluation.sharesPages(family, registration: registration) else { return body() }
            // The pages are dropped when the pass ends, so the check needs no separate expiry.
            let pages = ContextEvaluationBatch.Pages(family: family, registration: registration) {
                let receipts = captures()
                return (Set(receipts), self.contextPageAvailability(registration: registration, captures: receipts) { true })
            }
            return contextEvaluation.withPages(pages, body)
        }
    }
}
