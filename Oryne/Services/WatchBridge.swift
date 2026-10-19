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

    func start(context: ModelContext, ai: any OceanAIService) {
        guard importer == nil else { return }
        let folder = WatchInboxFolder.standard
        let importer = WatchTakeImporter(
            context: context,
            ai: ai,
            folder: folder,
            defaults: FastCapturePreferences.defaults
        )
        let link = WatchLink(folder: folder)
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
    /// launched by a push is not suspended halfway.
    @discardableResult
    func refresh() async -> Bool {
        let background = BackgroundTime(name: "Oryne.WatchInboxRefresh")
        defer { background.end() }
        var arrived = false
        if let inboxReader {
            arrived = await inboxReader.fetch()
        }
        await drain()
        return arrived
    }

    private func linkActivated(isPaired: Bool) {
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
