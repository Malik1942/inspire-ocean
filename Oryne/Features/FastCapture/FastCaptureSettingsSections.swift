import SwiftUI
import WatchConnectivity

/// Fast Capture's rows in the settings list. What an outside capture opens
/// with, and the screenshot it brings, sit in the Capture section; the
/// hardware shortcut is its own section, its setup path in the footer.
struct FastCaptureOpensWithRows: View {
    @AppStorage(
        FastCapturePreferenceKeys.inputPreference,
        store: FastCapturePreferences.defaults
    ) private var inputPreferenceRaw = FastCaptureInputPreference.voiceFirst.rawValue
    @AppStorage(
        FastCapturePreferenceKeys.autoScreenshot,
        store: FastCapturePreferences.defaults
    ) private var autoScreenshot = true

    var body: some View {
        Picker("Opens with", selection: $inputPreferenceRaw) {
            ForEach(FastCaptureInputPreference.allCases) { preference in
                Text(preference.label).tag(preference.rawValue)
            }
        }
        .pickerStyle(.menu)
        Toggle("Auto Screenshot", isOn: $autoScreenshot)
            .accessibilityIdentifier("settings.autoScreenshot")
    }
}

struct FastCaptureShortcutSection: View {
    @AppStorage(
        FastCapturePreferenceKeys.trigger,
        store: FastCapturePreferences.defaults
    ) private var triggerRaw = FastCaptureTrigger.actionButton.rawValue

    private var trigger: FastCaptureTrigger {
        FastCaptureTrigger(rawValue: triggerRaw) ?? .actionButton
    }

    var body: some View {
        Section {
            Picker("Hardware", selection: $triggerRaw) {
                ForEach(FastCaptureTrigger.allCases) { trigger in
                    Text(trigger.label).tag(trigger.rawValue)
                }
            }
            .pickerStyle(.menu)
            Link(destination: URL(string: "shortcuts://create-shortcut")!) {
                HStack {
                    Text("Open Shortcuts")
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(OceanTheme.mist)
                }
            }
        } header: {
            Text("Shortcut")
        } footer: {
            // The setup is a path to follow, not rows to tap.
            VStack(alignment: .leading, spacing: 4) {
                Text(trigger == .actionButton
                     ? LocalizedStringKey("Assign the Fast Capture shortcut.")
                     : LocalizedStringKey("Use a screenshot handoff shortcut."))
                Text(verbatim: trigger.setupSteps.joined(separator: " › "))
            }
        }
    }
}

/// The Apple Watch's way in: the Ultra's Action Button through its Shortcut
/// slot (watchOS lists only workout and dive apps there directly), or the
/// Oryne complication on any watch face. To be confirmed on device per
/// docs/HARDWARE_CHECKLIST.md › Apple Watch. Shown only where a watch can
/// pair (an iPhone).
struct FastCaptureWatchSection: View {
    static var isAvailable: Bool { WCSession.isSupported() }

    private static var actionButtonPath: [String] {
        [
            String(localized: "Settings on your watch"),
            String(localized: "Action Button"),
            String(localized: "Shortcut"),
            String(localized: "Catch a whisper")
        ]
    }

    var body: some View {
        Section {
            Text("Catch a whisper from your wrist.")
        } header: {
            Text("Apple Watch")
        } footer: {
            // The setup is a path to follow, not rows to tap.
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: Self.actionButtonPath.joined(separator: " › "))
                Text("No Action Button? Add the Oryne complication to a watch face.")
            }
        }
    }
}
