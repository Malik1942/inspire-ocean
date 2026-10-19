import Foundation
import SwiftData

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
            guard let reader = self?.inboxReader else { return }
            Task { await reader.deleteRecord(id) }
        }
        link.onArrival = {
            Task { @MainActor in await WatchBridge.shared.drain() }
        }
        link.onActivated = { isPaired in
            Task { @MainActor in WatchBridge.shared.linkActivated(isPaired: isPaired) }
        }
        self.importer = importer
        self.link = link
        link.activate()
    }

    /// Imports whatever has arrived and finishes any pending understanding.
    func drain() async {
        await importer?.drain()
    }

    /// Launch, foreground, and the inbox push: pull the iCloud inbox (once
    /// the reader runs), then import everything waiting.
    func refresh() async {
        if let inboxReader {
            _ = await inboxReader.fetch()
        }
        await drain()
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
        guard inboxReader == nil, WatchInboxSchema.isSignedBuild else { return }
        inboxReader = WatchInboxReader(folder: .standard, defaults: FastCapturePreferences.defaults)
        Task { await refresh() }
    }
}
