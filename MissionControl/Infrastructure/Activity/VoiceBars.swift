import SwiftUI

/// The activity pill's voice bars (30 October): five small bars in the theme accent. Ready: a low wave
/// that rocks back and forth; Thinking: lively, like speech; a heartbeat lights them one by one as it
/// loads; Done: green with a wave running left to right; Needs you: red, knocking twice.
/// Heights, brightness and colour ease every frame, so changing state never jumps.
struct VoiceBars: View {
    enum Mood: Equatable { case ready, thinking, working(Double?), done, attention }
    var mood: Mood
    var accent: Color
    var height: CGFloat = 18
    var reduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var motion = VoiceBarsMotion()
    var body: some View {
        let still = reduceMotion || systemReduceMotion
        let colour = VoiceBarsMotion.colour(mood, accent: accent, dark: scheme == .dark)
        TimelineView(.animation(minimumInterval: nil, paused: still)) { context in
            let frame = motion.step(to: context.date, mood: mood, colour: colour, still: still)
            HStack(spacing: height * 0.14) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule().fill(Color(frame.colour)).opacity(frame.opacity[index])
                        .frame(width: max(2.5, height * 0.17), height: max(2.5, height * frame.heights[index]))
                }
            }
            .frame(height: height)
        }
        .accessibilityHidden(true)
    }
}

/// Per-view motion state: targets come from the mood and the time, and the drawn values
/// approach them smoothly (heights in about a tenth of a second, colour in about 1.4 seconds).
final class VoiceBarsMotion {
    private var last: Date?
    private var heights = [Double](repeating: 0.3, count: 5)
    private var opacity = [Double](repeating: 0.8, count: 5)
    private var colour: SIMD3<Double>?
    private var doneStart: Date?
    private var wasDone = false

    static func colour(_ mood: VoiceBars.Mood, accent: Color, dark: Bool) -> SIMD3<Double> {
        switch mood {
        case .done: return dark ? SIMD3(0.36, 0.82, 0.48) : SIMD3(0.12, 0.62, 0.27)
        case .attention: return dark ? SIMD3(1, 0.42, 0.38) : SIMD3(0.85, 0.19, 0.21)
        default:
            let rgb = NSColor(accent).usingColorSpace(.sRGB) ?? .systemBlue
            return SIMD3(Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
        }
    }

    func step(to date: Date, mood: VoiceBars.Mood, colour goal: SIMD3<Double>, still: Bool) -> (heights: [Double], opacity: [Double], colour: SIMD3<Double>) {
        let dt = last.map { min(0.1, max(0, date.timeIntervalSince($0))) } ?? 0
        let first = last == nil
        last = date
        if mood == .done && !wasDone { doneStart = date }
        wasDone = mood == .done
        let target = Self.target(mood, time: date.timeIntervalSinceReferenceDate, sinceDone: doneStart.map { date.timeIntervalSince($0) } ?? 0, still: still)
        let snap = still || first
        for index in 0..<5 {
            heights[index] += (target.heights[index] - heights[index]) * (snap ? 1 : 1 - exp(-dt / 0.06))
            opacity[index] += (target.opacity[index] - opacity[index]) * (snap ? 1 : 1 - exp(-dt / 0.25))
        }
        var mixed = colour ?? goal
        mixed += (goal - mixed) * (snap ? 1 : 1 - exp(-dt / 0.45))
        colour = mixed
        return (heights, opacity, mixed)
    }

    /// Bar heights (fractions of the full height) and brightness for a mood at a moment.
    static func target(_ mood: VoiceBars.Mood, time t: Double, sinceDone: Double, still: Bool) -> (heights: [Double], opacity: [Double]) {
        let bars = Array(0..<5).map(Double.init)
        func bump(_ x: Double, _ centre: Double, _ width: Double) -> Double { exp(-pow((x - centre) / width, 2)) }
        switch mood {
        case .ready:
            if still { return (Array(repeating: 0.32, count: 5), Array(repeating: 0.8, count: 5)) }
            // A low swell that rocks from end to end and back.
            let phase = (t / 1.7).truncatingRemainder(dividingBy: 2), crest = (1 - abs(phase - 1)) * 4
            let eased = (1 - cos(crest / 4 * .pi)) / 2 * 4 // slows at each end before turning back
            return (bars.map { 0.24 + 0.22 * bump($0, eased, 1.2) }, Array(repeating: 0.8, count: 5))
        case .thinking, .working(nil):
            if still { return ([0.45, 0.75, 1, 0.75, 0.45], Array(repeating: 1, count: 5)) }
            let speed = [7.1, 5.3, 8.2, 6.1, 7.7], offset = [0, 1.3, 2.1, 0.7, 2.9]
            return (bars.indices.map { 0.28 + 0.72 * abs(sin(t * speed[$0] + offset[$0])) }, Array(repeating: 1, count: 5))
        case .working(let progress?):
            // Loading: bars light one by one; the one being filled keeps talking.
            let lit = min(5, max(0, progress * 5)), full = Int(lit)
            let heights = bars.indices.map { index -> Double in
                if index < full { return 0.85 }
                if index == full && full < 5 { return still ? 0.6 : 0.35 + 0.5 * abs(sin(t * 7 + Double(index))) }
                return 0.24
            }
            return (heights, bars.indices.map { $0 <= full ? 1 : 0.35 })
        case .done:
            if still { return ([0.4, 0.6, 0.85, 1, 0.7], Array(repeating: 1, count: 5)) }
            // A wave running left to right, over and over while it stays green.
            let crest = (sinceDone / 1.3).truncatingRemainder(dividingBy: 1) * 6.4 - 1
            return (bars.map { 0.3 + 0.62 * bump($0, crest, 0.95) }, Array(repeating: 1, count: 5))
        case .attention:
            if still { return (Array(repeating: 0.8, count: 5), Array(repeating: 1, count: 5)) }
            // Two quick knocks, then a rest.
            let beat = t.truncatingRemainder(dividingBy: 2.6)
            let knock = min(1, bump(beat, 0.18, 0.08) + bump(beat, 0.57, 0.08))
            return (bars.map { 0.3 + (0.6 + 0.04 * $0.truncatingRemainder(dividingBy: 2)) * knock }, Array(repeating: 1, count: 5))
        }
    }
}
