import Foundation
import CryptoKit

/// Request-local projections. Stored references point to canonical records; no second source archive.
struct ContextKnowledgeRecord {
    var reference: ContextPageReference
    var title: String
    var text: String
    var date: Date
    var areas: [LifeArea] = []
    var memoryID: UUID? = nil
    var projectID: UUID? = nil
    var relevance: String? = nil
    var input: [String: String] {
        var value = ["id": reference.contextKey, "revision": reference.revision, "title": title,
                     "text": text, "observed": date.ISO8601Format()]
        if let relevance { value["relevance"] = relevance }
        return value
    }
}
extension ContextPageReference {
    var contextKey: String { kind + ":" + key }
}
enum ContextKnowledgeRules {
    static func bytePrefix(_ text: String, maximumBytes: Int) -> String {
        var result = "", count = 0
        for character in text {
            let value = String(character), bytes = value.utf8.count
            guard count + bytes <= maximumBytes else { break }
            result += value; count += bytes
        }
        return result
    }
    static func projectText(title: String, kind: String, notes: String, status: String, due: String?, parent: String?, scope: String) -> String {
        "Title: \(title)\nKind: \(kind)\nStatus: \(status)\nDue: \(due ?? "None recorded")\nParent identity: \(parent ?? "Root")\nContext: \(scope)\nHuman project notes:\n\(notes)"
    }
    static func actionText(confirmed: Int, receipts: [String]) -> String {
        "Verified historical app operations: \(confirmed). This records the app operation only, not real-world completion.\n" + receipts.joined(separator: "\n")
    }
    static func excerpt(_ text: String, offset: Int, limit: Int) -> (text: String, next: Int?, total: Int) {
        let start = min(max(0, offset), text.count)
        let value = String(text.dropFirst(start).prefix(max(0, limit)))
        let end = start + value.count
        return (value, end < text.count ? end : nil, text.count)
    }
    static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func json(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    static func current(_ references: [ContextPageReference], records: [ContextKnowledgeRecord]) -> Bool {
        let current = Dictionary(records.map { ($0.reference.contextKey, $0.reference.revision) }, uniquingKeysWith: { first, _ in first })
        return references.allSatisfy { current[$0.contextKey] == $0.revision }
    }
    static func matches(_ query: String?, title: String, synopsis: String, key: String, selfLabel: String = "") -> Bool {
        guard let query else { return true }
        let terms = MemoryRetrieval.queryTerms(query, selfLabel: selfLabel)
        return !terms.isDisjoint(with: MemoryRetrieval.tokens(title + " " + synopsis + " " + key))
    }
    /// Retrieval candidates only; lexical overlap never establishes project ownership or plan identity.
    static func projectCandidate(_ record: ContextKnowledgeRecord, title: String, notes: String, selfLabel: String = "") -> Bool {
        guard record.reference.kind == "human" || record.reference.kind == "whatsapp" || record.reference.kind.hasPrefix("native-") else { return false }
        let titleTerms = MemoryRetrieval.queryTerms(title, selfLabel: selfLabel).filter { $0.count >= 3 }
        let textTerms = MemoryRetrieval.tokens(record.text + " " + record.title)
        let overlap = titleTerms.intersection(textTerms)
        if overlap.count >= 2 || (titleTerms.count == 1 && overlap.first.map { $0.count >= 5 } == true) { return true }
        let noteTerms = MemoryRetrieval.tokens(notes).filter { $0.count >= 5 }
        return !overlap.isEmpty && noteTerms.intersection(textTerms).count >= 2
    }
}

