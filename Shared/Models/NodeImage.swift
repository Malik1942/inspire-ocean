import Foundation
import SwiftData

/// One image attached to a `Node`.
///
/// A child entity — not a `[Data]` on the node — so each image keeps its own
/// `@Attribute(.externalStorage)` blob and syncs as its own CKAsset, exactly the
/// way `Node.imageData`/`audioData`/`linkImageData` do. A `[Data]` array would be
/// stored as one inline blob, ballooning the CloudKit record; a child per image
/// keeps records small and lets `sortIndex` preserve the user's order.
///
/// CloudKit mirroring rules: every stored property carries a default and the
/// back-relationship is optional; no unique constraints (de-dup by `id` if a
/// transient merge ever surfaces two).
@Model
final class NodeImage {
    var id: UUID = UUID()

    /// The (downsampled) image bytes, stored externally so they sync like every
    /// other large blob on a `Node`. Optional so a record can materialize
    /// partially during a CloudKit merge.
    @Attribute(.externalStorage) var data: Data?

    /// Explicit display order within the node's image set.
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    @Relationship(inverse: \Node.images) var node: Node?

    init(id: UUID = UUID(), data: Data? = nil, sortIndex: Int = 0, createdAt: Date = .now) {
        self.id = id
        self.data = data
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}
