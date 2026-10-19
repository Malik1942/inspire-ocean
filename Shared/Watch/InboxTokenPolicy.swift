import Foundation

/// What one fetched iCloud inbox record came to.
enum InboxRecordOutcome: Equatable {
    /// Its audio is in the inbox folder, waiting for the importer.
    case accepted
    /// Permanently unusable (not a take, a malformed name or fields): skip it.
    case invalid
    /// Couldn't be copied now (disk full, file protection, an asset not yet
    /// downloaded, a per-record error): it must be read again.
    case failedForNow
}

/// When the reader may persist its change token: only while no record in
/// this fetch failed for now, so the next fetch reads it again instead of
/// stepping past a take that never reached the phone. Invalid records never
/// hold the token back (they would hold it forever).
enum InboxTokenPolicy {
    static func maySaveToken(after outcomes: [InboxRecordOutcome]) -> Bool {
        !outcomes.contains(.failedForNow)
    }
}
