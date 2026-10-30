import SwiftUI

/// The toolbar's swirl orb (30 October). Everything stays inside its circle: Ready drifts slowly
/// under a calm veil, Thinking churns, a heartbeat frosts the orb and a glow rises with progress,
/// Done turns green with one soft bloom, and Needs you turns red and knocks twice from the core.
/// Speed, colours and layers ease every frame, so changing state never jumps.
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
        TimelineView(.animation(minimumInterval: mood == .ready ? 1.0 / 20 : 1.0 / 40, paused: still)) { context in
            SwirlFace(frame: motion.step(to: context.date, target: target, still: still), size: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SwirlTarget {
    var colours: [SIMD3<Double>]
    var speed: Double, churn: Double, veil: Double, frost: Double, fill: Double, knock: Double
    var done: Bool
    init(mood: SwirlOrb.Mood, accent: Color) {
        let tones = ThemeTones(accent)
        let theme = [tones.tone(brightness: 0.84), tones.tone(hueShift: 0.035, saturation: 0.45, brightness: 0.98), tones.tone(hueShift: -0.05, saturation: 1.25, brightness: 0.58)]
        colours = theme; speed = 0.25; churn = 0; veil = 0.42; frost = 0; fill = 0; knock = 0; done = false
        switch mood {
        case .ready: break
        case .thinking, .working(nil): speed = 1.6; churn = 1; veil = 0
        case .working(let progress?): speed = 0.8; churn = 0.35; veil = 0; frost = 0.62; fill = min(1, max(0, progress))
        case .done:
            colours = [SIMD3(0.19, 0.78, 0.37), SIMD3(0.74, 0.96, 0.80), SIMD3(0.06, 0.62, 0.48)]
            speed = 0.4; veil = 0.18; done = true; fill = 1
        case .attention:
            colours = [SIMD3(0.95, 0.27, 0.24), SIMD3(1, 0.69, 0.65), SIMD3(0.71, 0.09, 0.24)]
            speed = 0.4; veil = 0.12; knock = 1
        }
    }
}

struct SwirlFrame {
    var colours: [SIMD3<Double>]
    var phase: Double, churn: Double, veil: Double, frost: Double, fill: Double, knock: Double, bloom: Double, breath: Double
}

/// Per-view motion state. Each value approaches its target with a time constant of about
/// half a second (settled in roughly 1.4 seconds); the swirl's phase integrates the eased speed.
final class SwirlMotion {
    private var last: Date?
    private var phase = 0.0, speed = 0.25
    private var colours: [SIMD3<Double>]?
    private var churn = 0.0, veil = 0.42, frost = 0.0, fill = 0.0, knock = 0.0
    private var bloomStart: Date?
    private var wasDone = false
    func step(to date: Date, target: SwirlTarget, still: Bool) -> SwirlFrame {
        let dt = last.map { min(0.25, max(0, date.timeIntervalSince($0))) } ?? 0
        last = date
        let ease = still || colours == nil ? 1 : 1 - exp(-dt / 0.45)
        func approach(_ value: inout Double, _ goal: Double) { value += (goal - value) * ease }
        var mixed = colours ?? target.colours
        for index in mixed.indices { mixed[index] += (target.colours[index] - mixed[index]) * ease }
        colours = mixed
        approach(&speed, target.speed); approach(&churn, target.churn); approach(&veil, target.veil)
        approach(&frost, target.frost); approach(&knock, target.knock)
        // The fill follows progress a little faster, and drains only while hidden.
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
        let time = date.timeIntervalSinceReferenceDate
        let beat = time.truncatingRemainder(dividingBy: 2.6)
        func bump(_ centre: Double) -> Double { exp(-pow((beat - centre) / 0.07, 2)) }
        let knocking = still ? 0.6 : 0.85 * (bump(0.18) + bump(0.57))
        return SwirlFrame(colours: mixed, phase: phase, churn: churn, veil: veil, frost: frost, fill: fill,
                          knock: knock * knocking, bloom: bloom, breath: still ? 0 : sin(time * 2 * .pi / 7))
    }
}

private struct SwirlFace: View {
    let frame: SwirlFrame
    let size: CGFloat
    var body: some View {
        let primary = Color(frame.colours[0]), light = Color(frame.colours[1]), deep = Color(frame.colours[2])
        let phase = frame.phase
        ZStack {
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, Float(0.5 + 0.12 * sin(phase * 1.1))], [Float(0.5 + 0.18 * cos(phase)), Float(0.5 + 0.18 * sin(phase * 1.3))], [1, Float(0.5 + 0.12 * cos(phase * 0.9))],
                [0, 1], [0.5, 1], [1, 1]
            ], colors: [light, primary, deep, primary, light, primary, deep, primary, light])
            // The slow drift: a blurred colour wheel turning with the phase.
            AngularGradient(colors: [primary, light, deep, primary, light, deep, primary], center: UnitPoint(x: 0.45, y: 0.5))
                .scaleEffect(1.6).rotationEffect(.radians(phase)).blur(radius: size * 0.12).opacity(0.7)
            // Thinking: a faster, higher-contrast churn fades in on top.
            AngularGradient(colors: [.clear, light, .clear, deep, .clear, light, .clear], center: UnitPoint(x: 0.55, y: 0.45))
                .scaleEffect(1.5).rotationEffect(.radians(-phase * 2.4)).blur(radius: size * 0.07).opacity(frame.churn)
            primary.opacity(frame.veil)
            // Heartbeat: the orb frosts over and a glow rises from the bottom with progress.
            light.mix(with: .white, by: 0.45).opacity(frame.frost)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(stops: [.init(color: light.opacity(0), location: 0), .init(color: light.opacity(0.6), location: 0.14),
                                       .init(color: primary.opacity(0.95), location: 0.34), .init(color: deep, location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: size * (frame.fill * 1.22))
            }
            .blur(radius: size * 0.045)
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
        .scaleEffect(1 + 0.012 * frame.breath)
        .shadow(color: .black.opacity(0.14), radius: size * 0.08, y: size * 0.03)
    }
}
