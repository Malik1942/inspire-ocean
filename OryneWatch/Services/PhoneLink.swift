import Foundation
import WatchConnectivity
import os

/// Failures only, and never user content: a take ID at most.
private let log = Logger(subsystem: "com.inspireocean.app.watchkitapp", category: "sync")

/// The watch's end of WatchConnectivity: hands takes to the system as file
/// transfers, pings the phone awake, receives the phone's confirmations and
/// wrist snapshot (application context, or a reply when the watch asks),
/// fetches a thought's audio for replay, and says when today's thought was
/// met. Delegate callbacks arrive off the main thread and hop to the main
/// actor before touching anything.
final class PhoneLink: NSObject, WCSessionDelegate {
    /// What an audio fetch came to.
    enum AudioFetch: Equatable {
        /// The recording, in `PlaybackCache`.
        case file(URL)
        /// The phone can't be reached right now.
        case phoneAway
        /// Refused (no audio any more), an error, or no file in time.
        case failed
    }

    static let audioFetchTimeout: Duration = .seconds(30)

    var onConfirmations: (@MainActor ([WatchConfirmation]) -> Void)?
    var onSnapshot: (@MainActor (WristSnapshot) -> Void)?
    var onTransferFinished: (@MainActor (_ id: UUID, _ delivered: Bool) -> Void)?
    var onActivated: (@MainActor () -> Void)?

    private let session = WCSession.default

    private struct AudioWaiter {
        let token: UUID
        let continuation: CheckedContinuation<AudioFetch, Never>
    }

    /// Fetches waiting for their file, by thought ID. Delegate callbacks
    /// reach this off the main thread, hence the lock.
    private let waitersLock = NSLock()
    private var audioWaiters: [UUID: AudioWaiter] = [:]

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

    /// Asks the phone, which wakes in the background if it must, for a fresh
    /// snapshot. Out of reach this does nothing: the held snapshot stays.
    func requestSnapshot() {
        guard isReachable else { return }
        session.sendMessage(
            [WatchWire.snapshotRequestKey: true],
            replyHandler: { [weak self] reply in
                guard let snapshot = WatchWire.snapshot(from: reply) else { return }
                Task { @MainActor in self?.onSnapshot?(snapshot) }
            },
            errorHandler: { error in
                let error = error as NSError
                log.error("Snapshot request failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            }
        )
    }

    /// Asks the phone for one thought's audio and waits for the file:
    /// `.phoneAway` at once when it can't be reached; `.failed` on a refusal,
    /// an error, or no file within `audioFetchTimeout`.
    func fetchAudio(_ id: UUID) async -> AudioFetch {
        guard isReachable else { return .phoneAway }
        let token = UUID()
        return await withCheckedContinuation { continuation in
            waitersLock.lock()
            let replaced = audioWaiters.updateValue(AudioWaiter(token: token, continuation: continuation), forKey: id)
            waitersLock.unlock()
            replaced?.continuation.resume(returning: .failed)
            session.sendMessage(
                [WatchWire.audioRequestKey: id.uuidString],
                replyHandler: { [weak self] reply in
                    guard reply[WatchWire.audioOKKey] as? Bool != true else { return }
                    self?.finishAudio(id, .failed, token: token)
                },
                errorHandler: { [weak self] error in
                    let error = error as NSError
                    log.error("Audio request for \(id.uuidString, privacy: .public) failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
                    self?.finishAudio(id, .failed, token: token)
                }
            )
            Task { [weak self] in
                try? await Task.sleep(for: Self.audioFetchTimeout)
                self?.finishAudio(id, .failed, token: token)
            }
        }
    }

    /// Today's thought was opened on the wrist. Queued by the system, so it
    /// reaches the phone even when the phone is away now.
    func sendMet(_ id: UUID) {
        guard isActivated else { return }
        session.transferUserInfo([WatchWire.metKey: id.uuidString])
    }

    /// Answers the fetch waiting on `id`, once. `token` ties a refusal or a
    /// timeout to the fetch that sent it, so a late one never fails a newer
    /// fetch; a file answers whichever fetch waits, and a file nobody waits
    /// for is deleted.
    private func finishAudio(_ id: UUID, _ result: AudioFetch, token: UUID? = nil) {
        waitersLock.lock()
        let waiter = audioWaiters[id].flatMap { token == nil || $0.token == token ? $0 : nil }
        if waiter != nil { audioWaiters[id] = nil }
        waitersLock.unlock()
        guard let waiter else {
            if case .file(let url) = result { try? FileManager.default.removeItem(at: url) }
            return
        }
        waiter.continuation.resume(returning: result)
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let context = session.receivedApplicationContext
        let confirmations = WatchWire.confirmations(fromContext: context)
        let snapshot = WatchWire.snapshot(from: context)
        Task { @MainActor in
            self.onActivated?()
            if !confirmations.isEmpty { self.onConfirmations?(confirmations) }
            if let snapshot { self.onSnapshot?(snapshot) }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let confirmations = WatchWire.confirmations(fromContext: applicationContext)
        let snapshot = WatchWire.snapshot(from: applicationContext)
        Task { @MainActor in
            self.onConfirmations?(confirmations)
            if let snapshot { self.onSnapshot?(snapshot) }
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let id = WatchWire.take(fromMetadata: fileTransfer.file.metadata)?.id else { return }
        if let error = error as NSError? {
            log.error("Transfer of take \(id.uuidString, privacy: .public) finished with an error: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
        let delivered = error == nil
        Task { @MainActor in self.onTransferFinished?(id, delivered) }
    }

    /// Audio the phone sent for replay. Moved before returning: the system
    /// deletes the file afterwards.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let raw = file.metadata?[WatchWire.audioForKey] as? String, let id = UUID(uuidString: raw) else { return }
        let destination = PlaybackCache.url(for: id)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: file.fileURL, to: destination)
        } catch {
            let error = error as NSError
            log.error("Couldn't keep audio for \(id.uuidString, privacy: .public): \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            finishAudio(id, .failed)
            return
        }
        finishAudio(id, .file(destination))
    }
}

extension PhoneLink: PhoneLinking {}
