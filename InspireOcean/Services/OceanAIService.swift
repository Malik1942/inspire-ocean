import Foundation
import SwiftUI

/// A branch Ocean suggests the user could grow from a thought.
struct SuggestedBranch: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var type: BranchType
}

/// A grounded Ocean Dialogue response (§11): a reflection, the source nodes it
/// drew from, an optional pattern summary, and suggested branches.
struct OceanResponse {
    var reflection: String
    var sourceNodeIDs: [UUID]
    var patternSummary: String?
    var suggestedBranches: [SuggestedBranch]
    /// Research mode's outward step: directions drawn from knowledge beyond
    /// the user's notes. Kept separate from `reflection` so the UI can mark
    /// its provenance unmistakably — grounded water and open sea never mix.
    var outwardNote: String? = nil
}

/// One prior turn of an Ocean Dialogue, passed back into `respond` so
/// follow-ups ("tell me more about that") keep their footing.
struct DialogueTurn: Sendable {
    var isUser: Bool
    var text: String
}

/// The AI seam for Oryn.
///
/// V1 ships an on-device implementation (`LocalOceanAIService`). The PRD calls
/// for cloud AI for transcription, semantic search, synthesis and dialogue
/// (§14); `CloudOceanAIService` is the drop-in seam for that, conforming to the
/// exact same protocol so the UI never changes.
protocol OceanAIService {
    /// Transcribe a recorded voice drift. Returns nil if transcription fails.
    func transcribe(audioURL: URL) async -> String?

    /// The understanding step — run when a thought is saved or updated, before
    /// anything is labelled or matched: interpret the fragment's meaning into
    /// a concise essence (its title), 1–3 conceptual themes, and a soft mood.
    /// Uses the on-device foundation model when available; the fallback still
    /// reasons about meaning (concept-space embeddings), never bare keywords.
    func understand(_ text: String) async -> ThoughtUnderstanding

    /// Nodes related to `node` *by meaning* — blended embedding similarity,
    /// conceptual-theme overlap and mood — used for rediscovery and Expanded
    /// Node View "nearby thoughts". Weak matches are dropped rather than
    /// padded: fewer honest neighbors beat `limit` stretched ones.
    func relatedNodeIDs(to node: Node, among nodes: [Node], limit: Int) -> [UUID]

    /// Carry an Ocean Dialogue turn, grounded in the user's saved nodes.
    /// `history` is the last few turns (oldest first), for continuity.
    func respond(to query: String, history: [DialogueTurn], mode: DialogueMode, nodes: [Node]) async -> OceanResponse
}

// MARK: - Environment injection

private struct OceanAIKey: EnvironmentKey {
    static let defaultValue: any OceanAIService = LocalOceanAIService()
}

extension EnvironmentValues {
    var oceanAI: any OceanAIService {
        get { self[OceanAIKey.self] }
        set { self[OceanAIKey.self] = newValue }
    }
}
