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
    @State private var store = AIActivityStore()
    @State private var feedbackDate = Date.now
    @State private var feedbackMessage = "Reminder created"
    private let registration = "design-preview"
    private var scheme: ColorScheme { appearance == "dark" ? .dark : appearance == "light" ? .light : systemScheme }
    private var palette: WorkspacePalette { .resolved(raw: colours, mode: scheme == .dark ? "dark" : "light", theme: "warm", accent: "sage") }
    private var reduced: Bool { motion == WorkspaceMotion.reduced.rawValue }
    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                WorkspaceBackdropView(palette: palette)
                widgets.padding(16)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, style: .continuous))
            .background(palette[.sidebar])
            .environment(\.workspacePalette, palette)
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
                    Text("The pill in the toolbar is the real one, fed made-up activity.").font(.caption).foregroundStyle(.secondary)
                }
                AppearanceSettings()
            }
            .formStyle(.grouped).frame(width: 440)
        }
        .background(palette[.sidebar])
        .toolbar {
            ToolbarItem(placement: .principal) {
                AIActivityPill(store: store, registration: registration, current: current, feedback: feedback, palette: palette,
                               openChat: {}, openDestination: { _ in }, busy: mood == .thinking)
                    .frame(height: WorkspaceChrome.toolbarItemHeight, alignment: .center)
            }.sharedBackgroundVisibility(.hidden)
        }
        .toolbarBackground(palette[.sidebar], for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .frame(minWidth: 1240, minHeight: 800)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
    private var current: AIActivityRecord? {
        guard case .working(let progress) = mood else { return nil }
        let stage = ["Context", "Your feedback", "Email review", "Memory & organisation", "Suggestions & drafts", "Today’s brief"][min(5, Int((progress ?? 0) * 6))]
        return AIActivityRecord(id: "heartbeat:preview", registration: registration, kind: .heartbeat, state: .running, title: "Heartbeat", message: stage, progress: progress)
    }
    private var feedback: AIActivityFeedback? { mood == .done ? AIActivityFeedback(registration: registration, message: feedbackMessage, date: feedbackDate) : nil }
    private var widgets: some View {
        Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                card {
                    WidgetHeader(title: "Today’s brief", symbol: "sun.max") { Text("Updated 08:02").font(.caption2).foregroundStyle(.secondary); Image(systemName: "arrow.clockwise"); Image(systemName: "ellipsis") }
                    WidgetHeadline(text: "Good morning.", size: 30)
                    Text("A light day. Design studio is at 10:00 in Room 2.14, and your tutor asked everyone to bring printed drafts. Lunch with Alex is at 13:00. The parcel needs collecting from the post office before 17:30. Your essay draft is due on Monday, and Saturday morning is free if you want to start it then.")
                        .font(.system(size: 14)).lineSpacing(5)
                }
                card {
                    WidgetHeader(title: "Calendar", symbol: "calendar") { Image(systemName: "plus") }
                    WidgetHeadline(text: "Design studio in 19 min", lines: 1)
                    event("10:00", "Design studio", "Room 2.14")
                    event("13:00", "Lunch with Alex", "Café by the library")
                    event("15:30", "Gym", "Sports centre")
                    event("18:00", "Seminar reading", "At home")
                }
            }
            GridRow {
                card {
                    WidgetHeader(title: "Reminders", symbol: "checklist") { Image(systemName: "plus") }
                    WidgetHeadline(text: "Collect parcel by 17:30.")
                    reminder("Collect parcel", due: Calendar.current.date(bySettingHour: 17, minute: 30, second: 0, of: .now), hasTime: true)
                    reminder("Email tutor about the essay", due: Calendar.current.date(byAdding: .day, value: 1, to: .now), hasTime: false)
                    reminder("Return library books", due: Calendar.current.date(byAdding: .day, value: 4, to: .now), hasTime: false)
                    reminder("Buy printer paper", due: nil, hasTime: false)
                }
                card {
                    WidgetHeader(title: "Your PA", symbol: "sparkles") { Image(systemName: "square.and.pencil") }
                    HStack { Spacer(); Text("What’s left for today?").padding(.horizontal, 12).padding(.vertical, 7).background(palette[.userBubble], in: RoundedRectangle(cornerRadius: 14)) }
                    Text("Design studio at 10:00, lunch with Alex at 13:00, and the parcel before 17:30.")
                }
            }
        }
    }
    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) { content(); Spacer(minLength: 0) }
            .font(.system(size: 13))
            .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .workspaceSurface(palette)
    }
    private func event(_ time: String, _ title: String, _ place: String) -> some View {
        HStack(spacing: 10) {
            TimePill(text: time)
            Text(title).lineLimit(1)
            Text(place).foregroundStyle(palette[.text].opacity(0.55)).lineLimit(1)
        }
    }
    private func reminder(_ title: String, due: Date?, hasTime: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle").font(.system(size: 17)).foregroundStyle(palette[.text].opacity(0.5))
            Text(title).lineLimit(1)
            Spacer(minLength: 6)
            if let due { DueBadge(due: due, hasTime: hasTime) }
        }
    }
    private func set(_ next: SwirlOrb.Mood) {
        run?.cancel()
        store = AIActivityStore()
        if next == .attention {
            store.upsert(AIActivityRecord(id: "review:preview", registration: registration, kind: .review, state: .needsAnswer, title: "Dentist", message: "Is this the right dentist?"))
        }
        if next == .done { feedbackMessage = "Reminder created"; feedbackDate = .now }
        mood = next
    }
    /// Six stages like a real heartbeat, then success for six seconds, then Ready.
    private func runHeartbeat() {
        run?.cancel(); store = AIActivityStore()
        run = Task {
            for stage in 0...6 {
                mood = .working(Double(stage) / 6)
                try? await Task.sleep(for: .seconds(1.3))
                if Task.isCancelled { return }
            }
            feedbackMessage = "Heartbeat finished"; feedbackDate = .now; mood = .done
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { mood = .ready }
        }
    }
}
#endif
