import SwiftUI

/// One toolbar item: the circular shortcut opens chat; its message opens saved Activity.
struct AIActivityPill: View {
    var store: AIActivityStore
    var registration: String
    var current: AIActivityRecord?
    var feedback: AIActivityFeedback? = nil
    var palette: WorkspacePalette
    var openChat: () -> Void
    var openDestination: (AIActivityDestination) -> Void
    var isVisible: (AIActivityRecord) -> Bool = { _ in true }
    var relatedDestinations:(AIActivityRecord)->[AIActivityDestination] = {_ in []}
    var presentation:(AIActivityRecord)->AIActivityRecord = {$0}
    /// A chat reply is being written; it has no activity record but the orb should look busy.
    var busy = false
    @State private var activityOpen = false
    @AppStorage(WorkspaceStyleKey.motion) private var motion = WorkspaceMotion.full.rawValue
    @AppStorage(WorkspaceStyleKey.surface) private var surface = WorkspaceSurface.glass.rawValue
    @State private var outcomeClock = Date.now
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Resolve history/visibility once, rather than once for every label,
        // progress and accessibility property in this toolbar render.
        let originals=store.records(registration).filter{isVisible($0)}
        let saved=originals.map(presentation)
        let active:AIActivityRecord? = {
            guard var current,current.state == .running,current.registration == registration,isVisible(current) else {return nil}
            if let saved=saved.first(where:{$0.id == current.id}) {current.acknowledged=saved.acknowledged}
            return current
        }()
        let now=max(outcomeClock,.now)
        let displayed=AIActivityPillRules.displayed(saved,current:active,registration:registration,now:now)
        let confirmation=store.error == nil ? AIActivityPillRules.feedback(feedback,displayed:displayed,registration:registration,now:now) : nil
        let successExpiry=displayed.flatMap{$0.state == .succeeded ? $0.date.addingTimeInterval(AIActivityPillRules.successDuration) : nil}
        let expiry=[confirmation?.expiry,successExpiry,AIActivitySummary.nextExpiry(saved,registration:registration,now:now)].compactMap{$0}.min()
        let attention = saved.contains{$0.registration == registration && AIActivitySummary.includesNotification($0,now:now) && $0.needsAttention} || store.error != nil
        let dismissible=active == nil && store.error == nil && displayed?.needsAttention == true
            ? originals.first{$0.id == displayed?.id && $0.needsAttention} : nil
        let success=confirmation != nil || active == nil && displayed?.state == .succeeded
        let failed=active == nil && displayed?.state.isFailure == true
        let successColour=scheme == .dark ? Color(red:0.44,green:0.83,blue:0.55) : Color(red:0.10,green:0.43,blue:0.22)
        let needsYou=active == nil && (displayed?.needsAttention == true || store.error != nil)
        let statusColour:Color=success ? successColour : failed || needsYou ? .red : palette[.text]
        let progress:Double?=nil
        let mood:SwirlOrb.Mood=active.map{$0.kind == .heartbeat ? .working($0.progress) : .thinking} ?? (busy ? .thinking : success ? .done : failed || needsYou || attention ? .attention : .ready)
        let message=store.error ?? confirmation.map{PAProse.display($0.message)} ?? displayed.map{AIActivityPresentation.message($0,compact:true)} ?? "3PO is ready"
        let accessibilityStatus=message+(progress.map{". \(Int($0*100)) percent progress."} ?? "")+(attention ? ". An outcome needs attention." : "")
        HStack(spacing: 0) {
            Button(action: openChat) {
                SwirlOrb(mood:mood,accent:palette[.accent],size:30,reduceMotion:motion == WorkspaceMotion.reduced.rawValue)
                    .frame(width: 34, height: 34).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Open 3PO chat")
            .accessibilityLabel("Open 3PO chat")
            Button { activityOpen.toggle() } label: {
                HStack(spacing: 8) {
                    Text(message).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        .truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                    if active?.state == .running && progress == nil {
                        ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                    }
                    if attention || active?.state != .running {
                        Image(systemName: success ? "checkmark.circle.fill" : displayed?.state == .needsAnswer ? "questionmark.circle.fill" : attention ? "exclamationmark.circle.fill" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(success ? successColour : failed || attention ? Color.red : palette[.accent].opacity(0.8))
                    }
                }.foregroundStyle(statusColour).padding(.leading, 9).padding(.trailing, 7)
                    .frame(width: dismissible == nil ? 268 : 244, height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(message)
            .accessibilityLabel("AI activity")
            .accessibilityValue(accessibilityStatus)
            .popover(isPresented: $activityOpen, arrowEdge: .bottom) {
                AIActivityView(store: store, registration: registration, current: active, palette: palette, now:now,
                               openChat: { activityOpen = false; openChat() },
                               openDestination: { activityOpen = false; openDestination($0) }, isVisible: isVisible,relatedDestinations:relatedDestinations,presentation:presentation)
            }
            if let record=dismissible {
                Button { _=store.dismiss(record,registration:registration) } label: {
                    Image(systemName:"xmark").font(.system(size:10,weight:.semibold))
                        .frame(width:24,height:34).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(statusColour)
                .disabled(store.readOnly)
                .help("Dismiss this alert")
                .accessibilityLabel(record.kind == .heartbeat ? "Dismiss heartbeat alert" : "Dismiss AI activity alert")
                .accessibilityHint("Removes this notification without deleting its saved outcome.")
                .accessibilityIdentifier("aiActivityDismissAlert")
            }
        }
        .padding(.horizontal,4)
        .padding(.vertical,2)
        .background(success ? successColour.opacity(0.08) : .clear, in: Capsule())
        .background(palette[.widget].opacity(surface == WorkspaceSurface.glass.rawValue ? 0.62 : 0.92), in: Capsule())
        .background(surface == WorkspaceSurface.glass.rawValue ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.clear), in: Capsule())
        .overlay(Capsule().stroke(success ? successColour.opacity(0.4) : failed || attention ? Color.red.opacity(0.45) : palette[.text].opacity(0.13), lineWidth: 0.75))
        .task(id:expiry) {
            guard let expiry else {return}
            let remaining=expiry.timeIntervalSinceNow
            if remaining > 0 {try? await Task.sleep(for:.seconds(remaining))}
            guard !Task.isCancelled else {return}
            outcomeClock = .now
        }

    }
}

/// Local inspection only. Navigation makes no source or AI requests.
struct AIActivityView: View {
    var store: AIActivityStore
    var registration: String
    var current: AIActivityRecord?
    var palette: WorkspacePalette
    var now:Date
    var openChat: () -> Void
    var openDestination: (AIActivityDestination) -> Void
    var isVisible: (AIActivityRecord) -> Bool = { _ in true }
    var relatedDestinations:(AIActivityRecord)->[AIActivityDestination] = {_ in []}
    var presentation:(AIActivityRecord)->AIActivityRecord = {$0}

    @Environment(\.colorScheme) private var scheme
    private var visibleCurrent: AIActivityRecord? { current.flatMap { $0.kind != .heartbeat && $0.registration == registration && isVisible($0) ? $0 : nil } }
    private var records: [AIActivityRecord] {
        let saved = store.records(registration).filter{isVisible($0)}.map(presentation)
        return AIActivitySummary.recent(saved,current:visibleCurrent,registration:registration,now:now)
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
        }
        .padding(18).frame(width: 405)
        .foregroundStyle(palette[.text])
        .background(palette[.widget])
        .tint(palette[.accent])
    }
    private func activity(_ record: AIActivityRecord) -> some View {
        let colour:Color=record.state == .succeeded ? (scheme == .dark ? Color(red:0.44,green:0.83,blue:0.55) : Color(red:0.10,green:0.43,blue:0.22)) : record.state.isFailure ? .red : record.state == .needsAnswer ? .orange : palette[.text]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment:.top,spacing:8) {
                Image(systemName:record.state.symbol)
                Text(AIActivityPresentation.message(record)).font(.callout.weight(.medium)).lineLimit(3).textSelection(.enabled)
            }.foregroundStyle(colour)
            if record.state == .running {ProgressView().controlSize(.small)}
            if record.kind == .review || record.kind == .feedback {
                Text(PAProse.display(record.title)).font(.caption).foregroundStyle(palette[.text].opacity(0.66)).lineLimit(1)
            }
            HStack {
                if let destination=record.destination {
                    Button {openDestination(destination)} label:{Label(destination.title,systemImage:destination.symbol)}.controlSize(.small)
                }
                if record.needsAttention,let original=store.state.records.first(where:{$0.registration == registration && $0.id == record.id && $0.needsAttention}) {
                    Button("Dismiss") { _=store.dismiss(original,registration:registration) }
                        .controlSize(.small).disabled(store.readOnly)
                        .help("Remove this notification without deleting its saved outcome")
                        .accessibilityLabel(record.kind == .heartbeat ? "Dismiss heartbeat alert" : "Dismiss AI activity alert")
                        .accessibilityIdentifier("aiActivityDismissAlert-"+record.id)
                }
                Spacer(minLength:4)
                Text(record.date,format:.dateTime.day().month(.abbreviated).hour().minute()).font(.caption2).foregroundStyle(palette[.text].opacity(0.62))
            }
        }
        .padding(12)
        .background(colour.opacity(0.045),in:RoundedRectangle(cornerRadius:11))
        .overlay(RoundedRectangle(cornerRadius:11).stroke(colour.opacity(record.state == .succeeded || record.state.needsAttention ? 0.3 : 0.15),lineWidth:0.7))
    }
}

private enum AIActivityPresentation {
    static func message(_ record: AIActivityRecord,compact:Bool = false) -> String {
        let message=AIActivitySummary.text(PAProse.display(record.message),compact:compact && record.state == .succeeded)
        let text=message.isEmpty ? PAProse.display(record.title) : message
        switch record.state {
        case .failed:return prefixed(record.kind == .heartbeat ? "Heartbeat failed" : "Failed",text:text)
        case .partial:return prefixed(record.kind == .heartbeat ? "Heartbeat partly completed" : "Partly completed",text:text)
        case .interrupted:return prefixed("Interrupted",text:text)
        case .uncertain:return prefixed("Save needs checking",text:text)
        case .needsAnswer:return prefixed("Needs your answer",text:text)
        case .running:return record.kind == .heartbeat ? "Heartbeat running…" : record.kind == .review ? "Working on "+PAProse.display(record.title) : "Working on your actions…"
        default:return text
        }
    }
    private static func prefixed(_ label:String,text:String)->String {
        text.lowercased().hasPrefix(label.lowercased()) ? text : label+": "+text
    }
}
