import SwiftUI
import StoreKit

/// Primary navigation: Ocean · Ask · Library, with the capture bar above the
/// tab bar. Capture is a gesture, not a tab: tap the field to type, hold the
/// disc to whisper (docs/plans/phone-refocus/SPEC.md).
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
    /// Another field has the keyboard (Library's search, a sheet's field):
    /// the capture bar steps aside rather than ride on top of it.
    @State private var keyboardUp = false

    private var control: CaptureControl { appState.captureControl }

    /// Nothing is covering the tabs: no Fast Capture overlay, no onboarding
    /// sheet, no sheet up in the Ocean. The review ask only ever fires here.
    private var canFulfillReview: Bool {
        appState.fastCaptureRequest == nil
            && !showFastCaptureOnboarding
            && !appState.isPresentingOceanSheet
    }

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            OceanFieldView()
                .tabItem { tabLabel(OceanTab.homeTitle, systemImage: "water.waves") }
                .tag(OceanTab.ocean)

            AskView()
                .tabItem { tabLabel("Ask", systemImage: "bubble.left") }
                .tag(OceanTab.ask)

            LibraryView()
                .tabItem { tabLabel("Library", systemImage: "rectangle.stack") }
                .tag(OceanTab.library)
        }
        .environment(appState)
        .environment(control)
        .overlay {
            if let request = appState.fastCaptureRequest {
                FastCaptureSessionView(
                    request: request,
                    onFinish: {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                            appState.fastCaptureRequest = nil
                        }
                    }
                )
                .environment(appState)
                .environment(control)
                .transition(.opacity)
            }
        }
        // The capture bar rides above the tab bar (Ocean and Library). A
        // hold that begins on its disc keeps its finger while the overlay
        // rises; the overlay's own disc takes over once the finger lifts.
        // The bar steps aside the moment the overlay is up (its composer is
        // the bar, expanded), except while a hold that began on the bar's
        // disc still has its finger down, and while the overlay is only its
        // toast, which sits above the bar.
        .modifier(CaptureBarPlacement(
            show: appState.selectedTab != .ask
                && !keyboardUp
                && (appState.fastCaptureRequest == nil || control.touch != .up || control.toastShowing),
            control: control
        ))
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
            control.tapToToggle = CaptureControl.assistiveTechnologyRunning
            appState.consumePendingFastCapture()
            guard !fastCaptureOnboardingCompleted else { return }
            try? await Task.sleep(for: .milliseconds(650))
            showFastCaptureOnboarding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            control.tapToToggle = CaptureControl.assistiveTechnologyRunning
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)) { _ in
            control.tapToToggle = CaptureControl.assistiveTechnologyRunning
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            appState.consumePendingFastCapture()
        }
        .onOpenURL { url in
            appState.handleDeepLink(url)
        }
        // The floating button's gesture, resolved: a short press opens the
        // overlay typing-first; a hold (or a tap in tap-to-toggle mode) opens
        // it listening, the finger still down.
        .onChange(of: control.tapCount) { _, _ in
            guard appState.fastCaptureRequest == nil, !control.overlayOpen else { return }
            appState.startFastCapture(source: .inApp, inputPreference: .typingFirst)
        }
        .onChange(of: control.touch) { _, touch in
            guard appState.fastCaptureRequest == nil, !control.overlayOpen, touch != .up else { return }
            appState.startFastCapture(source: .inApp, inputPreference: .voiceFirst)
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

/// Shared capture geometry: the bar is a 56 pt capsule, the disc 44 pt,
/// inset 6 on every side so disc and capsule end are concentric, 12 pt
/// above the tab bar. The overlay's disc is the same 44.
enum FastCaptureLayout {
    static let barHeight: CGFloat = 56
    static let buttonSize: CGFloat = 44
    static let discInset: CGFloat = 6
    /// The tab bar (49 pt) plus the 12 pt gap under the bar.
    static let tabBarClearance: CGFloat = 49 + 12
    /// What scrolling content under the bar leaves clear: bar, gap, and a
    /// breath above it.
    static let contentClearance: CGFloat = tabBarClearance + barHeight + 16
    /// Ask's bar lives in its page's bottom safe-area inset, which already
    /// clears the tab bar; this lifts it to the capture bar's exact height.
    static let insetBarLift: CGFloat = 12
}
