import AppIntents
import SwiftData
import UniformTypeIdentifiers
import Foundation

/// Capture a spoken or typed thought into Oryne from Siri, Shortcuts, or
/// Spotlight — without opening the app.
///
/// "Add buy more film to Oryne" captures that text directly. Plain
/// "Add to Oryne" makes Siri ask *what* to capture and transcribes your
/// spoken answer. The fragment is titled on-device (Foundation Models when the
/// device is eligible, heuristic otherwise).
struct AddInspirationIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Inspiration"
    static let description = IntentDescription(
        "Capture a thought into Oryne.",
        categoryName: "Capture"
    )
    /// Run silently in the background — don't interrupt the user by launching.
    static let openAppWhenRun = false

    @Parameter(title: "Inspiration", requestValueDialog: "What would you like to capture?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to Oryne")
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

        let understanding = await LocalOceanAIService().understand(trimmed)
        NodeComposer.applyUnderstanding(understanding, to: node)
        try? context.save()

        return .result(dialog: "Drifted into your Ocean.")
    }
}

/// Save an image — e.g. a screenshot from the Shortcuts "Take Screenshot"
/// action — into Oryne, with an optional note.
///
/// iOS doesn't let an app grab another app's screen by voice alone, so screen
/// capture works through a Shortcut/automation: *Take Screenshot → Save to
/// Oryne*. This intent is the destination for that flow (and the share
/// sheet covers the manual case).
struct SaveToOceanIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Image to Oryne"
    static let description = IntentDescription(
        "Save a screenshot or image into Oryne.",
        categoryName: "Capture"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Image", supportedContentTypes: [.image])
    var image: IntentFile

    @Parameter(title: "Note", default: "")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$image) to Oryne") {
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
            let understanding = await LocalOceanAIService().understand(trimmedNote)
            NodeComposer.applyUnderstanding(understanding, to: node)
        }
        try? context.save()

        return .result(dialog: "Saved to your Ocean.")
    }
}

/// Opens the app straight into the low-friction Fast Capture overlay. This is
/// the intent users assign to the Action Button through Shortcuts.
struct StartFastCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Fast Capture"
    static let description = IntentDescription(
        "Open Oryne in a lightweight capture state.",
        categoryName: "Fast Capture"
    )
    static let openAppWhenRun = true

    @Parameter(title: "Opening Thought", default: "")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("Start Fast Capture") {
            \.$note
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        FastCaptureLaunchStore.stagePendingRequest(
            source: configuredTriggerSource,
            seedText: note
        )
        return .result(dialog: "Fast Capture is ready.")
    }
}

/// Receives a screenshot from a Shortcut before opening Fast Capture. The
/// screenshot action itself must live in Shortcuts; iOS does not let a normal
/// app silently capture another app's screen.
struct StartContextCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Context Capture"
    static let description = IntentDescription(
        "Open Fast Capture with the current screenshot attached.",
        categoryName: "Fast Capture"
    )
    static let openAppWhenRun = true

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var screenshot: IntentFile

    @Parameter(title: "Opening Thought", default: "")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("Start Context Capture with \(\.$screenshot)") {
            \.$note
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let imageData = FastCapturePreferences.autoScreenshotEnabled ? screenshot.data : nil
        FastCaptureLaunchStore.stagePendingRequest(
            source: configuredTriggerSource,
            imageData: imageData,
            seedText: note
        )
        return .result(dialog: "Fast Capture is ready.")
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
        AppShortcut(
            intent: StartFastCaptureIntent(),
            phrases: [
                "Start Fast Capture in \(.applicationName)",
                "Fast Capture in \(.applicationName)",
                "Catch this in \(.applicationName)"
            ],
            shortTitle: "Fast Capture",
            systemImageName: "bolt.circle"
        )
        AppShortcut(
            intent: StartContextCaptureIntent(),
            phrases: [
                "Capture this screen in \(.applicationName)",
                "Start Context Capture in \(.applicationName)"
            ],
            shortTitle: "Context Capture",
            systemImageName: "camera.viewfinder"
        )
    }
}

private var configuredTriggerSource: FastCaptureLaunchSource {
    switch FastCapturePreferences.trigger {
    case .actionButton: return .actionButton
    case .cameraControl: return .cameraControl
    }
}
