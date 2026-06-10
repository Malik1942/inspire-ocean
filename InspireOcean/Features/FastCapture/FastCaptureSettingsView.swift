import SwiftUI

struct FastCaptureSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @AppStorage(
        FastCapturePreferenceKeys.trigger,
        store: FastCapturePreferences.defaults
    ) private var triggerRaw = FastCaptureTrigger.actionButton.rawValue
    @AppStorage(
        FastCapturePreferenceKeys.inputPreference,
        store: FastCapturePreferences.defaults
    ) private var inputPreferenceRaw = FastCaptureInputPreference.voiceFirst.rawValue
    @AppStorage(
        FastCapturePreferenceKeys.autoScreenshot,
        store: FastCapturePreferences.defaults
    ) private var autoScreenshot = true
    @AppStorage(
        FastCapturePreferenceKeys.onboardingCompleted,
        store: FastCapturePreferences.defaults
    ) private var onboardingCompleted = false

    @State private var showOnboarding = false

    private var trigger: FastCaptureTrigger {
        FastCaptureTrigger(rawValue: triggerRaw) ?? .actionButton
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground(animated: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        shortcutSection
                        inputSection
                        setupSection
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("Fast Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showOnboarding = true
                    } label: {
                        Image(systemName: "sparkle")
                    }
                    .accessibilityLabel("Open Fast Capture onboarding")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showOnboarding) {
                OceanOnboardingView(
                    onComplete: {
                        onboardingCompleted = true
                        showOnboarding = false
                    },
                    onTestCapture: {
                        onboardingCompleted = true
                        showOnboarding = false
                        dismiss()
                        appState.startFastCapture(source: .onboarding)
                    }
                )
            }
        }
    }

    private var shortcutSection: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                settingsHeader(
                    title: "Shortcut",
                    subtitle: "One press, one drift.",
                    systemImage: "bolt.circle.fill"
                )

                Picker("Hardware", selection: $triggerRaw) {
                    ForEach(FastCaptureTrigger.allCases) { trigger in
                        Label(trigger.label, systemImage: trigger.symbol)
                            .tag(trigger.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var inputSection: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                settingsHeader(
                    title: "Capture",
                    subtitle: "Begin with the least resistance.",
                    systemImage: "waveform.circle.fill"
                )

                Picker("Input", selection: $inputPreferenceRaw) {
                    ForEach(FastCaptureInputPreference.allCases) { preference in
                        Label(preference.label, systemImage: preference.symbol)
                            .tag(preference.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $autoScreenshot) {
                    Label("Auto Screenshot", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(OceanTheme.foam)
                }
                .tint(OceanTheme.accent)
                .foregroundStyle(OceanTheme.foam)
            }
        }
    }

    private var setupSection: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                settingsHeader(
                    title: trigger.label,
                    subtitle: trigger == .actionButton ? "Assign the Fast Capture shortcut." : "Use a screenshot handoff shortcut.",
                    systemImage: trigger.symbol
                )

                VStack(spacing: 10) {
                    ForEach(Array(trigger.setupSteps.enumerated()), id: \.offset) { index, title in
                        FastCaptureSetupStep(number: index + 1, title: title)
                    }
                }

                Link(destination: URL(string: "shortcuts://create-shortcut")!) {
                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .foregroundStyle(OceanTheme.foam)
            }
        }
    }

    private func settingsHeader(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(OceanTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(OceanTheme.foam)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(OceanTheme.mist)
            }
        }
    }
}

private struct FastCaptureSetupStep: View {
    let number: Int
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(OceanTheme.abyss)
                .frame(width: 22, height: 22)
                .background(OceanTheme.accent, in: Circle())

            Text(title)
                .font(.subheadline)
                .foregroundStyle(OceanTheme.foam)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
