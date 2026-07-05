import SpriteKit
import UIKit

/// The Ocean's viewport: an SKCameraNode panned by dragging anywhere.
///
/// Every touch can pan. `UIPanGestureRecognizer` has ~10pt of built-in
/// hysteresis before it begins, so a stationary tap or a kinship hold never
/// triggers it; only a real drag does, wherever it starts, orb or open water.
/// When the pan recognizes it cancels the scene's in-flight touch sequence
/// (`cancelsTouchesInView`), cleanly aborting a pending tap or an active hold.
/// Momentum carries a released pan and decays exponentially; the edges of the
/// world rubber band with the standard iOS curve while dragging past the
/// bounds and spring back on release. Pan is direct manipulation, so it works
/// identically under Reduce Motion and Calm Accessibility. No zoom in this patch.
@MainActor
final class OceanCameraController: NSObject {

    let node = SKCameraNode()

    /// World bounds in scene coordinates, layout extent plus margin.
    var worldBounds: CGRect = .zero

    /// Fired once each time a pan and its momentum come fully to rest, so
    /// the scene can refresh camera-dependent state (accessibility frames).
    var onRest: (() -> Void)?

    private weak var scene: SKScene?
    private var pan: UIPanGestureRecognizer?
    private var velocity = CGVector.zero
    private var dragging = false
    private var moving = false
    private var lastTime: TimeInterval = 0
    /// The unresisted "virtual" camera position during a drag. It tracks the
    /// finger 1:1; the rubber-band curve maps its overscroll onto the
    /// displayed position, so overscroll resets itself once it re-enters bounds.
    private var raw = CGPoint.zero

    /// The layout bakes the scroll margin into the world bounds it emits
    /// (and the x axis must stay exactly viewport-wide so it locks), so the
    /// camera adds none of its own.
    private let margin: CGFloat = 0
    /// Standard iOS rubber-band constant (UIScrollView uses 0.55): the follow
    /// past the edge starts strong and progressively stiffens.
    private let rubberConstant: CGFloat = 0.55
    /// Momentum matches `UIScrollView.DecelerationRate.normal` (0.998/ms), an
    /// exponential constant of `-1000 * ln(0.998) ≈ 2.0 /s`: it halves roughly
    /// every 0.35s, a longer, iOS-native glide.
    private let momentumDecay: CGFloat = 2.0
    /// Critically damped spring back: ~0.3s to settle, no oscillation.
    private let springRate: CGFloat = 7
    private let restSpeed: CGFloat = 4

    // MARK: Lifecycle

    func attach(to view: SKView, scene: SKScene) {
        self.scene = scene
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.maximumNumberOfTouches = 1
        // The default, made explicit as a contract: when the pan recognizes,
        // the scene's in-flight touch sequence gets `touchesCancelled`, which
        // cleanly aborts a pending tap or an active kinship hold. The pan's
        // ~10pt recognition hysteresis means a stationary tap or hold never
        // fires it, so touches need no per-touch pre-filtering.
        recognizer.cancelsTouchesInView = true
        view.addGestureRecognizer(recognizer)
        pan = recognizer
    }

    func detach(from view: SKView) {
        if let pan { view.removeGestureRecognizer(pan) }
        pan = nil
    }

    // MARK: Gesture

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }
        switch gesture.state {
        case .began:
            dragging = true
            moving = true
            velocity = .zero
            // The virtual position starts at the camera and tracks the finger
            // 1:1 from here; it re-syncs to the displayed position on every grab.
            raw = node.position
        case .changed:
            guard let scene else { break }
            let translation = gesture.translation(in: view)
            gesture.setTranslation(.zero, in: view)
            // View y grows downward, scene y grows upward. The virtual position
            // follows the finger with no resistance; the displayed position
            // applies the rubber-band curve to however far the virtual position
            // has pushed past the world's edge. In bounds the curve is the
            // identity, so the two stay equal and overscroll self-resets the
            // moment the finger comes back inside.
            raw.x -= translation.x
            raw.y += translation.y
            let limit = clamped(raw)
            node.position = CGPoint(
                x: limit.x + rubberBand(raw.x - limit.x, dim: scene.size.width),
                y: limit.y + rubberBand(raw.y - limit.y, dim: scene.size.height)
            )
        case .ended, .cancelled, .failed:
            dragging = false
            let v = gesture.velocity(in: view)
            velocity = CGVector(dx: -v.x, dy: v.y)
        default:
            break
        }
    }

    /// The standard iOS rubber-band curve for one axis: strong initial follow
    /// that progressively stiffens, so the edge feels alive without letting the
    /// content run away. `offset` is the signed distance past the clamped
    /// limit; `dim` is the viewport size along that axis. Sign is preserved and
    /// the curve passes through the origin, so an in-bounds offset of zero maps
    /// to zero.
    private func rubberBand(_ offset: CGFloat, dim: CGFloat) -> CGFloat {
        guard dim > 0, offset != 0 else { return 0 }
        let sign: CGFloat = offset < 0 ? -1 : 1
        let magnitude = abs(offset)
        return sign * (1 - 1 / (magnitude * rubberConstant / dim + 1)) * dim
    }

    // MARK: Frame loop

    func update(_ currentTime: TimeInterval) {
        defer { lastTime = currentTime }
        let dt = CGFloat(min(max(currentTime - lastTime, 0), 1.0 / 20))
        guard dt > 0, !dragging else { return }

        var position = node.position
        position.x += velocity.dx * dt
        position.y += velocity.dy * dt
        let decay = exp(-momentumDecay * dt)
        velocity.dx *= decay
        velocity.dy *= decay

        let limit = clamped(position)

        // Past the edge, the boundary absorbs momentum hard (UIScrollView feel):
        // the deeper the overshoot, the faster velocity bleeds, so a hard flick
        // barely crosses the rim instead of sailing ~200pt past it. Ramped in
        // from the edge so there is no discontinuity at the rim. A locked axis
        // has position == limit there, so it contributes 0 and stays centered.
        let overshoot = hypot(position.x - limit.x, position.y - limit.y)
        if overshoot > 0.5 {
            let boundaryDecay = min(1, 12 * dt) * min(1, overshoot / 40)
            velocity.dx *= (1 - boundaryDecay)
            velocity.dy *= (1 - boundaryDecay)
        }

        // Spring back inside the world, critically damped by construction:
        // the offset shrinks proportionally each frame, it never oscillates.
        let pull = min(1, springRate * dt)
        position.x += (limit.x - position.x) * pull
        position.y += (limit.y - position.y) * pull
        node.position = position

        let offset = hypot(position.x - limit.x, position.y - limit.y)
        let speed = hypot(velocity.dx, velocity.dy)
        if moving, speed < restSpeed, offset < 0.5 {
            velocity = .zero
            moving = false
            onRest?()
        }
    }

    // MARK: Framing

    /// Places the camera, clamped to the world.
    func frame(on point: CGPoint) {
        node.position = clamped(point)
        moving = false
        velocity = .zero
    }

    func reclamp() {
        node.position = clamped(node.position)
    }

    /// A new touch catches any in-flight glide where it is, the way an iOS
    /// scroll view stops under a finger. The scene calls this on touch-down so
    /// the camera holds still while a tap is hit-tested (momentum must not
    /// drift the scene out from under the finger onto the wrong mote) and so a
    /// drag resumes from a stable position. No-op when already at rest.
    func halt() {
        guard moving else { return }
        velocity = .zero
        moving = false
        onRest?()
    }

    /// The camera center range keeping the viewport inside the world plus
    /// margin. Axes where the world is smaller than the viewport lock
    /// centered, so a young ocean simply sits still.
    private func clamped(_ point: CGPoint) -> CGPoint {
        guard let scene, scene.size.width > 1, !worldBounds.isEmpty else { return point }
        let bounds = worldBounds.insetBy(dx: -margin, dy: -margin)
        let halfW = scene.size.width / 2
        let halfH = scene.size.height / 2
        let x: CGFloat = bounds.width <= scene.size.width
            ? bounds.midX
            : min(max(point.x, bounds.minX + halfW), bounds.maxX - halfW)
        let y: CGFloat = bounds.height <= scene.size.height
            ? bounds.midY
            : min(max(point.y, bounds.minY + halfH), bounds.maxY - halfH)
        return CGPoint(x: x, y: y)
    }
}
