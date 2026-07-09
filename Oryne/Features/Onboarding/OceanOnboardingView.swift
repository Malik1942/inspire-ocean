import SwiftUI

/// First-run onboarding: establishes the mental model — capture fragments
/// before they disappear, and the Ocean gives them back — then folds Fast
/// Capture setup into the final step, which hands off to the seeded
/// Introduction current for the concrete tour.
///
/// Deliberately not a tutorial: three short screens of orientation, one of
/// setup. Skippable at any point; shown once (replayable from Fast Capture
/// settings via the sparkle button). The bolt reference in the setup caption
/// stays plain text — symbol glyphs inside Text render inconsistently here.
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

                VStack(spacing: 18) {
                    TabView(selection: $page) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            OceanOnboardingPageView(page: page)
                                .tag(index)
                                .padding(.horizontal)
                        }

                        FastCaptureSetupPage(onTestCapture: completeAndTest)
                            .tag(pages.count)
                            .padding(.horizontal)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))

                    controls
                        .padding(.horizontal)
                        .padding(.bottom, 18)
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
                        .font(.headline.weight(.medium))
                        .tracking(2.5)
                        .padding(.leading, 2.5)
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

    private var controls: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button {
                    withAnimation(.snappy) { page -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .foregroundStyle(OceanTheme.foam)
                .accessibilityLabel("Previous")
            }

            Button {
                if isLastPage {
                    onComplete()
                    dismiss()
                } else {
                    withAnimation(.snappy) { page += 1 }
                }
            } label: {
                Label((isLastPage ? "Enter the Ocean" : "Continue") as LocalizedStringKey,
                      systemImage: isLastPage ? "water.waves" : "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(OceanTheme.accent, in: Capsule())
            .foregroundStyle(OceanTheme.abyss)
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
            text: "Speak, type, or capture from anywhere. The Ocean receives the thought without asking you to organize it first."
        ),
        OceanOnboardingPage(
            visual: .resurface,
            title: "The Ocean gives back.",
            text: "Thoughts gather into currents and resurface when they matter. Ask a question, and the Ocean answers from everything you have caught."
        )
    ]
}

private struct OceanOnboardingPageView: View {
    let page: OceanOnboardingPage

    var body: some View {
        VStack {
            Spacer(minLength: 12)

            GlassCard(padding: 22) {
                VStack(spacing: 20) {
                    OceanOnboardingVisual(variant: page.visual)
                        .frame(height: 130)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 8) {
                        Text(page.title)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(OceanTheme.foam)

                        Text(page.text)
                            .font(.subheadline)
                            .lineSpacing(3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(OceanTheme.mist)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 42)
        }
    }
}

// MARK: - Setup page (screen 6)

/// Fast Capture setup, folded into onboarding. Binds directly to the same
/// App-Group preferences the Fast Capture settings screen uses; the full
/// Action Button / Camera Control walkthrough stays in settings (⚡ on
/// Capture) so this step stays light.
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
            Spacer(minLength: 12)

            GlassCard(padding: 22) {
                VStack(spacing: 18) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 44, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(OceanTheme.accent)
                        .frame(width: 72, height: 72)
                        .background(Color.white.opacity(0.07), in: Circle())

                    VStack(spacing: 8) {
                        Text("Set up Fast Capture.")
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(OceanTheme.foam)

                        Text("Choose how you want to catch thoughts quickly.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(OceanTheme.mist)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Input", selection: $inputPreferenceRaw) {
                            ForEach(FastCaptureInputPreference.allCases) { preference in
                                Label(preference.label, systemImage: preference.symbol)
                                    .tag(preference.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle(isOn: $autoScreenshot) {
                            Label("Screenshot + voice", systemImage: "photo.on.rectangle")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(OceanTheme.foam)
                        }
                        .tint(OceanTheme.accent)

                        Text("The Action Button and Camera Control shortcuts live in Fast Capture settings, the bolt on Capture.")
                            .font(.caption)
                            .foregroundStyle(OceanTheme.faint)
                            .fixedSize(horizontal: false, vertical: true)

                        // The handoff: the concrete tour lives in the Ocean
                        // itself, as the seeded Introduction current.
                        Text("The Ocean opens with a short introduction. Read it, then let it drift out.")
                            .font(.caption)
                            .foregroundStyle(OceanTheme.mist)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: onTestCapture) {
                        Label("Try a first capture", systemImage: "mic.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(OceanTheme.mist)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 42)
        }
    }
}

// MARK: - Mini visuals

/// Small, quiet illustrations in the Ocean's own node language — soft orbs,
/// hairline rims, one warm accent. Drawn with Canvas; the highlighted node
/// breathes slowly, matching the field's motion language.
private struct OceanOnboardingVisual: View {
    enum Variant {
        case stillWater   // calm, even field
        case capture      // one bright fragment entering from above
        case resurface    // one warm fragment rising from the depth
    }

    let variant: Variant

    /// (x, y) in unit space, radius in points, dim 0…1.
    private var orbs: [(x: CGFloat, y: CGFloat, r: CGFloat, dim: CGFloat)] {
        switch variant {
        case .stillWater:
            return [(0.22, 0.42, 13, 0.6), (0.46, 0.66, 10, 0.4), (0.62, 0.34, 15, 0.8),
                    (0.81, 0.62, 11, 0.5), (0.38, 0.25, 8, 0.3)]
        case .capture:
            return [(0.28, 0.72, 11, 0.5), (0.5, 0.82, 9, 0.4), (0.72, 0.7, 12, 0.55)]
        case .resurface:
            return [(0.24, 0.8, 10, 0.4), (0.46, 0.88, 8, 0.3), (0.68, 0.82, 11, 0.45),
                    (0.86, 0.74, 7, 0.3)]
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let breathe = 1 + 0.04 * sin(t * 0.9)

                // Quiet base fragments.
                for orb in orbs {
                    drawOrb(ctx, at: CGPoint(x: orb.x * size.width, y: orb.y * size.height),
                            radius: orb.r, dim: orb.dim)
                }

                switch variant {
                case .stillWater:
                    break

                case .capture:
                    // A bright fragment entering from above, trail fading behind it.
                    let p = CGPoint(x: 0.5 * size.width, y: 0.3 * size.height)
                    for (i, fade) in [0.18, 0.10, 0.05].enumerated() {
                        let trail = CGPoint(x: p.x, y: p.y - CGFloat(i + 1) * 14)
                        ctx.fill(Path(ellipseIn: CGRect(x: trail.x - 2, y: trail.y - 2, width: 4, height: 4)),
                                 with: .color(.white.opacity(fade)))
                    }
                    drawOrb(ctx, at: p, radius: 13 * breathe, dim: 1.0)

                case .resurface:
                    // One warm fragment rising out of the depth.
                    let p = CGPoint(x: 0.5 * size.width, y: 0.34 * size.height)
                    let glow = CGRect(x: p.x - 22, y: p.y - 22, width: 44, height: 44)
                    ctx.fill(Path(ellipseIn: glow),
                             with: .color(OceanTheme.glowWarm.opacity(0.10)))
                    drawOrb(ctx, at: p, radius: 14 * breathe, dim: 1.0, warm: true)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawOrb(_ ctx: GraphicsContext, at p: CGPoint, radius: CGFloat,
                         dim: CGFloat, warm: Bool = false) {
        let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.04 + 0.05 * dim)))
        let rim: Color = warm ? OceanTheme.glowWarm : .white
        ctx.stroke(Path(ellipseIn: rect),
                   with: .color(rim.opacity(warm ? 0.45 : 0.10 + 0.16 * dim)),
                   lineWidth: warm ? 0.75 : 0.5)
    }
}
