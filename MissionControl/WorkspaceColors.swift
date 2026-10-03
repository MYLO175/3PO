import SwiftUI
import AppKit

struct WorkspaceColorOverrides: Codable {
    var profiles: [String:[String:String]] = [:]
    init(raw: String) { self = (try? JSONDecoder().decode(Self.self,from:Data(raw.utf8))) ?? Self() }
    init() {}
    var encoded: String { String(data:(try? JSONEncoder().encode(self)) ?? Data(),encoding:.utf8) ?? "{}" }
    static func components(_ hex: String) -> (Double,Double,Double)? {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard value.count == 6, value.allSatisfy({ $0.isHexDigit }), let number = UInt32(value,radix:16) else { return nil }
        return (Double((number >> 16) & 255)/255,Double((number >> 8) & 255)/255,Double(number & 255)/255)
    }
    func color(_ role: WorkspaceColorRole, mode: String) -> Color? {
        guard let hex = profiles[mode]?[role.rawValue], let (r,g,b) = Self.components(hex) else { return nil }
        return Color(.sRGB,red:r,green:g,blue:b,opacity:1)
    }
    mutating func set(_ role: WorkspaceColorRole, mode: String, color: Color?) {
        if let color, let rgb = NSColor(color).usingColorSpace(.sRGB) {
            profiles[mode,default:[:]][role.rawValue] = String(format:"#%02X%02X%02X",Int((rgb.redComponent*255).rounded()),Int((rgb.greenComponent*255).rounded()),Int((rgb.blueComponent*255).rounded()))
        } else { profiles[mode]?[role.rawValue] = nil }
    }
}
enum WorkspaceColorRole: String, CaseIterable, Identifiable {
    case canvas, sidebar, widget, text, accent, border, assistantBubble, userBubble, input
    var id: String { rawValue }
    var title: String { switch self {
    case .canvas:return "Dashboard background"; case .sidebar:return "Sidebar background"; case .widget:return "Widget background"
    case .text:return "Text"; case .accent:return "Accent and controls"; case .border:return "Widget borders"
    case .assistantBubble:return "PA message bubbles"; case .userBubble:return "Your message bubbles"; case .input:return "Chat input background"
    } }
}
struct WorkspacePalette {
    var colors: [WorkspaceColorRole:Color]
    subscript(_ role: WorkspaceColorRole) -> Color { colors[role]! }
    static func resolved(raw: String, mode: String, theme: String, accent: String) -> Self {
        let dark = mode == "dark", overrides = WorkspaceColorOverrides(raw:raw)
        func native(_ value: NSColor) -> Color {
            let appearance = NSAppearance(named:dark ? .darkAqua : .aqua)!
            var result = value
            appearance.performAsCurrentDrawingAppearance { result = value.usingColorSpace(.sRGB) ?? value }
            return Color(nsColor:result)
        }
        let tint: Color = accent == "blue" ? .blue : accent == "rose" ? Color(red:0.69,green:0.36,blue:0.43) : dark ? Color(red:0.60,green:0.76,blue:0.64) : Color(red:0.32,green:0.48,blue:0.38)
        let canvas = theme == "native" ? native(.windowBackgroundColor) : dark ? Color(red:0.12,green:0.13,blue:0.12) : Color(red:0.96,green:0.95,blue:0.92)
        let text = overrides.color(.text,mode:mode) ?? native(.labelColor)
        let accentColor = overrides.color(.accent,mode:mode) ?? tint
        let defaults: [WorkspaceColorRole:Color] = [.canvas:canvas,.sidebar:canvas,.widget:native(.controlBackgroundColor),.text:text,.accent:accentColor,.border:text.opacity(0.06),.assistantBubble:text.opacity(0.035),.userBubble:accentColor.opacity(0.12),.input:native(.textBackgroundColor)]
        return .init(colors:Dictionary(uniqueKeysWithValues:WorkspaceColorRole.allCases.map { ($0,overrides.color($0,mode:mode) ?? defaults[$0]!) }))
    }
    static var standard: Self { resolved(raw:"{}",mode:NSApp?.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? "dark" : "light",theme:"native",accent:"blue") }
}
private struct WorkspacePaletteKey: EnvironmentKey { static var defaultValue: WorkspacePalette { .standard } }
extension EnvironmentValues {
    var workspacePalette: WorkspacePalette { get { self[WorkspacePaletteKey.self] } set { self[WorkspacePaletteKey.self] = newValue } }
}
struct WorkspaceColorEditor: View {
    @AppStorage("workspaceColorOverrides") private var raw = "{}"
    @AppStorage("workspaceTheme") private var theme = "warm"
    @AppStorage("workspaceAccent") private var accent = "sage"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "light"
    private var overrides: WorkspaceColorOverrides { .init(raw:raw) }
    private var palette: WorkspacePalette { .resolved(raw:raw,mode:mode,theme:theme,accent:accent) }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("Workspace colours").font(.title2.weight(.semibold)); Spacer(); Picker("Palette",selection:$mode) { Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented).labelsHidden().frame(width:150) }
            Text("Changes save automatically. Light and dark keep their own colours; System appearance switches between them.").font(.callout).foregroundStyle(.secondary)
            preview
            ScrollView {
                VStack(spacing:12) {
                    ForEach(WorkspaceColorRole.allCases) { role in
                        HStack {
                            Text(role.title).frame(maxWidth:.infinity,alignment:.leading)
                            ColorPicker(role.title,selection:binding(role),supportsOpacity:false).labelsHidden()
                            WorkspaceHexField(value:overrides.profiles[mode]?[role.rawValue] ?? "",title:role.title) { hex in
                                var value = overrides
                                value.profiles[mode,default:[:]][role.rawValue] = hex
                                raw = value.encoded
                            }.id(mode + role.rawValue)
                            Button("Default") { var value = overrides; value.set(role,mode:mode,color:nil); raw = value.encoded }.buttonStyle(.borderless).disabled(overrides.profiles[mode]?[role.rawValue] == nil).help("Use the theme's default for " + role.title.lowercased())
                        }
                    }
                }.padding(4)
            }
            HStack { Button("Reset this palette") { var value = overrides; value.profiles[mode] = nil; raw = value.encoded }; Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width:560,height:620).onAppear { mode = scheme == .dark ? "dark" : "light" }
    }
    private func binding(_ role: WorkspaceColorRole) -> Binding<Color> {
        Binding(get:{ palette[role] },set:{ color in var value = overrides; value.set(role,mode:mode,color:color); raw = value.encoded })
    }
    private var preview: some View {
        HStack(spacing:10) {
            VStack(alignment:.leading,spacing:8) { Text("Dashboard").font(.caption.weight(.semibold)); Label("Today",systemImage:"square.grid.2x2").foregroundStyle(palette[.accent]); Spacer() }.padding(10).frame(width:105).background(palette[.sidebar],in:RoundedRectangle(cornerRadius:8))
            VStack(alignment:.leading,spacing:7) {
                Text("Your PA").font(.headline)
                Text("A little clarity for your day.").font(.caption).foregroundStyle(.secondary)
                Text("Good morning.").padding(6).background(palette[.assistantBubble],in:RoundedRectangle(cornerRadius:6))
                HStack { Spacer(); Text("What's on today?").padding(6).background(palette[.userBubble],in:RoundedRectangle(cornerRadius:6)) }
                HStack { Text("Message your PA").foregroundStyle(.secondary); Spacer(); Image(systemName:"paperplane").foregroundStyle(palette[.accent]) }.font(.caption).padding(6).background(palette[.input],in:RoundedRectangle(cornerRadius:5))
            }.font(.caption).padding(10).background(palette[.widget],in:RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(palette[.border]))
        }.foregroundStyle(palette[.text]).padding(10).frame(height:180).background(palette[.canvas],in:RoundedRectangle(cornerRadius:12))
    }
}

private struct WorkspaceHexField: View {
    let value: String
    let title: String
    var save: (String) -> Void
    @State private var draft = ""
    @State private var invalid = false
    var body: some View {
        TextField("Theme",text:$draft)
            .font(.system(.caption,design:.monospaced)).textFieldStyle(.roundedBorder).frame(width:80)
            .accessibilityLabel(title + " hex colour")
            .help(invalid ? "Enter six hexadecimal digits, for example #345678" : "Enter a hex colour, for example #345678, then press Return")
            .overlay(RoundedRectangle(cornerRadius:4).stroke(invalid ? Color.red : Color.clear))
            .onAppear { draft = value }
            .onChange(of:value) { _,newValue in draft = newValue; invalid = false }
            .onSubmit {
                let hex = draft.trimmingCharacters(in:.whitespacesAndNewlines)
                guard WorkspaceColorOverrides.components(hex) != nil else { invalid = true; return }
                let canonical = "#" + (hex.hasPrefix("#") ? String(hex.dropFirst()) : hex).uppercased()
                invalid = false; draft = canonical; save(canonical)
            }
    }
}
