import SwiftUI

/// A resolved placement for one *current* — a conceptual region of the Ocean
/// holding every thought that expresses one theme. Currents are the field's
/// large, labeled, always-legible objects. They carry atmosphere and meaning;
/// density is expressed by the particles orbiting them, never by a number.
struct ClusterPlacement: Identifiable {
    let id: String           // concept key ("water & ocean")
    var label: String        // what the user reads ("Water & Ocean")
    var center: CGPoint
    var radius: CGFloat      // visual core radius (scales with member count)
    var hue: Double
    var prominence: Double   // 0...1, recency of the newest member
    var labelOffset: CGSize  // small deterministic drift so labels feel placed, not pinned
}

/// A resolved placement for one thought — a small particle in the water.
///
/// Particles orbiting a current (`orbitKey != nil`) express that current's
/// density; standalone particles are thoughts that belong to no region yet.
/// Either way, a particle *is* an individual thought and opens it when tapped.
struct MotePlacement: Identifiable {
    let id: UUID             // the node's id
    var base: CGPoint        // resting position (orbit point at baseAngle, or scatter spot)
    var radius: CGFloat
    var hue: Double
    var kind: NodeKind
    var isResurfacing: Bool

    // Orbit around a current — nil for standalone thoughts that drift freely.
    var orbitKey: String?    // the current's cluster id (drives sway + direction)
    var orbitCenter: CGPoint = .zero
    var orbitRadius: CGFloat = 0
    var baseAngle: Double = 0
}

struct OceanLayout {
    var clusters: [ClusterPlacement] = []
    var motes: [MotePlacement] = []
    var signature: String = ""
}

/// Cluster-first layout for the Ocean Field.
///
/// The field's large objects are *concept clusters*, not individual ideas:
/// every themed thought belongs to the current named by its primary theme,
/// and orbits it as a small particle — more particles, denser current.
/// Thoughts that haven't been understood yet (no themes) drift standalone
/// between the currents and regroup once understanding lands.
/// The result is deterministic and cached by `signature`; ambient drift and
/// orbital motion are layered on top in the view.
enum OceanLayoutEngine {

    /// Stream key for thoughts without themes (kept for the stream sheet's
    /// membership filter; such thoughts render standalone in the field).
    static let adriftKey = "adrift"

    /// Particles drawn per current; beyond this, density reads as "full".
    static let maxVisibleMotes = 12

    /// Concept keys are stored lowercase; currents wear them in Title Case.
    static func displayLabel(for key: String) -> String {
        key.split(separator: " ")
            .map { $0 == "&" ? "&" : $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Deterministic 0..<1 noise — the irregularity that keeps the field from
    /// reading as a tidy graph, stable across launches.
    private static func noise(_ key: String, _ salt: String) -> Double {
        Double(NodeComposer.stableHash(key + salt) % 1000) / 1000
    }

    static func signature(nodes: [Node], size: CGSize, resurfacingID: UUID?) -> String {
        // Primary theme is part of the signature: when async understanding
        // lands on a fresh capture, its cluster changes and the field must
        // recompute — ids alone wouldn't notice.
        let ids = nodes.map { $0.id.uuidString + "·" + ($0.themes.first ?? "") }
            .sorted().joined(separator: ",")
        return "\(ids)|\(Int(size.width))x\(Int(size.height))|\(resurfacingID?.uuidString ?? "-")"
    }

    static func compute(nodes: [Node], size: CGSize, resurfacingID: UUID?) -> OceanLayout {
        guard size.width > 50, size.height > 50, !nodes.isEmpty else { return OceanLayout() }

        let topInset: CGFloat = 168     // clears the header
        let bottomInset: CGFloat = 120  // clears the tab bar
        let sideInset: CGFloat = 52
        let usableH = max(120, size.height - topInset - bottomInset)
        let cx = size.width / 2
        let anchorY = topInset + usableH * 0.46
        let now = Date.now

        // MARK: 1 — themed thoughts gather into currents; the rest drift free

        var groups: [String: [Node]] = [:]
        var floaters: [Node] = []
        for node in nodes {
            if let theme = node.themes.first {
                groups[theme, default: []].append(node)
            } else {
                floaters.append(node)
            }
        }

        // Deterministic order: biggest current first, label breaks ties.
        let ordered = groups.sorted { a, b in
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            return a.key < b.key
        }

        // MARK: 2 — size and prominence

        func clusterRadius(memberCount: Int) -> CGFloat {
            min(46, 22 + 7 * CGFloat(Double(memberCount).squareRoot()))
        }
        func prominence(of members: [Node]) -> Double {
            let newest = members.map(\.createdAt).max() ?? .distantPast
            let days = now.timeIntervalSince(newest) / 86_400
            return min(1, max(0.25, exp(-days / 10)))
        }

        // MARK: 3 — seed centers on a *loosened* golden-angle spiral, then relax
        //
        // Each current's angle, distance and size carry deterministic noise so
        // the resting field reads as drifting regions, not an evenly spaced
        // diagram. The relaxation below still guarantees breathing room.

        var clusters: [ClusterPlacement] = []
        for (i, entry) in ordered.enumerated() {
            let r = clusterRadius(memberCount: entry.value.count)
                + CGFloat(noise(entry.key, "r") * 6 - 3)
            let angle = Double(i) * 2.39996 + 0.9 + (noise(entry.key, "a") - 0.5) * 1.1
            let spread: CGFloat = i == 0
                ? CGFloat(noise(entry.key, "d")) * 26
                : (64 + 30 * CGFloat(Double(i).squareRoot())) * CGFloat(0.78 + noise(entry.key, "d") * 0.5)
            let seed = CGPoint(
                x: cx + CGFloat(cos(angle)) * spread,
                y: anchorY + CGFloat(sin(angle)) * spread * (usableH / max(usableH, size.width))
            )
            clusters.append(ClusterPlacement(
                id: entry.key,
                label: displayLabel(for: entry.key),
                center: seed,
                radius: r,
                hue: NodeComposer.hue(for: entry.key),
                prominence: prominence(of: entry.value),
                labelOffset: CGSize(
                    width: (noise(entry.key, "lx") - 0.5) * 20,
                    height: noise(entry.key, "ly") * 6
                )
            ))
        }

        // Reserve room for the particle ring and the label under each current.
        func spacingRadius(_ c: ClusterPlacement) -> CGFloat { c.radius + 52 }

        // Labels hang in a rectangle *below* each orb, so vertical neighbors
        // need more room than circular distance suggests. Shrinking dy before
        // measuring makes the same physical gap read closer when it is
        // vertical, which pushes stacked currents ~30% further apart.
        let labelBias: CGFloat = 0.78

        let seeds = clusters.map(\.center)
        var vel = Array(repeating: CGVector(dx: 0, dy: 0), count: clusters.count)
        for _ in 0..<160 {
            var force = Array(repeating: CGVector(dx: 0, dy: 0), count: clusters.count)
            for i in clusters.indices {
                var f = CGVector(dx: 0, dy: 0)
                // spring back toward the seed spiral (keeps global shape)
                f.dx += (seeds[i].x - clusters[i].center.x) * 0.012
                f.dy += (seeds[i].y - clusters[i].center.y) * 0.012
                // repulsion between currents (vertically biased for labels)
                for j in clusters.indices where j != i {
                    let dx = clusters[i].center.x - clusters[j].center.x
                    let dy = clusters[i].center.y - clusters[j].center.y
                    let dist = max(1, (dx * dx + dy * labelBias * dy * labelBias).squareRoot())
                    let minDist = spacingRadius(clusters[i]) + spacingRadius(clusters[j]) - 30
                    if dist < minDist {
                        let push = (minDist - dist) / dist
                        f.dx += dx * push * 0.5
                        f.dy += dy * labelBias * push * 0.5
                    }
                }
                force[i] = f
            }
            for i in clusters.indices {
                vel[i].dx = (vel[i].dx + force[i].dx) * 0.82
                vel[i].dy = (vel[i].dy + force[i].dy) * 0.82
                var p = clusters[i].center
                p.x += vel[i].dx
                p.y += vel[i].dy
                let margin = clusters[i].radius + 26
                p.x = min(size.width - sideInset - margin + 26, max(sideInset + margin - 26, p.x))
                p.y = min(size.height - bottomInset - margin, max(topInset + margin, p.y))
                clusters[i].center = p
            }
        }

        // MARK: 4 — particles orbit their current

        var motes: [MotePlacement] = []
        for (clusterIndex, entry) in ordered.enumerated() {
            let cluster = clusters[clusterIndex]
            let members = entry.value.sorted { $0.createdAt > $1.createdAt }

            // Cap drawn particles; always keep the resurfacing thought visible.
            var visible = Array(members.prefix(maxVisibleMotes))
            if let rid = resurfacingID,
               let resurfacingNode = members.first(where: { $0.id == rid }),
               !visible.contains(where: { $0.id == rid }) {
                visible[visible.count - 1] = resurfacingNode
            }

            // Particles occupy a 240° arc that skips the bottom of the ring,
            // where the label hangs — so a particle can never sit on (or sway
            // across) its own current's label. In screen coordinates 90° is
            // straight down; [30°, 150°] is reserved for the label.
            // Within the arc, spacing and distance are deliberately uneven —
            // some particles huddle, some stray — so the ring reads as life
            // gathered around a current, not as a diagram.
            let arcStart = 150.0 * .pi / 180
            let arcSpan = 240.0 * .pi / 180
            for (i, node) in visible.enumerated() {
                let slot = (Double(i) + 0.5) / Double(visible.count)
                let angleJitter = (noise(node.id.uuidString, "θ") - 0.5) * 0.42
                let angle = min(arcStart + arcSpan - 0.10,
                                max(arcStart + 0.10, arcStart + slot * arcSpan + angleJitter))
                let dist = cluster.radius + 12 + CGFloat(noise(node.id.uuidString, "ρ")) * 14
                let base = CGPoint(
                    x: cluster.center.x + CGFloat(cos(angle)) * dist,
                    y: cluster.center.y + CGFloat(sin(angle)) * dist
                )
                motes.append(MotePlacement(
                    id: node.id,
                    base: base,
                    radius: node.id == resurfacingID
                        ? 8
                        : 4.5 + CGFloat(noise(node.id.uuidString, "s")) * 2.2,
                    hue: node.hue,
                    kind: node.kind,
                    isResurfacing: node.id == resurfacingID,
                    orbitKey: cluster.id,
                    orbitCenter: cluster.center,
                    orbitRadius: dist,
                    baseAngle: angle
                ))
            }
        }

        // MARK: 5 — standalone thoughts scatter between the currents

        var placedFloaters: [CGPoint] = []
        for node in floaters {
            let h = NodeComposer.stableHash(node.id.uuidString)
            var p = CGPoint(
                x: sideInset + CGFloat(h % 100) / 100 * (size.width - sideInset * 2),
                y: topInset + 20 + CGFloat((h / 100) % 100) / 100 * (usableH - 40)
            )
            // Nudge out of currents (ring and label included), and apart from
            // each other. The same vertical bias keeps floaters off the label
            // rectangle hanging below each orb.
            for _ in 0..<24 {
                var moved = false
                for c in clusters {
                    let dx = p.x - c.center.x, dy = p.y - c.center.y
                    let dist = max(1, (dx * dx + dy * labelBias * dy * labelBias).squareRoot())
                    let minDist = c.radius + 40
                    if dist < minDist {
                        p.x += dx / dist * (minDist - dist)
                        p.y += dy / dist * (minDist - dist)
                        moved = true
                    }
                }
                for q in placedFloaters {
                    let dx = p.x - q.x, dy = p.y - q.y
                    let dist = max(1, (dx * dx + dy * dy).squareRoot())
                    if dist < 24 {
                        p.x += dx / dist * (24 - dist)
                        p.y += dy / dist * (24 - dist)
                        moved = true
                    }
                }
                p.x = min(size.width - 18, max(18, p.x))
                p.y = min(size.height - bottomInset - 8, max(topInset + 8, p.y))
                if !moved { break }
            }
            placedFloaters.append(p)
            motes.append(MotePlacement(
                id: node.id,
                base: p,
                radius: node.id == resurfacingID ? 8 : 6,
                hue: node.hue,
                kind: node.kind,
                isResurfacing: node.id == resurfacingID,
                orbitKey: nil
            ))
        }

        return OceanLayout(
            clusters: clusters,
            motes: motes,
            signature: signature(nodes: nodes, size: size, resurfacingID: resurfacingID)
        )
    }
}
