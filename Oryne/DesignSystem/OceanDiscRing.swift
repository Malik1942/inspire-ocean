import SwiftUI

/// The ring on a disc, the capture disc and Ask's send: the icon's own mark,
/// the one rim in the app (design/identity-2.1.md, R3; PHILOSOPHY §4). At
/// rest a hairline in the ring's blue; ready to send, a little firmer. A
/// disc that can do nothing at rest (Ask's send before there is a question)
/// shows no ring until it is ready, so the ring itself says "ready".
///
/// While a take is live the ring holds the app's two lights, the warm light a
/// thought comes back in and its own cool blue (Malik, 2026-11-02). The warmth
/// flows in from the upper left, where the light falls on Tide; the two
/// lights drift round the ring at the slow, uneven pace of water rather than
/// a machine's, the warm side swelling a little with the voice; when the take
/// ends the warmth cools back into the blue, as the capture toast's ring
/// does. Stilled (Reduce Motion, Calm), the lights hold their places and the
/// warmth comes and goes in a plain fade.
struct OceanDiscRing: View {
    var listening = false
    var ready = false
    /// False for a disc that is disabled at rest: no ring until it is ready.
    var showsAtRest = true
    /// The microphone's level, 0 to 1, while listening.
    var level: Double = 0
    let size: CGFloat

    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the warm light has come in: 0 at rest, 1 while listening.
    @State private var warmth: Double = 0
    /// When this take began, so the warm light always enters at the upper left.
    @State private var since = Date.now

    private var stilled: Bool { calm || reduceMotion }

    /// One turn of the lights, and the ebb that keeps the pace from being
    /// even. Art-directed: slow enough to read as light, never as progress.
    private static var period: Double { 5.6 }
    private static var ebbPeriod: Double { 3.4 }
    private static var ebb: Double { 16 }

    var body: some View {
        let base = ready ? OceanSize.ringStroke : OceanSize.ringHairline
        let width = base + (OceanSize.ringStrokeListening - base) * warmth
        ZStack {
            Circle()
                .strokeBorder(OceanTheme.ring, lineWidth: width)
                .opacity(showsAtRest || ready || listening ? 1 : 0)
            if listening || warmth > 0 {
                TimelineView(.animation(paused: stilled)) { timeline in
                    let t = stilled ? 0 : timeline.date.timeIntervalSince(since)
                    let turn = t / Self.period * 360 + sin(t * 2 * .pi / Self.ebbPeriod) * Self.ebb
                    Circle()
                        .strokeBorder(lights, lineWidth: width)
                        .rotationEffect(.degrees(225 + turn))
                }
                .opacity(warmth * (stilled ? 1 : 0.8 + 0.2 * min(max(level, 0), 1)))
                .animation(.easeOut(duration: 0.25), value: level) // art-directed: swells softly with the voice
            }
        }
        .frame(width: size, height: size)
        .onChange(of: listening, initial: true) { _, now in
            if now { since = .now }
            withAnimation(stilled ? OceanMotion.quick : now ? OceanMotion.lift : OceanMotion.gentle) {
                warmth = now ? 1 : 0
            }
        }
        .accessibilityHidden(true)
    }

    /// Warm on one side, brightest where it begins, cooling into the ring's
    /// blue on the other, and warming again on the way round.
    private var lights: AngularGradient {
        AngularGradient(stops: [
            .init(color: OceanTheme.warmGlint, location: 0),
            .init(color: OceanTheme.warm, location: 0.14),
            .init(color: OceanTheme.ring, location: 0.46),
            .init(color: OceanTheme.ring, location: 0.6),
            .init(color: OceanTheme.warm, location: 0.88),
            .init(color: OceanTheme.warmGlint, location: 1)
        ], center: .center)
    }
}
