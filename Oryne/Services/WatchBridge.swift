import Foundation
import SwiftData

/// Wires the phone's wrist-take pipeline together: the inbox folder, the
/// importer, and the WatchConnectivity link (the iCloud inbox reader joins in
/// a later step). A singleton because system callbacks (the WCSession
/// delegate, the app delegate's push handler) need to reach it.
@MainActor
final class WatchBridge {
    static let shared = WatchBridge()

    private var importer: WatchTakeImporter?
    private var link: WatchLink?

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

    /// Launch and foreground: import everything waiting.
    func refresh() async {
        await drain()
    }

    private func linkActivated(isPaired: Bool) {
        guard isPaired, let importer else { return }
        // A watch that missed an update catches up on activation.
        link?.send(importer.recentConfirmations)
    }
}
