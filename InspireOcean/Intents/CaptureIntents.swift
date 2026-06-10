import AppIntents
import SwiftData
import UniformTypeIdentifiers
import Foundation

/// Capture a spoken or typed thought into Inspire Ocean from Siri, Shortcuts, or
/// Spotlight — without opening the app.
///
/// "Add buy more film to Inspire Ocean" captures that text directly. Plain
/// "Add to Inspire Ocean" makes Siri ask *what* to capture and transcribes your
/// spoken answer. The fragment is titled on-device (Foundation Models when the
/// device is eligible, heuristic otherwise).
struct AddInspirationIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Inspiration"
    static let description = IntentDescription(
        "Capture a thought into your Inspire Ocean.",
        categoryName: "Capture"
    )
    /// Run silently in the background — don't interrupt the user by launching.
    static let openAppWhenRun = false

    @Parameter(title: "Inspiration", requestValueDialog: "What would you like to capture?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to Inspire Ocean")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "I didn't catch anything to capture.")
        }

        let context = Persistence.shared.mainContext
        let node = NodeComposer.make(kind: .text, text: trimmed)
        context.insert(node)

        let ai = LocalOceanAIService()
        node.title = await ai.conciseTitle(for: trimmed)
        try? context.save()

        return .result(dialog: "Drifted into your Ocean.")
    }
}

/// Save an image — e.g. a screenshot from the Shortcuts "Take Screenshot"
/// action — into Inspire Ocean, with an optional note.
///
/// iOS doesn't let an app grab another app's screen by voice alone, so screen
/// capture works through a Shortcut/automation: *Take Screenshot → Save to
/// Inspire Ocean*. This intent is the destination for that flow (and the share
/// sheet covers the manual case).
struct SaveToOceanIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Image to Inspire Ocean"
    static let description = IntentDescription(
        "Save a screenshot or image into your Inspire Ocean.",
        categoryName: "Capture"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Image", supportedContentTypes: [.image])
    var image: IntentFile

    @Parameter(title: "Note", default: "")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$image) to Inspire Ocean") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let data = image.data
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let context = Persistence.shared.mainContext
        let node = NodeComposer.make(kind: .image, text: trimmedNote, imageData: data)
        context.insert(node)

        if !trimmedNote.isEmpty {
            node.title = await LocalOceanAIService().conciseTitle(for: trimmedNote)
        }
        try? context.save()

        return .result(dialog: "Saved to your Ocean.")
    }
}

/// Registers spoken phrases so the intents work with Siri out of the box (no
/// manual Shortcut setup required).
struct OceanAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddInspirationIntent(),
            phrases: [
                "Add an inspiration to \(.applicationName)",
                "Add to \(.applicationName)",
                "Capture a thought in \(.applicationName)",
                "New drift in \(.applicationName)"
            ],
            shortTitle: "Add Inspiration",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: SaveToOceanIntent(),
            phrases: [
                "Save this to \(.applicationName)",
                "Save a screenshot to \(.applicationName)"
            ],
            shortTitle: "Save to Ocean",
            systemImageName: "photo.on.rectangle.angled"
        )
    }
}
