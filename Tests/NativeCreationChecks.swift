import Foundation
import SwiftData
@main struct Checks {
    @MainActor static func main() throws {
        let request = NativeCreationRequest(kind:.reminder,registration:"fixture-account",title:"Duplicate title")
        let base = NativeEditDetails(kind:.reminder,itemID:request.id.uuidString,occurrenceID:request.id.uuidString,sourceID:"list-ID",title:request.title,notes:"",writable:true)
        try NativeCreationRules.validate(request:request,baseline:base,edited:base)
        func rejects(_ body: () throws -> Void) { do { try body(); preconditionFailure("Unexpected success") } catch {} }
        var wrong = request; wrong.id = UUID(); rejects { try NativeCreationRules.validate(request:wrong,baseline:base,edited:base) }
        var noTitle = base; noTitle.title = " "; rejects { try NativeCreationRules.validate(request:request,baseline:base,edited:noTitle) }
        var readOnly = base; readOnly.writable = false; rejects { try NativeCreationRules.validate(request:request,baseline:readOnly,edited:base) }
        let instant=ISO8601DateFormatter().date(from:"2027-01-21T16:00:00Z")!
        var dated=request;dated.kind = .event;dated.suggestedStart=instant;dated.suggestedHasTime=true;dated.suggestedTimeZone="Europe/London"
        var event=base;event.kind = .event
        let deadline=NativeCreationRules.applyingSuggestion(dated,to:event)
        precondition(deadline.start == instant && deadline.end == instant.addingTimeInterval(900) && !deadline.allDay,"Supported deadline instant prefilled with visible short marker")
        dated.suggestedStart=ISO8601DateFormatter().date(from:"2027-06-03T23:00:00Z")!;dated.suggestedHasTime=false
        let day=NativeCreationRules.applyingSuggestion(dated,to:event)
        precondition(day.allDay && day.end.timeIntervalSince(day.start) == 86400,"Date-only suggestion is one local all-day reference")
        dated.suggestedEnd=day.start.addingTimeInterval(86400)
        let range=NativeCreationRules.applyingSuggestion(dated,to:event)
        precondition(range.end.timeIntervalSince(range.start) == 172800,"Inclusive source end becomes exclusive editor end")
        let container = try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let store = NativeCreationStore(container:container)
        precondition(NativeCreationRules.allowed(store.state,key:request.key))
        try store.begin(request); precondition(!NativeCreationRules.allowed(store.state,key:request.key))
        rejects { try store.begin(request) }
        var alternative = request; alternative.kind = .event
        precondition(alternative.key == request.key)
        rejects { try store.begin(alternative) }
        let pending = NativeCreationStore(container:container)
        rejects { try pending.begin(request) }; precondition(pending.receipt(request) == nil)
        let receipt = NativeCreationReceipt(requestID:request.id,registration:request.registration,kind:request.kind,itemID:"exact-new-ID",title:request.title,destination:"To do · Test",created:.now,sourceScope:"fixture")
        var invalid = receipt; invalid.registration = "other-account"; rejects { try store.complete(request,receipt:invalid) }
        try store.complete(request,receipt:receipt)
        rejects { try store.complete(request,receipt:receipt) }
        let completed = NativeCreationStore(container:container)
        precondition(completed.receipt(request) == receipt)
        rejects { try completed.begin(request) }
        var otherAccount = request; otherAccount.registration = "other-account"; try completed.begin(otherAccount)
        let unavailable = NativeCreationStore(container:nil)
        rejects { try unavailable.begin(request) }; precondition(unavailable.state.claims.isEmpty)
        let ownership=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let firstOwner=NativeCreationStore(container:ownership),staleOwner=NativeCreationStore(container:ownership)
        try firstOwner.begin(request)
        let different=NativeCreationRequest(kind:.reminder,registration:"fixture-account",title:"Other request")
        rejects {try staleOwner.begin(different)}
        let retained=NativeCreationStore(container:ownership)
        precondition(retained.state.claims.count == 1 && retained.state.claims[request.key] != nil,"A stale form owner never overwrites a newer pending native claim")
        let record = try container.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first!
        let preserved = Data("{\"version\":99,\"claims\":{}}".utf8); record.data = preserved; try container.mainContext.save()
        let unsupported = NativeCreationStore(container:container)
        precondition(!unsupported.readable); rejects { try unsupported.begin(request) }; precondition(record.data == preserved)
        print("PASS creation identity/title/read-only validation; pending/completed duplicate refusal across reload; registration isolation; unavailable/unknown storage preserved")
    }
}
