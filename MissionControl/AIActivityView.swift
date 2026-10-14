import SwiftUI

/// One toolbar item: the circular shortcut opens chat; its message opens saved Activity.
struct AIActivityPill: View {
    var store: AIActivityStore
    var registration: String
    var current: AIActivityRecord?
    var palette: WorkspacePalette
    var openChat: () -> Void
    var openDestination: (AIActivityDestination) -> Void
    var isVisible: (AIActivityRecord) -> Bool = { _ in true }
    var relatedDestinations:(AIActivityRecord)->[AIActivityDestination] = {_ in []}
    @State private var activityOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Resolve history/visibility once, rather than once for every label,
        // progress and accessibility property in this toolbar render.
        let saved=store.records(registration).filter{$0.kind != .heartbeat && $0.failureAlert && isVisible($0)}
        let active:AIActivityRecord? = {
            guard var current,current.state == .running,current.registration == registration,isVisible(current) else {return nil}
            if let saved=saved.first(where:{$0.id == current.id}) {current.acknowledged=saved.acknowledged}
            return current
        }()
        let displayed=active ?? saved.first
        let attention = !saved.isEmpty || store.error != nil
        let progress:Double?=nil
        let message=displayed.map(AIActivityPresentation.message) ?? "3PO is ready"
        let accessibilityStatus=message+(progress.map{". \(Int($0*100)) percent progress."} ?? "")+(attention ? ". An outcome needs attention." : "")
        HStack(spacing: 0) {
            Button(action: openChat) {
                ZStack {
                    Circle().fill(palette[.accent].opacity(0.13))
                    if let progress {
                        Circle().stroke(palette[.accent].opacity(0.18), lineWidth: 2)
                        Circle().trim(from: 0, to: progress)
                            .stroke(palette[.accent], style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette[.accent])
                }.frame(width: 29, height: 29).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Open 3PO chat")
            .accessibilityLabel("Open 3PO chat")
            Button { activityOpen.toggle() } label: {
                HStack(spacing: 8) {
                    Text(message).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        .truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                    if active?.state == .running && progress == nil {
                        ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                    }
                    if attention || active?.state != .running {
                        Image(systemName: attention ? "exclamationmark.circle.fill" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(attention ? Color.orange : palette[.accent].opacity(0.8))
                    }
                }.foregroundStyle(palette[.text]).padding(.leading, 9).padding(.trailing, 7)
                    .frame(width: 237, height: 29).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(message)
            .accessibilityLabel("AI activity")
            .accessibilityValue(accessibilityStatus)
            .popover(isPresented: $activityOpen, arrowEdge: .bottom) {
                AIActivityView(store: store, registration: registration, current: active, palette: palette,
                               openChat: { activityOpen = false; openChat() },
                               openDestination: { activityOpen = false; openDestination($0) }, isVisible: isVisible,relatedDestinations:relatedDestinations)
            }
        }
        .padding(4)
        .background(palette[.widget].opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(attention ? Color.orange.opacity(0.55) : palette[.text].opacity(0.13), lineWidth: 0.75))
    }
}

/// Local inspection only. Navigation and acknowledgement make no source or AI requests.
struct AIActivityView: View {
    var store: AIActivityStore
    var registration: String
    var current: AIActivityRecord?
    var palette: WorkspacePalette
    var openChat: () -> Void
    var openDestination: (AIActivityDestination) -> Void
    var isVisible: (AIActivityRecord) -> Bool = { _ in true }
    var relatedDestinations:(AIActivityRecord)->[AIActivityDestination] = {_ in []}

    private var visibleCurrent: AIActivityRecord? { current.flatMap { $0.kind != .heartbeat && $0.registration == registration && isVisible($0) ? $0 : nil } }
    private var records: [AIActivityRecord] {
        let saved = store.records(registration).filter{$0.kind != .heartbeat && isVisible($0)}
        guard let current = visibleCurrent else { return saved }
        // A live snapshot augments the same event rather than rendering it twice.
        var merged = saved.filter { $0.id != current.id }
        var snapshot = current
        if let saved = saved.first(where: { $0.id == current.id }) { snapshot.acknowledged = saved.acknowledged }
        merged.insert(snapshot, at: 0)
        return merged
    }
    var body: some View {
        let shown=records
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AI activity").font(.title3.weight(.semibold))
                Spacer()
                Button(action: openChat) { Label("Open chat", systemImage: "bubble.left.and.bubble.right") }
                    .controlSize(.small)
            }
            if let error = store.error {
                Label(PAProse.display(error), systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if shown.isEmpty {
                Text("3PO is ready").font(.callout).foregroundStyle(palette[.text].opacity(0.66)).padding(.vertical, 14)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(shown) { record in activity(record) }
                    }.padding(.vertical, 1)
                }.frame(maxHeight: 380)
            }
            if store.undoDate(registration) != nil {
                Button("Undo acknowledgement") { store.undoAcknowledgement(registration) }.controlSize(.small)
            }
        }
        .padding(18).frame(width: 405)
        .foregroundStyle(palette[.text])
        .background(palette[.widget])
        .tint(palette[.accent])
    }
    private func activity(_ record: AIActivityRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: record.state.symbol).foregroundStyle(record.needsAttention ? Color.orange : palette[.accent])
                Text(PAProse.display(record.title)).font(.callout.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 6)
                Text(record.state.title).font(.caption2.weight(.medium))
                    .foregroundStyle(record.needsAttention ? Color.orange : palette[.text].opacity(0.62))
            }
            Text(AIActivityPresentation.message(record)).font(.callout).lineSpacing(2).textSelection(.enabled)
            if record.state == .running {ProgressView().controlSize(.small)}
            HStack(spacing: 5) {
                Text(record.kind.title)
                Text("·")
                Text(record.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                if record.acknowledged { Text("· Acknowledged") }
            }.font(.caption2).foregroundStyle(palette[.text].opacity(0.62))
            if !relatedDestinations(record).isEmpty {
                HStack(spacing:8) {ForEach(Array(relatedDestinations(record).enumerated()),id:\.offset) {_,destination in
                    Button {openDestination(destination)} label:{Label(destination.title,systemImage:destination.symbol)}
                }}.controlSize(.small)
            }
            HStack(spacing: 8) {
                if let destination = record.destination {
                    Button { openDestination(destination) } label: { Label(destination.title, systemImage: destination.symbol) }
                }
                if record.state.isTerminal && !record.acknowledged && !store.readOnly {
                    Spacer(minLength: 0)
                    Button("Acknowledge") { store.acknowledge(record.id, registration: registration) }
                        .help("Acknowledge this AI outcome. The underlying task and saved results are unchanged.")
                }
            }.controlSize(.small)
        }
        .padding(12)
        .background(palette[.accent].opacity(record.acknowledged ? 0.035 : 0.065), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(record.needsAttention ? Color.orange.opacity(0.28) : palette[.border].opacity(0.55), lineWidth: 0.7))
    }
}

private enum AIActivityPresentation {
    static func message(_ record: AIActivityRecord) -> String {
        let message = PAProse.display(record.message).trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = PAProse.display(record.title) + " · " + record.state.title.lowercased()
        let text = message.isEmpty ? fallback : message
        switch record.state {
        case .failed: return prefixed("Failed", text: text)
        case .partial: return prefixed("Partly completed", text: text)
        case .interrupted: return prefixed("Interrupted", text: text)
        case .uncertain: return prefixed("Outcome unconfirmed", text: text)
        case .needsAnswer: return prefixed("Needs your answer", text: text)
        default: return text
        }
    }
    private static func prefixed(_ label: String, text: String) -> String {
        text.lowercased().hasPrefix(label.lowercased()) ? text : label + ": " + text
    }
}
