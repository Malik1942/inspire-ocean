import AppIntents

/// The one intent behind the Action Button (through its Shortcut slot) and
/// Siri. Implemented in the watch app itself, not an extension, as Apple
/// requires for Action Button intents. Idle or Caught → record; recording →
/// stop and catch.
struct CatchThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Catch a whisper"
    static let description = IntentDescription("Start or stop a whisper on your wrist.")
    static let openAppWhenRun = true

    @Dependency private var model: WatchCaptureModel

    @MainActor
    func perform() async throws -> some IntentResult {
        await model.toggle()
        return .result()
    }
}

struct OryneWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // "Catch this in Oryne" belongs to iPhone Fast Capture
        // (Oryne/Intents/CaptureIntents.swift); these phrases must not collide.
        AppShortcut(
            intent: CatchThoughtIntent(),
            phrases: [
                "Whisper to \(.applicationName)",
                "Record a whisper in \(.applicationName)"
            ],
            shortTitle: "Catch a whisper",
            systemImageName: "waveform"
        )
    }
}
