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
                        }

                        FastCaptureSetupPage(onTestCapture: completeAndTest)
                            .tag(pages.count)
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
                        .oceanText(OceanType.wordmark)
                        .padding(.leading, OceanType.wordmark.tracking) // art-directed
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
        HStack(spacing: OceanSpacing.gap) {
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
        OceanOnboardingScroll {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: OceanSpacing.block)
                Text(page.title)
                    .oceanText(OceanType.pageTitle)
                    .foregroundStyle(OceanTheme.foam)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(page.text)
                    .oceanText(OceanType.body)
                    .foregroundStyle(OceanTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, OceanSpacing.item)
                Spacer(minLength: OceanSpacing.section)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // One light in the water behind the words, as on the pages: warm
        // only on the page about a thought coming back, the ring's cool
        // light on the others (design/identity-2.1.md, R2). Art-directed.
        .background(alignment: .center) {
            let light = page.visual == .resurface ? OceanTheme.stageLight : OceanTheme.ring
            RadialGradient(
                colors: [light.opacity(page.visual == .resurface ? 0.14 : 0.06),
                         light.opacity(0.02), .clear],
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
        OceanOnboardingScroll {
            VStack {
                Spacer(minLength: OceanSpacing.item)

                VStack(alignment: .leading, spacing: OceanSpacing.inset) {
                    Image(systemName: "bolt.circle.fill")
                        .oceanText(OceanType.glyphHero)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(OceanTheme.accent)

                    VStack(alignment: .leading, spacing: OceanSpacing.item) {
                        Text("Set up Fast Capture.")
                            .oceanText(OceanType.sheetTitle)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(OceanTheme.foam)
                            .accessibilityAddTraits(.isHeader)

                        Text("How a capture from the Action Button, Control Center or the widget should open.")
                            .oceanText(OceanType.body)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(OceanTheme.text)
                    }

                    VStack(alignment: .leading, spacing: OceanSpacing.inset) {
                        VStack(alignment: .leading, spacing: OceanSpacing.afterLabel) {
                            OceanSectionLabel("Opens with")
                            Picker("Opens with", selection: $inputPreferenceRaw) {
                                ForEach(FastCaptureInputPreference.allCases) { preference in
                                    Text(preference.label)
                                        .tag(preference.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Toggle(isOn: $autoScreenshot) {
                            Label("Screenshot + voice", systemImage: "photo.on.rectangle")
                                .labelStyle(OceanControlLabelStyle())
                                .oceanText(OceanType.control)
                                .foregroundStyle(OceanTheme.foam)
                        }
                        .toggleStyle(.oceanSwitch)

                        Text("The Action Button and Camera Control shortcuts live in Settings, under the gear on any tab.")
                            .oceanText(OceanType.meta)
                            .foregroundStyle(OceanTheme.mist)
                            .fixedSize(horizontal: false, vertical: true)

                        // The handoff: the concrete tour lives in the Ocean
                        // itself, as the seeded Introduction current.
                        Text("Tide opens with a short introduction current. Read it, then let it drift out.")
                            .oceanText(OceanType.meta)
                            .foregroundStyle(OceanTheme.mist)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: onTestCapture) {
                        Label("Try a first capture", systemImage: "mic.circle")
                    }
                    .buttonStyle(.oceanSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OceanSpacing.inset)
                .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)))

                Spacer(minLength: OceanSpacing.section)
            }
        }
    }
}

// MARK: - Page frame

/// A page of the flow, composed in its own height while its words fit and
/// scrolling once they outgrow it (the larger accessibility sizes) instead
/// of clipping. The content is framed at least the page's height, which
/// proposes that height to it, so its spacers share the free water exactly
/// as on a page that cannot scroll. The reading column and the gutter sit
/// inside the scroll, so a tile's shadow is never cut at the scroll's edge.
private struct OceanOnboardingScroll<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .oceanReadableColumn()
                    .padding(.horizontal, OceanSpacing.gutter)
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
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
