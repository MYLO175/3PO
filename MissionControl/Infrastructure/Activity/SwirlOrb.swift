import SwiftUI

/// The toolbar's swirl orb (30 October). Everything stays inside its circle and nothing spins:
/// a colour mesh waves on overlapping sine paths while soft blobs drift through it. Ready flows
/// gently, Thinking waves harder and faster, a heartbeat frosts the orb and a glow rises with
/// progress, Done turns green with one soft bloom, and Needs you turns red and knocks twice.
/// Speed, waviness, colours and layers ease every frame, so changing state never jumps.
struct SwirlOrb: View {
    enum Mood: Equatable { case ready, thinking, working(Double?), done, attention }
    var mood: Mood
    var accent: Color
    var size: CGFloat = 26
    var reduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var motion = SwirlMotion()
    var body: some View {
        let still = reduceMotion || systemReduceMotion
        let target = SwirlTarget(mood: mood, accent: accent)
        TimelineView(.animation(minimumInterval: nil, paused: still)) { context in
            SwirlFace(frame: motion.step(to: context.date, target: target, still: still), size: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SwirlTarget {
    var colours: [SIMD3<Double>]
    var speed = 0.55, warp = 0.55, churn = 0.0, veil = 0.12, frost = 0.0, fill = 0.0, knock = 0.0
    var done = false
    init(mood: SwirlOrb.Mood, accent: Color) {
        let tones = ThemeTones(accent)
        colours = [tones.tone(brightness: 0.84), tones.tone(hueShift: 0.035, saturation: 0.45, brightness: 0.98), tones.tone(hueShift: -0.05, saturation: 1.25, brightness: 0.58)]
        switch mood {
        case .ready: break
        case .thinking, .working(nil): speed = 1.5; warp = 1; churn = 1; veil = 0
        case .working(let progress?): speed = 0.9; warp = 0.75; churn = 0.35; veil = 0; frost = 0.62; fill = min(1, max(0, progress))
        case .done:
            colours = [SIMD3(0.19, 0.78, 0.37), SIMD3(0.74, 0.96, 0.80), SIMD3(0.06, 0.62, 0.48)]
            veil = 0.08; done = true; fill = 1
        case .attention:
            colours = [SIMD3(0.95, 0.27, 0.24), SIMD3(1, 0.69, 0.65), SIMD3(0.71, 0.09, 0.24)]
            speed = 0.5; warp = 0.5; veil = 0.05; knock = 1
        }
    }
}

struct SwirlFrame {
    var colours: [SIMD3<Double>]
    var phase: Double, warp: Double, churn: Double, veil: Double, frost: Double, fill: Double, knock: Double, bloom: Double
}

/// Per-view motion state. Each value approaches its target with a time constant of about
/// half a second (settled in roughly 1.4 seconds); the phase integrates the eased speed.
final class SwirlMotion {
    private var last: Date?
    private var phase = 0.0, speed = 0.55, warp = 0.55
    private var colours: [SIMD3<Double>]?
    private var churn = 0.0, veil = 0.12, frost = 0.0, fill = 0.0, knock = 0.0
    private var bloomStart: Date?
    private var wasDone = false
    func step(to date: Date, target: SwirlTarget, still: Bool) -> SwirlFrame {
        let dt = last.map { min(0.1, max(0, date.timeIntervalSince($0))) } ?? 0
        last = date
        let ease = still || colours == nil ? 1 : 1 - exp(-dt / 0.45)
        func approach(_ value: inout Double, _ goal: Double) { value += (goal - value) * ease }
        var mixed = colours ?? target.colours
        for index in mixed.indices { mixed[index] += (target.colours[index] - mixed[index]) * ease }
        colours = mixed
        approach(&speed, target.speed); approach(&warp, target.warp); approach(&churn, target.churn)
        approach(&veil, target.veil); approach(&frost, target.frost); approach(&knock, target.knock)
        // The fill follows progress a little faster than the other layers.
        fill += (target.fill - fill) * (still ? 1 : 1 - exp(-dt / (target.fill < fill && frost > 0.05 ? 1.2 : 0.3)))
        phase += dt * speed
        if target.done && !wasDone { bloomStart = date }
        wasDone = target.done
        var bloom = 0.0
        if let start = bloomStart, !still {
            let t = date.timeIntervalSince(start)
            bloom = t < 0.48 ? t / 0.48 * 0.9 : max(0, 0.9 * (1 - (t - 0.48) / 1.12))
            if t > 1.6 { bloomStart = nil }
        }
        let beat = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6)
        func bump(_ centre: Double) -> Double { exp(-pow((beat - centre) / 0.07, 2)) }
        let knocking = still ? 0.6 : 0.85 * (bump(0.18) + bump(0.57))
        return SwirlFrame(colours: mixed, phase: phase, warp: warp, churn: churn, veil: veil, frost: frost, fill: fill, knock: knock * knocking, bloom: bloom)
    }
}

private struct SwirlFace: View {
    let frame: SwirlFrame
    let size: CGFloat
    var body: some View {
        let primary = Color(frame.colours[0]), light = Color(frame.colours[1]), deep = Color(frame.colours[2])
        let t = frame.phase
        ZStack {
            MeshGradient(width: 4, height: 4, points: points, colors: vertexColours)
            // Soft blobs drifting on Lissajous paths; Thinking makes them stronger and adds a bright one.
            blob(light, scale: 0.5, x: 0.26 * sin(t * 0.83 + 0.4), y: 0.22 * sin(t * 1.21 + 1.8), blur: 0.14, opacity: 0.5 + 0.3 * frame.churn)
            blob(deep, scale: 0.55, x: 0.24 * cos(t * 0.71 + 2), y: 0.26 * sin(t * 0.97), blur: 0.16, opacity: 0.4 + 0.3 * frame.churn)
            blob(.white, scale: 0.3, x: 0.3 * sin(t * 1.9), y: 0.28 * cos(t * 1.6 + 1), blur: 0.1, opacity: 0.45 * frame.churn)
            primary.opacity(frame.veil)
            // Heartbeat: the orb frosts over and a glow rises from the bottom with progress.
            light.mix(with: .white, by: 0.45).opacity(frame.frost)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(stops: [.init(color: light.opacity(0), location: 0), .init(color: light.opacity(0.6), location: 0.14),
                                       .init(color: primary.opacity(0.95), location: 0.34), .init(color: deep, location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: size * (frame.fill * 1.22))
            }
            .opacity(min(1, frame.frost / 0.5))
            // Needs you: two quick knocks from the core, then a rest.
            RadialGradient(colors: [.white.opacity(0.95), light.opacity(0.85), .clear], center: .center, startRadius: 0, endRadius: size * 0.34)
                .scaleEffect(0.8 + 0.25 * frame.knock).opacity(frame.knock)
            // Done: one soft bloom inside.
            RadialGradient(colors: [.white.opacity(0.9), light.opacity(0.7), .clear], center: .center, startRadius: 0, endRadius: size * 0.5)
                .scaleEffect(0.3 + frame.bloom).opacity(frame.bloom)
            // Gloss and depth stay fixed.
            RadialGradient(colors: [.white.opacity(0.7), .white.opacity(0)], center: UnitPoint(x: 0.34, y: 0.24), startRadius: 0, endRadius: size * 0.3)
            LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
        }
        .compositingGroup()
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: size * 0.08, y: size * 0.03)
    }
    /// Interior points wave on two overlapping sines; edge points slide along their edge; corners stay put.
    private var points: [SIMD2<Float>] {
        let t = frame.phase, w = frame.warp
        return (0..<16).map { index in
            let i = index % 4, j = index / 4, seed = Double(index)
            var dx = 0.13 * w * sin(t * (0.9 + 0.13 * Double(i)) + seed * 1.7) + 0.05 * w * sin(t * 2.3 + seed)
            var dy = 0.13 * w * cos(t * (0.8 + 0.11 * Double(j)) + seed * 2.1) + 0.05 * w * cos(t * 1.9 + seed * 0.7)
            if i == 0 || i == 3 { dx = 0 }
            if j == 0 || j == 3 { dy = 0 }
            return SIMD2(Float(Double(i) / 3 + dx), Float(Double(j) / 3 + dy))
        }
    }
    /// Colour waves travel across the mesh, so the shades flow rather than turn.
    private var vertexColours: [Color] {
        let t = frame.phase, palette = frame.colours
        return (0..<16).map { index in
            let i = Double(index % 4), j = Double(index / 4)
            let a = 0.5 + 0.5 * sin(t * 0.7 + i * 1.9 + j * 1.3), b = 0.5 + 0.5 * sin(t * 0.53 - i * 1.1 + j * 2.2)
            let base = palette[0] + (palette[1] - palette[0]) * (a * 0.85)
            return Color(base + (palette[2] - base) * (b * 0.7))
        }
    }
    /// Soft-edged by its own gradient rather than a blur, so it draws the same everywhere and costs less.
    private func blob(_ colour: Color, scale: CGFloat, x: Double, y: Double, blur: CGFloat, opacity: Double) -> some View {
        let radius = size * (scale / 2 + blur)
        return RadialGradient(colors: [colour, colour.opacity(0.55), colour.opacity(0)], center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: size * x, y: size * y).opacity(opacity)
    }
}
