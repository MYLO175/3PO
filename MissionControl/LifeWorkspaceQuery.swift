import Foundation

/// Resolve the same canonical IDs counted by the map, preserving workspace order and ownership.
enum LifeAreaWorkspace {
    static func items(_ area:LifeArea,notebook:LifeNotebook,items:[LifeItem])->[LifeItem] {
        let ids=Set(notebook.anchors.filter{$0.areas.contains(area)}.map(\.id))
        return items.filter{$0.deletedAt == nil && ids.contains("life:"+$0.id.uuidString)}
    }
}

struct LifeItemQuery {
    var root: UUID? = nil
    var query = ""
    var unfinished = false
    var dueBefore: String? = nil
    var maxMinutes: Int? = nil
    func matching(_ items: [LifeItem]) -> [LifeItem] {
        let descendants = root.map { LifeWorkspaceRules.descendants($0, in: items) }
        let terms = LifeWorkspaceRules.key(query).split(separator: " ").map(String.init)
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return items.filter { item in
            guard descendants.map({ $0.contains(item.id) || item.id == root }) ?? true,
                  !unfinished || (item.status != .done && item.status != .archived),
                  dueBefore.map({ limit in item.due.map { $0 <= limit } ?? false }) ?? true,
                  maxMinutes.map({ limit in item.estimateMinutes.map { $0 <= limit } ?? false }) ?? true else { return false }
            var text = item.title + " " + item.notes, cursor = item.parentID, seen = Set<UUID>()
            while let id = cursor, seen.insert(id).inserted, let parent = byID[id] { text += " " + parent.title; cursor = parent.parentID }
            let key = LifeWorkspaceRules.key(text)
            return terms.allSatisfy { key.contains($0) }
        }
    }
    static func path(_ item: LifeItem, in items: [LifeItem]) -> [LifeItem] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = [item], cursor = item.parentID, seen: Set<UUID> = [item.id]
        while let id = cursor, seen.insert(id).inserted, let parent = byID[id] { result.insert(parent, at: 0); cursor = parent.parentID }
        return result
    }
}
