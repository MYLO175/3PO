import Foundation
import CoreGraphics

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


/// Browsing is distinct from a widget's saved starting branch. Home/back never edit it.
struct LifeProjectNavigation:Equatable {
    private(set) var isBrowsing=false
    private(set) var currentID:UUID?
    func destination(startingAt root:UUID?)->UUID? { isBrowsing ? currentID : root }
    mutating func open(_ id:UUID) { isBrowsing=true;currentID=id }
    mutating func home() { isBrowsing=true;currentID=nil }
    mutating func back(startingAt root:UUID?,items:[LifeItem]) {
        let parent=items.first{$0.id == destination(startingAt:root)}?.parentID
        isBrowsing=true;currentID=parent.flatMap { id in items.contains{$0.id == id} ? id : nil }
    }
    mutating func reconcile(items:[LifeItem]) { if isBrowsing,let currentID,!items.contains(where:{$0.id == currentID}) { home() } }
}

/// A local browsing projection. PA searches remain descendant-aware; folder pages do not.
enum LifeFolderContents {
    static func children(of parent:UUID?,in items:[LifeItem],unfinished:Bool=false)->[LifeItem] {
        let live=items.filter{$0.deletedAt == nil},ids=Set(items.filter{$0.deletedAt == nil}.map(\.id))
        return live.filter { item in
            let inside=parent.map{item.parentID == $0} ?? (item.parentID.map{!ids.contains($0)} ?? true)
            return inside && (!unfinished || !item.kind.isWork || (item.status != .done && item.status != .archived))
        }
    }
    static func progress(under parent:UUID,in items:[LifeItem])->LifeTaskProgress {
        let ids=LifeWorkspaceRules.descendants(parent,in:items)
        return LifeTaskProgress(items:items.filter{ids.contains($0.id) && $0.deletedAt == nil})
    }
}

/// Waiting remains a saved state, displayed in To do. Archived work stays out of progress.
enum LifeTaskStage:String,CaseIterable,Identifiable {
    case todo="To do",inProgress="In progress",done="Done"
    var id:String { rawValue }
    var status:LifeItemStatus { switch self { case .todo:.planned;case .inProgress:.active;case .done:.done } }
    static func stage(for status:LifeItemStatus)->Self? {
        switch status { case .planned,.waiting:.todo;case .active:.inProgress;case .done:.done;case .archived:nil }
    }
}
struct LifeTaskProgress:Equatable {
    var counts:[Int]
    init(items:[LifeItem]) { counts=LifeTaskStage.allCases.map { stage in items.filter{$0.kind.isWork && $0.deletedAt == nil && LifeTaskStage.stage(for:$0.status) == stage}.count } }
    var total:Int { counts.reduce(0,+) }
    var percentages:[Int] {
        guard total > 0 else { return [0,0,0] }
        let values=counts.map{Double($0)*100/Double(total)}
        var rounded=values.map{Int($0.rounded(.down))}
        let remainder=100-rounded.reduce(0,+)
        let order=values.indices.sorted { a,b in let left=values[a]-Double(rounded[a]),right=values[b]-Double(rounded[b]);return left == right ? a < b : left > right }
        for index in order.prefix(remainder) { rounded[index]+=1 }
        return rounded
    }
}

/// Forty-millisecond steps; no persistence or status change while scrolling.
enum LifeBoardScrollRules {
    static func step(pointerY:CGFloat,height:CGFloat,offset:CGFloat,contentHeight:CGFloat)->CGFloat {
        guard height > 0,contentHeight > height,pointerY >= 0,pointerY <= height else {return 0}
        let edge=min(48,height/4)
        let speed:CGFloat=pointerY < edge ? -(edge-pointerY)/edge : pointerY > height-edge ? (pointerY-height+edge)/edge : 0
        let next=min(max(0,offset+speed*10),max(0,contentHeight-height))
        return next-offset
    }
}

/// Insertion feedback uses stationary captured slots, never the translated folder tile.
struct LifeFolderInsertion:Equatable {
    var target:UUID
    var after:Bool
    var before:UUID?
}
enum LifeFolderOrder {
    static func insertion(at point:CGPoint,dragging id:UUID,orderedIDs:[UUID],frames:[UUID:CGRect])->LifeFolderInsertion? {
        let peers=orderedIDs.filter{$0 != id}
        guard let target=peers.first(where:{frames[$0]?.insetBy(dx:-10,dy:0).contains(point) == true}),let frame=frames[target],let index=peers.firstIndex(of:target) else {return nil}
        let after=point.x >= frame.midX
        return .init(target:target,after:after,before:after ? peers.dropFirst(index+1).first : target)
    }
}
