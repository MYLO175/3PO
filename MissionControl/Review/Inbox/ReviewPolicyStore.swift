import Foundation
import Observation

/// One readable Review document; human edits and heartbeat consolidation retain version history.
@MainActor @Observable final class ReviewPolicyStore {
    private struct State: Codable, Equatable {var schema = 1; var versions: [ReviewPolicyVersion] = []}
    private var state = State()
    private(set) var readable = true
    private(set) var error: String?
    @ObservationIgnored private let load: () throws -> Data?
    @ObservationIgnored private let persist: ((Data, Data?) throws -> Void)?
    var writable: Bool {readable && persist != nil}
    init(load: @escaping () throws -> Data?, persist: ((Data, Data?) throws -> Void)?) {
        self.load = load; self.persist = persist
        do {if let data = try load() {state = try Self.decode(data)}}
        catch {readable = false; self.error = "Saved Review policy could not be read. Original records are preserved; editing and new Review assessment are unavailable."}
    }
    private static func decode(_ data: Data) throws -> State {
        let value = try JSONDecoder().decode(State.self, from: data)
        guard value.schema == 1, Set(value.versions.map(\.id)).count == value.versions.count,
              value.versions.allSatisfy({!$0.registration.isEmpty && ReviewPolicyRules.validText($0.text)}) else {throw SummaryFailure.invalid}
        return value
    }
    private func base(_ registration: String) -> ReviewPolicyVersion? {
        state.versions.last { $0.registration == registration && $0.consolidatedFrom == nil }
    }
    private func pending(_ registration: String, preferences: [ReviewGuidancePreference]) -> [ReviewGuidancePreference] {
        let included = base(registration)?.includedPreferences ?? []
        return preferences.filter { !included.contains($0.dependency) }
    }
    private func input(_ registration: String, preferences: [ReviewGuidancePreference]) -> ReviewGuidanceInput {
        .init(baseRevision: base(registration)?.id.uuidString ?? ReviewPolicyRules.defaultRevision,
              preferences: pending(registration, preferences: preferences).map(\.dependency).sorted { $0.id < $1.id })
    }
    private func consolidated(_ registration: String, input: ReviewGuidanceInput) -> ReviewPolicyVersion? {
        state.versions.last { $0.registration == registration && $0.consolidatedFrom == input }
    }
    func policy(_ registration: String, preferences: [ReviewGuidancePreference] = []) -> ReviewPolicyCapture {
        let original = base(registration)?.capture ?? .init(registration: registration, revision: ReviewPolicyRules.defaultRevision, text: ReviewPolicyRules.defaultText, isDefault: true)
        let pending = pending(registration, preferences: preferences)
        guard !pending.isEmpty else { return original }
        let input = input(registration, preferences: preferences)
        if let saved = consolidated(registration, input: input) { return saved.capture }
        // Fresh guidance applies immediately, including while synthesis is waiting or failed.
        // Never reuse a synthesis containing a disabled, corrected or unavailable preference.
        var seen = Set<String>()
        let rules = pending.compactMap { preference -> String? in
            let text = preference.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(text).inserted, !original.text.contains(text) else { return nil }
            return text
        }
        let text = ([original.text] + rules).joined(separator: "\n\n")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let revision = MemoryDependencyRules.fingerprint(["base": original.revision, "inputs": String(decoding: (try? encoder.encode(input)) ?? Data(), as: UTF8.self), "text": text])
        return .init(registration: registration, revision: revision, text: text, isDefault: false)
    }
    func needsConsolidation(_ registration: String, preferences: [ReviewGuidancePreference]) -> Bool {
        !pending(registration, preferences: preferences).isEmpty && consolidated(registration, input: input(registration, preferences: preferences)) == nil
    }
    func matches(_ capture: ReviewPolicyCapture, preferences: [ReviewGuidancePreference] = []) -> Bool {
        readable && policy(capture.registration, preferences: preferences) == capture
    }
    func history(_ registration: String) -> [ReviewPolicyVersion] {Array(state.versions.filter {$0.registration == registration}.reversed())}
    @discardableResult func save(_ text: String, registration: String, expected: ReviewPolicyCapture, reset: Bool = false, restoredFrom: UUID? = nil,
                                 preferences: [ReviewGuidancePreference] = [], consolidate: Bool = false) -> Bool {
        guard writable, let persist else {error = error ?? "Review policy storage is unavailable."; return false}
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !registration.isEmpty, expected.registration == registration, matches(expected, preferences: preferences) else {error = "The account or Review guidance changed. Reopen it before saving."; return false}
        guard ReviewPolicyRules.validText(trimmed) else {error = "Write a Review policy of at most \(ReviewPolicyRules.textLimit) characters."; return false}
        if let restoredFrom, !history(registration).contains(where: {$0.id == restoredFrom && $0.text == trimmed}) {error = "That Review policy version is unavailable."; return false}
        var next = state
        var version = ReviewPolicyVersion(registration: registration, text: trimmed, isDefault: reset, restoredFrom: restoredFrom)
        if consolidate {
            guard needsConsolidation(registration, preferences: preferences) else { return true }
            version.consolidatedFrom = input(registration, preferences: preferences)
        } else {
            // Keep prior acknowledgements when a human edits with memory paused or
            // a rule disabled. Re-enabling it must not undo their deliberate edit.
            var included = base(registration)?.includedPreferences ?? []
            for preference in preferences where !included.contains(preference.dependency) { included.append(preference.dependency) }
            if !included.isEmpty { version.includedPreferences = included }
        }
        next.versions.append(version)
        var persisted = false
        do {
            // Check on-disk ownership before overwriting an independently saved version.
            let originalData = try load()
            let current = try originalData.map(Self.decode) ?? State()
            guard current == state else {state = current; error = "The saved Review policy changed. Reopen it before saving."; return false}
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(next)
            try persist(data, originalData)
            persisted = true
            guard try load() == data else {readable = false; error = "Review policy save needs checking. Reopen the app before editing it again."; return false}
            state = next; error = nil; return true
        } catch {if persisted {readable = false}; self.error = "Review policy could not be saved. Your text is still here."; return false}
    }
    @discardableResult func reset(_ registration: String, expected: ReviewPolicyCapture, preferences: [ReviewGuidancePreference] = []) -> Bool {
        save(ReviewPolicyRules.defaultText, registration: registration, expected: expected, reset: true, preferences: preferences)
    }
    @discardableResult func restore(_ version: ReviewPolicyVersion, expected: ReviewPolicyCapture, preferences: [ReviewGuidancePreference] = []) -> Bool {
        guard history(expected.registration).contains(version), version.registration == expected.registration else {error = "That Review policy version belongs to a different account or is unavailable."; return false}
        return save(version.text, registration: expected.registration, expected: expected, reset: version.isDefault, restoredFrom: version.id, preferences: preferences)
    }
}
