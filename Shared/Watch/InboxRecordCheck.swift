import Foundation
import CloudKit

/// What a fetched iCloud inbox record holds, decided before anything is
/// copied. The reader acts on it; `WatchInboxSchemaTests` holds the rule.
enum InboxRecordCheck: Equatable {
    /// A take whose audio has downloaded: copy it into the inbox folder.
    case ready(WatchTake, audio: URL)
    /// Never usable: skip it. It must not hold the change token back, or it
    /// would hold it forever.
    case invalid(Fault)
    /// The audio asset hasn't finished downloading: read it again later.
    case notDownloaded

    /// Why a record can never become a take. Logged, never shown.
    enum Fault: String {
        /// Another record type, a name that isn't a take ID, or missing fields.
        case notATake
        /// The watch always writes an audio asset; this record has none.
        case noAudio
    }

    init(take: WatchTake?, hasAudio: Bool, downloadedAudio: URL?) {
        guard let take else {
            self = .invalid(.notATake)
            return
        }
        guard hasAudio else {
            self = .invalid(.noAudio)
            return
        }
        guard let downloadedAudio else {
            self = .notDownloaded
            return
        }
        self = .ready(take, audio: downloadedAudio)
    }
}

extension WatchInboxSchema {
    static func check(_ record: CKRecord) -> InboxRecordCheck {
        InboxRecordCheck(
            take: take(from: record),
            hasAudio: record[Field.audio] is CKAsset,
            downloadedAudio: audioURL(in: record)
        )
    }
}
