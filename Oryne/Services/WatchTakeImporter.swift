import Foundation
import SwiftData
import UIKit

/// Turns wrist takes waiting in the inbox folder into ordinary voice
/// thoughts, exactly once each, then understands them the way an in-app
/// whisper is understood. Both delivery paths (WatchConnectivity and the
/// iCloud inbox) and the launch sweep call `drain()`. One pass runs at a
/// time; a call that arrives mid-pass gets another pass.
@MainActor
final class WatchTakeImporter {
    private let context: ModelContext
    private let ai: any OceanAIService
    private let folder: WatchInboxFolder
    private let defaults: UserDefaults
    private var ledger: ImportLedger
    private var isDraining = false
    private var needsAnotherPass = false

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
        guard !isDraining else {
            needsAnotherPass = true
            return
        }
        isDraining = true
        // Transcription can take seconds; a background delivery shouldn't be
        // cut off mid-pass. If iOS ends it anyway, the next drain resumes.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Oryne.WatchTakeImport")
        defer {
            isDraining = false
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }
        repeat {
            needsAnotherPass = false
            importWaitingTakes()
            await understandImported()
        } while needsAnotherPass
    }

    // MARK: Import

    private func importWaitingTakes() {
        var imported = false
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
                // user already deleted: never recreate it.
                folder.remove(take.id)
                didSettle?(take.id)
                continue
            }
            guard let audio = try? Data(contentsOf: folder.audioURL(for: take.id)), !audio.isEmpty else {
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
            imported = true
        }
        if imported { confirmationsChanged?(ledger.recentConfirmations()) }
    }

    // MARK: Understanding

    private func understandImported() async {
        for id in ledger.awaitingUnderstanding {
            if node(id) != nil {
                await VoiceUnderstanding.run(nodeID: id, audioTempURL: nil, context: context, ai: ai)
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
