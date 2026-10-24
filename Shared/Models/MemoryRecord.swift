import Foundation
import SwiftData

/// What kind of durable observation a memory record is.
enum MemoryKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case concern
    case project
    case person
    case preference
    case habit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .concern: return String(localized: "memory.kind.concern", defaultValue: "Concerns")
        case .project: return String(localized: "memory.kind.project", defaultValue: "Projects")
        case .person: return String(localized: "memory.kind.person", defaultValue: "People")
        case .preference: return String(localized: "memory.kind.preference", defaultValue: "Preferences")
        case .habit: return String(localized: "memory.kind.habit", defaultValue: "Habits")
        }
    }

    var symbol: String {
        switch self {
        case .concern: return "circle.dotted"
        case .project: return "hammer"
        case .person: return "person"
        case .preference: return "slider.horizontal.3"
        case .habit: return "repeat"
        }
    }
}

/// One line Oryne knows about the person (docs/plans/memory-layer/SPEC.md,
/// layer 3): a recurring concern, a project under way, someone who keeps
/// appearing, a preference, a habit. Written only by consolidation from the
/// person's own thoughts, shown in Settings, deletable and editable there;
/// read by Ask as a short preamble. Like the rest of the memory it syncs
/// through CloudKit (decision 5).
@Model
final class MemoryRecord {
    // CloudKit mirroring: no unique constraints, every stored property defaulted.
    var id: UUID = UUID()
    var kindRaw: String = MemoryKind.concern.rawValue
    /// One sentence, addressed to the person ("You keep returning to…").
    var text: String = ""
    /// The thoughts it was drawn from; when every one is gone, so is the record.
    var evidenceNodeIDs: [UUID] = []
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// The user rewrote it: consolidation never changes or removes it.
    var userEdited: Bool = false
    /// The user sent it away. The row stays as a tombstone so the refusal
    /// syncs with the records (a dismissal kept only on one phone would let
    /// the other phone propose it again); nothing reads or shows it, and
    /// consolidation will not write its like again.
    var dismissedAt: Date? = nil

    var isDismissed: Bool { dismissedAt != nil }

    init(kind: MemoryKind, text: String, evidenceNodeIDs: [UUID] = []) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.text = text
        self.evidenceNodeIDs = evidenceNodeIDs
        self.createdAt = .now
        self.updatedAt = .now
    }

    var kind: MemoryKind {
        get { MemoryKind(rawValue: kindRaw) ?? .concern }
        set { kindRaw = newValue.rawValue }
    }
}
