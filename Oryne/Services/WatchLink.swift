import Foundation
import WatchConnectivity
import os

/// Failures only, and never user content: a take ID at most.
private let log = Logger(subsystem: "com.inspireocean.app", category: "watch")

/// The phone's end of WatchConnectivity. Receives wrist takes as files,
/// answers the watch's wake ping, and tells the watch which takes are in the
/// Ocean (application context). Delegate callbacks arrive on a background
/// queue; anything that touches the store hops to the main actor through
/// `onArrival`.
final class WatchLink: NSObject, WCSessionDelegate {
    private let folder: WatchInboxFolder

    /// A take landed in the inbox folder, or the watch pinged: import now.
    var onArrival: (() -> Void)?
    /// Activation finished; `isPaired` is now meaningful.
    var onActivated: ((_ isPaired: Bool) -> Void)?

    init(folder: WatchInboxFolder) {
        self.folder = folder
    }

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    var isSupported: Bool { WCSession.isSupported() }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Replaces the application context with the latest confirmations. A
    /// no-op until a watch with Oryne installed is paired.
    func send(_ confirmations: [WatchConfirmation]) {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled
        else { return }
        do {
            try session.updateApplicationContext(WatchWire.context(for: confirmations))
        } catch {
            let error = error as NSError
            log.error("updateApplicationContext failed (\(confirmations.count, privacy: .public) confirmations): \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error as NSError? {
            log.error("Activation finished with an error (state \(activationState.rawValue, privacy: .public)): \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
        onActivated?(activationState == .activated && session.isPaired)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched watches: activate again for the new one.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let take = WatchWire.take(fromMetadata: file.metadata) else {
            log.error("A received file had undecodable metadata; the system deletes it")
            return
        }
        // Move before returning: the system deletes the file afterwards.
        do {
            try folder.accept(take, movingAudioFrom: file.fileURL)
        } catch {
            // The watch keeps the take until it is confirmed: it falls back to iCloud.
            let error = error as NSError
            log.error("Couldn't accept take \(take.id.uuidString, privacy: .public): \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            return
        }
        onArrival?()
    }

    /// The wake ping. Being launched to receive it is the point: once the
    /// session is active, the queued file transfer is delivered.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        onArrival?()
    }
}
