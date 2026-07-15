import SwiftUI

/// A resolved placement for one *current*, a conceptual region of the Ocean
/// holding every thought that expresses one theme. Currents are the field's
/// large, labeled, always-legible objects. They carry atmosphere and meaning;
/// density is expressed by the particles orbiting them, never by a number.
struct ClusterPlacement: Identifiable {
    let id: String           // concept key ("water & ocean")
    var label: String        // what the user reads ("Water & Ocean")
    var center: CGPoint      // world coordinates, y down
    var radius: CGFloat      // visual core radius (scales with member count)
    var hue: Double
    var prominence: Double   // 0...1, recency of the newest member
    var labelOffset: CGSize  // small deterministic drift so labels feel placed, not pinned
    var labelSize: CGSize    // measured render box; part of the collision footprint
    var enclosingRadius: CGFloat  // center to farthest owned shape edge, drift included
}

/// A resolved placement for one thought, a small particle in the water.
struct MotePlacement: Identifiable {
    let id: UUID             // the node's id
    var base: CGPoint        // resting position in world coordinates
    var radius: CGFloat
    var hue: Double
    var kind: NodeKind
    var isResurfacing: Bool

    // Orbit around a current; nil for standalone thoughts that drift freely.
    var orbitKey: String?
    var orbitCenter: CGPoint = .zero
    var orbitRadius: CGFloat = 0
    var baseAngle: Double = 0
}

/// One current's kinship to another: their streams overlap because a thought
/// expresses both themes. Strength is how much they share, so kinship can be
/// felt by degree, not just present or absent.
struct CurrentKinship: Hashable {
    let key: String
    let strength: Double
}

struct OceanLayout {
    var clusters: [ClusterPlacement] = []
    var motes: [MotePlacement] = []
    var signature: String = ""
    /// The water's full extent in world coordinates. The screen is a viewport
    /// onto this; the camera pans across it.
    var worldBounds: CGRect = .zero
    /// Member sets per current, kept so the next compute can tell which
    /// clusters actually changed and leave the rest exactly where they are.
    var membership: [String: Set<UUID>] = [:]
    /// For each current, the other currents its stream overlaps, strongest
    /// first. Drives the long-press kinship reveal; positions never depend on
    /// it, so it stays out of the layout hash.
    var kinship: [String: [CurrentKinship]] = [:]
}

/// Cluster-first layout for the Ocean Field, world-space edition.
///
/// The old engine compressed everything into one screen; this one inverts the
/// constraint. Density is fixed by *footprints*: each bubble reserves its
/// visual radius plus its maximum drift excursion plus label clearance, two
/// footprints never intersect, and when space runs out the world grows
/// outward. The screen is a viewport; the camera reaches the rest.
///
/// Everything is deterministic: every random-looking number derives from
/// `NodeComposer.stableHash`, so a fixed seed reproduces the identical world
/// across launches, and the incremental path keeps settled clusters exactly
/// where they were.
enum OceanLayoutEngine {

    /// Stream key for thoughts without themes (kept for the stream sheet's
    /// membership filter; such thoughts render standalone in the field).
    static let adriftKey = "adrift"

    /// Particles drawn per current: a small constellation of the newest
    /// thoughts, never a swarm. The orb's size carries the real mass and the
    /// stream holds the full list; six delicate dots read as gathered life,
    /// twelve read as noise.
    static let maxVisibleMotes = 6

    // MARK: Footprint metrics
    //
    // Worst-case per-frame drift excursions, mirrored from the scene
    // (OceanNodes tick): individual mote wander 1.5 + 1.5e capped at 3,
    // buoyancy 3e capped at 3, cluster sway 4, breathing 2 percent of orb
    // radius. The individual caps were retuned down again (from 6 and 5)
    // for the affiliation patch: the family's shared sway is now the
    // dominant motion (common fate), and the whisper of individual drift is
    // what makes 1.5x-radius tight orbits hard-safe.
    enum Metrics {
        /// Clear water demanded between separate currents, around labels,
        /// and between strangers.
        static let waterGap: CGFloat = 10
        /// Clear water within one current: siblings sit close.
        static let snugGap: CGFloat = 4
        /// A mote's center never exceeds this multiple of its parent orb's
        /// radius: when the orb is off screen, so is its family. Widened from
        /// 1.5 so the ring sits farther off the rim and reads as its own band
        /// of light; the reach is horizontal (dots stay clamped inside the
        /// orb's vertical span), so this does not deepen the dive.
        static let orbitCap: CGFloat = 1.7
        static let moteWander: CGFloat = 3
        static let moteBuoyancy: CGFloat = 3
        static let clusterSway: CGFloat = 4
        static let breathe: CGFloat = 0.02

        /// Vertical rhythm of the dive: the gap between vertically adjacent
        /// currents is proportional to the smaller of the two orbs (this
        /// ratio times its radius), held inside a hard safety band. Small
        /// neighbors sit close, large ones breathe; the maximum stays a hard
        /// cap because long empty stretches are a layout failure.
        static let gapRatio: CGFloat = 0.45
        static let gapMin: CGFloat = 12
        static let gapMax: CGFloat = 46
        /// Floor for the lateral swing off the spine, alternating per cluster.
        /// The swing now scales with the safe range (see `placeOnSpine`); this
        /// is the minimum offset it uses whenever the range allows it.
        static let zigzagMin: CGFloat = 60
        /// The swing's safe range is measured against this width, never the
        /// real screen. Orbs have absolute sizes, so a swing that scales with
        /// the device pins every current against the edges of a Max-class
        /// phone and hollows out the middle; capping the width reproduces the
        /// standard-phone composition, centered, with the extra width becoming
        /// even side margins. Screens at or below the reference are untouched
        /// (the cap is a no-op there), and the hard edge invariant keeps
        /// holding because a capped swing only ever moves inward.
        static let spineReferenceWidth: CGFloat = 393

        /// The world is exactly one viewport wide: the portrait screen
        /// width, stable per device and independent of rotation.
        static var designWidth: CGFloat {
            let bounds = UIScreen.main.bounds
            return min(bounds.width, bounds.height)
        }

        /// Required center distance between two motes of the same current
        /// (they share the current's sway, so it cancels pairwise; wander is
        /// independent per node, buoyancy differs by at most its full range).
        static func intraMoteDistance(_ rA: CGFloat, _ rB: CGFloat) -> CGFloat {
            rA + rB + 2 * moteWander + moteBuoyancy + snugGap
        }

        /// Between motes of different currents: sway no longer cancels and
        /// the full water gap applies.
        static func crossMoteDistance(_ rA: CGFloat, _ rB: CGFloat) -> CGFloat {
            rA + rB + 2 * moteWander + moteBuoyancy + 2 * clusterSway + waterGap
        }
    }

    /// Concept keys are stored lowercase; currents wear them in Title Case.
    static func displayLabel(for key: String) -> String {
        key.split(separator: " ")
            .map { $0 == "&" ? "&" : $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Deterministic 0..<1 noise, stable across launches.
    private static func noise(_ key: String, _ salt: String) -> Double {
        Double(NodeComposer.stableHash(key + salt) % 1000) / 1000
    }

    /// The current a node belongs to. The user's manual move lock
    /// (`anchorThemeKey`) wins over the primary theme; layout only ever
    /// decides position, never membership.
    static func currentKey(for node: Node) -> String? {
        node.anchorThemeKey ?? node.themes.first
    }

    /// Currents that overlap `key` by shared membership: the same relation
    /// that lets one thought visit more than one stream (a stream shows every
    /// thought whose themes include its concept, or that is anchored to it).
    /// Strength is the Jaccard overlap of the two currents' streams. Only
    /// currents that actually exist as orbs (some thought's primary) are
    /// returned, so the field and the detail row agree. Strongest first;
    /// deterministic, so no seed is involved.
    static func relatedCurrents(to key: String, among nodes: [Node]) -> [CurrentKinship] {
        guard key != adriftKey else { return [] }
        let active = nodes.filter { !$0.isArchived }
        let existing = Set(active.compactMap { currentKey(for: $0) })
        func members(_ k: String) -> Set<UUID> {
            Set(active.filter { $0.themes.contains(k) || $0.anchorThemeKey == k }.map(\.id))
        }
        let mine = members(key)
        guard !mine.isEmpty else { return [] }

        var others = Set<String>()
        for node in active where mine.contains(node.id) {
            for theme in node.themes where theme != key && existing.contains(theme) {
                others.insert(theme)
            }
            if let anchor = node.anchorThemeKey, anchor != key, existing.contains(anchor) {
                others.insert(anchor)
            }
        }

        var result: [CurrentKinship] = []
        for other in others where other != adriftKey {
            let theirs = members(other)
            let shared = mine.intersection(theirs).count
            guard shared > 0 else { continue }
            let union = mine.union(theirs).count
            result.append(CurrentKinship(key: other, strength: Double(shared) / Double(union)))
        }
        return result.sorted {
            $0.strength != $1.strength ? $0.strength > $1.strength : $0.key < $1.key
        }
    }

    /// Viewport size is deliberately absent: the layout no longer depends on
    /// the screen. Rotation and resize are camera concerns.
    static func signature(nodes: [Node], resurfacingID: UUID?) -> String {
        let ids = nodes.map { $0.id.uuidString + "·" + (currentKey(for: $0) ?? "") }
            .sorted().joined(separator: ",")
        return "\(ids)|\(resurfacingID?.uuidString ?? "-")"
    }

    // MARK: Compute

    /// Lays out the whole ocean in world coordinates.
    ///
    /// With `previous` supplied (the normal case after launch), clusters whose
    /// member set is unchanged keep centroid and member bases verbatim;
    /// clusters that gained or lost a member keep their centroid and repack
    /// locally; only genuinely new clusters and floaters are placed fresh. A
    /// capture therefore nudges its own current and nothing else.
    static func compute(
        nodes: [Node],
        resurfacingID: UUID?,
        previous: OceanLayout? = nil
    ) -> OceanLayout {
        guard !nodes.isEmpty else { return OceanLayout() }
        let now = Date.now

        // MARK: 1: themed thoughts gather into currents; the rest drift free

        var groups: [String: [Node]] = [:]
        var floaters: [Node] = []
        for node in nodes {
            if let theme = currentKey(for: node) {
                groups[theme, default: []].append(node)
            } else {
                floaters.append(node)
            }
        }
        func clusterRadius(memberCount: Int) -> CGFloat {
            min(46, 22 + 7 * CGFloat(Double(memberCount).squareRoot()))
        }
        func prominence(of members: [Node]) -> Double {
            let newest = members.map(\.createdAt).max() ?? .distantPast
            let days = now.timeIntervalSince(newest) / 86_400
            return min(1, max(0.25, exp(-days / 10)))
        }

        // The dive's order: most energetic water first, so opening the
        // Ocean always starts at the most recent thinking. Themeless
        // thoughts gather in the adrift current at the very bottom; they
        // are real thoughts with a real (existing) stream, just no theme
        // yet, and the gathering orb ends the orphan-dot problem.
        var entries = groups.sorted { a, b in
            let pa = prominence(of: a.value), pb = prominence(of: b.value)
            if pa != pb { return pa > pb }
            return a.key < b.key
        }
        if !floaters.isEmpty {
            entries.append((key: adriftKey, value: floaters))
        }

        // MARK: 2: pack each current locally (a tight ring around the orb)

        var packs: [String: ClusterPack] = [:]
        for (key, members) in entries {
            packs[key] = pack(
                key: key,
                members: members,
                radius: clusterRadius(memberCount: members.count),
                prominence: prominence(of: members),
                resurfacingID: resurfacingID,
                now: now
            )
        }

        // MARK: 3: place centroids; unchanged clusters stay put

        let previousMembership = previous?.membership ?? [:]
        let previousCenters: [String: CGPoint] = Dictionary(
            uniqueKeysWithValues: (previous?.clusters ?? []).map { ($0.id, $0.center) })

        var placed: [(key: String, shape: ClusterShape, orbRadius: CGFloat)] = []
        var pending: [(key: String, pack: ClusterPack)] = []

        for (key, _) in entries {
            guard let pack = packs[key] else { continue }
            if let center = previousCenters[key], previousMembership[key] != nil {
                // A settled current keeps its water even if members changed;
                // only its own ring repacks. Spatial stability beats ideal
                // packing.
                placed.append((key, ClusterShape(center: center, pack: pack), pack.radius))
            } else {
                pending.append((key, pack))
            }
        }

        // Fresh currents stack down the spine: alternate a gentle zigzag,
        // keep the size-relative gap to the current above, and never cross
        // the horizontal screen edges. New currents always append below the
        // settled water, so nothing above them moves.
        for (key, pack) in pending {
            let center = placeOnSpine(
                key: key, pack: pack,
                among: placed.map { ($0.shape, $0.orbRadius) },
                stackIndex: placed.count)
            placed.append((key, ClusterShape(center: center, pack: pack), pack.radius))
        }

        let centerByKey = Dictionary(uniqueKeysWithValues: placed.map { ($0.key, $0.shape.center) })

        // MARK: 4: materialize clusters and their motes in world space

        var clusters: [ClusterPlacement] = []
        var motes: [MotePlacement] = []
        var membership: [String: Set<UUID>] = [:]

        for (key, members) in entries {
            guard let pack = packs[key], let center = centerByKey[key] else { continue }
            membership[key] = Set(members.map(\.id))
            clusters.append(ClusterPlacement(
                id: key,
                label: pack.label,
                center: center,
                radius: pack.radius,
                hue: NodeComposer.hue(for: key),
                prominence: pack.prominence,
                labelOffset: pack.labelOffset,
                labelSize: pack.labelSize,
                enclosingRadius: pack.enclosingRadius
            ))
            for slot in pack.slots {
                let base = CGPoint(x: center.x + slot.offset.dx, y: center.y + slot.offset.dy)
                motes.append(MotePlacement(
                    id: slot.id,
                    base: base,
                    radius: slot.radius,
                    hue: slot.hue,
                    kind: slot.kind,
                    isResurfacing: slot.isResurfacing,
                    orbitKey: key,
                    orbitCenter: center,
                    orbitRadius: hypot(slot.offset.dx, slot.offset.dy),
                    baseAngle: slot.angle
                ))
            }
        }

        // MARK: 5: world bounds
        //
        // Exactly one viewport wide: the camera's existing young-ocean rule
        // locks any axis where the world fits the viewport, so emitting the
        // design width is the whole horizontal lock. Vertical carries the
        // scroll margin instead (the camera's own margin is zero).

        let halfW = Metrics.designWidth / 2
        var top = CGFloat.greatestFiniteMagnitude
        var bottom = -CGFloat.greatestFiniteMagnitude
        for (_, shape, _) in placed {
            top = min(top, shape.visualTop)
            bottom = max(bottom, shape.visualBottom)
        }
        if top > bottom { top = -100; bottom = 100 }

        // Vertical padding is the chrome's: the header and Resurfacing card
        // cover the top of the viewport and the tab bar covers the bottom,
        // so the world carries enough slack for the first current to clear
        // the header on open and the last (the adrift orb and its label) to
        // scroll fully above the tab bar.
        let headerInset: CGFloat = 150
        let tabBarInset: CGFloat = 120

        // Kinship between currents, for the long-press reveal. Derived only
        // from theme membership, so it is deterministic and adds no motion.
        var kinship: [String: [CurrentKinship]] = [:]
        for (key, _) in entries where key != adriftKey {
            let related = relatedCurrents(to: key, among: nodes)
            if !related.isEmpty { kinship[key] = related }
        }

        return OceanLayout(
            clusters: clusters,
            motes: motes,
            signature: signature(nodes: nodes, resurfacingID: resurfacingID),
            worldBounds: CGRect(
                x: -halfW, y: top - headerInset,
                width: Metrics.designWidth,
                height: (bottom - top) + headerInset + tabBarInset),
            membership: membership,
            kinship: kinship
        )
    }

    // MARK: - Local packing

    private struct MoteSlot {
        let id: UUID
        let radius: CGFloat
        let hue: Double
        let kind: NodeKind
        let isResurfacing: Bool
        let angle: Double
        let offset: CGVector
    }

    private struct ClusterPack {
        let label: String
        let radius: CGFloat
        let prominence: Double
        let labelOffset: CGSize
        let labelSize: CGSize
        let slots: [MoteSlot]
        let enclosingRadius: CGFloat
        /// The orb plus its dot ring, every drift margin included: the
        /// collision circle other currents keep clear of.
        let bodyRadius: CGFloat
        /// The visible top of the family: the ring's crest including the dot
        /// itself, without drift margins. The vertical rhythm measures from
        /// here, so invisible margins never pad a gap.
        let crownExtent: CGFloat
        /// The clean vertical reach up and down: the orb itself with breathing
        /// and sway. Dots are clamped inside the orb's vertical span, so the
        /// orb, not the wide ring, defines the top and bottom for stacking.
        /// This is what keeps the dive tight; the ring only reaches sideways.
        let orbExtent: CGFloat
        /// Where the label box hangs relative to the orb center. Its size is
        /// `labelSize`; the collision footprint treats it as a rectangle so
        /// neighboring currents can sit beside a label, not clear a circle
        /// that pretends the label reaches in every direction.
        let labelCenterOffset: CGVector
    }

    /// A placed current's collision footprint: the body as a circle (orb
    /// plus its wide ring), the label as a rectangle. The label is narrow
    /// text, so a rectangle models it far more tightly than a circle, which
    /// is what lets currents stack close when a neighbor sits off to the
    /// side. The rectangle matches exactly what the audit enforces.
    private struct ClusterShape {
        let center: CGPoint
        let bodyRadius: CGFloat
        /// The label text box, already grown by the sway margin so a drifted
        /// label still fits inside it.
        let labelRect: CGRect
        /// Where this current visually ends: orb underside or label bottom,
        /// whichever is lower. The stacking rhythm measures from here.
        let visualBottom: CGFloat
        /// The visible crest of the current (orb top). The world's top edge
        /// sits here, so no invisible drift margin pads the head of the dive.
        let visualTop: CGFloat

        init(center: CGPoint, pack: ClusterPack) {
            self.center = center
            self.bodyRadius = pack.bodyRadius
            let labelCenter = CGPoint(
                x: center.x + pack.labelCenterOffset.dx,
                y: center.y + pack.labelCenterOffset.dy)
            self.labelRect = CGRect(
                x: labelCenter.x - pack.labelSize.width / 2 - Metrics.clusterSway,
                y: labelCenter.y - pack.labelSize.height / 2 - Metrics.clusterSway,
                width: pack.labelSize.width + 2 * Metrics.clusterSway,
                height: pack.labelSize.height + 2 * Metrics.clusterSway)
            self.visualBottom = max(center.y + pack.orbExtent, labelRect.maxY)
            // The visible top is the orb crest; dots are clamped inside the
            // orb's vertical span, so nothing reaches higher.
            self.visualTop = center.y - pack.orbExtent
        }

        private static func circleClearsRect(_ c: CGPoint, _ r: CGFloat,
                                             _ rect: CGRect, by gap: CGFloat) -> Bool {
            let dx = max(rect.minX - c.x, 0, c.x - rect.maxX)
            let dy = max(rect.minY - c.y, 0, c.y - rect.maxY)
            return hypot(dx, dy) >= r + gap
        }

        func clears(_ other: ClusterShape, by gap: CGFloat) -> Bool {
            // Body vs body, body vs the other's label rect, and the two label
            // rects. Each label already carries its sway margin, so a half
            // gap each keeps clear water between them.
            hypot(center.x - other.center.x, center.y - other.center.y)
                    >= bodyRadius + other.bodyRadius + gap
                && Self.circleClearsRect(center, bodyRadius, other.labelRect, by: gap)
                && Self.circleClearsRect(other.center, other.bodyRadius, labelRect, by: gap)
                && !labelRect.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(other.labelRect)
        }
    }

    /// Packs one current in local coordinates: the orb at the origin and a
    /// single tight ring of its newest thoughts hugging the rim, capped at
    /// 1.5x the orb radius so the family can never stray from its parent.
    /// Small orbs show fewer dots (whatever the tight ring can hold with
    /// hard separation) instead of crowding.
    private static func pack(
        key: String,
        members: [Node],
        radius: CGFloat,
        prominence: Double,
        resurfacingID: UUID?,
        now: Date
    ) -> ClusterPack {
        // The adrift gathering current is app-generated, so its label is a
        // localized string; every real current wears its concept key.
        let label = key == adriftKey
            ? String(localized: "Adrift")
            : displayLabel(for: key)
        let labelSize = OceanLabelStyle.measure(label)
        let labelOffset = CGSize(
            width: (noise(key, "lx") - 0.5) * 16,
            height: noise(key, "ly") * 6
        )

        func moteRadius(_ node: Node) -> CGFloat {
            node.id == resurfacingID ? 8 : 4.5 + CGFloat(noise(node.id.uuidString, "s")) * 2.2
        }

        let sorted = members.sorted { $0.createdAt > $1.createdAt }
        var candidates = Array(sorted.prefix(maxVisibleMotes))
        if let rid = resurfacingID,
           let resurfacingNode = sorted.first(where: { $0.id == rid }),
           !candidates.contains(where: { $0.id == rid }) {
            candidates[candidates.count - 1] = resurfacingNode
        }

        // The label hangs below the orb; the arc [30, 150] degrees is its
        // reserved water, same reservation as always.
        let arcStart = 150.0 * .pi / 180
        let arcSpan = 240.0 * .pi / 180

        // Every dot rides its own radius in the 1.45 to 1.65x band, floored so
        // it always clears the rim by at least 5 pt (the additive floor wins on
        // small orbs where the multiplier would clip). Dots stay outside the
        // orb in clear water, farther off the rim than before.
        let ringMax = Metrics.orbitCap * radius - 2
        func ringRadius(_ moteR: CGFloat, _ id: String) -> CGFloat {
            let base = (1.45 + noise(id, "rr") * 0.2) * radius
            return min(max(base, radius + moteR + 5), ringMax)
        }

        // The orphan guarantee does not need a squashed orbit: with the world
        // one viewport wide and the camera x locked, an orphan can only happen
        // vertically, so only the vertical extent is clamped. A dot that would
        // cross the clamp slides along its ring toward the sides, same
        // hemisphere, radius untouched, never inward.
        func slide(_ angle: Double, ring: CGFloat, moteR: CGFloat) -> Double {
            let maxDy = radius - moteR - 7
            guard maxDy > 0 else {
                return cos(angle) >= 0 ? 0 : .pi
            }
            let dy = Double(ring) * sin(angle)
            guard abs(dy) > Double(maxDy) else { return angle }
            let banked = asin(min(1, Double(maxDy / ring)))
            let vertical: Double = dy > 0 ? banked : -banked
            return cos(angle) >= 0 ? vertical : .pi - vertical
        }

        // Organic ring: each dot draws its own angle and radius from the
        // cluster id, so the arrangement is unique to this current and
        // identical across relaunches. A dot is accepted only if it clears
        // every placed dot by the hard intra-family separation; on repeated
        // misses it stays in the stream. No fixed slots, no mirror symmetry,
        // no two clusters alike. Resurfacing goes first so it always shows.
        let ordered = candidates.sorted { a, b in
            (a.id == resurfacingID ? 0 : 1) < (b.id == resurfacingID ? 0 : 1)
        }
        var slots: [MoteSlot] = []
        for node in ordered {
            let moteR = moteRadius(node)
            let ringR = ringRadius(moteR, node.id.uuidString)
            var chosen: (angle: Double, offset: CGVector)?
            for attempt in 0..<28 {
                let raw = arcStart + noise(node.id.uuidString, "a\(attempt)") * arcSpan
                let angle = slide(raw, ring: ringR, moteR: moteR)
                let off = CGVector(dx: CGFloat(cos(angle)) * ringR,
                                   dy: CGFloat(sin(angle)) * ringR)
                let clears = slots.allSatisfy { s in
                    hypot(off.dx - s.offset.dx, off.dy - s.offset.dy)
                        >= Metrics.intraMoteDistance(moteR, s.radius)
                }
                if clears { chosen = (angle, off); break }
            }
            guard let chosen else { continue }
            slots.append(MoteSlot(
                id: node.id,
                radius: moteR,
                hue: node.hue,
                kind: node.kind,
                isResurfacing: node.id == resurfacingID,
                angle: chosen.angle,
                offset: chosen.offset
            ))
        }

        // Never a lone dot: one particle reads as a notification badge, not a
        // constellation. A current that can place only one (a single member,
        // or an orb too tight to separate two) shows none, and the orb stands
        // alone and clean. Two is the floor for "gathered life"; one is worse
        // than zero.
        if slots.count == 1 { slots.removeAll() }

        // Center to farthest owned edge, drift included. With no dots the body
        // is just the orb; with dots the ring reaches widest at the cap, so use
        // the cap and the largest dot actually placed to stay conservative.
        let placedRMax = slots.map(\.radius).max() ?? 0
        let outermost = slots.isEmpty ? 0 : ringMax
        let labelReach = CGFloat(hypot(
            Double(labelSize.width / 2 + abs(labelOffset.width)),
            Double(radius + 13 + labelOffset.height + labelSize.height)
        ))
        // The body circle carries every margin a stranger's dot could need
        // against this family's dots (both wanders, buoyancy, both sways,
        // half the water gap each side), so two bodies at water-gap distance
        // can never let their dots touch, even facing each other head on.
        let moteReach = slots.isEmpty ? 0
            : outermost + placedRMax + Metrics.moteWander + Metrics.moteBuoyancy
                + Metrics.clusterSway + Metrics.waterGap / 2
        let orbReach = radius * (1 + Metrics.breathe) + Metrics.clusterSway
        let enclosing = max(moteReach, max(orbReach, labelReach + Metrics.clusterSway)) + 4

        return ClusterPack(
            label: label,
            radius: radius,
            prominence: prominence,
            labelOffset: labelOffset,
            labelSize: labelSize,
            slots: slots,
            enclosingRadius: enclosing,
            bodyRadius: max(moteReach, orbReach) + 2,
            crownExtent: slots.isEmpty ? orbReach : outermost + placedRMax,
            orbExtent: orbReach,
            labelCenterOffset: CGVector(
                dx: labelOffset.width,
                dy: radius + 13 + labelOffset.height + labelSize.height / 2)
        )
    }

    // MARK: - Poisson placement

    /// Deterministic spine stacking: each fresh current sits below all the
    /// settled water, swinging a gentle alternating zigzag off the spine,
    /// with a size-relative gap to the current above it. Nothing ever
    /// crosses the horizontal screen edges, at rest or mid-drift, so the
    /// whole ocean is one vertical dive.
    private static func placeOnSpine(
        key: String,
        pack: ClusterPack,
        among placed: [(shape: ClusterShape, orbRadius: CGFloat)],
        stackIndex: Int
    ) -> CGPoint {
        // The widest thing this current owns decides how far off the spine
        // it may swing: body circle or the label's horizontal reach. The
        // range is measured against the reference width, not the device
        // width, so Max-class screens keep the standard composition instead
        // of flinging every current to the edges (see `spineReferenceWidth`).
        let halfW = min(Metrics.designWidth, Metrics.spineReferenceWidth) / 2
        let reachX = max(
            pack.bodyRadius,
            abs(pack.labelCenterOffset.dx) + pack.labelSize.width / 2)
        let maxX = max(0, halfW - reachX - Metrics.clusterSway)
        let sign: CGFloat = stackIndex.isMultiple(of: 2) ? -1 : 1
        // Swing 80 to 95 percent of the safe range (deterministically
        // jittered) so currents use the full reference width, never exceeding
        // maxX (the hard horizontal-edge invariant) and never collapsing below
        // the old floor when maxX allows it. Small orbs reach near the edges;
        // very wide currents have a small maxX and naturally stay central.
        let desired = maxX * (0.80 + 0.15 * CGFloat(noise(key, "zig")))
        let x = sign * max(min(Metrics.zigzagMin, maxX), min(desired, maxX))

        guard !placed.isEmpty else {
            // The head of the dive: the orb top defines the world's top.
            return CGPoint(x: x, y: pack.orbExtent)
        }

        // The gap breathes with the smaller of the two neighbors, measured
        // between clean visible extents: the current above's visible bottom
        // to this current's orb top. The wide ring reaches only sideways, so
        // the orb defines the vertical rhythm and the dive stays tight.
        let neighbor = placed.max { $0.shape.visualBottom < $1.shape.visualBottom }!
        let bottom = neighbor.shape.visualBottom
        let proportional = Metrics.gapRatio * min(neighbor.orbRadius, pack.radius)
        let gap = min(Metrics.gapMax, max(Metrics.gapMin, proportional))
            * (0.92 + 0.16 * CGFloat(noise(key, "gap")))
        var center = CGPoint(x: x, y: bottom + gap + pack.orbExtent)

        // The zigzag plus rhythm all but guarantees clearance; if a very
        // wide pair still touches, ease straight down only as far as needed.
        var shape = ClusterShape(center: center, pack: pack)
        var guardCount = 0
        while !placed.allSatisfy({ shape.clears($0.shape, by: Metrics.waterGap) }), guardCount < 400 {
            center.y += 6
            shape = ClusterShape(center: center, pack: pack)
            guardCount += 1
        }
        return center
    }

    // MARK: - Overlap audit

    #if DEBUG
    /// A deterministic checksum over every resting position, for the
    /// fixed-seed acceptance check: two launches over the same store must
    /// print the same hash.
    static func layoutHash(_ layout: OceanLayout) -> String {
        let parts = layout.clusters.map {
            "\($0.id):\(Int($0.center.x.rounded())),\(Int($0.center.y.rounded()))"
        } + layout.motes.map {
            "\($0.id.uuidString):\(Int($0.base.x.rounded())),\(Int($0.base.y.rounded()))"
        }
        let joined = parts.sorted().joined(separator: "|")
        return String(format: "%016llx", UInt64(bitPattern: Int64(NodeComposer.stableHash(joined))))
    }

    /// Affiliation check across the whole dive: simulated viewports stepped
    /// every 100 pt of scroll must never contain a mote whose parent orb sits
    /// entirely outside the same viewport. Zero results means no orphans
    /// anywhere in the scroll range.
    static func orphanScan(_ layout: OceanLayout, viewport: CGSize) -> [String] {
        guard viewport.height > 1, !layout.motes.isEmpty else { return [] }
        var violations: [String] = []
        let parents = Dictionary(uniqueKeysWithValues: layout.clusters.map { ($0.id, $0) })
        let world = layout.worldBounds
        let bottomLimit = world.maxY - viewport.height / 2
        var camY = world.minY + viewport.height / 2

        while true {
            let view = CGRect(
                x: -viewport.width / 2, y: camY - viewport.height / 2,
                width: viewport.width, height: viewport.height)
            for m in layout.motes {
                let moteFrame = CGRect(
                    x: m.base.x - m.radius, y: m.base.y - m.radius,
                    width: m.radius * 2, height: m.radius * 2)
                guard moteFrame.intersects(view),
                      let key = m.orbitKey, let parent = parents[key] else { continue }
                let orbFrame = CGRect(
                    x: parent.center.x - parent.radius, y: parent.center.y - parent.radius,
                    width: parent.radius * 2, height: parent.radius * 2)
                if !orbFrame.intersects(view) {
                    violations.append("orphan mote of \(key) at scroll \(Int(camY))")
                }
            }
            if camY >= bottomLimit { break }
            camY = min(camY + 100, bottomLimit)
        }
        return violations
    }
    #endif

    #if DEBUG
    /// Machine check for the acceptance criteria: every pair of drift-inflated
    /// footprints must keep clear water. Returns human-readable violations;
    /// empty means the layout is sound.
    static func audit(_ layout: OceanLayout) -> [String] {
        var violations: [String] = []

        func moteMargin(_ m: MotePlacement) -> CGFloat {
            m.radius + Metrics.moteWander + Metrics.moteBuoyancy
        }
        func labelRect(_ c: ClusterPlacement) -> CGRect {
            CGRect(
                x: c.center.x + c.labelOffset.width - c.labelSize.width / 2,
                y: c.center.y + c.radius + 13 + c.labelOffset.height,
                width: c.labelSize.width,
                height: c.labelSize.height
            )
        }
        func circleRectClearance(_ p: CGPoint, _ rect: CGRect) -> CGFloat {
            let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
            let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
            return hypot(dx, dy)
        }

        let motes = layout.motes
        for i in motes.indices {
            for j in (i + 1)..<motes.count {
                let a = motes[i], b = motes[j]
                let same = a.orbitKey != nil && a.orbitKey == b.orbitKey
                let need = same
                    ? Metrics.intraMoteDistance(a.radius, b.radius)
                    : Metrics.crossMoteDistance(a.radius, b.radius)
                let d = hypot(a.base.x - b.base.x, a.base.y - b.base.y)
                if d < need - 0.5 {
                    violations.append("mote pair \(d.rounded()) < \(need.rounded())")
                }
            }
            let m = motes[i]
            for c in layout.clusters {
                let own = m.orbitKey == c.id
                let dOrb = hypot(m.base.x - c.center.x, m.base.y - c.center.y)
                if own {
                    // Affiliation is the hard rule: a family dot rests
                    // strictly outside its orb's rim (now by at least 4 pt,
                    // matching the wider ring floor), stays within the orbit
                    // cap, and never escapes the body footprint.
                    if dOrb < c.radius + m.radius + 4 - 0.5 {
                        violations.append(
                            "mote inside rim of \(c.id): \(dOrb.rounded()) < \((c.radius + m.radius + 4).rounded())")
                    }
                    if dOrb > Metrics.orbitCap * c.radius + 0.5 {
                        violations.append(
                            "mote beyond orbit cap of \(c.id): \(dOrb.rounded()) > \((Metrics.orbitCap * c.radius).rounded())")
                    }
                    let reach = dOrb + m.radius + Metrics.moteWander + Metrics.moteBuoyancy
                    if reach > c.enclosingRadius + 0.5 {
                        violations.append("mote escapes body of \(c.id)")
                    }
                } else {
                    let needOrb = m.radius + c.radius * (1 + Metrics.breathe)
                        + Metrics.moteWander + Metrics.moteBuoyancy
                        + 2 * Metrics.clusterSway + Metrics.waterGap
                    if dOrb < needOrb - 0.5 {
                        violations.append("mote vs orb \(c.id) \(dOrb.rounded()) < \(needOrb.rounded())")
                    }
                }
                // A stranger's label keeps full clear water; the family's
                // own label is family too, so snug water suffices.
                let needLabel = m.radius + Metrics.moteWander + Metrics.moteBuoyancy
                    + (own ? Metrics.snugGap : 2 * Metrics.clusterSway + Metrics.waterGap)
                let dLabel = circleRectClearance(m.base, labelRect(c))
                if dLabel < needLabel - 0.5 {
                    violations.append("mote vs label \(c.id) \(dLabel.rounded()) < \(needLabel.rounded())")
                }
            }
        }

        // Single-axis rule: nothing may cross the horizontal screen edges,
        // at rest or mid-drift.
        let halfW = Metrics.designWidth / 2
        for c in layout.clusters {
            let bodyReach = abs(c.center.x) + c.radius * (1 + Metrics.breathe) + Metrics.clusterSway
            let label = labelRect(c).insetBy(dx: -Metrics.clusterSway, dy: 0)
            if bodyReach > halfW + 0.5 || label.minX < -halfW - 0.5 || label.maxX > halfW + 0.5 {
                violations.append("\(c.id) crosses a horizontal edge")
            }
        }
        for m in motes where abs(m.base.x) + m.radius + Metrics.moteWander
            + Metrics.clusterSway > halfW + 0.5 {
            violations.append("mote crosses a horizontal edge")
        }

        let clusters = layout.clusters
        for i in clusters.indices {
            for j in (i + 1)..<clusters.count {
                let a = clusters[i], b = clusters[j]
                let needOrb = a.radius * (1 + Metrics.breathe) + b.radius * (1 + Metrics.breathe)
                    + 2 * Metrics.clusterSway + Metrics.waterGap
                let d = hypot(a.center.x - b.center.x, a.center.y - b.center.y)
                if d < needOrb - 0.5 {
                    violations.append("orbs \(a.id)/\(b.id) \(d.rounded()) < \(needOrb.rounded())")
                }
                let rectClear = circleRectClearance(b.center, labelRect(a))
                let needRect = b.radius * (1 + Metrics.breathe) + 2 * Metrics.clusterSway + Metrics.waterGap
                if rectClear < needRect - 0.5 {
                    violations.append("label \(a.id) vs orb \(b.id) \(rectClear.rounded()) < \(needRect.rounded())")
                }
                let la = labelRect(a).insetBy(dx: -Metrics.clusterSway, dy: -Metrics.clusterSway)
                let lb = labelRect(b).insetBy(
                    dx: -(Metrics.clusterSway + Metrics.waterGap),
                    dy: -(Metrics.clusterSway + Metrics.waterGap))
                if la.intersects(lb) {
                    violations.append("labels \(a.id)/\(b.id) intersect")
                }
            }
        }

        // Organic rings must be unique: no two currents share an arrangement.
        // Fingerprint each ring by its sorted, rounded angle set.
        var byCluster: [String: [Int]] = [:]
        for m in layout.motes {
            guard let key = m.orbitKey else { continue }
            byCluster[key, default: []].append(Int((m.baseAngle * 180 / .pi).rounded()))
        }
        var seenRings: [String: String] = [:]
        for (key, angles) in byCluster {
            let fingerprint = angles.sorted().map(String.init).joined(separator: ",")
            if let twin = seenRings[fingerprint] {
                violations.append("ring of \(key) matches \(twin)")
            } else {
                seenRings[fingerprint] = key
            }
        }
        return violations
    }
    #endif
}
