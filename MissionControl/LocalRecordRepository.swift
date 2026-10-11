import Foundation
import SwiftData

/// Keyed persistence with an operation-owned context. A failed save cannot leave
/// dirty receipts in the UI context or roll back another service's work.
@MainActor final class LocalRecordRepository {
    private let container: ModelContainer
    private let beforeCommit: (ModelContext) throws -> Void
    init(container: ModelContainer, beforeCommit: @escaping (ModelContext) throws -> Void = { _ in }) {
        self.container = container
        self.beforeCommit = beforeCommit
    }
    static func request(_ key: String) -> FetchDescriptor<CachedDashboard> {
        var request = FetchDescriptor<CachedDashboard>(predicate: #Predicate { $0.key == key })
        request.fetchLimit = 1
        return request
    }
    static func read(_ key: String, container: ModelContainer?) throws -> Data? {
        guard let container else { return nil }
        return try LocalRecordRepository(container: container).read(key)
    }
    func read(_ key: String) throws -> Data? {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try context.fetch(Self.request(key)).first?.data
    }
    func decode<Value: Decodable>(_ key: String, as type: Value.Type = Value.self) throws -> Value? {
        try read(key).map { try JSONDecoder().decode(type, from: $0) }
    }
    func save<Value: Encodable>(_ value: Value, key: String) throws {
        try write([key: JSONEncoder().encode(value)])
    }
    /// Related data and its progress receipt commit together. Callers publish
    /// their new in-memory state only after this method succeeds.
    func write(_ values: [String: Data], removing keys: Set<String> = [], now: Date = .now) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            for key in keys.subtracting(values.keys) {
                if let record = try context.fetch(Self.request(key)).first { context.delete(record) }
            }
            for key in values.keys.sorted() {
                let data = values[key]!
                if let record = try context.fetch(Self.request(key)).first {
                    record.data = data
                    record.updated = now
                } else { context.insert(CachedDashboard(key: key, data: data, updated: now)) }
            }
            try beforeCommit(context)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
