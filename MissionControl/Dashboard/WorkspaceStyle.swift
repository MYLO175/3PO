import SwiftUI
import AppKit

/// Dashboard look chosen in Settings → Appearance (30 October). Stored per Mac beside the
/// colour theme. Reduce Transparency and Reduce Motion in System Settings always win.
enum WorkspaceStyleKey {
    static let surface = "workspaceSurface"
    static let backdrop = "workspaceBackdrop"
    static let glowFollowsTime = "workspaceGlowFollowsTime"
    static let motion = "workspaceMotion"
    static let switcher = "workspaceDashboardSwitcher"
}
/// Where the dashboards are listed: icons in the top bar (full-width dashboard) or the sidebar.
enum WorkspaceSwitcher: String, CaseIterable, Identifiable {
    case topBar, sidebar
    var id: String { rawValue }
    var title: String { self == .topBar ? "Top bar" : "Sidebar" }
}
/// The standard (non-compact) toolbar is 52 points; the 34-point pill leaves even space above and below;
/// the canvas starts right under it, so the pill sits midway between window and dashboard.
enum WorkspaceChrome {
    static let toolbarItemHeight: CGFloat = 52
}
enum WorkspaceSurface: String, CaseIterable, Identifiable {
    case glass, solid
    var id: String { rawValue }
    var title: String { self == .glass ? "Glass" : "Solid" }
}
enum WorkspaceBackdrop: String, CaseIterable, Identifiable {
    case ambient, plain
    var id: String { rawValue }
    var title: String { self == .ambient ? "Ambient glow" : "Plain" }
}
enum WorkspaceMotion: String, CaseIterable, Identifiable {
    case full, reduced
    var id: String { rawValue }
    var title: String { self == .full ? "Full" : "Reduced" }
}

/// Lighter and deeper neighbours of a theme accent, so new effects work for every preset and custom theme.
struct ThemeTones {
    var hue: Double, saturation: Double
    init(_ accent: Color) {
        let colour = NSColor(accent).usingColorSpace(.sRGB) ?? .systemBlue
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h); saturation = min(1, max(0.35, Double(s) * 1.1))
    }
    func tone(hueShift: Double = 0, saturation scale: Double = 1, brightness: Double) -> SIMD3<Double> {
        let colour = NSColor(hue: CGFloat((hue + hueShift + 1).truncatingRemainder(dividingBy: 1)), saturation: CGFloat(min(1, saturation * scale)), brightness: CGFloat(brightness), alpha: 1)
        let rgb = colour.usingColorSpace(.sRGB) ?? colour
        return SIMD3(Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
    }
}
extension Color {
    init(_ rgb: SIMD3<Double>) { self.init(.sRGB, red: rgb.x, green: rgb.y, blue: rgb.z) }
}

private struct InWorkspaceTileKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True inside a dashboard tile, whose surface replaces a panel's own background.
    var inWorkspaceTile: Bool { get { self[InWorkspaceTileKey.self] } set { self[InWorkspaceTileKey.self] = newValue } }
}

/// One widget surface for every tile: frosted glass over the backdrop, or a solid lifted card.
struct WorkspaceSurfaceModifier: ViewModifier {
    var palette: WorkspacePalette
    var highlight: Color?
    var lifted = false
    @AppStorage(WorkspaceStyleKey.surface) private var surface = WorkspaceSurface.glass.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    private var motion = MotionPreference()
    static let radius: CGFloat = 22
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let glass = surface == WorkspaceSurface.glass.rawValue && !reduceTransparency
        let dark = scheme == .dark
        content
            .background {
                // Glass must read as a layer above the glow: more frosted, and tinted with a less saturated
                // widget colour so it never matches the glow behind it, with its own light along the top.
                if glass {
                    shape.fill(palette[.widget].mix(with: dark ? Color(white: 0.1) : .white, by: dark ? 0.45 : 0.35).opacity(dark ? 0.72 : 0.68))
                        .background(.regularMaterial, in: shape)
                        .overlay(shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.07 : 0.3), .white.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3))))
                }
                else { shape.fill(palette[.widget]) }
            }
            .clipShape(shape)
            .overlay {
                if let highlight { shape.strokeBorder(highlight, lineWidth: 2) }
                else {
                    // The theme's border role still draws; glass adds a light top edge over it.
                    shape.strokeBorder(palette[.border], lineWidth: 1)
                    if glass { shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.12 : 0.6), .white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 1) }
                }
            }
            .shadow(color: .black.opacity(lifted ? 0.16 : hovering ? (dark ? 0.55 : 0.12) : dark ? 0.45 : 0.08), radius: lifted || hovering ? 22 : 18, y: lifted || hovering ? 10 : 8)
            .offset(y: hovering && highlight == nil && !motion.reduced ? -2 : 0)
            .onHover { inside in withAnimation(motion.animation(.smooth(duration: 0.25))) { hovering = inside } }
    }
}
extension View {
    func workspaceSurface(_ palette: WorkspacePalette, highlight: Color? = nil, lifted: Bool = false) -> some View {
        modifier(WorkspaceSurfaceModifier(palette: palette, highlight: highlight, lifted: lifted))
    }
}

/// The dashboard background. The glow only uses the theme's accent, a neighbouring shade and the
/// user-bubble colour; following the time of day moves it and adds a slight warm or cool cast.
/// It stays still between those moves: a constantly drifting backdrop made every glass widget
/// re-blur each frame. It is clipped and never takes clicks, so it can't cover the sidebar.
struct WorkspaceBackdropView: View {
    var palette: WorkspacePalette
    @AppStorage(WorkspaceStyleKey.backdrop) private var backdrop = WorkspaceBackdrop.ambient.rawValue
    @AppStorage(WorkspaceStyleKey.glowFollowsTime) private var followsTime = true
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            palette[.canvas]
            if backdrop == WorkspaceBackdrop.ambient.rawValue {
                TimelineView(.periodic(from: .now, by: 300)) { context in
                    glow(GlowPeriod(date: context.date, follows: followsTime))
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    private func glow(_ period: GlowPeriod) -> some View {
        let tones = ThemeTones(palette[.accent]), dark = scheme == .dark
        let lift = dark ? 0.55 : 0.82
        let first = Color(tones.tone(brightness: lift)).mix(with: period.cast, by: period.castAmount)
        let second = Color(tones.tone(hueShift: 0.06, saturation: 0.8, brightness: dark ? 0.5 : 0.86)).mix(with: period.cast, by: period.castAmount)
        let strength = (dark ? 0.32 : 0.42) * period.intensity
        return ZStack {
            spot(first.opacity(strength), at: period.spots[0], size: 0.95)
            spot(second.opacity(strength), at: period.spots[1], size: 1.05)
            spot(palette[.userBubble].opacity(strength * 0.8), at: period.spots[2], size: 0.9)
        }
        .padding(-80)
        .animation(.easeInOut(duration: 3), value: period)
    }
    private func spot(_ colour: Color, at point: UnitPoint, size: Double) -> some View {
        EllipticalGradient(colors: [colour, colour.opacity(0)], center: point, startRadiusFraction: 0, endRadiusFraction: 0.5 * size)
    }
}
/// Where the glow sits at each time of day. Its bright patches stay in the lower half and at the sides,
/// away from widget tops where the glass carries its own light. Not following the time keeps one arrangement.
struct GlowPeriod: Equatable {
    var spots: [UnitPoint]
    var intensity = 1.0
    var cast = Color.white
    var castAmount = 0.0
    init(date: Date, follows: Bool, calendar: Calendar = .current) {
        guard follows else { spots = [.init(x: 0.12, y: 0.9), .init(x: 0.88, y: 0.85), .init(x: 0.5, y: 1.05)]; return }
        switch calendar.component(.hour, from: date) {
        case 5..<11:
            spots = [.init(x: 0.06, y: 0.95), .init(x: 0.45, y: 1.05), .init(x: 0.95, y: 0.7)]
            cast = Color(red: 1, green: 0.70, blue: 0.48); castAmount = 0.16
        case 11..<17:
            spots = [.init(x: 0.5, y: 1.08), .init(x: 0.04, y: 0.65), .init(x: 0.96, y: 0.65)]
            intensity = 1.1
        case 17..<21:
            spots = [.init(x: 0.94, y: 0.95), .init(x: 0.6, y: 1.05), .init(x: 0.04, y: 0.78)]
            cast = Color(red: 1, green: 0.5, blue: 0.4); castAmount = 0.16
        default:
            spots = [.init(x: 0.15, y: 1.02), .init(x: 0.85, y: 0.92), .init(x: 0.5, y: 0.8)]
            intensity = 0.65; cast = Color(red: 0.36, green: 0.42, blue: 1); castAmount = 0.12
        }
    }
}

/// Settings → Appearance. Native form chrome; the dashboard follows each change immediately.
struct AppearanceSettings: View {
    @AppStorage("workspaceAppearance") private var appearance = "system"
    @AppStorage("workspaceColorOverrides") private var colours = "{}"
    @AppStorage("workspaceSelectedSavedTheme") private var selectedSavedTheme = ""
    @AppStorage("workspaceSavedThemes") private var savedThemes = "{}"
    @AppStorage(WorkspaceStyleKey.surface) private var surface = WorkspaceSurface.glass.rawValue
    @AppStorage(WorkspaceStyleKey.backdrop) private var backdrop = WorkspaceBackdrop.ambient.rawValue
    @AppStorage(WorkspaceStyleKey.glowFollowsTime) private var followsTime = true
    @AppStorage(WorkspaceStyleKey.motion) private var motion = WorkspaceMotion.full.rawValue
    @AppStorage(WorkspaceHeadlineFont.key) private var headline = WorkspaceHeadlineFont.serif.rawValue
    @AppStorage(WorkspaceStyleKey.switcher) private var switcher = WorkspaceSwitcher.topBar.rawValue
    @Environment(\.colorScheme) private var scheme
    @State private var editingColours = false
    @State private var replacing: WorkspaceColorTheme?
    private var overrides: WorkspaceColorOverrides { .init(raw: colours) }
    private var current: WorkspaceColorTheme? { WorkspaceColorTheme.allCases.first { $0.profiles == overrides.profiles } }
    private var currentName: String {
        if let current { return current.title }
        if let saved = (try? WorkspaceThemeLibrary(raw: savedThemes))?.themes.first(where: { $0.id.uuidString == selectedSavedTheme }) { return saved.name }
        return overrides.profiles.isEmpty ? "Theme defaults" : "Custom colours"
    }
    var body: some View {
        Section("Colours") {
            LabeledContent("Theme") {
                HStack(spacing: 9) {
                    ForEach(WorkspaceColorTheme.allCases) { preset in
                        Button { choose(preset) } label: { swatch(preset) }
                            .buttonStyle(.plain).help(preset.title + " · " + preset.detail).accessibilityLabel(preset.title)
                            .accessibilityAddTraits(preset == current ? .isSelected : [])
                    }
                }
            }
            LabeledContent(currentName) { Button("Customise colours…") { editingColours = true } }
            Picker("Light or dark", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                .pickerStyle(.segmented)
        }
        Section {
            Picker("Dashboards", selection: $switcher) { ForEach(WorkspaceSwitcher.allCases) { Text($0.title).tag($0.rawValue) } }.pickerStyle(.segmented)
        } header: { Text("Layout") } footer: {
            Text("Top bar shows each dashboard as an icon beside the window controls, and the dashboard fills the window. Add a dashboard in Edit layout.").font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Picker("Widgets", selection: $surface) { ForEach(WorkspaceSurface.allCases) { Text($0.title).tag($0.rawValue) } }.pickerStyle(.segmented)
            Picker("Background", selection: $backdrop) { ForEach(WorkspaceBackdrop.allCases) { Text($0.title).tag($0.rawValue) } }.pickerStyle(.segmented)
            Toggle("Follow the time of day", isOn: $followsTime).disabled(backdrop != WorkspaceBackdrop.ambient.rawValue)
        } header: { Text("Surfaces") } footer: {
            Text("Solid is used automatically when Reduce transparency is on. The glow always uses your theme’s colours; following the time of day only moves it and warms or cools it slightly.").font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Picker("Headlines", selection: $headline) { ForEach(WorkspaceHeadlineFont.allCases) { Text($0.title).tag($0.rawValue) } }.pickerStyle(.segmented)
        } header: { Text("Type") } footer: {
            Text("Used for the brief’s greeting and the one line under a widget’s title. Numbers stay in SF Rounded.").font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Picker("Animations", selection: $motion) { ForEach(WorkspaceMotion.allCases) { Text($0.title).tag($0.rawValue) } }.pickerStyle(.segmented)
        } header: { Text("Motion") } footer: {
            Text("Reduced keeps the pill’s bars still and turns off moving numbers and sliding highlights. Reduce motion in System Settings does the same.").font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $editingColours) { WorkspaceColorEditor() }
        .confirmationDialog("Replace your custom colours?", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }), presenting: replacing) { preset in
            Button("Use " + preset.title) { apply(preset) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("Your current colours aren’t saved as a theme. Save them first in Customise colours to keep them.") }
    }
    private func swatch(_ preset: WorkspaceColorTheme) -> some View {
        let profile = preset.profile(scheme == .dark ? "dark" : "light")
        func colour(_ role: WorkspaceColorRole) -> Color {
            guard let hex = profile[role.rawValue], let (r, g, b) = WorkspaceColorOverrides.components(hex) else { return .gray }
            return Color(.sRGB, red: r, green: g, blue: b)
        }
        return Circle().fill(LinearGradient(stops: [.init(color: colour(.canvas), location: 0.5), .init(color: colour(.accent), location: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
            .frame(width: 22, height: 22)
            .padding(2)
            .overlay(Circle().strokeBorder(preset == current ? Color.accentColor : .clear, lineWidth: 2))
    }
    /// Custom colours that aren't a preset or a saved theme are confirmed before a preset replaces them.
    private func choose(_ preset: WorkspaceColorTheme) {
        guard preset != current else { return }
        let unsaved = current == nil && !overrides.profiles.isEmpty && selectedSavedTheme.isEmpty
        if unsaved { replacing = preset } else { apply(preset) }
    }
    private func apply(_ preset: WorkspaceColorTheme) {
        var value = overrides
        value.profiles = preset.profiles
        colours = value.encoded
        selectedSavedTheme = ""
    }
}
