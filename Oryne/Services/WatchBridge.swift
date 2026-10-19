import Foundation
import SwiftData

/// Wires the phone's wrist-take pipeline together: the inbox folder and the
/// importer (and, in later steps, the WatchConnectivity link and the iCloud
/// inbox reader). A singleton because system callbacks (the WCSession
/// delegate, the app delegate's push handler) need to reach it.
@MainActor
final class WatchBridge {
    static let shared = WatchBridge()

    private var importer: WatchTakeImporter?

    func start(context: ModelContext, ai: any OceanAIService) {
        guard importer == nil else { return }
        importer = WatchTakeImporter(
            context: context,
            ai: ai,
            folder: .standard,
            defaults: FastCapturePreferences.defaults
        )
    }

    /// Imports whatever has arrived and finishes any pending understanding.
    func drain() async {
        await importer?.drain()
    }

    /// Launch and foreground: import everything waiting.
    func refresh() async {
        await drain()
    }
}
