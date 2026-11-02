import SwiftUI

/// Headline type chosen in Settings → Appearance; numbers keep SF Rounded.
enum WorkspaceHeadlineFont: String, CaseIterable, Identifiable {
    case serif, rounded, standard
    static let key = "workspaceHeadlineFont"
    var id: String { rawValue }
    var title: String { switch self { case .serif: "New York"; case .rounded: "SF Rounded"; case .standard: "SF Pro" } }
    var design: Font.Design { switch self { case .serif: .serif; case .rounded: .rounded; case .standard: .default } }
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

private struct WidgetLayoutKey: EnvironmentKey { static let defaultValue = WidgetLayout.large }
extension EnvironmentValues {
    /// The tile's arrangement from its grid size; the full widget outside dashboard tiles.
    var widgetLayout: WidgetLayout { get { self[WidgetLayoutKey.self] } set { self[WidgetLayoutKey.self] = newValue } }
}

/// A glance's headline number: a big rounded count over a short label ("3" / "due today").
struct GlanceCount: View {
    var value: Int
    var label: String
    var urgent = false
    @Environment(\.workspacePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(urgent ? Color.red : palette[.text]).rollingNumber(value)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(palette[.text].opacity(0.6)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}

/// A glance's rows: as many as fit, side by side in columns once the widget is wide, with
/// "N more" when some are left out. A tall widget scrolls through them all instead.
struct GlanceRows<Item: Identifiable, Row: View>: View {
    var items: [Item]
    var rowHeight: CGFloat
    var empty: String
    var scrolls = false
    var columnWidth: CGFloat = 210
    @ViewBuilder var row: (Item) -> Row
    @Environment(\.workspacePalette) private var palette
    private let spacing: CGFloat = 6
    var body: some View {
        if items.isEmpty {
            Text(empty).font(.callout).foregroundStyle(palette[.text].opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if scrolls {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: spacing) { ForEach(items) { row($0).frame(minHeight: rowHeight, alignment: .leading) } }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.never).scrollEdgeFade()
        } else {
            GeometryReader { geometry in
                let columns = max(1, Int((geometry.size.width + 14) / (columnWidth + 14)))
                let perColumn = max(1, Int((geometry.size.height + spacing) / (rowHeight + spacing)))
                // When some are left out, the last column gives up only enough height for one caption line.
                let lastColumn = items.count > columns * perColumn ? Int((geometry.size.height - 14) / (rowHeight + spacing)) : perColumn
                let shown = Array(items.prefix(max(1, (columns - 1) * perColumn + lastColumn)))
                HStack(alignment: .top, spacing: 14) {
                    ForEach(0..<columns, id: \.self) { column in
                        VStack(alignment: .leading, spacing: spacing) {
                            ForEach(Array(shown.dropFirst(column * perColumn).prefix(perColumn))) { row($0).frame(height: rowHeight, alignment: .leading) }
                            if column == columns - 1, items.count > shown.count {
                                Text("\(items.count - shown.count) more").font(.caption2.weight(.medium)).foregroundStyle(palette[.text].opacity(0.55)).lineLimit(1)
                            }
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
    }
}
