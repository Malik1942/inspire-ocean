import SwiftUI

/// First-run onboarding: establishes the mental model — capture fragments
/// before they disappear, and the Ocean gives them back — then folds Fast
/// Capture setup into the final step, which hands off to the seeded
/// Introduction current for the concrete tour.
///
/// Deliberately not a tutorial: three short screens of orientation, one of
/// setup. Skippable at any point; shown once (replayable from Fast Capture
/// settings via the sparkle button).
struct OceanOnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var onComplete: () -> Void
    var onTestCapture: () -> Void

    @State private var page = 0

    private let pages = OceanOnboardingPage.pages
    private var pageCount: Int { pages.count + 1 }   // + setup screen
    private var isLastPage: Bool { page == pageCount - 1 }

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground()

                VStack(spacing: OceanSpacing.inset) {
                    TabView(selection: $page) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            OceanOnboardingPageView(page: page)
                                .tag(index)
                                .padding(.horizontal, OceanSpacing.gutter)
                        }

                        FastCaptureSetupPage(onTestCapture: completeAndTest)
                            .tag(pages.count)
                            .padding(.horizontal, OceanSpacing.gutter)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))

                    controls
                        .padding(.horizontal, OceanSpacing.gutter)
                        .padding(.bottom, OceanSpacing.inset)
                }
            }
            .navigationTitle("Oryne")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                // The wordmark. A short name needs a little air to hold the
                // bar: gentle tracking, with leading padding offsetting the
                // trailing letterspace so it sits optically centered.
                ToolbarItem(placement: .principal) {
                    Text("Oryne")
                        .font(OceanType.wordmark)
                        .tracking(OceanType.wordmarkTracking)
                        .padding(.leading, OceanType.wordmarkTracking)
                        .foregroundStyle(OceanTheme.foam)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        onComplete()
                        dismiss()
                    }
                    .foregroundStyle(OceanTheme.mist)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Back as a tool, and the one main action of the whole flow as Primary,
    /// filling the rest of the row.
    private var controls: some View {
        HStack(spacing: OceanSpacing.item) {
            if page > 0 {
                Button {
                    withAnimation(OceanMotion.lift) { page -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.oceanIcon)
                .accessibilityLabel("Previous")
            }

            Button {
                if isLastPage {
                    onComplete()
                    dismiss()
                } else {
                    withAnimation(OceanMotion.lift) { page += 1 }
                }
            } label: {
                Label((isLastPage ? "Enter the Ocean" : "Continue") as LocalizedStringKey,
                      systemImage: isLastPage ? "water.waves" : "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.oceanPrimary)
        }
    }

    private func completeAndTest() {
        onTestCapture()
        dismiss()
    }
}

// MARK: - Pages

private struct OceanOnboardingPage {
    var visual: OceanOnboardingVisual.Variant
    var title: LocalizedStringKey
    var text: LocalizedStringKey

    /// The mental model, in three quiet steps: what this is, how thoughts
    /// get in, and how they come back. The concrete tour lives in the
    /// seeded Introduction current, which the setup page points to.
    static let pages: [OceanOnboardingPage] = [
        OceanOnboardingPage(
            visual: .stillWater,
            title: "Not another notes app.",
            text: "Oryne is a place for unfinished thoughts, passing signals, and ideas that are not ready to become plans yet."
        ),
        OceanOnboardingPage(
            visual: .capture,
            title: "Catch fragments before they disappear.",
            text: "Tap the bar to type, or tap the disc and whisper. From the Action Button, Control Center or the widget, it is one press. The Ocean receives the thought without asking you to organize it first."
        ),
        OceanOnboardingPage(
            visual: .resurface,
            title: "The tide brings them back.",
            text: "Each day one older thought resurfaces on Tide. Thoughts that belong together gather into currents. Ask a question, and the Ocean answers from what you have caught."
        )
    ]
}

private struct OceanOnboardingPageView: View {
    let page: OceanOnboardingPage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: OceanSpacing.block)
            Text(page.title)
                .font(OceanType.resurfacingTitle)
                .foregroundStyle(OceanTheme.foam)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(page.text)
                .font(OceanType.secondary)
                .lineSpacing(OceanType.secondaryLeading)
                .foregroundStyle(OceanTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, OceanSpacing.item)
            Spacer(minLength: OceanSpacing.section)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OceanSpacing.tight)
        // The same light Tide gives its resurfacing thought: one lamp in
        // the water behind the words, warmest on the page about returning.
        // Art-directed, like Tide's lamp.
        .background(alignment: .center) {
            RadialGradient(
                colors: [OceanTheme.glowWarm.opacity(page.visual == .resurface ? 0.12 : 0.06),
                         OceanTheme.glowWarm.opacity(0.02), .clear],
                center: .center, startRadius: 0, endRadius: 240
            )
            .frame(width: 520, height: 400)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Setup page (screen 6)

/// Fast Capture setup, folded into onboarding. Binds directly to the same
/// App-Group preferences the Fast Capture settings screen uses; the full
/// Action Button / Camera Control walkthrough stays in settings (⚡ on
/// Capture) so this step stays light. A tile, like every surface in the
/// content layer.
private struct FastCaptureSetupPage: View {
    var onTestCapture: () -> Void

    @AppStorage(
        FastCapturePreferenceKeys.inputPreference,
        store: FastCapturePreferences.defaults
    ) private var inputPreferenceRaw = FastCaptureInputPreference.voiceFirst.rawValue
    @AppStorage(
        FastCapturePreferenceKeys.autoScreenshot,
        store: FastCapturePreferences.defaults
    ) private var autoScreenshot = true

    var body: some View {
        VStack {
            Spacer(minLength: OceanSpacing.item)

            VStack(spacing: OceanSpacing.inset) {
                Image(systemName: "bolt.circle.fill")
                    .font(OceanType.glyphHero)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(OceanTheme.accent)

                VStack(spacing: OceanSpacing.gap) {
                    Text("Set up Fast Capture.")
                        .font(OceanType.subjectTitle)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(OceanTheme.foam)

                    Text("How a capture from the Action Button, Control Center or the widget should open.")
                        .font(OceanType.secondary)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(OceanTheme.mist)
                }

                VStack(alignment: .leading, spacing: OceanSpacing.inset) {
                    Picker("Opens with", selection: $inputPreferenceRaw) {
                        ForEach(FastCaptureInputPreference.allCases) { preference in
                            Label(preference.label, systemImage: preference.symbol)
                                .tag(preference.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(isOn: $autoScreenshot) {
                        Label("Screenshot + voice", systemImage: "photo.on.rectangle")
                            .font(OceanType.control)
                            .foregroundStyle(OceanTheme.foam)
                    }
                    .toggleStyle(.oceanSwitch)

                    Text("The Action Button and Camera Control shortcuts live in Settings, under the gear on any tab.")
                        .font(OceanType.note)
                        .foregroundStyle(OceanTheme.faint)
                        .fixedSize(horizontal: false, vertical: true)

                    // The handoff: the concrete tour lives in the Ocean
                    // itself, as the seeded Introduction current.
                    Text("Tide opens with a short introduction current. Read it, then let it drift out.")
                        .font(OceanType.note)
                        .foregroundStyle(OceanTheme.mist)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onTestCapture) {
                    Label("Try a first capture", systemImage: "mic.circle")
                }
                .buttonStyle(.oceanSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(OceanSpacing.inset)
            .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)))

            Spacer(minLength: OceanSpacing.section)
        }
    }
}

// MARK: - Page kinds

/// What each orientation page is about; the lamp warms on the returning page.
private enum OceanOnboardingVisual {
    enum Variant {
        case stillWater
        case capture
        case resurface
    }
}
