#if DEBUG
import SwiftUI

/// Fictional, source-free look at the 30 October design: the swirl orb in every state, a simulated
/// heartbeat, glass or solid widgets over the glow, and the real Settings → Appearance controls.
/// Preferences live in a throwaway suite, so the installed app's look is untouched.
struct DesignPreview: View {
    @State private var suite: String = {
        let name = "threepo-design-preview-" + UUID().uuidString
        var colours = WorkspaceColorOverrides(); colours.profiles = WorkspaceColorTheme.threePO.profiles
        UserDefaults(suiteName: name)?.set(colours.encoded, forKey: "workspaceColorOverrides")
        return name
    }()
    var body: some View {
        DesignPreviewContent()
            .defaultAppStorage(UserDefaults(suiteName: suite)!)
            .onDisappear { UserDefaults.standard.removePersistentDomain(forName: suite) }
    }
}

extension DesignPreview {
    /// `--preview-design --snapshot`: still orb rows for three themes in both modes (ImageRenderer),
    /// and the whole preview window offscreen, written to /tmp. Motion is held so frames are repeatable.
    @MainActor static func render() async {
        let moods: [SwirlOrb.Mood] = [.ready, .thinking, .working(0.55), .done, .attention]
        for (name, preset) in [("3po", WorkspaceColorTheme.threePO), ("ocean", .ocean), ("nebula", .nebula)] {
            for mode in ["light", "dark"] {
                var overrides = WorkspaceColorOverrides(); overrides.profiles = preset.profiles
                let palette = WorkspacePalette.resolved(raw: overrides.encoded, mode: mode, theme: "warm", accent: "sage")
                let row = HStack(spacing: 24) {
                    ForEach(Array(moods.enumerated()), id: \.offset) { _, mood in SwirlOrb(mood: mood, accent: palette[.accent], size: 120, reduceMotion: true) }
                }.padding(30).background(palette[.canvas])
                let renderer = ImageRenderer(content: row); renderer.scale = 2
                if let image = renderer.cgImage { write(NSBitmapImageRep(cgImage: image), "orbs-\(name)-\(mode)") }
            }
        }
        for mode in ["light", "dark"] {
            let suite = "threepo-design-snapshot-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
            var colours = WorkspaceColorOverrides(); colours.profiles = WorkspaceColorTheme.threePO.profiles
            defaults.set(colours.encoded, forKey: "workspaceColorOverrides"); defaults.set(mode, forKey: "workspaceAppearance"); defaults.set(WorkspaceMotion.reduced.rawValue, forKey: WorkspaceStyleKey.motion)
            let hosting = NSHostingView(rootView: DesignPreviewContent().defaultAppStorage(defaults))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = hosting
            window.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
            window.orderFront(nil)
            try? await Task.sleep(for: .milliseconds(900))
            hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) { hosting.cacheDisplay(in: hosting.bounds, to: bitmap); write(bitmap, "window-\(mode)") }
            window.close()
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
    }
    private static func write(_ bitmap: NSBitmapImageRep, _ name: String) {
        try? bitmap.representation(using: .png, properties: [:])?.write(to: EvaluationOutput.url("/tmp/missioncontrol-design-" + name + ".png"), options: .atomic)
    }
}

private struct DesignPreviewContent: View {
    @AppStorage("workspaceColorOverrides") private var colours = "{}"
    @AppStorage("workspaceAppearance") private var appearance = "system"
    @AppStorage(WorkspaceStyleKey.motion) private var motion = WorkspaceMotion.full.rawValue
    @Environment(\.colorScheme) private var systemScheme
    @State private var mood: SwirlOrb.Mood = .ready
    @State private var run: Task<Void, Never>?
    private var scheme: ColorScheme { appearance == "dark" ? .dark : appearance == "light" ? .light : systemScheme }
    private var palette: WorkspacePalette { .resolved(raw: colours, mode: scheme == .dark ? "dark" : "light", theme: "warm", accent: "sage") }
    private var reduced: Bool { motion == WorkspaceMotion.reduced.rawValue }
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack { Spacer(); pill; Spacer() }.frame(height: 52).background(palette[.sidebar])
                ZStack {
                    WorkspaceBackdropView(palette: palette)
                    widgets.padding(16)
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, style: .continuous))
                .background(palette[.sidebar])
            }
            .foregroundStyle(palette[.text]).tint(palette[.accent])
            Divider()
            Form {
                Section("Try the orb") {
                    HStack(spacing: 18) {
                        SwirlOrb(mood: mood, accent: palette[.accent], size: 120, reduceMotion: reduced)
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Ready") { set(.ready) }
                            Button("Thinking") { set(.thinking) }
                            Button("Run heartbeat") { runHeartbeat() }
                            Button("Done") { set(.done) }
                            Button("Needs you") { set(.attention) }
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 6)
                    HStack(spacing: 14) {
                        ForEach(Array([SwirlOrb.Mood.ready, .thinking, .working(0.55), .done, .attention].enumerated()), id: \.offset) { _, each in
                            SwirlOrb(mood: each, accent: palette[.accent], size: 28, reduceMotion: reduced)
                        }
                    }
                    Text("Every state stays inside the circle. Colours fade over about 1.4 seconds.").font(.caption).foregroundStyle(.secondary)
                }
                AppearanceSettings()
            }
            .formStyle(.grouped).frame(width: 440)
        }
        .frame(minWidth: 1240, minHeight: 800)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
    private var pill: some View {
        let label: (String, String) = {
            switch mood {
            case .ready: return ("3PO is ready", "Brief updated 08:02")
            case .thinking: return ("Thinking", "Answering in chat")
            case .working(let progress): return ("Heartbeat · \(Int((progress ?? 0) * 100))%", "Today’s brief")
            case .done: return ("Reminder created", "Print drafts · Today 09:50")
            case .attention: return ("Needs your answer", "Is this the right dentist?")
            }
        }()
        return HStack(spacing: 8) {
            SwirlOrb(mood: mood, accent: palette[.accent], size: 25, reduceMotion: reduced).frame(width: 29, height: 29)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.0).font(.system(size: 11, weight: .semibold))
                Text(label.1).font(.system(size: 10)).opacity(0.6)
            }.frame(width: 190, alignment: .leading)
        }
        .foregroundStyle(mood == .done ? Color.green : mood == .attention ? Color.red : palette[.text])
        .padding(.horizontal, 4).padding(.vertical, 2).padding(.trailing, 8)
        .background(palette[.widget].opacity(0.62), in: Capsule()).background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(palette[.text].opacity(0.13), lineWidth: 0.75))
    }
    private var widgets: some View {
        Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                card("Today’s brief", "sun.max") {
                    Text("Good morning.").font(.system(size: 30, weight: .semibold, design: .serif))
                    Text("A light day: one class, one errand, and an essay to start.").font(.system(size: 14, design: .serif)).opacity(0.8)
                    Divider()
                    line("10:00", "Design studio · bring printed drafts")
                    line("13:00", "Lunch with Alex")
                    line("17:30", "Collect the parcel", due: true)
                    line(nil, "Essay draft due", trailing: "Mon")
                }
                card("Calendar", "calendar") {
                    line("10:00", "Design studio")
                    line("13:00", "Lunch with Alex")
                    line("15:30", "Gym")
                    line("18:00", "Seminar reading")
                }
            }
            GridRow {
                card("Reminders", "checklist") {
                    reminder("Collect parcel", time: "17:30", due: true)
                    reminder("Email tutor about the essay", trailing: "Tomorrow")
                    reminder("Buy printer paper")
                }
                card("Your PA", "sparkles") {
                    HStack { Spacer(); Text("What’s left for today?").padding(.horizontal, 12).padding(.vertical, 7).background(palette[.userBubble], in: RoundedRectangle(cornerRadius: 14)) }
                    Text("Design studio at 10:00, lunch with Alex at 13:00, and the parcel before 17:30.")
                }
            }
        }
    }
    private func card(_ title: String, _ symbol: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette[.accent])
                    .frame(width: 26, height: 26).background(palette[.accent].opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.3).foregroundStyle(palette[.accent])
                Spacer()
            }
            content()
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .workspaceSurface(palette)
    }
    /// Clock times sit in a fixed-width pill (red when it's a deadline); words such as
    /// “Tomorrow” or a weekday are plain trailing text, never a pill.
    private func line(_ time: String?, _ text: String, due: Bool = false, trailing: String? = nil) -> some View {
        HStack(spacing: 10) {
            if let time { timePill(time, due: due) }
            else { Circle().fill(palette[.accent].opacity(0.6)).frame(width: 5, height: 5).frame(width: 52) }
            Text(text).lineLimit(1)
            Spacer(minLength: 6)
            if let trailing { Text(trailing).font(.system(size: 12)).foregroundStyle(palette[.text].opacity(0.55)) }
        }
    }
    private func reminder(_ title: String, time: String? = nil, due: Bool = false, trailing: String? = nil) -> some View {
        HStack(spacing: 10) {
            Circle().strokeBorder(palette[.text].opacity(0.35), lineWidth: 1.5).frame(width: 16, height: 16)
            Text(title).lineLimit(1)
            Spacer(minLength: 6)
            if let time { timePill(time, due: due) }
            if let trailing { Text(trailing).font(.system(size: 12)).foregroundStyle(palette[.text].opacity(0.55)) }
        }
    }
    private func timePill(_ time: String, due: Bool) -> some View {
        let colour = due ? Color.red : palette[.accent]
        return Text(time).font(.system(size: 11.5, weight: .semibold).monospacedDigit()).foregroundStyle(colour)
            .frame(width: 52).padding(.vertical, 3).background(colour.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
    }
    private func set(_ next: SwirlOrb.Mood) { run?.cancel(); mood = next }
    /// Six stages like a real heartbeat, then success for six seconds, then Ready.
    private func runHeartbeat() {
        run?.cancel()
        run = Task {
            for stage in 0...6 {
                mood = .working(Double(stage) / 6)
                try? await Task.sleep(for: .seconds(1.3))
                if Task.isCancelled { return }
            }
            mood = .done
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { mood = .ready }
        }
    }
}
#endif
