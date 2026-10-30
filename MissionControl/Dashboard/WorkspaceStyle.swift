import SwiftUI
import AppKit

/// Dashboard look chosen in Settings → Appearance (30 October). Stored per Mac beside the
/// colour theme. Reduce Transparency and Reduce Motion in System Settings always win.
enum WorkspaceStyleKey {
    static let surface = "workspaceSurface"
    static let backdrop = "workspaceBackdrop"
    static let glowFollowsTime = "workspaceGlowFollowsTime"
    static let motion = "workspaceMotion"
}
/// The compact toolbar is 40 points tall and doesn't grow for taller items. The canvas starts right
/// under it, and the 34-point pill leaves 3 points above and below, midway between window and dashboard.
enum WorkspaceChrome {
    static let toolbarItemHeight: CGFloat = 40
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
    static let radius: CGFloat = 22
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let glass = surface == WorkspaceSurface.glass.rawValue && !reduceTransparency
        let dark = scheme == .dark
        content
            .background {
                if glass { shape.fill(palette[.widget].opacity(dark ? 0.5 : 0.55)).background(.ultraThinMaterial, in: shape) }
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
            .shadow(color: .black.opacity(lifted ? 0.16 : dark ? 0.32 : 0.08), radius: lifted ? 22 : 16, y: lifted ? 10 : 7)
    }
}
extension View {
    func workspaceSurface(_ palette: WorkspacePalette, highlight: Color? = nil, lifted: Bool = false) -> some View {
        modifier(WorkspaceSurfaceModifier(palette: palette, highlight: highlight, lifted: lifted))
    }
}

/// The dashboard background. The glow only uses the theme's accent, a neighbouring shade and the
/// user-bubble colour; following the time of day moves it and adds a slight warm or cool cast.
struct WorkspaceBackdropView: View {
    var palette: WorkspacePalette
    @AppStorage(WorkspaceStyleKey.backdrop) private var backdrop = WorkspaceBackdrop.ambient.rawValue
    @AppStorage(WorkspaceStyleKey.glowFollowsTime) private var followsTime = true
    @AppStorage(WorkspaceStyleKey.motion) private var motion = WorkspaceMotion.full.rawValue
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var drifting = false
    private var still: Bool { motion == WorkspaceMotion.reduced.rawValue || systemReduceMotion }
    var body: some View {
        ZStack {
            palette[.canvas]
            if backdrop == WorkspaceBackdrop.ambient.rawValue {
                TimelineView(.periodic(from: .now, by: 300)) { context in
                    glow(GlowPeriod(date: context.date, follows: followsTime))
                }
                .scaleEffect(drifting ? 1.06 : 1)
                .offset(x: drifting ? 18 : -12, y: drifting ? -14 : 10)
                .animation(still ? nil : .easeInOut(duration: 26).repeatForever(autoreverses: true), value: drifting)
                .onAppear { drifting = !still }
                .onChange(of: still) { drifting = !still }
            }
        }
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
/// Where the glow sits at each time of day. Not following the time keeps one fixed arrangement.
struct GlowPeriod: Equatable {
    var spots: [UnitPoint]
    var intensity = 1.0
    var cast = Color.white
    var castAmount = 0.0
    init(date: Date, follows: Bool, calendar: Calendar = .current) {
        guard follows else { spots = [.init(x: 0.18, y: 0.18), .init(x: 0.82, y: 0.22), .init(x: 0.55, y: 0.95)]; return }
        switch calendar.component(.hour, from: date) {
        case 5..<11:
            spots = [.init(x: 0.1, y: 0.92), .init(x: 0.42, y: 0.12), .init(x: 0.88, y: 0.78)]
            cast = Color(red: 1, green: 0.70, blue: 0.48); castAmount = 0.16
        case 11..<17:
            spots = [.init(x: 0.5, y: 0), .init(x: 0.88, y: 0.35), .init(x: 0.12, y: 0.7)]
            intensity = 1.1
        case 17..<21:
            spots = [.init(x: 0.9, y: 0.9), .init(x: 0.62, y: 0.28), .init(x: 0.1, y: 0.18)]
            cast = Color(red: 1, green: 0.5, blue: 0.4); castAmount = 0.16
        default:
            spots = [.init(x: 0.22, y: 0.08), .init(x: 0.8, y: 0.88), .init(x: 0.5, y: 0.5)]
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
            Text("Reduced keeps the background and the toolbar orb still. Reduce motion in System Settings does the same.").font(.caption).foregroundStyle(.secondary)
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
