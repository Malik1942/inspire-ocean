import SwiftUI

/// The Ocean's ambient atmosphere: slow-drifting motes and a soft depth fog.
///
/// This is the *atmosphere layer* — purely decorative and never interactive.
/// The interaction layer (the fragments) stays calm and legible while the space
/// feels alive.
///
/// Design targets:
/// - 18 motes at very low opacity — barely-there, like suspended particles.
/// - Ultra-slow rise and sway so the motion is noticed only when stared at.
/// - `TimelineView(.animation)` with no minimum-interval floor, so ProMotion
///   devices update at full 120 Hz and the float is silky.
struct AtmosphereView: View {

    private struct Mote {
        let x:       Double   // 0…1 normalised horizontal start
        let baseY:   Double   // 0…1 normalised vertical start (wraps)
        let radius:  Double   // visual radius in points
        let speed:   Double   // rise speed (fraction of height per second)
        let drift:   Double   // peak horizontal sway in points
        let phase:   Double   // per-mote phase offset (radians)
        let opacity: Double   // max opacity
    }

    private let field: [Mote]

    init() {
        var rng = SeededRandom(seed: 0x0CEA_0CEA)
        // 18 motes — enough to feel alive, sparse enough to feel delicate.
        field = (0..<18).map { _ in
            Mote(
                x:       rng.next(),
                baseY:   rng.next(),
                radius:  0.5 + rng.next() * 1.6,          // 0.5 – 2.1 pt
                speed:   0.0018 + rng.next() * 0.0055,    // very slow rise
                drift:   3.0  + rng.next() * 12.0,        // 3 – 15 pt sway
                phase:   rng.next() * 6.283,
                opacity: 0.03 + rng.next() * 0.09          // 0.03 – 0.12 (subtle)
            )
        }
    }

    var body: some View {
        // No minimumInterval — runs at full ProMotion refresh rate.
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in

                // Depth vignette: faint brightening near the surface (top).
                let fog = Gradient(colors: [
                    OceanTheme.surface.opacity(0.05),
                    .clear,
                    OceanTheme.abyss.opacity(0.18)
                ])
                ctx.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(fog,
                                          startPoint: .zero,
                                          endPoint: CGPoint(x: 0, y: size.height))
                )

                for m in field {
                    // Motes drift slowly upward and wrap back from the bottom.
                    let progress = (t * m.speed + m.baseY).truncatingRemainder(dividingBy: 1)
                    let y = (1 - progress) * size.height

                    // Ultra-slow lateral sway (0.06 rad/s ≈ one cycle per 105 s).
                    let sway = sin(t * 0.06 + m.phase) * m.drift
                    let x    = m.x * size.width + sway

                    let r    = m.radius
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)

                    // Fade in at the bottom, fade out at the top.
                    let edgeFade = min(progress * 5, (1 - progress) * 5, 1.0)
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .color(OceanTheme.accent.opacity(m.opacity * edgeFade))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Deterministic PRNG

/// Tiny seeded PRNG so the atmosphere is identical across launches.
private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }
}
