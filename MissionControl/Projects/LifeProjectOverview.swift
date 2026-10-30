import SwiftUI
import AppKit

extension LifeDueUrgency {
    var color: Color { switch self { case .late: .red; case .soon: .orange; case .later: .secondary } }
}
struct LifeDueChip: View {
    let due: String
    var body: some View {
        if let label = LifeDue.label(due) {
            Text(label.text).font(.caption2.weight(.medium)).lineLimit(1).padding(.horizontal,6).padding(.vertical,2)
                .foregroundStyle(label.urgency.color).background(label.urgency.color.opacity(0.13),in:RoundedRectangle(cornerRadius:5))
                .help("Due "+LifeWorkspaceRules.displayDate(due))
        }
    }
}
/// A space at a glance: progress across everything inside it and its next deadline.
struct LifeProjectCard: View {
    let item: LifeItem
    let index: LifeProjectIndex
    var highlighted = false
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        let progress = index.progress(under:item.id), late = index.lateCount(under:item.id)
        VStack(alignment:.leading,spacing:9) {
            HStack(alignment:.firstTextBaseline,spacing:8) {
                Image(systemName:item.displaySymbol).foregroundStyle(palette[.accent])
                Text(item.title).font(.callout.weight(.semibold)).foregroundStyle(palette[.text]).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength:4)
                if late > 0 { Text("\(late) late").font(.caption.weight(.medium)).foregroundStyle(.red) }
            }
            if progress.total > 0 { LifeTaskProgressView(progress:progress,compact:true) }
            else { Capsule().fill(palette[.text].opacity(0.07)).frame(height:7) }
            if let next = index.nextDue(under:item.id), let due = next.due {
                HStack(spacing:6) { LifeDueChip(due:due); Text(next.title).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            } else {
                let count = index.children(of:item.id).count
                Text(count == 0 ? "Empty" : "No deadlines · \(count) inside").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12).frame(maxWidth:.infinity,minHeight:92,alignment:.topLeading)
        .background(palette[.input].opacity(highlighted ? 0.95 : 0.6),in:RoundedRectangle(cornerRadius:12))
        .contentShape(RoundedRectangle(cornerRadius:12))
    }
}
/// Project-only deadlines: late work, then the next two weeks, each labelled with where it lives.
/// Calendar and Reminders stay separate.
struct LifeDueSoonSection: View {
    let index: LifeProjectIndex
    var readOnly = false
    let complete: (LifeItem) -> Void
    let open: (LifeItem) -> Void
    @State private var showAll = false
    @Environment(\.workspacePalette) private var palette
    private let limit = 8
    private struct DueGroup: Identifiable { let title: String; let items: [LifeItem]; var id: String { title } }
    var body: some View {
        let due = index.dueSoon(under:nil)
        VStack(alignment:.leading,spacing:10) {
            Text("Due soon").font(.headline)
            if due.isEmpty { Text("Nothing due in the next two weeks.").font(.callout).foregroundStyle(.secondary) }
            ForEach(groups(showAll ? due : Array(due.prefix(limit)))) { group in
                VStack(alignment:.leading,spacing:0) {
                    Text(group.title).font(.caption.weight(.semibold)).foregroundStyle(group.title == "Late" ? Color.red : Color.secondary).padding(.bottom,2)
                    ForEach(group.items) { row($0) }
                }
            }
            if due.count > limit {
                Button(showAll ? "Show fewer" : "Show \(due.count-limit) more") { showAll.toggle() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func groups(_ items: [LifeItem]) -> [DueGroup] {
        func days(_ item: LifeItem) -> Int { item.due.flatMap { LifeDue.days($0) } ?? 0 }
        return [DueGroup(title:"Late",items:items.filter { days($0) < 0 }),DueGroup(title:"This week",items:items.filter { (0...6).contains(days($0)) }),DueGroup(title:"Next week",items:items.filter { days($0) >= 7 })].filter { !$0.items.isEmpty }
    }
    private func row(_ item: LifeItem) -> some View {
        let place = index.path(item).dropLast().map(\.title).joined(separator:" › ")
        return HStack(alignment:.top,spacing:9) {
            Button { complete(item) } label: { Image(systemName:"circle").font(.body).foregroundStyle(palette[.text].opacity(0.4)) }
                .buttonStyle(.plain).disabled(readOnly).padding(.top,1).accessibilityLabel("Complete task: "+item.title).help("Changes this workspace task only")
            VStack(alignment:.leading,spacing:3) {
                Text(item.title).font(.callout.weight(.medium)).foregroundStyle(palette[.text]).fixedSize(horizontal:false,vertical:true)
                if item.status == .waiting || !place.isEmpty {
                    HStack(spacing:6) {
                        if item.status == .waiting { Text(item.status.title).font(.caption2).foregroundStyle(.secondary) }
                        if !place.isEmpty { Label(place,systemImage:"folder").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
            }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle()).onTapGesture { open(item) }
                .accessibilityAddTraits(.isButton).accessibilityAction { open(item) }
            if let due = item.due { LifeDueChip(due:due) }
        }.padding(.vertical,6).padding(.horizontal,4)
    }
}
/// Inline task entry under a stage heading. Return saves and stays open for the next one;
/// Esc, or a click elsewhere while it is still empty, closes it. A trailing date phrase
/// ("fri", "14 nov") becomes the local deadline.
struct LifeInlineTaskAdd: View {
    let save: (String,String?) -> Bool
    let close: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        let parsed = LifeDueParser.parse(text)
        HStack(spacing:8) {
            Image(systemName:"circle").foregroundStyle(palette[.text].opacity(0.3))
            TextField("Type to add a task",text:$text).textFieldStyle(.plain).focused($focused).onSubmit(submit).onExitCommand(perform:close)
            if let due = parsed.due { LifeDueChip(due:due) }
        }
        .padding(10).background(palette[.input],in:RoundedRectangle(cornerRadius:9))
        .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(palette[.accent].opacity(0.6)))
        .background(LifeOutsideClickMonitor { if text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { close() } })
        .onAppear { focused = true }
        .help("End with a date if you like: today, tomorrow, fri, next week, in 3 days, 14 nov. Return adds, Esc closes.")
    }
    private func submit() {
        let parsed = LifeDueParser.parse(text)
        guard !parsed.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        if save(parsed.title,parsed.due) { text = "" }
        focused = true
    }
}
/// Reports a mouse-down elsewhere in the same window without consuming it.
struct LifeOutsideClickMonitor: NSViewRepresentable {
    let outside: () -> Void
    func makeNSView(context: Context) -> Probe { let view = Probe(); view.outside = outside; return view }
    func updateNSView(_ view: Probe, context: Context) { view.outside = outside }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.stop() }
    final class Probe: NSView {
        var outside: (() -> Void)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching:.leftMouseDown) { [weak self] event in
                if let self, let window = self.window, event.window === window, !self.bounds.contains(self.convert(event.locationInWindow,from:nil)) {
                    DispatchQueue.main.async { self.outside?() }
                }
                return event
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}
