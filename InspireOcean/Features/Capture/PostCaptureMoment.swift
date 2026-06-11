import SwiftUI
import SwiftData

/// The post-capture "understanding moment" (PRD §12: AI as reflective partner).
///
/// After a fragment is released, the confirmation quietly evolves as on-device
/// understanding lands:
///   received (poetic phrase) → understood (interpreted title)
///   → optionally: one nearby fragment + two quiet actions.
///
/// It is purely presentational and ephemeral — auto-fades if ignored, costs
/// nothing to dismiss, and never blocks capture. If the title or related
/// lookup never resolves, it behaves exactly like the old confirmation flash.
struct PostCaptureMoment: Identifiable, Equatable {
    let id: UUID              // the captured node's id
    var phrase: String        // the poetic "received" phrase
    var title: String?        // interpreted title, once resolved
    var related: RelatedHint?

    struct RelatedHint: Equatable {
        let nodeID: UUID
        let title: String
    }

    static let receivedPhrases = [
        "Drifted into the Ocean", "Carried out to sea", "The Ocean caught it", "Released"
    ]

    static func received(for nodeID: UUID) -> PostCaptureMoment {
        PostCaptureMoment(id: nodeID, phrase: receivedPhrases.randomElement() ?? "Released")
    }

    /// One *strong* nearby fragment for the freshly captured node, or nil.
    ///
    /// Reuses the existing semantic ranking; the similarity floor keeps the
    /// hint honest — a weak match shows nothing rather than a stretch.
    @MainActor
    static func strongRelatedHint(
        for nodeID: UUID,
        context: ModelContext,
        ai: any OceanAIService
    ) -> RelatedHint? {
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { !$0.isArchived })
        guard let nodes = try? context.fetch(descriptor),
              let node = nodes.first(where: { $0.id == nodeID })
        else { return nil }

        let candidates = ai.relatedNodeIDs(to: node, among: nodes, limit: 1)
        guard let bestID = candidates.first,
              let best = nodes.first(where: { $0.id == bestID })
        else { return nil }

        // A notch above the nearby-thoughts floor: the hint names one
        // fragment with confidence, so it needs meaning-level strength.
        let strength = SemanticThemes.relatedness(
            textA: node.meaningText, themesA: node.themes, moodA: node.mood,
            textB: best.meaningText, themesB: best.themes, moodB: best.mood
        )
        guard strength >= 0.5 else { return nil }

        return RelatedHint(nodeID: best.id, title: best.displayTitle)
    }
}

// MARK: - View

/// The capsule itself. Phase one is visually identical to the previous
/// `DriftConfirmation`; later phases reuse the same material, hairline and
/// motion language used across the app.
struct PostCaptureMomentView: View {
    let moment: PostCaptureMoment
    var onTurnIntoQuestion: () -> Void
    var onSeeInOcean: () -> Void

    var body: some View {
        Group {
            if let title = moment.title {
                understood(title)
            } else {
                received
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: moment)
    }

    /// Phase 1 — exactly the old confirmation flash.
    private var received: some View {
        Label(moment.phrase, systemImage: "checkmark.seal.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(OceanTheme.foam)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
    }

    /// Phase 2/3 — the Ocean's interpretation, and one quiet nearby thought.
    private func understood(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Understood as")
                    .font(.caption2)
                    .foregroundStyle(OceanTheme.faint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(2)
            }

            if let related = moment.related {
                Text("Drifts near “\(related.title)”")
                    .font(.caption2)
                    .foregroundStyle(OceanTheme.mist)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    quietAction("Turn into question", system: "questionmark.circle",
                                action: onTurnIntoQuestion)
                    quietAction("See in Ocean", system: "water.waves",
                                action: onSeeInOcean)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func quietAction(_ title: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system)
                .font(.caption)
                .foregroundStyle(OceanTheme.foam)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Color.white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
