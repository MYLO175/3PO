import Foundation

struct AssistantTranscriptPage {
    var rows: [AssistantTranscriptRow]
    var totalCount: Int
    var threadCount: Int
    var lastThreadTurnID: UUID?
    var lastVisibleTurn: AssistantTurn?
}

struct AssistantChatHistoryEntry: Identifiable {
    var sessionID: UUID?
    var started: Date
    var title: String
    var id: String { sessionID?.uuidString ?? "original" }

    /// Prepared only when opening History; streaming never groups old turns.
    static func entries(_ feed: AssistantConversation?) -> [Self] {
        guard let feed else { return [] }
        let turns = feed.turns.filter { $0.contextID == nil && $0.profileSessionID == nil }
        let groups = Dictionary(grouping: turns, by: \.chatSessionID)
        var sessions: [UUID?: Date] = [nil: feed.created]
        for session in feed.pastChatSessions ?? [] { sessions[session.id] = session.started }
        for (session, turns) in groups where sessions[session] == nil { sessions[session] = turns.compactMap(\.created).min() ?? feed.created }
        return sessions.compactMap { session, started in
            guard session != feed.chatSession?.id else { return nil }
            let turns = groups[session] ?? []
            let prompt = turns.first { $0.role == "user" && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.content
            let title = prompt.map { String($0.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(120)) } ?? (session == nil ? "Original chat" : "Empty chat")
            return .init(sessionID: session, started: started, title: title)
        }.sorted { $0.started == $1.started ? $0.id < $1.id : $0.started > $1.started }
    }
}

/// Stable completed history is prepared only when the owning service changes its
/// transcript revision. Delivery support is checked independently on every read:
/// current permissions/evidence and temporal expiry are never frozen by the cache.
/// Those service reads remain in the caller's SwiftUI/Observation tracking scope.
@MainActor final class AssistantTranscriptProjectionCache {
    private var key: Key?
    private var entries: [Entry] = []
    private var positions: [UUID: Int] = [:]
    private var delivered: [AssistantTurn] = []
    private var visibility: [UUID: Bool] = [:]
    private var rows: [AssistantTranscriptRow] = []
    private(set) var threadBuilds = 0
    private(set) var rowBuilds = 0
    private struct Key: Equatable {
        var owner: ObjectIdentifier
        var revision: UUID
        var registration: String
        var feed: UUID?
        var topic: UUID?
        var session: UUID?
        var filterSession: Bool
        var calendar: Calendar
    }
    private struct Entry {
        var turn: AssistantTurn
        var index: Int
        var topic: Bool
    }
    func value(owner: AnyObject, revision: UUID, registration: String, feed: AssistantConversation?, topic: AssistantConversation?, activeTurnID: UUID?, limit: Int, sessionID: UUID? = nil, filterSession: Bool = false, calendar: Calendar = .current, visible: (AssistantTurn) -> Bool) -> AssistantTranscriptPage {
        let feed = feed?.accountID == registration ? feed : nil
        let topic = topic?.accountID == registration ? topic : nil
        var changed = false
        let current = Key(owner: ObjectIdentifier(owner), revision: revision, registration: registration, feed: feed?.id, topic: topic?.id, session: sessionID, filterSession: filterSession, calendar: calendar)
        if key != current {
            var next = (feed?.turns ?? []).enumerated().compactMap { offset, turn in
                turn.contextID == topic?.id && turn.profileSessionID == nil && (!filterSession || turn.chatSessionID == sessionID) ? Entry(turn: turn, index: offset, topic: false) : nil
            }
            next += (topic?.turns ?? []).enumerated().compactMap { offset, turn in
                turn.profileSessionID == nil && (!filterSession || turn.chatSessionID == sessionID) ? Entry(turn: turn, index: offset, topic: true) : nil
            }
            entries = next.enumerated().sorted {
                let a = $0.element.turn.created ?? .distantPast, b = $1.element.turn.created ?? .distantPast
                return a == b ? $0.offset < $1.offset : a < b
            }.map(\.element)
            positions = Dictionary(entries.enumerated().map { ($0.element.turn.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
            delivered = entries.compactMap { $0.turn.deliveryID == nil ? nil : $0.turn }
            key = current; visibility = [:]; threadBuilds += 1; changed = true
        }
        refreshVisibility(visible, calendar: calendar, force: changed)
        var page = Array(rows.suffix(max(0, limit)))
        var live: AssistantTurn?
        if let activeTurnID, let position = positions[activeTurnID] {
            let entry = entries[position], turns = entry.topic ? topic?.turns : feed?.turns
            if let turns, turns.indices.contains(entry.index), turns[entry.index].id == activeTurnID { live = turns[entry.index] }
        }
        if let live, let index = page.firstIndex(where: { $0.id == live.id }) { page[index].turn = live }
        let last = rows.last.map { row in live?.id == row.id ? live! : row.turn }
        return .init(rows: page, totalCount: rows.count, threadCount: entries.count, lastThreadTurnID: entries.last?.turn.id, lastVisibleTurn: last)
    }
    private func refreshVisibility(_ visible: (AssistantTurn) -> Bool, calendar: Calendar, force: Bool) {
        let next = Dictionary(delivered.map { ($0.id, visible($0)) }, uniquingKeysWith: { first, _ in first })
        if force || next != visibility {
            rows = ConversationRules.transcript(entries.map(\.turn), visible: { $0.deliveryID == nil || next[$0.id] == true }, calendar: calendar)
            rowBuilds += 1
        }
        visibility = next
    }
}

/// Ignore content growth while following the bottom. Only a user scroll away
/// suspends following; reading older messages survives each streamed delta.
struct AssistantTranscriptScrollState: Equatable {
    private(set) var followsBottom = true
    mutating func update(distanceFromBottom: Double, userScrolling: Bool) {
        let near = distanceFromBottom.isFinite && distanceFromBottom <= 80
        if userScrolling || near { followsBottom = near }
    }
    mutating func pause() { followsBottom = false }
    mutating func reset() { followsBottom = true }
}

struct AssistantTranscriptRenderKey: Equatable {
    var turn: AssistantTurn
    var registration: String
    var conversationID: UUID?
    var topicID: UUID?
    var lastTurnID: UUID?
    var replying: Bool
    var toolStatus: String
    var discoveryEntries: [String: UUID]
}
