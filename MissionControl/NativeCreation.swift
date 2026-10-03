import Foundation

struct NativeCreationRequest: Identifiable {
    var id = UUID()
    var kind: NativeItemKind
    var registration: String
    var preferredDate: Date?
    var title = ""
    var notes = ""
    var discoveryID: String?
    var evidence: String?
    var requiresDateSelection = false
    var key: String { registration + ":" + id.uuidString }
}
struct NativeCreationReceipt: Codable, Equatable {
    var requestID: UUID
    var registration: String
    var kind: NativeItemKind
    var itemID: String
    var title: String
    var destination: String
    var created: Date
    var sourceScope: String
    var deliveryID: String { "native-create:" + registration + ":" + requestID.uuidString }
}
struct NativeCreationClaim: Codable, Equatable {
    var started: Date
    var receipt: NativeCreationReceipt?
}
struct NativeCreationState: Codable {
    var version = 1
    var claims: [String:NativeCreationClaim] = [:]
}
enum NativeCreationRules {
    static func validate(request: NativeCreationRequest, baseline: NativeEditDetails, edited: NativeEditDetails) throws {
        guard baseline.kind == request.kind, baseline.itemID == request.id.uuidString else { throw IntegrationError.missing }
        try NativeEditRules.validate(edited,baseline:baseline)
    }
    static func allowed(_ state: NativeCreationState, key: String) -> Bool { state.claims[key] == nil }
}
