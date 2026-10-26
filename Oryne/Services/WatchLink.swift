import Foundation
import WatchConnectivity
import os

/// Failures only, and never user content: a take ID at most.
private let log = Logger(subsystem: "com.inspireocean.app", category: "watch")

/// The phone's end of WatchConnectivity. Receives wrist takes as files,
/// answers the watch's wake ping, tells the watch which takes are in the
/// Ocean and what its thoughts are now (application context), answers its
/// requests for a fresh snapshot or a thought's audio, and hears when
/// today's thought was met on the wrist. Delegate callbacks arrive on a
/// background queue; anything that touches the store hops to the main actor.
final class WatchLink: NSObject, WCSessionDelegate {
    private let folder: WatchInboxFolder

    /// A take landed in the inbox folder, or the watch pinged: import now.
    var onArrival: (() -> Void)?
    /// Activation finished; `isPaired` is now meaningful.
    var onActivated: ((_ isPaired: Bool) -> Void)?
    /// A fresh snapshot, for a watch that asked.
    var snapshotProvider: (@MainActor () -> WristSnapshot?)?
    /// One thought's recording, for the watch to replay.
    var audioProvider: (@MainActor (UUID) -> Data?)?
    /// Today's thought was opened on the wrist.
    var onMet: (@MainActor (UUID) -> Void)?

    /// The last of each sent. An application context update replaces the
    /// whole dictionary, so both always go together.
    private var confirmations: [WatchConfirmation] = []
    private var snapshot: WristSnapshot?

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

    /// The latest confirmations. A no-op until a watch with Oryne installed
    /// is paired.
    func send(_ confirmations: [WatchConfirmation]) {
        self.confirmations = confirmations
        pushContext()
    }

    /// The latest wrist snapshot, delivered by the system as soon as the
    /// watch is in range.
    func send(_ snapshot: WristSnapshot) {
        self.snapshot = snapshot
        pushContext()
    }

    private func pushContext() {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled
        else { return }
        do {
            try session.updateApplicationContext(WatchWire.context(for: confirmations, snapshot: snapshot))
        } catch {
            let error = error as NSError
            log.error("updateApplicationContext failed (\(self.confirmations.count, privacy: .public) confirmations): \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
    }

    /// Writes the recording to a temporary file and hands it to the system;
    /// the file goes once the transfer finishes. False when there's nothing
    /// to send.
    @MainActor
    private func sendAudio(_ id: UUID) -> Bool {
        guard let session, session.activationState == .activated,
              let data = audioProvider?(id), !data.isEmpty
        else { return false }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wrist-audio-\(id.uuidString).m4a")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            let error = error as NSError
            log.error("Couldn't stage audio for \(id.uuidString, privacy: .public): \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            return false
        }
        session.transferFile(url, metadata: [WatchWire.audioForKey: id.uuidString])
        return true
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

    /// Audio sent for replay: its temporary file goes once the system is done.
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let raw = fileTransfer.file.metadata?[WatchWire.audioForKey] as? String else { return }
        if let error = error as NSError? {
            log.error("Audio for \(raw, privacy: .public) finished with an error: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }

    /// The wake ping. Being launched to receive it is the point: once the
    /// session is active, the queued file transfer is delivered.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        onArrival?()
    }

    /// The watch's requests that wait for an answer: a fresh snapshot, or a
    /// thought's audio (the reply says whether a file is on its way).
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if message[WatchWire.snapshotRequestKey] != nil {
            Task { @MainActor in
                let data = self.snapshotProvider?().flatMap(WatchWire.encode)
                replyHandler(data.map { [WatchWire.wristKey: $0] } ?? [:])
            }
        } else if let raw = message[WatchWire.audioRequestKey] as? String, let id = UUID(uuidString: raw) {
            Task { @MainActor in
                replyHandler([WatchWire.audioOKKey: self.sendAudio(id)])
            }
        } else {
            replyHandler([:])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let raw = userInfo[WatchWire.metKey] as? String, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in self.onMet?(id) }
    }
}
