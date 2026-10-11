import Foundation

/// Read-only native context boundary. Writing remains on the guarded EventKit APIs.
protocol NativeSourceReading {
    func calendar(from start: Date, to end: Date) async throws -> CalendarSnapshot
    func reminders() async throws -> ReminderSnapshot
    func completedReminders(excluded: Set<String>, now: Date) async throws -> [CompletedReminder]
}

extension NativeSourceReading {
    func completedReminders(excluded: Set<String>) async throws -> [CompletedReminder] {
        try await completedReminders(excluded: excluded, now: .now)
    }
}

enum NativeSourceReadError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let source):
            return "\(source) did not return a result. Refresh to try again."
        }
    }
}

enum NativeSourceRead {
    /// EventKit supplies nil for an unavailable result, whereas an empty array is
    /// a successful read. Keep that distinction before building any snapshot.
    static func requireSnapshot<Snapshot>(_ value: Snapshot?, source: String) throws -> Snapshot {
        guard let value else { throw NativeSourceReadError.unavailable(source) }
        return value
    }

    static func fetchSnapshot<Snapshot>(source: String, fetch: (@escaping (Snapshot?) -> Void) -> Void) async throws -> Snapshot {
        try Task.checkCancellation()
        let value: Snapshot = try await withCheckedThrowingContinuation { continuation in
            fetch { result in
                continuation.resume(with: Result { try requireSnapshot(result, source: source) })
            }
        }
        try Task.checkCancellation()
        return value
    }
}

/// A refresh replaces data only after a successful read. Consumers retain the
/// cached snapshot on failure, while health prevents it being used as fresh evidence.
struct NativeSourceCollection<Snapshot> {
    var snapshot: Snapshot
    var health: SourceHealth

    func collecting(read: () async throws -> Snapshot, now: () -> Date = { .now }) async -> Self {
        var updated = self
        do {
            try Task.checkCancellation()
            let value = try await read()
            try Task.checkCancellation()
            updated.snapshot = value
            updated.health = .init(lastSuccess: now())
        } catch {
            updated.health.loading = false
            updated.health.error = error is CancellationError ? "Refresh cancelled; previous data is retained." : error.localizedDescription
        }
        return updated
    }
}
