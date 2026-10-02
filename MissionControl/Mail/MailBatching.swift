import Foundation

struct MailWindowProgress: Codable, Identifiable, Sendable {
    var id: String
    var accountID: String
    var start: Date
    var end: Date
    var offset = 0
    var messageIDs: [Int]?
    var seenIDs: Set<String> = []
    var complete = false
    var lastSuccess: Date?
}

struct MailBatch: Decodable, Sendable {
    var messages: [MailMessage]
    var messageIDs: [Int]?
    var nextOffset: Int?
    var complete: Bool?
    var errors: [String]
}

struct MailIndexState: Codable {
    var windows: [MailWindowProgress] = []

    mutating func prepare(accounts: [MailAccount], now: Date = .now, calendar: Calendar = .current) {
        let cutoff = now.addingTimeInterval(-30 * 86400)
        let old = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        windows = accounts.flatMap { account -> [MailWindowProgress] in
            var result: [MailWindowProgress] = []
            var day = calendar.startOfDay(for: now)
            while calendar.date(byAdding: .day, value: 1, to: day)! > cutoff {
                let end = calendar.date(byAdding: .day, value: 1, to: day)!
                let id = account.id + "@" + String(day.timeIntervalSince1970)
                var window = old[id] ?? MailWindowProgress(id: id, accountID: account.id, start: max(day, cutoff), end: end)
                window.start = max(day, cutoff)
                window.end = end
                // Refresh recent days each polling cycle. Older days are audited
                // hourly; an interrupted batch keeps its exact ID list and cursor.
                let ageLimit: TimeInterval = end > now.addingTimeInterval(-86400) ? 300 : 3600
                if window.complete, let success = window.lastSuccess, now.timeIntervalSince(success) >= ageLimit {
                    window.complete = false; window.offset = 0; window.messageIDs = nil; window.seenIDs = []
                }
                result.append(window)
                day = calendar.date(byAdding: .day, value: -1, to: day)!
            }
            return result
        }
    }

    mutating func apply(_ batch: MailBatch, to id: String, snapshot: MailSnapshot, now: Date = .now) -> MailSnapshot {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return snapshot }
        windows[index].messageIDs = batch.messageIDs
        windows[index].offset = batch.nextOffset ?? 0
        windows[index].seenIDs.formUnion(batch.messages.map(\.id))
        windows[index].complete = batch.complete == true
        windows[index].lastSuccess = now
        let window = windows[index]
        var records = Dictionary(snapshot.messages.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for message in batch.messages { records[message.id] = message }
        if window.complete {
            records = records.filter { _, message in
                message.accountID != window.accountID || message.received < window.start || message.received >= window.end || window.seenIDs.contains(message.id)
            }
        }
        let enabled = Set(snapshot.accounts.map(\.id))
        return MailSnapshot(messages: records.values.filter { enabled.contains($0.accountID) && $0.received >= now.addingTimeInterval(-30 * 86400) }.sorted { $0.received > $1.received }, accounts: snapshot.accounts, errors: [])
    }

    var pending: Bool { windows.contains { !$0.complete } }
    func coverage(accounts: [MailAccount]) -> String {
        accounts.map { account in
            let days = windows.filter { $0.accountID == account.id }
            return "\(account.title) · \(days.filter(\.complete).count)/\(days.count) days"
        }.joined(separator: "  ·  ")
    }
}

struct MailCheckpoint: Codable {
    var snapshot: MailSnapshot
    var index: MailIndexState
}
