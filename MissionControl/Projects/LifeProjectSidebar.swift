import SwiftUI

struct LifeSpaceEntry: Identifiable { let item: LifeItem; let depth: Int; var id: UUID { item.id } }
extension LifeProjectIndex {
    /// Every space in outline order, for the narrow widget's jump menu.
    func spaceOutline(limit: Int = 200) -> [LifeSpaceEntry] {
        var result: [LifeSpaceEntry] = [], seen = Set<UUID>()
        func visit(_ parent: UUID?, _ depth: Int) {
            for item in children(of:parent) where !item.kind.isWork && result.count < limit && seen.insert(item.id).inserted {
                result.append(LifeSpaceEntry(item:item,depth:depth)); visit(item.id,depth+1)
            }
        }
        visit(nil,0); return result
    }
}

/// Wide Projects widgets: All projects, Unfiled tasks and the space tree beside the page.
/// Expansion is browsing state only; the open space and its parents are always shown.
struct LifeProjectSidebar: View {
    let index: LifeProjectIndex
    let selected: UUID?
    let unfiled: Bool
    let looseCount: Int
    let home: () -> Void
    let openUnfiled: () -> Void
    let open: (LifeItem) -> Void
    @State private var expanded: Set<UUID> = []
    @State private var collapsed: Set<UUID> = []
    @Environment(\.workspacePalette) private var palette
    private struct Row: Identifiable { let item: LifeItem; let depth: Int; let parent: Bool; let open: Bool; var id: UUID { item.id } }
    private var ancestors: Set<UUID> { selected.flatMap { index.byID[$0] }.map { Set(index.path($0).map(\.id)) } ?? [] }
    private var rows: [Row] {
        var result: [Row] = [], seen = Set<UUID>()
        let ancestors = ancestors
        func visit(_ parent: UUID?, _ depth: Int) {
            for item in index.children(of:parent) where !item.kind.isWork && seen.insert(item.id).inserted {
                let parent = index.children(of:item.id).contains { !$0.kind.isWork }
                let open = parent && !collapsed.contains(item.id) && (expanded.contains(item.id) || ancestors.contains(item.id))
                result.append(Row(item:item,depth:depth,parent:parent,open:open))
                if open { visit(item.id,depth+1) }
            }
        }
        visit(nil,0); return result
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:2) {
                entry(icon:"square.grid.2x2",title:"All projects",selected:selected == nil && !unfiled,late:index.lateCount(under:nil),action:home)
                if looseCount > 0 { entry(icon:"tray",title:"Unfiled tasks",selected:unfiled,count:looseCount,action:openUnfiled) }
                Text("Projects").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top,14).padding(.leading,8).padding(.bottom,4)
                ForEach(rows) { row in
                    HStack(spacing:0) {
                        if row.parent {
                            Button { toggle(row) } label: {
                                Image(systemName:"chevron.right").font(.caption2.weight(.semibold)).rotationEffect(.degrees(row.open ? 90 : 0)).frame(width:14,height:22).contentShape(Rectangle())
                            }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel((row.open ? "Collapse " : "Expand ")+row.item.title)
                        } else { Color.clear.frame(width:14,height:1) }
                        entry(icon:row.item.displaySymbol,title:row.item.title,selected:selected == row.item.id,late:index.lateCount(under:row.item.id),progress:index.progress(under:row.item.id)) { open(row.item) }
                    }.padding(.leading,CGFloat(min(row.depth,6))*14)
                }
            }.padding(.trailing,8)
        }
        .onChange(of:selected) { collapsed.subtract(ancestors) }
    }
    private func toggle(_ row: Row) {
        if row.open { collapsed.insert(row.item.id); expanded.remove(row.item.id) } else { expanded.insert(row.item.id); collapsed.remove(row.item.id) }
    }
    private func entry(icon: String, title: String, selected: Bool, late: Int = 0, count: Int? = nil, progress: LifeTaskProgress? = nil, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            HStack(spacing:7) {
                Image(systemName:icon).foregroundStyle(palette[.accent]).frame(width:16)
                Text(title).font(.callout).foregroundStyle(palette[.text]).lineLimit(1)
                Spacer(minLength:4)
                if late > 0 {
                    Text("\(late)").font(.caption2.weight(.bold)).foregroundStyle(.white).frame(minWidth:16,minHeight:16).background(Circle().fill(.red)).help("\(late) late")
                }
                if let count { Text("\(count)").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                if let progress, progress.total > 0 { LifeTaskProgressView(progress:progress,compact:true).frame(width:22) }
            }
            .padding(.vertical,5).padding(.horizontal,7)
            .background(selected ? palette[.accent].opacity(0.16) : Color.clear,in:RoundedRectangle(cornerRadius:7)).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
