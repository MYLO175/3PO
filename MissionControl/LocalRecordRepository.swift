import Foundation
import SwiftData
import Darwin

enum LocalRecordFailure: LocalizedError {
    case busy, changed, unsupportedFields
    var errorDescription: String? {
        switch self {
        case .busy: return "Another copy of 3PO is using this storage. Close it before continuing."
        case .changed: return "Saved data changed in another owner. Reopen it before saving; no changes were written."
        case .unsupportedFields: return "This edit cannot safely preserve fields saved by another version of 3PO. The original data is kept."
        }
    }
}

/// Advisory locks coordinate upgraded app copies; never unlink a live lock inode.
/// A process exit releases its lease, including after a crash.
final class LocalRecordFileLease {
    private let descriptor: Int32
    init(url: URL) throws {
        let fd = Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw LocalRecordFailure.busy
        }
        descriptor = fd
    }
    deinit { _ = flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}

enum LocalRecordVersion: Equatable {
    case missing, bytes(Data)
    init(_ data: Data?) { self = data.map(Self.bytes) ?? .missing }
}

/// Preserve additive fields while known nil values and explicit removals retain
/// their meaning. Synthesised Codable property names are the schema here.
enum LocalRecordCoding {
    static func preservingUnknown<Value: Encodable>(_ value: Value, original: Data?) throws -> Data {
        let encoded = try JSONEncoder().encode(value)
        guard let original else { return encoded }
        try requireLosslessNumbers(original)
        let new = try JSONSerialization.jsonObject(with: encoded)
        let old = try JSONSerialization.jsonObject(with: original)
        return try JSONSerialization.data(withJSONObject: merge(value, encoded: new, old: old), options: [.sortedKeys])
    }
    private static func merge(_ value: Any, encoded: Any, old: Any?) throws -> Any {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional, let child = mirror.children.first {
            return try merge(child.value, encoded: encoded, old: old)
        }
        if let values = encoded as? [Any], mirror.displayStyle == .collection {
            let prior = old as? [Any] ?? [], children = Array(mirror.children)
            let byID = Dictionary(prior.compactMap { row -> (String, Any)? in
                guard let id = (row as? [String: Any])?["id"] as? String else { return nil }
                return (id, row)
            }, uniquingKeysWith: { first, _ in first })
            let byUUID = Dictionary(byID.compactMap { key, row -> (UUID, Any)? in
                UUID(uuidString:key).map{($0,row)}
            }, uniquingKeysWith: { first, _ in first })
            let idless=prior.compactMap{$0 as? [String:Any]}.filter{$0["id"] == nil}
            let known=Set(children.first.map{Mirror(reflecting:$0.value).children.compactMap(\.label)} ?? [])
            let opaque=idless.contains{!Set($0.keys).isSubset(of:known)}
            var idlessMatches:[Data:[[String:Any]]]=[:]
            if opaque {
                for row in idless {
                    let key=try JSONSerialization.data(withJSONObject:row.filter{known.contains($0.key)},options:[.sortedKeys])
                    idlessMatches[key,default:[]].append(row)
                }
            }
            return try values.enumerated().map { index, row in
                let previous: Any?
                if let id = (row as? [String: Any])?["id"] as? String {
                    // UUID casing is a JSON representation detail. String
                    // operation keys remain exact and case-sensitive.
                    let typedID = index < children.count ? Mirror(reflecting:children[index].value).children.first{$0.label == "id"}?.value as? UUID : nil
                    previous = typedID.flatMap{byUUID[$0]} ?? byID[id]
                } else if let object=row as? [String:Any],index < children.count {
                    // Id-less rows (font runs/placement choices) cannot inherit
                    // opaque metadata from a different index after insertion,
                    // removal or reordering. Match exact known content or refuse
                    // an ambiguous transformation, retaining the original bytes.
                    if opaque {
                        let key=try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys])
                        let matches=idlessMatches[key] ?? []
                        guard matches.count == 1 else {throw LocalRecordFailure.unsupportedFields}
                        previous=matches.first
                    } else {previous=index < prior.count ? prior[index] : nil}
                } else { previous = index < prior.count ? prior[index] : nil }
                return try index < children.count ? merge(children[index].value, encoded: row, old: previous) : row
            }
        }
        guard var result = encoded as? [String: Any] else { return encoded }
        let prior = old as? [String: Any] ?? [:]
        if mirror.displayStyle == .dictionary {
            // Dictionary membership is intentional; never resurrect removed keys.
            for child in mirror.children {
                let pair = Array(Mirror(reflecting: child.value).children)
                if pair.count == 2, let key = pair[0].value as? String, let row = result[key] {
                    result[key] = try merge(pair[1].value, encoded: row, old: prior[key])
                }
            }
            return result
        }
        let known = Set(mirror.children.compactMap(\.label))
        for (key, row) in prior where !known.contains(key) && result[key] == nil { result[key] = row }
        for child in mirror.children {
            if let key = child.label, let row = result[key] { result[key] = try merge(child.value, encoded: row, old: prior[key]) }
        }
        return result
    }
    // Refuse opaque numbers Foundation cannot round-trip exactly. Preserve the
    // original record rather than silently truncating future numeric metadata.
    private static func requireLosslessNumbers(_ data: Data) throws {
        let bytes = Array(data), numeric = Set("0123456789.eE+-".utf8)
        var index = 0, inString = false, escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
            } else if byte == 34 { inString = true }
            else if byte == 45 || (48...57).contains(byte) {
                var end = index + 1
                while end < bytes.count && numeric.contains(bytes[end]) { end += 1 }
                let token = String(decoding: bytes[index..<end], as: UTF8.self)
                let parts = token.split { $0 == "e" || $0 == "E" }
                let mantissa = parts.first ?? "", digits = Array(mantissa.utf8.filter { (48...57).contains($0) }).drop { $0 == 48 }
                if !digits.isEmpty {
                    let trailing = digits.reversed().prefix { $0 == 48 }.count
                    let fraction = mantissa.firstIndex(of: ".").map { mantissa.distance(from: mantissa.index(after: $0), to: mantissa.endIndex) } ?? 0
                    guard let exponent = parts.count == 1 ? 0 : Int(parts[1]), (-128...127).contains(exponent),
                          digits.count - trailing <= 38, (-128...127).contains(exponent - fraction + trailing) else { throw LocalRecordFailure.unsupportedFields }
                    if parts.count > 1 || digits.count > 15 {
                        let parsed=try JSONSerialization.jsonObject(with:Data(("["+token+"]").utf8))
                        let encoded=try JSONSerialization.data(withJSONObject:parsed)
                        let output=String(decoding:encoded,as:UTF8.self).dropFirst().dropLast().trimmingCharacters(in:.whitespacesAndNewlines)
                        guard normalizedNumber(token) == normalizedNumber(output) else {throw LocalRecordFailure.unsupportedFields}
                    }
                }
                index = end; continue
            }
            index += 1
        }
    }
    private static func normalizedNumber(_ token:String)->String {
        let parts=token.split{$0 == "e" || $0 == "E"},mantissa=parts[0]
        let fraction=mantissa.firstIndex(of:".").map{mantissa.distance(from:mantissa.index(after:$0),to:mantissa.endIndex)} ?? 0
        let digits=Array(mantissa.utf8.filter{(48...57).contains($0)}).drop{$0 == 48}
        guard !digits.isEmpty else {return "0"}
        let trailing=digits.reversed().prefix{$0 == 48}.count
        return (mantissa.hasPrefix("-") ? "-" : "")+String(decoding:digits.dropLast(trailing),as:UTF8.self)+"@"+String((parts.count > 1 ? Int(parts[1])! : 0)-fraction+trailing)
    }
}

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
    func save<Value: Encodable>(_ value: Value, key: String, expected: LocalRecordVersion? = nil) throws {
        try write([key: JSONEncoder().encode(value)], expected: expected.map { [key: $0] } ?? [:])
    }
    /// Related data and its progress receipt commit together. Callers publish
    /// their new in-memory state only after this method succeeds.
    func write(_ values: [String: Data], removing keys: Set<String> = [], now: Date = .now,
               expected: [String: LocalRecordVersion] = [:]) throws {
        // Compare and save under one cooperating-writer lease, before creating
        // the context. In-memory fixtures are serialized by the main actor.
        let leases = try container.configurations.filter { !$0.isStoredInMemoryOnly }
            .map(\.url).sorted { $0.path < $1.path }.map { try LocalRecordFileLease(url: $0.appendingPathExtension("write-lock")) }
        defer { withExtendedLifetime(leases) {} }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            for (key, version) in expected {
                let data = try context.fetch(Self.request(key)).first?.data
                guard LocalRecordVersion(data) == version else { throw LocalRecordFailure.changed }
            }
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
