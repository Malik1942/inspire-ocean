import SpriteKit
import UIKit

/// The Ocean's viewport: an SKCameraNode panned by dragging open water.
///
/// A touch that begins on a bubble belongs to bubble interactions (taps
/// today, drags in a later effort); a touch on water pans. Momentum carries
/// a released pan and decays exponentially; the edges of the world rubber
/// band, resisting while dragging past the bounds and springing back on
/// release. Pan is direct manipulation, so it works identically under
/// Reduce Motion and Calm Accessibility. No zoom in this patch.
@MainActor
final class OceanCameraController: NSObject, UIGestureRecognizerDelegate {

    let node = SKCameraNode()

    /// World bounds in scene coordinates, layout extent plus margin.
    var worldBounds: CGRect = .zero

    /// Asks the scene whether a touch begins on a bubble.
    var beginsOnBubble: ((CGPoint) -> Bool)?

    /// Fired once each time a pan and its momentum come fully to rest, so
    /// the scene can refresh camera-dependent state (accessibility frames).
    var onRest: (() -> Void)?

    private weak var scene: SKScene?
    private var pan: UIPanGestureRecognizer?
    private var velocity = CGVector.zero
    private var dragging = false
    private var moving = false
    private var lastTime: TimeInterval = 0

    /// The layout bakes the scroll margin into the world bounds it emits
    /// (and the x axis must stay exactly viewport-wide so it locks), so the
    /// camera adds none of its own.
    private let margin: CGFloat = 0
    private let rubberResistance: CGFloat = 0.35
    /// Momentum halves roughly every fifth of a second: a glide, not a slide.
    private let momentumDecay: CGFloat = 3.4
    private let springRate: CGFloat = 9
    private let restSpeed: CGFloat = 4

    // MARK: Lifecycle

    func attach(to view: SKView, scene: SKScene) {
        self.scene = scene
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = self
        view.addGestureRecognizer(recognizer)
        pan = recognizer
    }

    func detach(from view: SKView) {
        if let pan { view.removeGestureRecognizer(pan) }
        pan = nil
    }

    // MARK: Gesture

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard let scene, let view = scene.view else { return true }
        let point = scene.convertPoint(fromView: touch.location(in: view))
        return !(beginsOnBubble?(point) ?? false)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }
        switch gesture.state {
        case .began:
            dragging = true
            moving = true
            velocity = .zero
        case .changed:
            let translation = gesture.translation(in: view)
            gesture.setTranslation(.zero, in: view)
            // View y grows downward, scene y grows upward.
            var proposed = CGPoint(
                x: node.position.x - translation.x,
                y: node.position.y + translation.y
            )
            // Past the edge, the water resists.
            let limit = clamped(proposed)
            proposed.x = limit.x + (proposed.x - limit.x) * rubberResistance
            proposed.y = limit.y + (proposed.y - limit.y) * rubberResistance
            node.position = proposed
        case .ended, .cancelled, .failed:
            dragging = false
            let v = gesture.velocity(in: view)
            velocity = CGVector(dx: -v.x, dy: v.y)
        default:
            break
        }
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

        // Spring back inside the world, critically damped by construction:
        // the offset shrinks proportionally each frame, it never oscillates.
        let limit = clamped(position)
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
