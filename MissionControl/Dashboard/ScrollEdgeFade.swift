import SwiftUI

/// Content hidden past a scroll view's top or bottom fades out instead of being cut off (1 November).
/// An edge with nothing beyond it stays sharp, so a list that fits shows no fade at all.
struct ScrollEdgeFade: ViewModifier {
    var length: CGFloat = 32
    @State private var hidden = HiddenEdges()
    private var motion = MotionPreference()
    init(length: CGFloat = 32) { self.length = length }
    struct HiddenEdges: Equatable { var top = false; var bottom = false }
    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: HiddenEdges.self) { geometry in
                HiddenEdges(top: geometry.visibleRect.minY > 0.5, bottom: geometry.visibleRect.maxY < geometry.contentSize.height - 0.5)
            } action: { _, edges in hidden = edges }
            .mask {
                VStack(spacing: 0) {
                    ramp(.top).frame(height: hidden.top ? length : 0)
                    Rectangle()
                    ramp(.bottom).frame(height: hidden.bottom ? length : 0)
                }.animation(motion.animation(.easeOut(duration: 0.2)), value: hidden)
            }
    }
    /// Eased rather than linear, so the fade has no visible start line.
    private func ramp(_ edge: VerticalEdge) -> LinearGradient {
        let stops: [Gradient.Stop] = [.init(color: .clear, location: 0), .init(color: .black.opacity(0.3), location: 0.35), .init(color: .black.opacity(0.75), location: 0.7), .init(color: .black, location: 1)]
        return LinearGradient(stops: stops, startPoint: edge == .top ? .top : .bottom, endPoint: edge == .top ? .bottom : .top)
    }
}

extension View {
    /// Fades hidden content at a scroll view's top and bottom edges; apply to the ScrollView itself.
    func scrollEdgeFade(_ enabled: Bool = true, length: CGFloat = 32) -> some View {
        modifier(ScrollEdgeFade(length: enabled ? length : 0))
    }
}
