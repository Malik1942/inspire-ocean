import Foundation
import WatchConnectivity
import os

/// Failures only, and never user content: a take ID at most.
private let log = Logger(subsystem: "com.inspireocean.app.watchkitapp", category: "sync")

/// The watch's end of WatchConnectivity: hands takes to the system as file
/// transfers, pings the phone awake, and receives the phone's confirmations
/// (application context). Delegate callbacks arrive off the main thread and
/// hop to the main actor before touching anything.
final class PhoneLink: NSObject, WCSessionDelegate {
    var onConfirmations: (@MainActor ([WatchConfirmation]) -> Void)?
    var onTransferFinished: (@MainActor (_ id: UUID, _ delivered: Bool) -> Void)?
    var onActivated: (@MainActor () -> Void)?

    private let session = WCSession.default

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    var isActivated: Bool {
        session.activationState == .activated
    }

    /// Meaningful only while the watch app is on screen.
    var isReachable: Bool {
        isActivated && session.isReachable
    }

    /// Take IDs whose transfer the system still holds.
    var outstandingTakeIDs: Set<UUID> {
        Set(session.outstandingFileTransfers.compactMap { WatchWire.take(fromMetadata: $0.file.metadata)?.id })
    }

    /// Queues the file with the system. False when the session isn't active.
    func send(_ take: WatchTake, audioURL: URL) -> Bool {
        guard isActivated else { return false }
        session.transferFile(audioURL, metadata: WatchWire.metadata(for: take))
        return true
    }

    /// Wakes the phone app so a queued transfer is delivered now rather than
    /// at its next launch.
    func wake(_ id: UUID) {
        guard isReachable else { return }
        session.sendMessage([WatchWire.wakeKey: id.uuidString], replyHandler: nil, errorHandler: nil)
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let confirmations = WatchWire.confirmations(fromContext: session.receivedApplicationContext)
        Task { @MainActor in
            self.onActivated?()
            if !confirmations.isEmpty { self.onConfirmations?(confirmations) }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let confirmations = WatchWire.confirmations(fromContext: applicationContext)
        Task { @MainActor in self.onConfirmations?(confirmations) }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let id = WatchWire.take(fromMetadata: fileTransfer.file.metadata)?.id else { return }
        if let error = error as NSError? {
            log.error("Transfer of take \(id.uuidString, privacy: .public) finished with an error: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
        let delivered = error == nil
        Task { @MainActor in self.onTransferFinished?(id, delivered) }
    }
}
