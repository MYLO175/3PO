import Foundation

extension LifeNotebook {
    /// Read-only projection: original facts/evidence and saved record IDs remain authoritative.
    func integrating(_ items: [LifeItem], links itemLinks: [LifeItemLink]) -> LifeNotebook {
        var result = self, mapping: [String:String] = [:]
        func kind(_ item: LifeItem) -> LifeEntityKind {
            switch item.kind { case .organisation: .organisation; case .course: .course; case .project: .project; case .person: .person; case .goal: .goal; default: .concept }
        }
        for entity in entities where entity.id != Self.selfID {
            let exact = items.filter { kind($0) == entity.kind && entity.kind != .person && entity.kind != .concept && Self.key($0.title) == Self.key(entity.label) && entity.id.hasPrefix(($0.conversationID?.uuidString ?? "shared") + ":") }
            let explicit = itemLinks.filter { $0.relation == .identifies && $0.target.kind == .memory && $0.target.containerID == entity.id && entity.memoryIDs.contains(UUID(uuidString:$0.target.id) ?? UUID()) }.compactMap { edge in items.first { $0.id == edge.from && kind($0) == entity.kind } }
            let materialised=items.filter{$0.notebookEntityID == entity.id && kind($0) == entity.kind}
            let candidates = !explicit.isEmpty ? explicit : !materialised.isEmpty ? materialised : exact
            if Set(candidates.map(\.id)).count == 1, let item = candidates.first { mapping[entity.id] = "life:" + item.id.uuidString }
        }
        var merged: [String:LifeEntity] = [:]
        for var entity in entities {
            entity.id = mapping[entity.id] ?? entity.id
            if var old = merged[entity.id] { old.memoryIDs.formUnion(entity.memoryIDs);old.areas.formUnion(entity.areas);merged[entity.id]=old } else { merged[entity.id]=entity }
        }
        for item in items {
            let id = "life:" + item.id.uuidString
            var entity = merged[id] ?? .init(id:id,label:item.title,kind:kind(item),areas:[],memoryIDs:[])
            entity.label=item.title;entity.kind=kind(item);entity.areas.formUnion(LifeItemQuery.path(item,in:items).flatMap(\.areas));merged[id]=entity
        }
        result.entities=merged.values.sorted { $0.id < $1.id }
        result.links=links.map { edge in var edge=edge;edge.from=mapping[edge.from] ?? edge.from;edge.to=mapping[edge.to] ?? edge.to;return edge }
        result.anchors=items.map { item in
            .init(id:"life:"+item.id.uuidString,label:item.title,kind:item.kind.rawValue,parent:item.parentID.map { "life:"+$0.uuidString },areas:Array(merged["life:"+item.id.uuidString]?.areas ?? []).sorted{$0.rawValue < $1.rawValue},notes:String(item.notes.prefix(600)),path:LifeItemQuery.path(item,in:items).map(\.title),relations:itemLinks.filter{edge in edge.from == item.id && edge.target.kind == .item && items.contains(where:{$0.id.uuidString == edge.target.id})}.map{$0.relation.rawValue+":"+$0.target.id})
        }
        for area in Set(result.anchors.flatMap(\.areas)) where !result.notes.contains(where:{$0.area == area}) { result.notes.append(.init(area:area,records:[])) }
        return result
    }
}
