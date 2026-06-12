import SwiftUI
import SwiftData

/// The post-capture trust moment (PRD §12: AI as reflective partner).
///
/// One capsule, three honest phases — the app's whole feedback language for
/// a release:
///
///   **catching** — the thought is being caught (a breath of working dots)
///   **safe**     — the save is *verified*; "Safe in your Ocean" appears only
///                  after the store said yes, then quietly evolves as
///                  understanding lands (interpreted title → one nearby thought)
///   **attention**— the save failed; explicit words and a way to act. Never
///                  auto-fades, never pretends.
///
/// Normal operation stays ambient and ephemeral: the capsule costs nothing to
/// ignore and never blocks the next capture. Only failure raises its voice.
struct PostCaptureMoment: Identifiable, Equatable {
    enum Phase: Equatable {
        case catching
        case safe
        case attention(String)
    }

    let id: UUID              // the captured node's id
    var phase: Phase = .catching
    var title: String?        // interpreted title, once resolved
    var related: RelatedHint?
    /// Understanding still in flight — the capsule breathes while it thinks.
    var interpreting: Bool = false
    /// Release can still be taken back (the takeback drains with the capsule).
    var canUndo: Bool = false

    struct RelatedHint: Equatable {
        let nodeID: UUID
        let title: String
        /// The nearby thought is an old one — a memory echo, not yesterday's note.
        var isEcho: Bool = false
    }

    static func catching(for nodeID: UUID) -> PostCaptureMoment {
        PostCaptureMoment(id: nodeID, phase: .catching, interpreting: true, canUndo: true)
    }

    /// One *strong* nearby fragment for the freshly captured node, or nil.
    ///
    /// Reuses the existing semantic ranking; the similarity floor keeps the
    /// hint honest — a weak match shows nothing rather than a stretch. A
    /// match older than a month is flagged as an echo, so the moment can say
    /// "an older thought stirs" instead of pointing at yesterday.
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

        return RelatedHint(
            nodeID: best.id,
            title: best.displayTitle,
            isEcho: Date.now.timeIntervalSince(best.createdAt) > 30 * 86_400
        )
    }
}

// MARK: - View

/// The capsule itself. Material, hairline and motion language match the rest
/// of the app; the attention card is the only state allowed to hold still.
struct PostCaptureMomentView: View {
    let moment: PostCaptureMoment
    var onTurnIntoQuestion: () -> Void
    var onSeeInOcean: () -> Void
    var onUndo: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil
    var onDismissAttention: (() -> Void)? = nil

    @Environment(\.calmAccessibility) private var calm

    var body: some View {
        Group {
            switch moment.phase {
            case .catching:
                catching
            case .attention(let message):
                attention(message)
            case .safe:
                if let title = moment.title {
                    understood(title)
                } else {
                    safe
                }
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: moment)
    }

    /// Working — the thought is being caught. A breath, not a spinner.
    private var catching: some View {
        HStack(spacing: 10) {
            BreathingDots()
            Text("Catching your thought…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(OceanTheme.mist)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// Safe — said only after the store verified the save.
    private var safe: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(OceanTheme.foam)
            Text("Safe in your Ocean")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OceanTheme.foam)
            if moment.interpreting {
                BreathingDots(size: 4)
            }
            if moment.canUndo, let onUndo {
                undoButton(onUndo)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// The Ocean's interpretation, and one quiet nearby thought.
    private func understood(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Understood as")
                        .font(.caption2)
                        .foregroundStyle(OceanTheme.faint)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OceanTheme.foam)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                if moment.canUndo, let onUndo {
                    undoButton(onUndo)
                }
            }

            if let related = moment.related {
                Text(related.isEcho
                     ? "An older thought stirs — “\(related.title)”"
                     : "Drifts near “\(related.title)”")
                    .font(.caption2)
                    .foregroundStyle(related.isEcho ? OceanTheme.glowWarm : OceanTheme.mist)
                    .lineLimit(1)
            }

            if moment.related != nil {
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

    /// Needs attention — explicit and actionable. Nothing here drifts away on
    /// its own; the thought is still on the surface that tried to release it.
    private func attention(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(OceanTheme.glowWarm)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OceanTheme.foam)
                    Text("Your words are still here — nothing was lost.")
                        .font(.caption2)
                        .foregroundStyle(OceanTheme.mist)
                }
            }

            HStack(spacing: 10) {
                if let onRetry {
                    Button(action: onRetry) {
                        Text("Try again")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, calm ? 11 : 8)
                    }
                    .background(OceanTheme.accent.opacity(0.9), in: Capsule())
                    .foregroundStyle(OceanTheme.abyss)
                }
                if let onDismissAttention {
                    Button(action: onDismissAttention) {
                        Text("Not now")
                            .font(.subheadline)
                            .foregroundStyle(OceanTheme.mist)
                            .padding(.horizontal, 12)
                            .padding(.vertical, calm ? 11 : 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(OceanTheme.glowWarm.opacity(0.30), lineWidth: 0.6)
        )
    }

    private func undoButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Undo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OceanTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, calm ? 9 : 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func quietAction(_ title: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system)
                .font(.caption)
                .foregroundStyle(OceanTheme.foam)
                .padding(.horizontal, 11)
                .padding(.vertical, calm ? 11 : 7)
                .background(Color.white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
