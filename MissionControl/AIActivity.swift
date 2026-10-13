import Foundation
import Observation

/// Saved output for the human to inspect. These records never authorise or replay work.
enum AIActivityKind: String, Codable, CaseIterable {
    case chat, review, heartbeat, feedback
    var title: String {
        switch self {
        case .chat: "3PO chat"
        case .review: "Review"
        case .heartbeat: "Heartbeat"
        case .feedback: "Feedback"
        }
    }
}

enum AIActivityStatus: String, Codable, CaseIterable {
    case queued, running, succeeded, partial, failed, stopped, interrupted, needsAnswer, uncertain
    var title: String {
        switch self {
        case .queued: "Queued"
        case .running: "Working"
        case .succeeded: "Completed"
        case .partial: "Partly completed"
        case .failed: "Failed"
        case .stopped: "Stopped"
        case .interrupted: "Interrupted"
        case .needsAnswer: "Needs your answer"
        case .uncertain: "Outcome unconfirmed"
        }
    }
    var isTerminal: Bool { self != .queued && self != .running }
    var needsAttention: Bool {
        [.partial, .failed, .interrupted, .needsAnswer, .uncertain].contains(self)
    }
    var symbol: String {
        switch self {
        case .queued: "clock"
        case .running: "sparkles"
        case .succeeded: "checkmark.circle.fill"
        case .partial, .failed, .interrupted, .uncertain: "exclamationmark.circle.fill"
        case .stopped: "stop.circle"
        case .needsAnswer: "questionmark.circle.fill"
        }
    }
}

/// Navigation hints are exact local targets, never instructions to infer or mutate.
enum AIActivityDestination: Codable, Equatable {
    case assistant(targetID: String? = nil)
    case review(targetID: String? = nil)
    case heartbeat(targetID: String? = nil)
    case project(targetID: String? = nil)
    case calendar(targetID: String? = nil)
    case reminders(targetID: String? = nil)
    case feedback(targetID: String? = nil)

    var targetID: String? {
        switch self {
        case .assistant(let id), .review(let id), .heartbeat(let id), .project(let id),
             .calendar(let id), .reminders(let id), .feedback(let id): id
        }
    }
    var title: String {
        switch self {
        case .assistant: "Open chat"
        case .review: "Open Review conversation"
        case .heartbeat: "Open heartbeat"
        case .project: "View project"
        case .calendar: "View Calendar"
        case .reminders: "View Reminders"
        case .feedback: "View feedback"
        }
    }
    var symbol: String {
        switch self {
        case .assistant: "bubble.left.and.bubble.right"
        case .review: "tray"
        case .heartbeat: "waveform.path.ecg"
        case .project: "folder"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .feedback: "text.bubble"
        }
    }
}

struct AIActivityRecord: Codable, Equatable, Identifiable {
    var id: String
    var registration: String
    var kind: AIActivityKind
    var state: AIActivityStatus
    var title: String
    var message: String
    var progress: Double?
    var created: Date
    var finished: Date?
    var destination: AIActivityDestination?
    var acknowledged: Bool

    init(id: String, registration: String, kind: AIActivityKind, state: AIActivityStatus,
         title: String, message: String, progress: Double? = nil, created: Date = .now,
         finished: Date? = nil, destination: AIActivityDestination? = nil, acknowledged: Bool = false) {
        self.id = id; self.registration = registration; self.kind = kind; self.state = state
        self.title = title; self.message = message; self.progress = progress; self.created = created
        self.finished = finished; self.destination = destination; self.acknowledged = acknowledged
    }
    var needsAttention: Bool { state.needsAttention && !acknowledged }
    var date: Date { finished ?? created }
}

struct AIActivityState: Codable, Equatable {
    var version = 1
    var records: [AIActivityRecord] = []
}

@MainActor @Observable final class AIActivityStore {
    private(set) var state = AIActivityState()
    private(set) var readable = true
    private(set) var error: String?
    var readOnly: Bool { !readable }
    @ObservationIgnored private let persist: (Data) throws -> Void
    private var acknowledgements: [String: AcknowledgementUndo] = [:]
    private struct AcknowledgementUndo {
        var id: String
        var created: Date
    }

    init(load: () throws -> Data? = { nil }, persist: @escaping (Data) throws -> Void = { _ in }) {
        self.persist = persist
        do {
            guard let data = try load() else { return }
            try Self.validateShape(data)
            let saved = try JSONDecoder().decode(AIActivityState.self, from: data)
            try Self.validate(saved)
            state = saved
        } catch {
            readable = false
            self.error = "Saved AI activity could not be read. Its original record is preserved; changes are disabled."
            return
        }
        // Reopening is a display recovery only. It never resumes or repeats a job.
        var recovered = state
        for index in recovered.records.indices where recovered.records[index].state == .running {
            recovered.records[index].state = .interrupted
            recovered.records[index].finished = max(.now, recovered.records[index].created)
            recovered.records[index].progress = nil
        }
        guard recovered != state else { return }
        do { try save(recovered) }
        catch {
            // Show the interruption even if storage cannot record it, retaining original bytes.
            state = recovered; readable = false
            self.error = "AI activity was interrupted, but recovery could not be saved. The original record is preserved; no work was replayed."
        }
    }

    func records(_ registration: String) -> [AIActivityRecord] {
        state.records.filter { $0.registration == registration }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.created != $1.created { return $0.created > $1.created }
            return $0.id < $1.id
        }
    }
    func latest(_ registration: String) -> AIActivityRecord? { records(registration).first }
    func undoDate(_ registration: String) -> Date? { acknowledgements[registration]?.created }
    func undoLabel(_ registration: String) -> String? {
        acknowledgements[registration] == nil ? nil : "Undo AI activity acknowledgement"
    }

    @discardableResult func upsert(_ record: AIActivityRecord) -> Bool {
        guard readable else { return false }
        var candidate = state
        if let index = candidate.records.firstIndex(where: { $0.id == record.id && $0.registration == record.registration }) {
            let old = candidate.records[index]
            guard old.created == record.created, old.kind == record.kind else {
                error = "This AI activity has a different captured identity; its saved record was preserved."
                return false
            }
            var updated = record
            updated.acknowledged = old.acknowledged
            candidate.records[index] = updated
        } else { candidate.records.append(record) }
        return commit(candidate)
    }

    @discardableResult func acknowledge(_ id: String, registration: String) -> Bool {
        guard readable, let index = state.records.firstIndex(where: { $0.id == id && $0.registration == registration }),
              state.records[index].state.isTerminal, !state.records[index].acknowledged else { return false }
        var candidate = state; candidate.records[index].acknowledged = true
        guard commit(candidate) else { return false }
        acknowledgements[registration] = .init(id: id, created: .now)
        return true
    }

    @discardableResult func undoAcknowledgement(_ registration: String) -> Bool {
        guard readable, let undo = acknowledgements[registration],
              let index = state.records.firstIndex(where: { $0.id == undo.id && $0.registration == registration }),
              state.records[index].acknowledged else { return false }
        var candidate = state; candidate.records[index].acknowledged = false
        guard commit(candidate) else { return false }
        acknowledgements.removeValue(forKey: registration)
        return true
    }

    private func commit(_ candidate: AIActivityState) -> Bool {
        guard candidate != state else { return true }
        do { try Self.validate(candidate); try save(candidate); error = nil; return true }
        catch { self.error = "AI activity could not be saved. Its previous history is preserved."; return false }
    }
    private func save(_ candidate: AIActivityState) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try persist(encoder.encode(candidate))
        state = candidate
    }
    private enum StorageFailure: Error { case invalid, unknown }
    private static func validate(_ state: AIActivityState) throws {
        guard state.version == 1 else { throw StorageFailure.unknown }
        var keys = Set<String>()
        for record in state.records {
            let key = record.registration + "\u{0}" + record.id
            guard !record.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !record.registration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !record.id.contains("\u{0}"), !record.registration.contains("\u{0}"), keys.insert(key).inserted,
                  !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.created.timeIntervalSince1970.isFinite,
                  record.finished.map({ $0.timeIntervalSince1970.isFinite && $0 >= record.created }) ?? true,
                  record.progress.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
                  record.destination?.targetID.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true
            else { throw StorageFailure.invalid }
        }
    }
    /// Unknown fields remain untouched instead of being lost through a Codable round-trip.
    private static func validateShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys).isSubset(of: ["version", "records"]), let records = root["records"] as? [[String: Any]]
        else { throw StorageFailure.unknown }
        let recordKeys: Set<String> = ["id", "registration", "kind", "state", "title", "message", "progress", "created", "finished", "destination", "acknowledged"]
        let destinationKeys: Set<String> = ["assistant", "review", "heartbeat", "project", "calendar", "reminders", "feedback"]
        for record in records {
            guard Set(record.keys).isSubset(of: recordKeys) else { throw StorageFailure.unknown }
            if let destination = record["destination"], !(destination is NSNull) {
                guard let value = destination as? [String: Any], value.count == 1,
                      let name = value.keys.first, destinationKeys.contains(name),
                      let fields = value[name] as? [String: Any], Set(fields.keys).isSubset(of: ["targetID"])
                else { throw StorageFailure.unknown }
            }
        }
    }
}
