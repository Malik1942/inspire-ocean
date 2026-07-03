import Foundation
import GameplayKit

/// One shared Perlin source for the whole Ocean.
///
/// Every node samples the same seamless noise field at its own seed offset,
/// so the water reads as one body moving, never as independent jitter. The
/// map tiles seamlessly, so a session can run for hours without ever walking
/// off the field.
final class DriftField {

    static let shared = DriftField()

    /// Noise space repeats every `extent` units; one unit is roughly one
    /// feature cycle of the Perlin source (frequency 1).
    private let extent: Double = 16
    private let samples: Int32 = 512
    private let map: GKNoiseMap

    private init() {
        let source = GKPerlinNoiseSource(
            frequency: 1.0,
            octaveCount: 3,
            persistence: 0.5,
            lacunarity: 2.0,
            seed: 0x0CEA
        )
        map = GKNoiseMap(
            GKNoise(source),
            size: vector_double2(extent, extent),
            origin: vector_double2(0, 0),
            sampleCount: vector_int2(samples, samples),
            seamless: true
        )
    }

    /// Smooth noise in -1...1 at a continuous position in noise space.
    /// Bilinear interpolation between grid samples keeps per-frame motion
    /// free of stepping; the wrap keeps it continuous across the tile seam.
    func value(x: Double, y: Double) -> Double {
        let n = Double(samples)
        func gridCoordinate(_ v: Double) -> Double {
            let wrapped = v.truncatingRemainder(dividingBy: extent)
            return (wrapped < 0 ? wrapped + extent : wrapped) / extent * n
        }
        let fx = gridCoordinate(x)
        let fy = gridCoordinate(y)
        let x0 = Int32(fx) % samples
        let y0 = Int32(fy) % samples
        let x1 = (x0 + 1) % samples
        let y1 = (y0 + 1) % samples
        let tx = fx - fx.rounded(.down)
        let ty = fy - fy.rounded(.down)

        let v00 = Double(map.value(at: vector_int2(x0, y0)))
        let v10 = Double(map.value(at: vector_int2(x1, y0)))
        let v01 = Double(map.value(at: vector_int2(x0, y1)))
        let v11 = Double(map.value(at: vector_int2(x1, y1)))

        let top = v00 + (v10 - v00) * tx
        let bottom = v01 + (v11 - v01) * tx
        return top + (bottom - top) * ty
    }
}

/// Per-node sampling parameters into the shared field: a stable seed offset,
/// a wander tempo, and a breathing rhythm, all derived deterministically from
/// the node's identity so the water looks the same across launches.
struct DriftSampler {

    /// Track rows in noise space: x wander and y wander read different rows
    /// so the two axes never move in lockstep.
    private let rowX: Double
    private let rowY: Double
    private let offsetX: Double
    private let offsetY: Double

    /// Seconds per wander cycle, 8 to 15 by seed.
    let wanderPeriod: Double

    /// Seconds per breathing cycle, 6 to 10 by seed, plus a phase offset so
    /// no two nodes breathe in step.
    private let breathePeriod: Double
    private let breathePhase: Double

    init(seedKey: String) {
        func unit(_ salt: String) -> Double {
            Double(NodeComposer.stableHash(seedKey + salt) % 1000) / 1000
        }
        rowX = unit("rowX") * 16
        rowY = unit("rowY") * 16
        offsetX = unit("offX") * 16
        offsetY = unit("offY") * 16
        wanderPeriod = 8 + unit("tempo") * 7
        breathePeriod = 6 + unit("breath") * 4
        breathePhase = unit("phase") * 2 * .pi
    }

    /// Organic positional wander at time `t`, scaled to `amplitude` points.
    /// `timeScale` above 1 makes the same path flow faster (energy).
    func wander(at t: TimeInterval, amplitude: Double, timeScale: Double = 1) -> CGVector {
        let progress = t * timeScale / wanderPeriod
        let dx = DriftField.shared.value(x: progress + offsetX, y: rowX) * amplitude
        let dy = DriftField.shared.value(x: progress + offsetY, y: rowY) * amplitude
        return CGVector(dx: dx, dy: dy)
    }

    /// Scale breathing around 1.0, plus or minus `depth` (0.02 is 2 percent).
    func breathing(at t: TimeInterval, depth: Double = 0.02) -> CGFloat {
        CGFloat(1 + depth * sin(t * 2 * .pi / breathePeriod + breathePhase))
    }
}
