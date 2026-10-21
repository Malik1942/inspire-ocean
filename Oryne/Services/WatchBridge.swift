import Foundation
import SwiftData
import UIKit

/// Wires the phone's wrist-take pipeline together: the inbox folder, the
/// importer, the WatchConnectivity link, and the iCloud inbox reader. A
/// singleton because system callbacks (the WCSession delegate, the app
/// delegate's push handler) need to reach it.
@MainActor
final class WatchBridge {
    static let shared = WatchBridge()

    private var importer: WatchTakeImporter?
    private var link: WatchLink?
    private var inboxReader: WatchInboxReader?
    private var inboxFolder: WatchInboxFolder?
    private var activationKnown = false
    private var activationWaiters: [CheckedContinuation<Void, Never>] = []

    func start(context: ModelContext, ai: any OceanAIService) {
        guard importer == nil else { return }
        // Never import into a store that won't outlive the process: when the
        // on-disk store failed and Persistence fell back to memory, confirming
        // would delete the watch's and iCloud's copies of takes that are then
        // gone at quit. The takes wait safely where they are.
        guard !context.container.configurations.contains(where: \.isStoredInMemoryOnly) else { return }
        let folder = WatchInboxFolder.standard
        let importer = WatchTakeImporter(
            context: context,
            ai: ai,
            folder: folder,
            defaults: FastCapturePreferences.defaults
        )
        let link = WatchLink(folder: folder)
        // An iPad never activates, so nothing may wait on it.
        if !link.isSupported { activationKnown = true }
        importer.confirmationsChanged = { [weak link] confirmations in
            link?.send(confirmations)
        }
        importer.didSettle = { [weak self] id in
            // A settled take's iCloud record is deleted even if the reader
            // isn't running yet or the delete fails offline: queue it first.
            // Unsigned builds never touch CloudKit, so they never queue.
            if WatchInboxSchema.isSignedBuild {
                var queue = InboxDeletionQueue.load(from: FastCapturePreferences.defaults)
                queue.add(id)
                queue.save(to: FastCapturePreferences.defaults)
            }
            guard let reader = self?.inboxReader else { return }
            Task { await reader.flushPendingDeletions() }
        }
        link.onArrival = {
            Task { @MainActor in await WatchBridge.shared.drain() }
        }
        link.onActivated = { isPaired in
            Task { @MainActor in WatchBridge.shared.linkActivated(isPaired: isPaired) }
        }
        self.importer = importer
        self.link = link
        self.inboxFolder = folder
        link.activate()
    }

    /// Imports whatever has arrived and finishes any pending understanding.
    func drain() async {
        await importer?.drain()
    }

    /// Launch, foreground, and the inbox push: pull the iCloud inbox (once
    /// the reader runs), then import everything waiting. True when a take
    /// arrived from iCloud. Holds background time throughout, so a fetch
    /// launched by a push is not suspended halfway, and waits briefly for
    /// WatchConnectivity on a cold launch so the reader can exist by then.
    @discardableResult
    func refresh() async -> Bool {
        guard importer != nil else { return false }   // nothing was started
        let background = BackgroundTime(name: "Oryne.WatchInboxRefresh")
        defer { background.end() }
        await waitForActivation()
        var arrived = false
        if let inboxReader {
            arrived = await inboxReader.fetch()
        }
        await drain()
        return arrived
    }

    /// Waits, at most `timeout`, until WatchConnectivity has said whether a
    /// watch is paired, so a push that cold-launches the app can still read
    /// the iCloud inbox (the reader exists only on the paired iPhone).
    private func waitForActivation(timeout: Duration = .seconds(5)) async {
        guard !activationKnown else { return }
        await withCheckedContinuation { continuation in
            activationWaiters.append(continuation)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resumeActivationWaiters()
            }
        }
    }

    /// Resumes every waiter exactly once: each leaves the list before it is
    /// resumed, so a later timeout or activation finds it gone.
    private func resumeActivationWaiters() {
        let waiters = activationWaiters
        activationWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func linkActivated(isPaired: Bool) {
        activationKnown = true
        // Waiters resume only after the reader exists (see `startInboxReader`).
        defer { resumeActivationWaiters() }
        guard isPaired, let importer else { return }
        // A watch that missed an update catches up on activation.
        link?.send(importer.recentConfirmations)
        startInboxReader()
    }

    /// Only the paired iPhone reads the inbox (an iPad importing too would
    /// mint duplicates), and only a signed build may touch CloudKit.
    private func startInboxReader() {
        guard inboxReader == nil, WatchInboxSchema.isSignedBuild, let inboxFolder else { return }
        inboxReader = WatchInboxReader(folder: inboxFolder, defaults: FastCapturePreferences.defaults)
        // A refresh already waiting on activation (the push that cold-launched
        // the app) fetches once it resumes, and the reader exists by then. A
        // fetch of our own could win the single flight from it, and that push
        // would answer no data for takes that did arrive.
        guard activationWaiters.isEmpty else { return }
        Task { await refresh() }
    }
}

/// One `beginBackgroundTask` assertion, ended exactly once: by `end()` or by
/// the system's expiration handler, whichever comes first.
@MainActor
private final class BackgroundTime {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
