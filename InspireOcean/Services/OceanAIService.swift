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
}

/// One prior turn of an Ocean Dialogue, passed back into `respond` so
/// follow-ups ("tell me more about that") keep their footing.
struct DialogueTurn: Sendable {
    var isUser: Bool
    var text: String
}

/// The AI seam for Inspire Ocean.
///
/// V1 ships an on-device implementation (`LocalOceanAIService`). The PRD calls
/// for cloud AI for transcription, semantic search, synthesis and dialogue
/// (§14); `CloudOceanAIService` is the drop-in seam for that, conforming to the
/// exact same protocol so the UI never changes.
protocol OceanAIService {
    /// Transcribe a recorded voice drift. Returns nil if transcription fails.
    func transcribe(audioURL: URL) async -> String?

    /// Detect lightweight themes for a captured fragment.
    func detectThemes(for text: String) -> [String]

    /// Nodes semantically related to `node`, used for rediscovery and Expanded
    /// Node View "nearby thoughts".
    func relatedNodeIDs(to node: Node, among nodes: [Node], limit: Int) -> [UUID]

    /// Carry an Ocean Dialogue turn, grounded in the user's saved nodes.
    /// `history` is the last few turns (oldest first), for continuity.
    func respond(to query: String, history: [DialogueTurn], mode: DialogueMode, nodes: [Node]) async -> OceanResponse

    /// A short, evocative title (≤ ~6 words) interpreting a fragment so it can be
    /// shown in full in the Library. Uses the on-device foundation model when
    /// available, with a heuristic fallback.
    func conciseTitle(for text: String) async -> String
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
