import SpriteKit
import SwiftUI

// MARK: - Textures

/// Pre-rendered orb textures, cached by bucket so SpriteKit batches draws.
///
/// SwiftUI's `.ultraThinMaterial` has no SpriteKit equivalent, so the glass
/// look is approximated over the known near-black palette: a faint white
/// body, a whisper of hue tint, a lit rim. Buckets (hue, radius, prominence)
/// keep the cache small; per-node variation (shimmer, energy) rides on
/// sprite alpha instead of texture count.
@MainActor
enum OrbTextures {

    private static var cache: [String: SKTexture] = [:]

    private static func hueBucket(_ hue: Double) -> Int {
        min(11, max(0, Int(hue * 12)))
    }
    private static func bucketedHue(_ hue: Double) -> Double {
        (Double(hueBucket(hue)) + 0.5) / 12
    }

    // MARK: Motes

    /// Canvas padding around a mote so the stroke never clips.
    static let motePadding: CGFloat = 2

    static func mote(hue: Double, radius: CGFloat, resurfacing: Bool) -> SKTexture {
        let r = (radius * 2).rounded() / 2
        let key = "mote·\(hueBucket(hue))·\(r)·\(resurfacing)"
        if let hit = cache[key] { return hit }

        let d = r * 2
        let canvas = CGSize(width: d + motePadding * 2, height: d + motePadding * 2)
        let rect = CGRect(x: motePadding, y: motePadding, width: d, height: d)
        let tint = UIColor(OceanTheme.color(forHue: bucketedHue(hue), brightness: 0.85))

        let image = UIGraphicsImageRenderer(size: canvas).image { ctx in
            let cg = ctx.cgContext
            // Glass body: a faint lift off the dark water.
            UIColor(white: 1, alpha: 0.08).setFill()
            cg.fillEllipse(in: rect)
            tint.withAlphaComponent(0.13).setFill()
            cg.fillEllipse(in: rect)
            // One restrained rim; warm for the resurfacing thought.
            let stroke = resurfacing
                ? UIColor(OceanTheme.glowWarm).withAlphaComponent(0.45)
                : UIColor(white: 1, alpha: 0.16)
            stroke.setStroke()
            cg.setLineWidth(0.75)
            cg.strokeEllipse(in: rect.insetBy(dx: 0.375, dy: 0.375))
        }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    // MARK: Clusters

    /// Canvas padding around a cluster orb: room for the soft depth shadow.
    static let clusterPadding: CGFloat = 26

    static func cluster(hue: Double, radius: CGFloat, prominence: Double) -> SKTexture {
        let r = (radius / 2).rounded() * 2
        let p = (prominence * 4).rounded() / 4
        let key = "cluster·\(hueBucket(hue))·\(r)·\(p)"
        if let hit = cache[key] { return hit }

        let d = r * 2
        let pad = clusterPadding
        let canvas = CGSize(width: d + pad * 2, height: d + pad * 2)
        let rect = CGRect(x: pad, y: pad, width: d, height: d)
        let tint = UIColor(OceanTheme.color(forHue: bucketedHue(hue), brightness: 0.62 + 0.38 * p))

        let image = UIGraphicsImageRenderer(size: canvas).image { ctx in
            let cg = ctx.cgContext

            // Soft depth shadow: a blurred dark pool sitting slightly low,
            // standing in for the SwiftUI drop shadow. Clipped to the outside
            // of the orb so the body keeps one flat glass tone (painting it
            // underneath would read as a bright core inside a dark ring).
            cg.saveGState()
            let outside = CGMutablePath()
            outside.addRect(CGRect(origin: .zero, size: canvas))
            outside.addEllipse(in: rect)
            cg.addPath(outside)
            cg.clip(using: .evenOdd)
            let shadowColors = [
                UIColor(white: 0, alpha: 0.22).cgColor,
                UIColor(white: 0, alpha: 0).cgColor
            ] as CFArray
            if let shadowGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: shadowColors, locations: [0, 1]) {
                let center = CGPoint(x: rect.midX, y: rect.midY + 6)
                cg.drawRadialGradient(
                    shadowGradient, startCenter: center, startRadius: r * 0.8,
                    endCenter: center, endRadius: r + 12, options: [])
            }
            cg.restoreGState()

            // Glass body and hue tint: brightness carries recency.
            UIColor(white: 1, alpha: 0.09).setFill()
            cg.fillEllipse(in: rect)
            tint.withAlphaComponent(0.10 + 0.09 * p).setFill()
            cg.fillEllipse(in: rect)

            // Soft light from above, fading out by the middle of the orb.
            cg.saveGState()
            cg.addEllipse(in: rect)
            cg.clip()
            let lightColors = [
                UIColor(white: 1, alpha: 0.14).cgColor,
                UIColor(white: 1, alpha: 0).cgColor
            ] as CFArray
            if let light = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: lightColors, locations: [0, 1]) {
                cg.drawLinearGradient(
                    light,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.midY),
                    options: [])
            }
            cg.restoreGState()

            UIColor(white: 1, alpha: 0.07 + 0.06 * p).setStroke()
            cg.setLineWidth(0.6)
            cg.strokeEllipse(in: rect.insetBy(dx: 0.3, dy: 0.3))
        }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    // MARK: Shared

    /// A soft radial glow, white so sprites can tint it per node.
    static let glow: SKTexture = {
        let side: CGFloat = 96
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let colors = [
                UIColor(white: 1, alpha: 1).cgColor,
                UIColor(white: 1, alpha: 0).cgColor
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors, locations: [0, 1]) {
                let center = CGPoint(x: side / 2, y: side / 2)
                ctx.cgContext.drawRadialGradient(
                    gradient, startCenter: center, startRadius: 0,
                    endCenter: center, endRadius: side / 2, options: [])
            }
        }
        return SKTexture(image: image)
    }()

}

// MARK: - Label typography

/// The current label's type, shared between rendering and layout: the layout
/// engine measures the exact box a label will render into, so label bounds
/// can join collision footprints and truncation cannot happen. Whisper light
/// by default, firmed and fully lit under Calm Accessibility.
enum OceanLabelStyle {

    /// Labels wrap to two lines at this width; the footprint reserves the
    /// measured box, so nothing narrower ever truncates.
    static let maxWidth: CGFloat = 160

    static func attributed(_ text: String, prominence: Double, calm: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let shadow = NSShadow()
        shadow.shadowColor = UIColor(white: 0, alpha: 0.55)
        shadow.shadowBlurRadius = 2.5
        shadow.shadowOffset = .zero
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: calm ? 12 : 11, weight: calm ? .medium : .light),
            .kern: calm ? 0.2 : 0.6,
            .foregroundColor: calm
                ? UIColor(white: 1, alpha: 0.92)
                : UIColor(white: 1, alpha: 0.5 * (0.74 + 0.24 * prominence)),
            .paragraphStyle: paragraph,
            .shadow: shadow
        ])
    }

    /// The rendered box for a label, taken as the wider of the normal and
    /// Calm Accessibility styles so toggling calm never needs a relayout.
    /// Cached: measurement runs on every layout pass.
    private static var measureCache: [String: CGSize] = [:]

    static func measure(_ text: String) -> CGSize {
        if let hit = measureCache[text] { return hit }
        var size = CGSize.zero
        for calm in [false, true] {
            let bounds = attributed(text, prominence: 1, calm: calm).boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            size.width = max(size.width, ceil(bounds.width))
            size.height = max(size.height, ceil(bounds.height))
        }
        measureCache[text] = size
        return size
    }
}

// MARK: - Settle

/// A resting-position transition the scene eases by hand in `update(_:)`,
/// because per-frame drift and SKAction moves would fight over `position`.
///
/// A transition created before the first frame (scene time unknown) carries
/// `start = pendingStart`; the update loop stamps the real start time on its
/// first pass, so a rise scheduled during cold launch still plays in full.
struct Settle {
    static let pendingStart: TimeInterval = -1

    var from: CGPoint
    var to: CGPoint
    var start: TimeInterval
    var duration: TimeInterval
    var easeOut: Bool

    static func immediate(_ point: CGPoint) -> Settle {
        Settle(from: point, to: point, start: 0, duration: 0, easeOut: false)
    }

    func position(at t: TimeInterval) -> CGPoint {
        guard duration > 0, t < start + duration else { return to }
        guard t > start else { return from }
        var k = (t - start) / duration
        // Ease out for rises, smoothstep for lateral settles.
        k = easeOut ? 1 - pow(1 - k, 3) : k * k * (3 - 2 * k)
        return CGPoint(x: from.x + (to.x - from.x) * k,
                       y: from.y + (to.y - from.y) * k)
    }
}

// MARK: - MoteNode

/// One thought in the water. The container's alpha is owned by SKActions
/// (fade in, fade out, crossfades); the sprites inside are owned by the
/// per-frame tick (breathing, glow, shimmer), so the two never fight.
final class MoteNode: SKNode {

    let fragmentID: UUID
    let sampler: DriftSampler
    private(set) var placement: MotePlacement
    var createdAt: Date
    var settle: Settle
    var energy: Double = FragmentEnergy.floor

    private let body: SKSpriteNode
    private let glow: SKSpriteNode

    /// Stable per-thought presence, matching the old shimmer: some sit
    /// forward in the water, some recede.
    private let shimmerAlpha: CGFloat

    init(placement: MotePlacement, createdAt: Date, resting: CGPoint) {
        self.fragmentID = placement.id
        self.placement = placement
        self.createdAt = createdAt
        self.sampler = DriftSampler(seedKey: placement.id.uuidString)
        self.settle = .immediate(resting)

        let shimmer = Double(NodeComposer.stableHash(placement.id.uuidString + "✦") % 1000) / 1000
        self.shimmerAlpha = 0.55 + CGFloat(shimmer) * 0.45

        glow = SKSpriteNode(texture: OrbTextures.glow)
        glow.colorBlendFactor = 1
        glow.zPosition = -1
        glow.alpha = 0

        body = SKSpriteNode(texture: nil)

        super.init()
        addChild(glow)
        addChild(body)
        apply(placement: placement)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("MoteNode is never decoded") }

    func apply(placement: MotePlacement) {
        self.placement = placement
        let d = placement.radius * 2
        body.texture = OrbTextures.mote(
            hue: placement.hue, radius: placement.radius,
            resurfacing: placement.isResurfacing)
        body.size = CGSize(width: d + OrbTextures.motePadding * 2,
                           height: d + OrbTextures.motePadding * 2)
        body.alpha = placement.isResurfacing ? 1 : shimmerAlpha
        glow.color = UIColor(OceanTheme.glowWarm)
        glow.size = CGSize(width: d * 3, height: d * 3)
    }

    /// Per-frame motion and light. `clusterOffset` is the sway of the mote's
    /// current, so a whole region moves as one body of water.
    func tick(t: TimeInterval, clusterOffset: CGVector, motion: MotionPolicy) {
        let resting = settle.position(at: t)
        guard motion == .full else {
            position = resting
            body.setScale(1)
            glow.alpha = glowAlpha(pulse: 0)
            return
        }

        // Common fate: the family's shared sway (clusterOffset) is the
        // dominant motion; each dot keeps only a whisper of its own wander,
        // 1.5 to 3 pt by energy, buoyancy up to 3. That whisper is what
        // makes the tight 1.5x orbits hard-safe; keep these caps in step
        // with OceanLayoutEngine.Metrics.
        let amplitude = 1.5 + 1.5 * energy
        let pace = 0.75 + 0.5 * energy
        let wander = sampler.wander(at: t, amplitude: amplitude, timeScale: pace)
        let buoyancy = CGFloat(3 * energy)

        position = CGPoint(
            x: resting.x + clusterOffset.dx + wander.dx,
            y: resting.y + clusterOffset.dy + wander.dy + buoyancy
        )
        body.setScale(sampler.breathing(at: t))
        glow.alpha = glowAlpha(pulse: (sin(t * 0.9) + 1) / 2)
    }

    /// Warmth by recency, kept quiet: the curve bends so only genuinely
    /// fresh thoughts glow noticeably and the field never fogs over.
    private func glowAlpha(pulse: Double) -> CGFloat {
        var alpha = 0.03 + 0.22 * pow(energy, 1.5)
        if placement.isResurfacing {
            // The old ambient pulse, kept: the day's thought quietly beats.
            alpha += 0.10 + 0.06 * pulse
        }
        return CGFloat(min(0.45, alpha))
    }
}

// MARK: - ClusterNode

/// One current: the labeled conceptual region thoughts gather around.
final class ClusterNode: SKNode {

    let clusterID: String
    let sampler: DriftSampler
    private(set) var placement: ClusterPlacement
    var settle: Settle

    private let body: SKSpriteNode
    private let label: SKLabelNode

    /// The current's sway this frame; members read it so the region moves
    /// as one.
    private(set) var currentOffset: CGVector = .zero

    init(placement: ClusterPlacement, resting: CGPoint, calm: Bool) {
        self.clusterID = placement.id
        self.placement = placement
        self.sampler = DriftSampler(seedKey: placement.id)
        self.settle = .immediate(resting)

        body = SKSpriteNode(texture: nil)
        label = SKLabelNode()
        label.numberOfLines = 2
        label.verticalAlignmentMode = .top
        label.horizontalAlignmentMode = .center

        super.init()
        addChild(body)
        addChild(label)
        apply(placement: placement, calm: calm)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ClusterNode is never decoded") }

    func apply(placement: ClusterPlacement, calm: Bool) {
        self.placement = placement
        let d = placement.radius * 2
        body.texture = OrbTextures.cluster(
            hue: placement.hue, radius: placement.radius,
            prominence: placement.prominence)
        body.size = CGSize(width: d + OrbTextures.clusterPadding * 2,
                           height: d + OrbTextures.clusterPadding * 2)
        zPosition = CGFloat(placement.prominence)

        // The wrap width is the measured width the layout reserved, so the
        // rendered label always fits the box that collision protected.
        label.preferredMaxLayoutWidth = placement.labelSize.width + 1
        label.attributedText = OceanLabelStyle.attributed(
            placement.label, prominence: placement.prominence, calm: calm)
        label.position = CGPoint(
            x: placement.labelOffset.width,
            y: -(placement.radius + 13 + placement.labelOffset.height)
        )
    }


    func tick(t: TimeInterval, motion: MotionPolicy) {
        let resting = settle.position(at: t)
        guard motion == .full else {
            currentOffset = .zero
            position = resting
            body.setScale(1)
            return
        }
        currentOffset = sampler.wander(at: t, amplitude: 4, timeScale: 0.6)
        position = CGPoint(x: resting.x + currentOffset.dx,
                           y: resting.y + currentOffset.dy)
        body.setScale(sampler.breathing(at: t))
    }
}
