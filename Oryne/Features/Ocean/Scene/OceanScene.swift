import SpriteKit
import UIKit

/// What the scene needs to know about one fragment, detached from SwiftData:
/// model objects never enter the render loop.
struct FragmentSnapshot: Equatable {
    let id: UUID
    let createdAt: Date
    let title: String
}

/// The Ocean field as a SpriteKit scene.
///
/// The contract with SwiftUI is narrow on purpose: data flows in through
/// `apply(layout:fragments:motion:calm:)` as value snapshots, events flow out
/// through the two tap closures, and every per-frame concern (drift,
/// breathing, energy, camera pan) lives in `update(_:)`. SwiftUI state
/// never changes per frame.
final class OceanScene: SKScene {

    // MARK: Events out

    var onTapFragment: ((UUID) -> Void)?
    var onTapCluster: ((String) -> Void)?

    // MARK: State

    private(set) var motion: MotionPolicy = .full
    private var calmPresentation = false

    private var clusterNodes: [String: ClusterNode] = [:]
    private var moteNodes: [UUID: MoteNode] = [:]
    private var currentLayout = OceanLayout()
    private var pending: (layout: OceanLayout, fragments: [FragmentSnapshot])?
    private var lastFragments: [UUID: FragmentSnapshot] = [:]

    private let cameraController = OceanCameraController()
    private var needsInitialFraming = true

    private var lastTime: TimeInterval = 0
    private var lastEnergyRefresh: TimeInterval = -.greatestFiniteMagnitude

    /// Scene-side transient boost for the resurfaced thought: it rises and
    /// glows for a while, then eases back to its true recency. Never persisted.
    private var boostStart: [UUID: TimeInterval] = [:]

    private var touchDown: (location: CGPoint, time: TimeInterval)?
    /// A press that landed on a current and may grow into a kinship hold. The
    /// slop check in `touchesMoved` cancels it, leaving the long-press-then-
    /// move path free for a future drag phase to claim.
    private var holdCandidate: (clusterID: String, start: TimeInterval)?
    /// The current whose kin are currently lit, so release settles exactly
    /// those neighbors back to baseline.
    private var activeKinshipCluster: String?

    // MARK: Tuning

    private enum Tuning {
        static let settleDuration: TimeInterval = 0.7
        static let riseDuration: TimeInterval = 2.5
        static let risePoints: CGFloat = 24
        static let fadeInDuration: TimeInterval = 0.45
        static let fadeOutDuration: TimeInterval = 0.3
        static let crossfadeDuration: TimeInterval = 0.25
        static let energyRefreshInterval: TimeInterval = 4
        static let boostAmount: Double = 0.35
        static let boostDecaySeconds: Double = 180
        static let moteZ: CGFloat = 10
        /// How long a still press on a current takes to become a kinship hold.
        /// Longer than a tap, short enough to feel deliberate.
        static let holdActivation: TimeInterval = 0.35
    }

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        if camera == nil {
            camera = cameraController.node
            addChild(cameraController.node)
            cameraController.attach(to: view, scene: self)
            cameraController.onRest = { [weak self] in
                guard let self else { return }
                self.rebuildAccessibility(fragments: self.lastFragments)
            }
        }
        flushPendingIfPossible()
    }

    override func willMove(from view: SKView) {
        cameraController.detach(from: view)
        super.willMove(from: view)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // The world no longer depends on the viewport; a resize only needs
        // the camera to stay inside the bounds.
        cameraController.reclamp()
        flushPendingIfPossible()
    }

    // MARK: Data in

    func apply(
        layout: OceanLayout,
        fragments: [FragmentSnapshot],
        motion: MotionPolicy,
        calm: Bool
    ) {
        self.motion = motion
        self.calmPresentation = calm

        guard view != nil, size.width > 1, size.height > 1 else {
            pending = (layout, fragments)
            return
        }
        pending = nil
        integrate(layout: layout, fragments: fragments)
    }

    private func flushPendingIfPossible() {
        guard let pending, view != nil, size.width > 1, size.height > 1 else { return }
        self.pending = nil
        integrate(layout: pending.layout, fragments: pending.fragments)
    }

    private func integrate(layout: OceanLayout, fragments: [FragmentSnapshot]) {
        // A relayout ends any in-progress kinship reveal cleanly, before the
        // cluster nodes and the kinship map underneath it change.
        releaseKinship()
        holdCandidate = nil

        let byID = Dictionary(uniqueKeysWithValues: fragments.map { ($0.id, $0) })

        // Currents.
        var seenClusters = Set<String>()
        for placement in layout.clusters {
            seenClusters.insert(placement.id)
            let resting = scenePoint(placement.center)
            if let node = clusterNodes[placement.id] {
                node.apply(placement: placement, calm: calmPresentation)
                moveNode(node, to: resting, settle: { node.settle = $0 })
            } else {
                let node = ClusterNode(placement: placement, resting: resting, calm: calmPresentation)
                node.position = resting
                fadeIn(node)
                addChild(node)
                clusterNodes[placement.id] = node
            }
        }
        for (id, node) in clusterNodes where !seenClusters.contains(id) {
            clusterNodes[id] = nil
            fadeOutAndRemove(node)
        }

        // Thoughts.
        var seenMotes = Set<UUID>()
        for placement in layout.motes {
            seenMotes.insert(placement.id)
            let resting = restingPoint(for: placement)
            let createdAt = byID[placement.id]?.createdAt ?? .now
            if let node = moteNodes[placement.id] {
                let becameResurfacing = placement.isResurfacing && !node.placement.isResurfacing
                node.createdAt = createdAt
                node.apply(placement: placement)
                if becameResurfacing {
                    rise(node, to: resting)
                } else {
                    moveNode(node, to: resting, settle: { node.settle = $0 })
                }
            } else {
                let node = MoteNode(placement: placement, createdAt: createdAt, resting: resting)
                node.zPosition = Tuning.moteZ
                node.position = resting
                if placement.isResurfacing {
                    rise(node, to: resting)
                } else {
                    fadeIn(node)
                }
                addChild(node)
                moteNodes[placement.id] = node
            }
        }
        for (id, node) in moteNodes where !seenMotes.contains(id) {
            moteNodes[id] = nil
            boostStart[id] = nil
            fadeOutAndRemove(node)
        }

        currentLayout = layout
        lastFragments = byID

        // The camera learns the water's new extent.
        cameraController.worldBounds = sceneRect(layout.worldBounds)
        frameInitiallyIfNeeded()

        #if DEBUG
        let violations = OceanLayoutEngine.audit(layout)
        let orphans = OceanLayoutEngine.orphanScan(layout, viewport: size)
        let screens = size.height > 1
            ? String(format: "%.2f", layout.worldBounds.height / size.height) : "?"
        print("OceanLayout AUDIT: \(violations.count) violations, "
            + "\(orphans.count) orphans, "
            + "\(layout.clusters.count) currents, \(layout.motes.count) motes, "
            + "world \(Int(layout.worldBounds.width))x\(Int(layout.worldBounds.height)) "
            + "(\(screens) screens), "
            + "hash \(OceanLayoutEngine.layoutHash(layout))")
        for violation in violations {
            print("OceanLayout AUDIT violation: \(violation)")
        }
        for orphan in orphans {
            print("OceanLayout ORPHAN: \(orphan)")
        }
        // Centers on one line so a capture's locality is checkable from the
        // console: unchanged currents must print identical coordinates.
        let centers = layout.clusters
            .map { "\($0.id)=(\(Int($0.center.x.rounded())),\(Int($0.center.y.rounded())))" }
            .sorted().joined(separator: " ")
        print("OceanLayout centers: \(centers)")
        #endif

        refreshEnergies(now: .now, t: lastTime)
        rebuildAccessibility(fragments: byID)
    }

    /// First presentation framing: the dive starts at the top, which the
    /// layout orders as the most energetic water. The vertical rhythm
    /// guarantees the next current always peeks past the bottom edge.
    private func frameInitiallyIfNeeded() {
        guard needsInitialFraming, size.width > 1, !currentLayout.clusters.isEmpty else { return }
        needsInitialFraming = false
        let world = sceneRect(currentLayout.worldBounds)
        cameraController.frame(on: CGPoint(x: 0, y: world.maxY))
    }

    // MARK: Transitions

    private func moveNode(_ node: SKNode, to resting: CGPoint, settle: (Settle) -> Void) {
        let current = node.position
        guard current.distance(to: resting) > 0.5 else {
            settle(.immediate(resting))
            return
        }
        if motion == .still {
            // Positions are information under stillness; changes crossfade.
            settle(.immediate(resting))
            node.run(.sequence([
                .fadeAlpha(to: 0, duration: Tuning.crossfadeDuration / 2),
                .run { node.position = resting },
                .fadeAlpha(to: 1, duration: Tuning.crossfadeDuration / 2)
            ]))
        } else {
            settle(Settle(
                from: current, to: resting,
                start: transitionStart, duration: Tuning.settleDuration, easeOut: false))
        }
    }

    /// Scene time for a transition scheduled right now. Before the first
    /// frame the clock is unknown; the sentinel lets `update(_:)` stamp it.
    private var transitionStart: TimeInterval {
        lastTime > 0 ? lastTime : Settle.pendingStart
    }

    /// The resurfaced thought comes up from the deep: a slow ease-out rise
    /// with a temporary energy boost that decays on its own.
    private func rise(_ node: MoteNode, to resting: CGPoint) {
        boostStart[node.fragmentID] = transitionStart
        if motion == .still {
            node.settle = .immediate(resting)
            node.alpha = 0
            node.run(.fadeIn(withDuration: Tuning.crossfadeDuration))
        } else {
            let deep = CGPoint(x: resting.x, y: resting.y - Tuning.risePoints)
            node.position = deep
            node.settle = Settle(
                from: deep, to: resting,
                start: transitionStart, duration: Tuning.riseDuration, easeOut: true)
        }
    }

    private func fadeIn(_ node: SKNode) {
        node.alpha = 0
        node.run(.fadeIn(withDuration: Tuning.fadeInDuration))
    }

    private func fadeOutAndRemove(_ node: SKNode) {
        node.run(.sequence([
            .fadeOut(withDuration: Tuning.fadeOutDuration),
            .removeFromParent()
        ]))
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        lastTime = currentTime

        if currentTime - lastEnergyRefresh > Tuning.energyRefreshInterval {
            lastEnergyRefresh = currentTime
            refreshEnergies(now: .now, t: currentTime)
        }

        for node in clusterNodes.values {
            if node.settle.start == Settle.pendingStart { node.settle.start = currentTime }
            node.tick(t: currentTime, motion: motion)
        }
        for node in moteNodes.values {
            if node.settle.start == Settle.pendingStart { node.settle.start = currentTime }
            if boostStart[node.fragmentID] == Settle.pendingStart {
                boostStart[node.fragmentID] = currentTime
            }
            let offset = node.placement.orbitKey
                .flatMap { clusterNodes[$0]?.currentOffset } ?? .zero
            node.tick(t: currentTime, clusterOffset: offset, motion: motion)
        }

        // A press held still on a current past the threshold lights its kin.
        if let hold = holdCandidate, activeKinshipCluster == nil,
           currentTime - hold.start >= Tuning.holdActivation {
            for kin in currentLayout.kinship[hold.clusterID] ?? [] {
                clusterNodes[kin.key]?.setKinship(kin.strength, motion: motion)
            }
            activeKinshipCluster = hold.clusterID
        }

        cameraController.update(currentTime)
    }

    /// Energy is a slow value (7 day half-life); refreshing it every few
    /// seconds is indistinguishable from continuous and keeps the frame loop
    /// to pure arithmetic.
    private func refreshEnergies(now: Date, t: TimeInterval) {
        for node in moteNodes.values {
            var energy = FragmentEnergy.energy(createdAt: node.createdAt, now: now)
            if let start = boostStart[node.fragmentID] {
                let elapsed = max(0, t - start)
                let boost = Tuning.boostAmount * exp(-elapsed / Tuning.boostDecaySeconds)
                if boost < 0.01 {
                    boostStart[node.fragmentID] = nil
                } else {
                    energy = min(1, energy + boost)
                }
            }
            node.energy = energy
        }
    }

    // MARK: Coordinates

    /// Layout world coordinates grow downward (UIKit style); scene y grows
    /// upward. One negation, applied at the boundary, independent of any
    /// viewport size.
    private func scenePoint(_ layoutPoint: CGPoint) -> CGPoint {
        CGPoint(x: layoutPoint.x, y: -layoutPoint.y)
    }

    private func sceneRect(_ layoutRect: CGRect) -> CGRect {
        CGRect(x: layoutRect.minX, y: -layoutRect.maxY,
               width: layoutRect.width, height: layoutRect.height)
    }

    private func restingPoint(for placement: MotePlacement) -> CGPoint {
        scenePoint(placement.base)
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let view else { return }
        // Catch any decelerating glide immediately: while momentum runs, the
        // camera moves the scene under a still finger, so an un-halted tap
        // would hit-test a drifted point and open the wrong current. Halting
        // freezes the camera for the tap and lets a drag resume from rest.
        cameraController.halt()
        let location = touch.location(in: self)
        // Slop is stored and compared in view space: during a pan the camera
        // moves under the finger, so scene-space distance is meaningless (it
        // can stay ~0 while the finger travels). Hit-testing still uses scene
        // coordinates below.
        touchDown = (touch.location(in: view), lastTime)
        // A press directly on a current (not a mote) may grow into a kinship
        // hold; motes keep tap only.
        if nearestMote(to: location) == nil, let cluster = clusterHit(at: location) {
            holdCandidate = (cluster.clusterID, lastTime)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let down = touchDown, let view else { return }
        // Past the tap slop this is no longer a hold. Measured in view space,
        // since a panning camera moves the scene under a stationary finger.
        // Cancelling here leaves the long-press-then-move path open for the
        // pan recognizer to take over.
        if touch.location(in: view).distance(to: down.location) >= 12 {
            holdCandidate = nil
            releaseKinship()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchDown = nil
        holdCandidate = nil
        releaseKinship()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasHold = activeKinshipCluster != nil
        releaseKinship()
        holdCandidate = nil
        defer { touchDown = nil }
        guard let touch = touches.first, let down = touchDown, let view else { return }
        // A hold that revealed kinship is its own gesture; releasing it never
        // also opens detail.
        guard !wasHold else { return }
        let location = touch.location(in: self)
        // View-space slop again: a real drag recognized as a pan cancels this
        // touch before it ever reaches here; a near-stationary lift opens.
        guard touch.location(in: view).distance(to: down.location) < 12 else { return }

        if let mote = nearestMote(to: location) {
            onTapFragment?(mote.fragmentID)
        } else if let cluster = clusterHit(at: location) {
            onTapCluster?(cluster.clusterID)
        }
    }

    /// Settle the currently lit kin currents back to baseline.
    private func releaseKinship() {
        guard let id = activeKinshipCluster else { return }
        for kin in currentLayout.kinship[id] ?? [] {
            clusterNodes[kin.key]?.setKinship(0, motion: motion)
        }
        activeKinshipCluster = nil
    }

    /// Generous targets for small visuals, matching the old invisible 36 to
    /// 44 pt touch circles.
    private func nearestMote(to point: CGPoint) -> MoteNode? {
        var best: (node: MoteNode, distance: CGFloat)?
        for node in moteNodes.values {
            let distance = node.position.distance(to: point)
            let reach = max(22, node.placement.radius + 14)
            if distance <= reach, distance < (best?.distance ?? .infinity) {
                best = (node, distance)
            }
        }
        return best?.node
    }

    /// The orb plus the label hanging below it: the most legible thing about
    /// a current should open it too.
    private func clusterHit(at point: CGPoint) -> ClusterNode? {
        for node in clusterNodes.values {
            let radius = node.placement.radius
            if node.position.distance(to: point) <= radius + 8 { return node }
            let labelWidth = max(96, radius * 2 * 1.6) + 24
            let labelTop = node.position.y - radius
            let labelBottom = labelTop - 60
            if abs(point.x - (node.position.x + node.placement.labelOffset.width)) <= labelWidth / 2,
               point.y <= labelTop, point.y >= labelBottom {
                return node
            }
        }
        return nil
    }

    // MARK: Accessibility

    /// SpriteKit is invisible to VoiceOver, so the scene publishes one
    /// element per current and per thought, anchored at resting positions.
    /// Frames are camera-dependent: rebuilt on every integrate and whenever
    /// a pan (and its momentum) comes to rest.
    private func rebuildAccessibility(fragments: [UUID: FragmentSnapshot]) {
        guard let view, size.width > 1 else { return }
        var elements: [UIAccessibilityElement] = []

        func viewFrame(worldCenter: CGPoint, box: CGSize) -> CGRect {
            let center = convertPoint(toView: scenePoint(worldCenter))
            return CGRect(
                x: center.x - box.width / 2, y: center.y - box.height / 2,
                width: box.width, height: box.height
            )
        }

        for placement in currentLayout.clusters {
            let element = OceanAccessibilityElement(accessibilityContainer: view)
            element.accessibilityLabel = placement.label
            element.accessibilityTraits = .button
            let d = placement.radius * 2
            element.accessibilityFrameInContainerSpace = viewFrame(
                worldCenter: CGPoint(x: placement.center.x, y: placement.center.y + 22),
                box: CGSize(width: d, height: d + 44)
            )
            let id = placement.id
            element.onActivate = { [weak self] in self?.onTapCluster?(id) }
            elements.append(element)
        }
        for placement in currentLayout.motes {
            let element = OceanAccessibilityElement(accessibilityContainer: view)
            element.accessibilityLabel = fragments[placement.id]?.title
            element.accessibilityTraits = .button
            element.accessibilityFrameInContainerSpace = viewFrame(
                worldCenter: placement.base, box: CGSize(width: 44, height: 44)
            )
            let id = placement.id
            element.onActivate = { [weak self] in self?.onTapFragment?(id) }
            elements.append(element)
        }
        view.accessibilityElements = elements
    }
}

/// An accessibility element that forwards activation to the scene.
private final class OceanAccessibilityElement: UIAccessibilityElement {
    var onActivate: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        guard let onActivate else { return false }
        onActivate()
        return true
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
