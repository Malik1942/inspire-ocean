import Foundation
import SwiftData

/// A persisted Ocean Dialogue thread.
@Model
final class Conversation {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var title: String

    @Relationship(deleteRule: .cascade) var messages: [ChatMessage]?

    init(id: UUID = UUID(), createdAt: Date = .now, title: String = "New dialogue") {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.title = title
        self.messages = []
    }

    var orderedMessages: [ChatMessage] {
        (messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}

/// A single turn in an Ocean Dialogue. Ocean responses are grounded in the
/// user's saved nodes (Risk mitigation: *AI feels generic → ground responses
/// in saved nodes*).
@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var roleRaw: String
    var text: String

    /// Source nodes this response was grounded in (by `Node.id`).
    var referencedNodeIDs: [UUID]
    /// Suggested branches the user can grow from this turn.
    var suggestedBranches: [String]
    var modeRaw: String?
    /// Research mode's outward step — knowledge from beyond the user's notes,
    /// stored apart from `text` so its provenance stays visible forever.
    var outwardText: String?

    @Relationship(inverse: \Conversation.messages) var conversation: Conversation?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        role: MessageRole,
        text: String,
        referencedNodeIDs: [UUID] = [],
        suggestedBranches: [String] = [],
        mode: DialogueMode? = nil,
        outwardText: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.roleRaw = role.rawValue
        self.text = text
        self.referencedNodeIDs = referencedNodeIDs
        self.suggestedBranches = suggestedBranches
        self.modeRaw = mode?.rawValue
        self.outwardText = outwardText
    }

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    var mode: DialogueMode? {
        modeRaw.flatMap(DialogueMode.init(rawValue:))
    }
}
