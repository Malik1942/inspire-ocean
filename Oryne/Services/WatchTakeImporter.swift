import Foundation
import SwiftData
import UIKit

/// Turns wrist takes waiting in the inbox folder into ordinary voice
/// thoughts, exactly once each, then understands them the way an in-app
/// whisper is understood. Both delivery paths (WatchConnectivity and the
/// iCloud inbox) and the launch sweep call `drain()`. Import is synchronous
/// and runs on every call; one understanding pass runs at a time and picks up
/// takes imported while it works.
@MainActor
final class WatchTakeImporter {
    private let context: ModelContext
    private let ai: any OceanAIService
    private let folder: WatchInboxFolder
    private let defaults: UserDefaults
    private var ledger: ImportLedger
    private var isUnderstanding = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// The watch should hear about these: after each import and each title.
    var confirmationsChanged: (([WatchConfirmation]) -> Void)?
    /// A take is settled (imported now, or already seen): its iCloud inbox
    /// record, if any, can go.
    var didSettle: ((UUID) -> Void)?

    init(context: ModelContext, ai: any OceanAIService, folder: WatchInboxFolder, defaults: UserDefaults) {
        self.context = context
        self.ai = ai
        self.folder = folder
        self.defaults = defaults
        var ledger = ImportLedger.load(from: defaults)
        ledger.prune(now: .now)
        self.ledger = ledger
    }

    var recentConfirmations: [WatchConfirmation] {
        ledger.recentConfirmations()
    }

    func drain() async {
        // Import never waits behind understanding; transcription can sit on
        // the speech permission prompt for as long as the user takes.
        importWaitingTakes()
        guard !isUnderstanding else { return }
        isUnderstanding = true
        // Transcription can take seconds; a background delivery shouldn't be
        // cut off mid-pass. If iOS ends it anyway, the next drain resumes.
        // The expiration handler runs on the main thread.
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Oryne.WatchTakeImport") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTask() }
        }
        defer {
            isUnderstanding = false
            endBackgroundTask()
        }
        await understandImported()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: Import

    private func importWaitingTakes() {
        var changed = false
        for take in folder.pending() {
            if !ledger.hasSeen(take.id), let existing = node(take.id) {
                // Already in the store, from before this ledger existed (a
                // reinstall): record it rather than duplicate it.
                ledger.markImported(take.id, at: .now)
                ledger.markUnderstood(take.id, title: title(of: existing))
                ledger.save(to: defaults)
            }
            if ledger.hasSeen(take.id) {
                // A second copy (the other path, a retry) or a thought the
                // user already deleted: never recreate it. Confirm again, the
                // watch resends only when it hasn't heard back.
                folder.remove(take.id)
                didSettle?(take.id)
                changed = true
                continue
            }
            let audio: Data
            do {
                audio = try Data(contentsOf: folder.audioURL(for: take.id))
            } catch {
                // Unreadable right now (protected until first unlock, an I/O
                // error): leave the files for the next pass. After an iCloud
                // delivery this may be the only copy.
                continue
            }
            if audio.isEmpty {
                // An empty delivery holds nothing to keep. The watch still has
                // the take and will send it again over iCloud.
                folder.remove(take.id)
                continue
            }
            let node = NodeComposer.make(kind: .voice, audioData: audio, detectThemes: false)
            node.id = take.id
            node.createdAt = take.createdAt
            node.updatedAt = take.createdAt
            context.insert(node)
            do {
                try context.save()
            } catch {
                // Leave the files in place: the next pass or launch retries.
                context.delete(node)
                continue
            }
            ledger.markImported(take.id, at: .now)
            ledger.save(to: defaults)
            folder.remove(take.id)
            didSettle?(take.id)
            changed = true
        }
        if changed { confirmationsChanged?(ledger.recentConfirmations()) }
    }

    // MARK: Understanding

    /// Understands every imported take, including ones imported while this
    /// pass runs. A cancelled pass leaves its take `imported`, so the next
    /// drain or launch finishes it.
    private func understandImported() async {
        var attempted: Set<UUID> = []
        while let id = ledger.awaitingUnderstanding.first(where: { !attempted.contains($0) }) {
            attempted.insert(id)
            if node(id) != nil {
                await VoiceUnderstanding.run(nodeID: id, audioTempURL: nil, context: context, ai: ai)
            }
            if Task.isCancelled { return }
            // A voice thought left with no transcript while Oryne wasn't on
            // screen may only mean the recognizer wasn't available in the
            // background: leave it imported, so the next foreground drain
            // tries again. On screen, no words is the answer.
            if let node = node(id), (node.transcription ?? "").isEmpty,
               UIApplication.shared.applicationState != .active {
                continue
            }
            ledger.markUnderstood(id, title: node(id).flatMap(title(of:)))
            ledger.save(to: defaults)
            confirmationsChanged?(ledger.recentConfirmations())
        }
    }

    // MARK: Helpers

    private func node(_ id: UUID) -> Node? {
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    /// The name the watch shows: the thought's title once it has one. Never
    /// the "Whisper" fallback, which would pretend to be a name.
    private func title(of node: Node) -> String? {
        let title = node.title.trimmed
        return title.isEmpty ? nil : title
    }
}
