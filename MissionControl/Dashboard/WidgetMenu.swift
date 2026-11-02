import SwiftUI
import AppKit

/// Widgets have no header (1 November): a widget is just its content, and its options are in a menu
/// on a right-click or Control-click anywhere on it, headed with the widget's name and when it last
/// updated. A problem with its source shows as a small dot in the top corner; clicking it explains.
extension View {
    /// Declares this widget's right-click menu; the tile around it (`widgetMenuHost`) shows it.
    func widgetMenu<Items: View>(_ title: String, status: String? = nil, health: SourceHealth? = nil, coverage: String? = nil, refresh: (() -> Void)? = nil, @ViewBuilder items: @escaping () -> Items) -> some View {
        preference(key: WidgetMenuKey.self, value: WidgetMenuDeclaration(title: title, status: status, health: health, coverage: coverage, refresh: refresh) { AnyView(items()) })
    }
    /// Shows the menu declared inside on a right-click anywhere here, padding included, and the
    /// problem dot in the top corner. Off while the layout is being edited.
    func widgetMenuHost(enabled: Bool = true, editLayout: (() -> Void)? = nil) -> some View {
        modifier(WidgetMenuHost(enabled: enabled, editLayout: editLayout))
    }
    /// Keeps this view's own `.contextMenu` (a card, a row) instead of its widget's menu.
    func keepsOwnRightClickMenu() -> some View { background(RightClickMenuOwnerMarker()) }
}

struct WidgetMenuDeclaration {
    var title: String
    var status: String?
    var health: SourceHealth?
    var coverage: String?
    var refresh: (() -> Void)?
    var items: () -> AnyView
    var heading: String {
        if let health, health.error != nil { return title + " · couldn’t refresh" }
        if let status, !status.isEmpty { return title + " · " + status }
        if let date = health?.lastSuccess { return title + " · updated " + date.formatted(date: .omitted, time: .shortened) }
        return title
    }
    var problem: SourceHealth? { health.flatMap { $0.error != nil && !$0.loading ? $0 : nil } }
}
struct WidgetMenuKey: PreferenceKey {
    static let defaultValue: WidgetMenuDeclaration? = nil
    static func reduce(value: inout WidgetMenuDeclaration?, nextValue: () -> WidgetMenuDeclaration?) { value = value ?? nextValue() }
}

private struct WidgetMenuHost: ViewModifier {
    var enabled: Bool
    var editLayout: (() -> Void)?
    @State private var accessibilityRequest = 0
    func body(content: Content) -> some View {
        content
            .backgroundPreferenceValue(WidgetMenuKey.self) { declaration in
                if let declaration {
                    WidgetMenuProbe(enabled: enabled, request: accessibilityRequest) {
                        // The heading goes in as a real section header; a SwiftUI Section would add a separator above it.
                        let menu = NSHostingMenu(rootView: WidgetMenuContent(declaration: declaration, editLayout: editLayout))
                        menu.insertItem(.sectionHeader(title: declaration.heading), at: 0)
                        return menu
                    }
                }
            }
            .overlayPreferenceValue(WidgetMenuKey.self, alignment: .topTrailing) { declaration in
                if let declaration, let problem = declaration.problem {
                    SourceStatusIndicator(title: declaration.title, health: problem, coverage: declaration.coverage, refresh: declaration.refresh).padding(8)
                }
            }
            .accessibilityAction(named: Text("Widget options")) { accessibilityRequest += 1 }
    }
}

private struct WidgetMenuContent: View {
    var declaration: WidgetMenuDeclaration
    var editLayout: (() -> Void)?
    var body: some View {
        declaration.items()
        if let editLayout {
            Divider()
            Button("Edit layout", systemImage: "square.grid.2x2", action: editLayout)
        }
    }
}

/// Watches for right-clicks and Control-clicks on its widget and shows the widget's menu. SwiftUI's
/// `.contextMenu` loses to selectable text's own Copy/Look Up menu (see TranscriptMessageMenu), and
/// widgets are full of selectable text. A smaller view inside with a menu of its own (a chat message,
/// a card marked `keepsOwnRightClickMenu`) keeps it, and so does a field being typed in.
struct WidgetMenuProbe: NSViewRepresentable {
    var enabled: Bool
    var request: Int
    var menu: () -> NSMenu
    func makeNSView(context: Context) -> Probe { let view = Probe(); view.lastRequest = request; update(view); return view }
    func updateNSView(_ view: Probe, context: Context) {
        update(view)
        if request != view.lastRequest { view.lastRequest = request; DispatchQueue.main.async { view.show() } }
    }
    private func update(_ view: Probe) { view.enabled = enabled; view.makeMenu = menu }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.stop() }
    final class Probe: NSView {
        var enabled = true
        var lastRequest = 0
        var makeMenu: (() -> NSMenu)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard window != nil else { return }
            RightClickMenuOwners.add(self)
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, let menu = self.widgetMenu(for: event) else { return event }
                NSMenu.popUpContextMenu(menu, with: event, for: self)
                return nil
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; RightClickMenuOwners.remove(self) }
        /// For VoiceOver's "Widget options" action: the menu opens at the widget's top corner.
        func show() {
            guard enabled, window != nil, let menu = makeMenu?() else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 16, y: isFlipped ? 16 : bounds.height - 16), in: self)
        }
        private func widgetMenu(for event: NSEvent) -> NSMenu? {
            guard enabled, event.type == .rightMouseDown || event.modifierFlags.contains(.control), let window, event.window === window, !isHiddenOrHasHiddenAncestor else { return nil }
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point), visibleRect.contains(point), !RightClickMenuOwners.smallerOwner(than: self, under: event) else { return nil }
            if let editor = window.firstResponder as? NSTextView, editor.isEditable, editor.bounds.contains(editor.convert(event.locationInWindow, from: nil)) { return nil }
            return makeMenu?()
        }
    }
}

/// Views that answer right-clicks with a menu of their own; the smallest one under the pointer wins,
/// whatever order their event monitors were added in (macOS calls them oldest first).
@MainActor enum RightClickMenuOwners {
    private static let views = NSHashTable<NSView>.weakObjects()
    static func add(_ view: NSView) { views.add(view) }
    static func remove(_ view: NSView) { views.remove(view) }
    static func smallerOwner(than view: NSView, under event: NSEvent) -> Bool {
        let area = view.bounds.width * view.bounds.height
        return views.allObjects.contains { other in
            guard other !== view, other.window === event.window, !other.isHiddenOrHasHiddenAncestor, other.bounds.width * other.bounds.height < area else { return false }
            let point = other.convert(event.locationInWindow, from: nil)
            return other.bounds.contains(point) && other.visibleRect.contains(point)
        }
    }
}

/// Marks the area of a view that keeps its own `.contextMenu`; it takes no clicks itself.
struct RightClickMenuOwnerMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) {}
    final class Marker: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { RightClickMenuOwners.remove(self) } else { RightClickMenuOwners.add(self) }
        }
    }
}
