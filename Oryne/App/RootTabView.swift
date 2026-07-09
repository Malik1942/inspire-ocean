import SwiftUI

/// Primary navigation (§13): Capture · Ocean · Ask · Library.
/// Library is the structured fallback "for accessibility and trust".
struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @AppStorage(
        FastCapturePreferenceKeys.onboardingCompleted,
        store: FastCapturePreferences.defaults
    ) private var fastCaptureOnboardingCompleted = false
    @AppStorage(
        CalmAccessibility.key,
        store: FastCapturePreferences.defaults
    ) private var calmAccessibilityOn = false

    @State private var appState = AppState()
    @State private var showFastCaptureOnboarding = false
    @State private var reviewFulfillTask: Task<Void, Never>?

    /// Nothing is covering the tabs: no Fast Capture overlay, no onboarding
    /// sheet, no sheet up in the Ocean. The review ask only ever fires here.
    private var canFulfillReview: Bool {
        appState.fastCaptureRequest == nil
            && !showFastCaptureOnboarding
            && !appState.isPresentingOceanSheet
    }

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            CaptureView()
                .tabItem { tabLabel("Capture", systemImage: "plus.circle") }
                .tag(OceanTab.capture)

            OceanFieldView()
                .tabItem { tabLabel("Ocean", systemImage: "water.waves") }
                .tag(OceanTab.ocean)

            AskView()
                .tabItem { tabLabel("Ask", systemImage: "bubble.left") }
                .tag(OceanTab.ask)

            LibraryView()
                .tabItem { tabLabel("Library", systemImage: "rectangle.stack") }
                .tag(OceanTab.library)
        }
        .environment(appState)
        .overlay {
            if let request = appState.fastCaptureRequest {
                FastCaptureSessionView(
                    request: request,
                    onFinish: {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                            appState.fastCaptureRequest = nil
                        }
                    },
                    onOpenNode: { nodeID in
                        appState.selectedTab = .ocean
                        // Let the overlay's dismissal animation finish first —
                        // presenting the node sheet in the same transaction as
                        // the overlay teardown drops the presentation.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(420))
                            appState.pendingFocusNodeID = nodeID
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: appState.fastCaptureRequest?.id)
        .sheet(isPresented: $showFastCaptureOnboarding) {
            OceanOnboardingView(
                onComplete: {
                    fastCaptureOnboardingCompleted = true
                    showFastCaptureOnboarding = false
                },
                onTestCapture: {
                    fastCaptureOnboardingCompleted = true
                    showFastCaptureOnboarding = false
                    appState.startFastCapture(source: .onboarding)
                }
            )
        }
        .task {
            appState.consumePendingFastCapture()
            guard !fastCaptureOnboardingCompleted else { return }
            try? await Task.sleep(for: .milliseconds(650))
            showFastCaptureOnboarding = true
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            appState.consumePendingFastCapture()
        }
        .onOpenURL { url in
            appState.handleDeepLink(url)
        }
        // A value-has-landed moment armed the once-ever review ask; fire it here,
        // where the environment action lives and every surface funnels through.
        // Held back, and retried, until nothing is covering the tabs, so the
        // system sheet never lands over the Fast Capture overlay or an Ocean
        // sheet (including the resurfaced thought that just armed it).
        .onChange(of: ReviewPrompt.shared.pendingRequest) { _, pending in
            if pending { scheduleReviewFulfillIfSafe() }
        }
        .onChange(of: appState.fastCaptureRequest?.id) { _, _ in scheduleReviewFulfillIfSafe() }
        .onChange(of: showFastCaptureOnboarding) { _, _ in scheduleReviewFulfillIfSafe() }
        .onChange(of: appState.isPresentingOceanSheet) { _, _ in scheduleReviewFulfillIfSafe() }
        // Outermost, so the Fast Capture overlay and every presented sheet
        // inherit the stilled-water environment along with the tabs.
        .environment(\.calmAccessibility, calmAccessibilityOn)
    }

    /// Re-checked on every change to what might cover the tabs; safe to call
    /// repeatedly. Cancels any earlier wait so only the latest attempt lands,
    /// and settles briefly once conditions clear (mirrors the overlay-dismiss
    /// settle above) so the ask never races a transition's last frame.
    private func scheduleReviewFulfillIfSafe() {
        reviewFulfillTask?.cancel()
        guard ReviewPrompt.shared.pendingRequest, canFulfillReview else { return }
        reviewFulfillTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, ReviewPrompt.shared.pendingRequest, canFulfillReview else { return }
            ReviewPrompt.shared.fulfill(using: requestReview)
        }
    }

    /// Tab label that always renders the outline (stroke) form of its symbol.
    ///
    /// TabView injects the `.fill` symbol variant into each tab item's
    /// environment, silently turning `plus.circle` into `plus.circle.fill`.
    /// Overriding the variant *on the label itself* is the level that wins —
    /// a TabView-wide `.environment(\.symbolVariants, .none)` does not reach
    /// the items. `water.waves` was never affected because it has no fill
    /// variant, which is why Ocean alone always looked like a stroke.
    private func tabLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .environment(\.symbolVariants, .none)
    }
}
