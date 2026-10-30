import SwiftUI

/// Headline type chosen in Settings → Appearance; numbers keep SF Rounded.
enum WorkspaceHeadlineFont: String, CaseIterable, Identifiable {
    case serif, rounded, standard
    static let key = "workspaceHeadlineFont"
    var id: String { rawValue }
    var title: String { switch self { case .serif: "New York"; case .rounded: "SF Rounded"; case .standard: "SF Pro" } }
    var design: Font.Design { switch self { case .serif: .serif; case .rounded: .rounded; case .standard: .default } }
}

/// One header for every dashboard widget (30 October): an accent icon chip, the title as a small
/// spaced capital label, optional details, then the widget's own controls on the right.
struct WidgetHeader<Accessory: View>: View {
    var title: String
    var symbol: String
    var meta: String? = nil
    @ViewBuilder var accessory: Accessory
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette[.accent])
                .frame(width: 26, height: 26)
                .background(palette[.accent].opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.3)
                .foregroundStyle(palette[.accent]).lineLimit(1).layoutPriority(1)
                .accessibilityLabel(title).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let meta { Text(meta).font(.caption2).foregroundStyle(palette[.text].opacity(0.6)).lineLimit(1) }
            accessory
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 28)
    }
}
extension WidgetHeader where Accessory == EmptyView {
    init(title: String, symbol: String, meta: String? = nil) { self.init(title: title, symbol: symbol, meta: meta) { EmptyView() } }
}

/// The one line that matters in a widget, in the headline font from Settings.
struct WidgetHeadline: View {
    var text: String
    var size: CGFloat = 19
    var lines = 2
    @AppStorage(WorkspaceHeadlineFont.key) private var font = WorkspaceHeadlineFont.serif.rawValue
    var body: some View {
        let choice = WorkspaceHeadlineFont(rawValue: font) ?? .serif
        Text(text).font(.system(size: size, weight: choice == .standard ? .bold : .semibold, design: choice.design))
            .tracking(choice == .standard ? -0.3 : -0.2).lineLimit(lines).fixedSize(horizontal: false, vertical: true)
    }
}

/// A clock time in a fixed-width pill; red when it is a deadline.
struct TimePill: View {
    var text: String
    var urgent = false
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        let colour = urgent ? Color.red : palette[.accent]
        Text(text).font(.system(size: 11.5, weight: .semibold).monospacedDigit()).foregroundStyle(colour)
            .lineLimit(1).frame(minWidth: 44).padding(.horizontal, 6).padding(.vertical, 3)
            .background(colour.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// When a reminder is due: red for today or overdue, orange for tomorrow, grey for later.
struct DueBadge: View {
    var due: Date
    var hasTime: Bool
    var now = Date.now
    @Environment(\.workspacePalette) private var palette
    @Environment(\.colorScheme) private var scheme
    enum Urgency { case overdue, today, tomorrow, later }
    static func urgency(_ due: Date, hasTime: Bool, now: Date, calendar: Calendar = .current) -> Urgency {
        let today = calendar.startOfDay(for: now)
        if due < today || hasTime && due < now { return .overdue }
        if calendar.isDate(due, inSameDayAs: now) { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), calendar.isDate(due, inSameDayAs: tomorrow) { return .tomorrow }
        return .later
    }
    static func label(_ due: Date, hasTime: Bool, now: Date, calendar: Calendar = .current) -> String {
        let time = due.formatted(date: .omitted, time: .shortened)
        switch urgency(due, hasTime: hasTime, now: now, calendar: calendar) {
        case .overdue: return calendar.isDate(due, inSameDayAs: now) && hasTime ? time : due.formatted(.dateTime.day().month(.abbreviated))
        case .today: return hasTime ? time : "Today"
        case .tomorrow: return "Tomorrow"
        case .later:
            let week = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
            return due < week ? due.formatted(.dateTime.weekday(.abbreviated)) : due.formatted(.dateTime.day().month(.abbreviated))
        }
    }
    var body: some View {
        let urgency = Self.urgency(due, hasTime: hasTime, now: now)
        let colour: Color? = urgency == .overdue || urgency == .today ? .red : urgency == .tomorrow ? .orange : nil
        Text(Self.label(due, hasTime: hasTime, now: now)).font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(colour ?? palette[.text].opacity(0.7)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((colour ?? palette[.text]).opacity(colour == nil ? 0.07 : scheme == .dark ? 0.2 : 0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel((urgency == .overdue ? "Overdue, " : "Due ") + due.formatted(date: .abbreviated, time: hasTime ? .shortened : .omitted))
    }
}

/// Motion from Settings → Appearance and System Settings; Reduced wins either way.
struct MotionPreference: DynamicProperty {
    @AppStorage(WorkspaceStyleKey.motion) private var setting = WorkspaceMotion.full.rawValue
    @Environment(\.accessibilityReduceMotion) private var system
    var reduced: Bool { system || setting == WorkspaceMotion.reduced.rawValue }
    func animation(_ animation: Animation) -> Animation? { reduced ? nil : animation }
}
/// Digits roll to their new value instead of jumping.
struct RollingNumber<Value: Equatable>: ViewModifier {
    var value: Value
    private var motion = MotionPreference()
    func body(content: Content) -> some View {
        content.contentTransition(motion.reduced ? .identity : .numericText()).animation(motion.animation(.smooth(duration: 0.4)), value: value)
    }
}
extension View {
    func rollingNumber<Value: Equatable>(_ value: Value) -> some View { modifier(RollingNumber(value: value)) }
}
