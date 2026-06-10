import SwiftUI

/// Visual tier of a fragment in the Ocean. Only a handful of fragments live in
/// the foreground at once; the rest fade into the depth as ambient background.
enum OceanTier {
    case foreground
    case background
}

/// A fully-resolved placement for one fragment: where it sits, how large and
/// prominent it is, and which tier it belongs to. Produced by `OceanLayoutEngine`.
struct OceanPlacement: Identifiable {
    let id: UUID
    var base: CGPoint        // resolved position before ambient drift
    var radius: CGFloat      // visual core radius
    var prominence: Double   // 0...1 visual weight (drives size/glow/brightness)
    var tier: OceanTier
    var isResurfacing: Bool
    var kind: NodeKind
    var title: String
}

struct OceanLayout {
    var placements: [UUID: OceanPlacement] = [:]
    /// Back-to-front draw order (background first, most-prominent last/on-top).
    var order: [UUID] = []
    var signature: String = ""
}

/// Force-relaxation layout for the Ocean Field.
///
/// Goals (per redesign): intentional spatial logic, guaranteed breathing room
/// (no overlap / no text collision), clear hierarchy, and a small legible
/// foreground. The result is deterministic and cached by `signature`, so the
/// field is stable between frames — ambient drift is layered on top in the view,
/// not baked into the layout (separating atmosphere from structure).
enum OceanLayoutEngine {

    static let maxForeground = 6

    static func signature(nodes: [Node], size: CGSize, resurfacingID: UUID?) -> String {
        let ids = nodes.map(\.id.uuidString).sorted().joined(separator: ",")
        return "\(ids)|\(Int(size.width))x\(Int(size.height))|\(resurfacingID?.uuidString ?? "-")"
    }

    static func compute(nodes: [Node], size: CGSize, resurfacingID: UUID?) -> OceanLayout {
        guard size.width > 50, size.height > 50, !nodes.isEmpty else { return OceanLayout() }

        let topInset: CGFloat = 168     // clears the header
        let bottomInset: CGFloat = 120  // clears the tab bar
        let sideInset: CGFloat = 36
        let usableH = max(120, size.height - topInset - bottomInset)
        let cx = size.width / 2
        let now = Date.now

        // MARK: 1 — relevance score → tier → prominence

        func ageDays(_ n: Node) -> Double { now.timeIntervalSince(n.createdAt) / 86_400 }
        func score(_ n: Node) -> Double {
            let recency = exp(-ageDays(n) / 9.0)                       // newer ≈ 1
            let branch = (n.children?.isEmpty == false) ? 0.18 : 0     // active ideas
            let rich = min(1.0, Double(n.searchableText.count) / 240) * 0.12
            let resurface = (n.id == resurfacingID) ? 1.2 : 0          // always foreground
            return recency + branch + rich + resurface
        }

        let scored = nodes.map { (node: $0, score: score($0)) }.sorted { $0.score > $1.score }
        let maxScore = scored.first?.score ?? 1
        let fgCount = min(maxForeground, nodes.count)

        var placements: [UUID: OceanPlacement] = [:]
        var primaryTheme: [UUID: String] = [:]

        for (index, entry) in scored.enumerated() {
            let n = entry.node
            let rel = maxScore > 0 ? entry.score / maxScore : 0
            let tier: OceanTier = index < fgCount ? .foreground : .background
            let prominence: Double
            let radius: CGFloat
            if tier == .foreground {
                prominence = 0.55 + 0.45 * rel
                radius = 22 + CGFloat(prominence) * 8            // dia 44…60 (was 48…76)
            } else {
                prominence = 0.12 + 0.22 * rel
                radius = 10 + CGFloat(prominence) * 7            // dia 20…34 (was tiny)
            }
            primaryTheme[n.id] = n.themes.first ?? "drift"
            placements[n.id] = OceanPlacement(
                id: n.id, base: .zero, radius: radius, prominence: prominence,
                tier: tier, isResurfacing: n.id == resurfacingID,
                kind: n.kind, title: n.displayTitle
            )
        }

        // MARK: 2 — theme cluster centers (related fragments attract)

        let themes = Array(Set(primaryTheme.values)).sorted()
        var clusterCenter: [String: CGPoint] = [:]
        let anchorY = topInset + usableH * 0.44
        if themes.count <= 1 {
            clusterCenter[themes.first ?? "drift"] = CGPoint(x: cx, y: anchorY)
        } else {
            let rx = (size.width - sideInset * 2) * 0.33
            let ry = usableH * 0.30
            for (i, t) in themes.enumerated() {
                let ang = Double(i) / Double(themes.count) * 2 * .pi - .pi / 2
                clusterCenter[t] = CGPoint(x: cx + CGFloat(cos(ang)) * rx,
                                           y: anchorY + CGFloat(sin(ang)) * ry)
            }
        }

        // MARK: 3 — recency → vertical target (newer floats up)

        let byRecency = nodes.sorted { $0.createdAt > $1.createdAt }
        var recencyY: [UUID: CGFloat] = [:]
        for (i, n) in byRecency.enumerated() {
            let f = nodes.count == 1 ? 0.3 : Double(i) / Double(nodes.count - 1)
            recencyY[n.id] = topInset + CGFloat(0.10 + f * 0.78) * usableH
        }

        // MARK: 4 — seed positions deterministically

        let ids = nodes.map(\.id)
        var pos: [UUID: CGPoint] = [:]
        var vel: [UUID: CGVector] = [:]
        for n in nodes {
            let c = clusterCenter[primaryTheme[n.id] ?? "drift"] ?? CGPoint(x: cx, y: anchorY)
            let jx = CGFloat(NodeComposer.stableHash(n.id.uuidString + "x") % 100) / 100 - 0.5
            let jy = CGFloat(NodeComposer.stableHash(n.id.uuidString + "y") % 100) / 100 - 0.5
            pos[n.id] = CGPoint(x: c.x + jx * 70, y: c.y + jy * 70)
            vel[n.id] = .zero
        }

        // Effective spacing radius reserves room for the label under foreground nodes,
        // guaranteeing text never collides with another fragment.
        func spacingRadius(_ id: UUID) -> CGFloat {
            guard let p = placements[id] else { return 20 }
            return p.radius + (p.tier == .foreground ? 30 : 5)
        }

        // MARK: 5 — relaxation

        let kGroup: CGFloat = 0.014
        let kRecency: CGFloat = 0.020
        let kSink: CGFloat = 0.45
        let kCenterX: CGFloat = 0.010
        let damping: CGFloat = 0.80

        for _ in 0..<170 {
            var force: [UUID: CGVector] = [:]
            for i in ids {
                guard let pi = pos[i], let pli = placements[i] else { continue }
                var f = CGVector(dx: 0, dy: 0)

                // grouping toward theme cluster
                let c = clusterCenter[primaryTheme[i] ?? "drift"] ?? CGPoint(x: cx, y: anchorY)
                f.dx += (c.x - pi.x) * kGroup
                f.dy += (c.y - pi.y) * kGroup

                // recency vertical spring
                if let ty = recencyY[i] { f.dy += (ty - pi.y) * kRecency }

                // background sinks a little deeper
                f.dy += CGFloat(1 - pli.prominence) * kSink

                // keep foreground from hugging the edges horizontally
                if pli.tier == .foreground { f.dx += (cx - pi.x) * kCenterX }

                // repulsion / collision avoidance
                for j in ids where j != i {
                    guard let pj = pos[j] else { continue }
                    let dx = pi.x - pj.x, dy = pi.y - pj.y
                    let dist = max(1, (dx * dx + dy * dy).squareRoot())
                    let minDist = spacingRadius(i) + spacingRadius(j)
                    if dist < minDist {
                        let push = (minDist - dist) / dist
                        f.dx += dx * push * 0.5
                        f.dy += dy * push * 0.5
                    }
                }
                force[i] = f
            }

            for i in ids {
                guard var p = pos[i], let pli = placements[i], let f = force[i] else { continue }
                // lower-prominence nodes yield more, so the foreground keeps its space
                let yield: CGFloat = pli.tier == .background ? 1.25 : 0.8
                var v = vel[i] ?? .zero
                v.dx = (v.dx + f.dx * yield) * damping
                v.dy = (v.dy + f.dy * yield) * damping
                p.x += v.dx
                p.y += v.dy
                p.x = min(size.width - sideInset - pli.radius, max(sideInset + pli.radius, p.x))
                p.y = min(size.height - bottomInset - pli.radius, max(topInset + pli.radius, p.y))
                pos[i] = p
                vel[i] = v
            }
        }

        for id in ids { placements[id]?.base = pos[id] ?? CGPoint(x: cx, y: anchorY) }

        // Draw background first, then foreground by ascending prominence (top = most prominent).
        let order = placements.values
            .sorted { a, b in
                if a.tier != b.tier { return a.tier == .background }
                return a.prominence < b.prominence
            }
            .map(\.id)

        return OceanLayout(
            placements: placements,
            order: order,
            signature: signature(nodes: nodes, size: size, resurfacingID: resurfacingID)
        )
    }
}
