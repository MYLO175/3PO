import Foundation
import CryptoKit

/// The experiment is additive. Existing memory records and pages are never migrated.
enum GraphitiMemoryMode: String, Codable, CaseIterable, Identifiable {
    case pages, graphiti, combined
    var id: String { rawValue }
    var title: String {
        switch self { case .pages: "Context pages"; case .graphiti: "Graphiti"; case .combined: "Pages + Graphiti" }
    }
}

struct GraphitiAccountState: Codable, Equatable {
    var mode: GraphitiMemoryMode = .pages
    var learningEnabled = false
    var paused = false
    var references: [String: String] = [:]
    var indexedCount = 0
    var pendingCount = 0
    var updated: Date?
}

enum GraphitiMemoryRules {
    static let maximumEpisodes = 2_000
    static let maximumEpisodeBytes = 12_000
    static let maximumSnapshotBytes = 1_500_000 // Encoded episodes; reserve transport space for request metadata.
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func episodeID(group: String, key: String, revision: String) -> String {
        let hex = String(hash(group + "\u{0}" + key + "\u{0}" + revision).prefix(32))
        return [String(hex.prefix(8)), String(hex.dropFirst(8).prefix(4)), "5" + String(hex.dropFirst(13).prefix(3)), "a" + String(hex.dropFirst(17).prefix(3)), String(hex.suffix(12))].joined(separator: "-")
    }
    static func json(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
    /// Allowlisted policy fields only. Graph-only comparison excludes factual pages,
    /// working changes, directory summaries and the ordinary personal overview.
    static func policyOnly(_ text: String) -> String {
        let value = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        return json(value.filter { ["featureInstructions", "scopeInstructions", "requestedInstruction", "instructionReading", "instructions", "unavailable"].contains($0.key) })
    }
}
