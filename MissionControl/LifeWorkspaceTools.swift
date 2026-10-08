import Foundation
import CryptoKit

/// One foreground turn issues optimistic record identities. Its ledger shares durable storage with manual edits.
@MainActor final class LifeWorkspaceToolSession {
    let model: DashboardModel
    let registration: String
    let topic: UUID?
    let includeTopics: Bool
    let turnID: UUID
    private(set) var issued: [UUID:LifeItem] = [:]
    private var issuedLinks: [UUID:UUID] = [:]
    private var issuedWidgets: [UUID:WidgetPlacement] = [:]
    private var changes = 0
    private let evaluationStore: LifeWorkspaceStore?
    private var store: LifeWorkspaceStore { evaluationStore ?? model.assistant.projects }
    init(model: DashboardModel, registration: String, topic: UUID?, includeTopics: Bool, turnID: UUID, evaluationStore: LifeWorkspaceStore? = nil) {
        self.evaluationStore = evaluationStore
        self.model = model; self.registration = registration; self.topic = topic; self.includeTopics = includeTopics; self.turnID = turnID
    }
    private func json(_ value: Any) throws -> String { String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)! }
    private func current(_ text: String?) throws -> LifeItem {
        guard let id = text.flatMap(UUID.init(uuidString:)), let issued = issued[id],
              let value = store.items(registration, topic: topic, includeTopics: includeTopics).first(where: { $0.id == id }), value.revision == issued.revision else {
            throw LifeWorkspaceFailure.message("Read the current exact project item before changing or linking it.")
        }
        return value
    }
    func targetData(_ args: [String:Any]) throws -> String? {
        var requested = Set<UUID>()
        for key in ["id", "from", "parent", "root", "before"] {
            if let token = args[key] as? String, let id = UUID(uuidString:token) { requested.insert(id) }
        }
        for entry in args["items"] as? [[String:Any]] ?? [] {
            if let token = entry["parent"] as? String, let id = UUID(uuidString:token) { requested.insert(id) }
        }
        let all = store.items(registration, topic:topic, includeTopics:includeTopics,includeDeleted:true)
        var targets: [[String:Any]] = requested.sorted { $0.uuidString < $1.uuidString }.compactMap { id in
            guard let item = issued[id], all.contains(where: { $0.id == id && $0.revision == item.revision }) else { return nil }
            return ["id":item.id.uuidString, "titleData":item.title, "kind":item.kind.workspaceKind.rawValue, "status":item.status.rawValue, "pathData":LifeItemQuery.path(item, in:all).map(\.title), "directContentCount":all.filter{$0.parentID == item.id && $0.deletedAt == nil}.count, "directContentsData":Array(all.filter{$0.parentID == item.id && $0.deletedAt == nil}.prefix(20)).map{["id":$0.id.uuidString,"title":$0.title,"kind":$0.kind.workspaceKind.rawValue]}]
        }
        if args.count == 1, args["authorization"] != nil, let ticket = store.undoEdit(registration) {
            targets.append(["undoItemID":ticket.before.id.uuidString, "titleData":ticket.before.title, "kind":ticket.before.kind.workspaceKind.rawValue])
        }
        if let id = (args["id"] as? String).flatMap(UUID.init(uuidString:)), issuedLinks[id] != nil, let link = store.state.links.first(where: { $0.id == id && $0.registration == registration }), let owner = issued[link.from] {
            targets.append(["relationshipID":link.id.uuidString, "ownerTitleData":owner.title, "relation":link.relation.rawValue, "kind":link.target.kind.rawValue])
        }
        let batch: [[String:Any]] = (args["items"] as? [[String:Any]] ?? []).enumerated().map { index, entry in
            ["batchParentToken":"batch:" + String(index), "proposedTitleData":entry["title"] ?? "", "proposedKind":entry["kind"] ?? "", "parent":entry["parent"] ?? NSNull()]
        }
        return try json(["resolvedIssuedItems":targets, "proposedBatchStructureData":batch])
    }
    private func object(_ item: LifeItem) -> [String:Any] {
        ["id":item.id.uuidString, "title":item.title, "kind":item.kind.workspaceKind.rawValue, "parent":item.parentID?.uuidString as Any? ?? NSNull(), "status":item.status.rawValue, "notes":String(item.notes.prefix(2000)), "notesTruncated":item.notes.count > 2000, "due":item.due as Any? ?? NSNull(), "estimateMinutes":item.estimateMinutes as Any? ?? NSNull(), "areas":item.areas.map(\.rawValue), "ownership":item.ownership ?? "workspace", "deleted":item.deletedAt != nil, "sortOrder":item.sortOrder as Any? ?? NSNull(), "path":LifeItemQuery.path(item, in:store.items(registration, topic:topic, includeTopics:includeTopics)).map(\.title)]
    }
    private func resolve(_ reference: LifeReference) -> LifeLinkOption? {
        if reference.kind == .item, let id = UUID(uuidString:reference.id), let item = store.items(registration, topic:topic, includeTopics:includeTopics).first(where: { $0.id == id }) {
            return .init(reference:reference, title:item.title, detail:item.kind.title)
        }
        return LifeWorkspaceContext.resolve(reference, model:model, registration:registration, topic:topic, includeTopics:includeTopics)
    }
    func execute(_ call: PAFunctionCall, args: [String:Any], reference: LifeReference? = nil) throws -> String {
        func text(_ key: String) -> String? { args[key] as? String }
        guard registration == model.chatGPT.activeID else { throw LifeWorkspaceFailure.message("Account changed; project operation stopped.") }
        let canonical = try JSONSerialization.data(withJSONObject: ["name":call.name, "arguments":args, "registration":registration, "topic":topic?.uuidString ?? "shared", "turn":turnID.uuidString], options: [.sortedKeys])
        let operationKey = "life:" + SHA256.hash(data: canonical).map { String(format:"%02x", $0) }.joined()
        if LifeWorkspaceTools.mutations.contains(call.name), let receipt = store.receipt(operationKey, registration: registration) {
            return try json(["saved":true, "alreadySaved":true, "result":receipt.result, "instruction":"This operation already has a durable receipt. Read current records before doing anything else."])
        }
        guard !LifeWorkspaceTools.mutations.contains(call.name) || changes < 8 else { throw LifeWorkspaceFailure.message("Eight local project operations reached this turn's bound. Completed work is retained.") }
        switch call.name {
        case "undo_life_edit":
            let summary = "Local project edit undone. Linked sources are unchanged."
            let itemID = store.undoEdit(registration)?.before.id
            try store.undo(registration, receipt:.init(id:operationKey, registration:registration, result:summary, itemID:itemID)); changes += 1
            if let itemID { issued.removeValue(forKey:itemID) }
            return try json(["saved":true, "result":summary])
        case "read_life_items":
            let root = try text("root").map { try current($0).id }
            guard LifeWorkspaceRules.dateValid(text("dueBefore")), (args["maxMinutes"] as? Int).map({ (1...100000).contains($0) }) != false else { throw LifeWorkspaceFailure.message("Use a date-only deadline or a positive estimate limit.") }
            let all = store.items(registration, topic: topic, includeTopics: includeTopics,includeDeleted:args["deleted"] as? Bool == true).filter{(args["deleted"] as? Bool == true) == ($0.deletedAt != nil)}
            let found = LifeItemQuery(root:root, query:text("query") ?? "", unfinished:args["unfinished"] as? Bool == true, dueBefore:text("dueBefore"), maxMinutes:args["maxMinutes"] as? Int).matching(all)
            var returned = Array(found.prefix(60))
            // Issue ancestors too: searching a module must expose its real parent, not invite title guessing.
            for item in Array(returned) { for parent in LifeItemQuery.path(item, in: all) where !returned.contains(where: { $0.id == parent.id }) && returned.count < 80 { returned.append(parent) } }
            for item in returned { issued[item.id] = item }
            let links = store.state.links.filter { issued[$0.from] != nil && $0.registration == registration && (includeTopics || $0.conversationID == nil || $0.conversationID == topic) }.prefix(120)
            var relationships: [[String:Any]] = []
            for link in links {
                issuedLinks[link.id] = store.revision
                if let target = resolve(link.target) {
                    relationships.append(["id":link.id.uuidString, "from":link.from.uuidString, "relation":link.relation.rawValue, "targetKind":link.target.kind.rawValue, "targetID":link.target.id, "targetData":target.title, "coverage":target.detail])
                } else {
                    relationships.append(["id":link.id.uuidString, "from":link.from.uuidString, "relation":link.relation.rawValue, "targetKind":link.target.kind.rawValue, "available":false, "coverage":"Outside current permitted scope or cached coverage. Identity/content withheld; removal does not change the source."])
                }
            }
            let widgets = model.workspace.selected.widgets.filter { $0.kind == .projects }
            for widget in widgets { issuedWidgets[widget.id] = widget }
            return try json(["items":returned.map(object), "relationships":relationships, "widgets":widgets.map { ["id":$0.id.uuidString, "view":$0.configuration.projectView ?? "Overview"] }, "coverage":"\(min(60,found.count)) of \(found.count) matching local records, plus issued ancestors. Relationships capped at120; unavailable source identities/content withheld. Local task state is not native completion. Missing records/links are not proof of absence."])
        case "delete_life_item":
            let item=try current(text("id")),summary="Moved “\(item.title)” to Recently deleted. Memory and external sources are retained."
            try store.trash(item.id,registration:registration,keepChildren:args["keepChildren"] as? Bool == true,expectedRevision:store.revision,receipt:.init(id:operationKey,registration:registration,result:summary,itemID:item.id));changes+=1;issued.removeValue(forKey:item.id)
            return try json(["saved":true,"result":summary])
        case "restore_life_item":
            guard let id=text("id").flatMap(UUID.init(uuidString:)),let prior=issued[id],store.state.items.contains(where:{$0.id == id && $0.registration == registration && $0.revision == prior.revision && $0.deletedAt != nil}) else { throw LifeWorkspaceFailure.message("Read the exact Recently deleted item before restoring.") }
            let summary="Restored “\(prior.title)” with its saved identities and links."
            try store.restore(id,registration:registration,expectedRevision:store.revision,receipt:.init(id:operationKey,registration:registration,result:summary,itemID:id));changes+=1
            return try json(["saved":true,"result":summary])
        case "reorder_life_item":
            let item=try current(text("id")),parent=try text("parent").map{try current($0).id},before=try text("before").map{try current($0).id}
            let summary="Rearranged “\(item.title)” and preserved its contents."
            try store.move(item.id,registration:registration,parent:parent,before:before,expectedRevision:store.revision,receipt:.init(id:operationKey,registration:registration,result:summary,itemID:item.id));changes+=1
            issued[item.id]=store.items(registration,topic:topic,includeTopics:includeTopics).first{$0.id == item.id}
            return try json(["saved":true,"result":summary])
        case "create_life_items":
            guard !issued.isEmpty || store.items(registration, topic:topic, includeTopics:includeTopics).isEmpty else { throw LifeWorkspaceFailure.message("Read the current structure before adding items.") }
            var values: [LifeItem] = []
            for entry in args["items"] as! [[String:Any]] {
                let parent: LifeItem?
                if let token = entry["parent"] as? String {
                    if token.hasPrefix("batch:"), let index = Int(token.dropFirst(6)), values.indices.contains(index) { parent = values[index] }
                    else { parent = try current(token) }
                } else { parent = nil }
                guard let kind = (entry["kind"] as? String).flatMap(LifeItemKind.init(rawValue:)), LifeItemKind.allCases.contains(kind) else {
                    throw LifeWorkspaceFailure.message("Create a space or a task.")
                }
                guard parent?.kind.isWork != true else { throw LifeWorkspaceFailure.message("Choose a space as the parent. Tasks cannot contain other items.") }
                let scope: UUID?
                if let parent { scope = parent.conversationID } else { scope = topic }
                values.append(.init(registration:registration, conversationID:scope, kind:kind, title:(entry["title"] as! String).trimmingCharacters(in:.whitespacesAndNewlines), parentID:parent?.id, notes:entry["notes"] as! String, due:entry["due"] as? String, estimateMinutes:entry["estimateMinutes"] as? Int, areas:(entry["areas"] as! [String]).compactMap(LifeArea.init(rawValue:)), sourceTurnID:turnID.uuidString, humanEvidence:String((text("authorization") ?? "").prefix(2000))))
            }
            let summary = "Created \(values.count) local workspace items."
            let saved = try store.create(values, receipt:.init(id:operationKey, registration:registration, result:summary, itemID:values.first?.id))
            for item in saved { issued[item.id] = item }; changes += 1
            return try json(["saved":true, "result":summary, "items":saved.map(object)])
        case "change_life_item":
            var item = try current(text("id")); let expected = item.revision
            if let title = text("title") { item.title = title.trimmingCharacters(in:.whitespacesAndNewlines) }
            if let notes = text("notes") { item.notes = notes }
            if let status = text("status").flatMap(LifeItemStatus.init(rawValue:)) { item.status = status }
            if let due = text("due") { item.due = due.isEmpty ? nil : due }
            if let minutes = args["estimateMinutes"] as? Int { item.estimateMinutes = minutes == 0 ? nil : minutes }
            if args["move"] as? Bool == true {
                item.parentID = try text("parent").map { try current($0).id }
                if item.kind == .project { item.placement = .init(status:"placed",reason:"Your chosen home is pinned.",parentPinned:true) }
            }
            let summary = "Updated “\(item.title)” locally. Linked sources are unchanged."
            let saved = try store.save(item, expected:expected, receipt:.init(id:operationKey, registration:registration, result:summary, itemID:item.id))
            issued[item.id] = saved; changes += 1
            return try json(["saved":true, "result":summary, "item":object(saved)])
        case "link_life_item":
            let owner = try current(text("from")), kind = LifeReferenceKind(rawValue:text("kind")!)!
            let target: LifeReference
            if kind == .item { target = .init(kind:.item, id:try current(text("id")).id.uuidString) }
            else {
                guard let reference, reference.kind == kind, reference.id == text("id") else { throw LifeWorkspaceFailure.message("Read the exact permitted memory/source before linking it.") }
                target = reference
            }
            let summary = "Linked “\(owner.title)” without changing its source."
            let link = try store.link(.init(registration:registration, conversationID:owner.conversationID, from:owner.id, relation:LifeRelation(rawValue:text("relation")!)!, target:target), expected:owner.revision, receipt:.init(id:operationKey, registration:registration, result:summary, itemID:owner.id))
            changes += 1; issuedLinks[link.id] = store.revision
            return try json(["saved":true, "result":summary, "relationshipID":link.id.uuidString])
        case "unlink_life_item":
            guard let id = text("id").flatMap(UUID.init(uuidString:)), let expected = issuedLinks[id] else { throw LifeWorkspaceFailure.message("Read the exact current relationship before removing it.") }
            let summary = "Removed the relationship. Both endpoints are retained."
            try store.unlink(id, registration:registration, expectedRevision:expected, receipt:.init(id:operationKey, registration:registration, result:summary, itemID:nil)); changes += 1
            return try json(["saved":true, "result":summary])
        case "show_project_view":
            guard evaluationStore == nil else { throw LifeWorkspaceFailure.message("Disposable evaluations cannot change your dashboard.") }
            guard let id = text("widget").flatMap(UUID.init(uuidString:)), let baseline = issuedWidgets[id], var widget = model.workspace.selected.widgets.first(where: { $0.id == id && $0.kind == .projects }), widget == baseline else { throw LifeWorkspaceFailure.message("Read an unchanged Projects widget on this dashboard first. Add one through Add widget if none is available.") }
            let root = try text("root").map { try current($0).id }
            if widget.configuration.projectRoots == nil { widget.configuration.projectRoots = [:] }
            widget.configuration.projectRoots?[registration] = root?.uuidString ?? ""; widget.configuration.projectView = text("view"); widget.configuration.projectOnlyUnfinished = args["unfinished"] as? Bool
            model.workspace.update(widget)
            guard model.workspace.error == nil, model.workspace.selected.widgets.contains(widget) else { throw LifeWorkspaceFailure.message(model.workspace.error ?? "The project view could not be saved.") }
            issuedWidgets[id] = widget
            changes += 1
            return try json(["saved":true, "result":"Project view updated. Dashboard Undo is available."])
        default: throw LifeWorkspaceFailure.message("Unknown local project operation.")
        }
    }
}
