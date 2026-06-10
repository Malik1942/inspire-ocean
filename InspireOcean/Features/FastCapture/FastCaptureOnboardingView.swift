import SwiftUI

struct FastCaptureOnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var onComplete: () -> Void
    var onTestCapture: () -> Void

    @State private var page = 0

    private let pages = FastCaptureOnboardingPage.pages

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground()

                VStack(spacing: 18) {
                    TabView(selection: $page) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            FastCaptureOnboardingPageView(page: page)
                                .tag(index)
                                .padding(.horizontal)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))

                    controls
                        .padding(.horizontal)
                        .padding(.bottom, 18)
                }
            }
            .navigationTitle("Fast Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onComplete()
                        dismiss()
                    }
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
                if page == pages.count - 1 {
                    onTestCapture()
                    dismiss()
                } else {
                    withAnimation(.snappy) { page += 1 }
                }
            } label: {
                Label(page == pages.count - 1 ? "Test Capture" : "Continue",
                      systemImage: page == pages.count - 1 ? "mic.circle.fill" : "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(OceanTheme.accent, in: Capsule())
            .foregroundStyle(OceanTheme.abyss)
        }
    }
}

private struct FastCaptureOnboardingPage: Identifiable {
    let id = UUID()
    var symbol: String
    var title: String
    var text: String
    var steps: [String] = []

    static let pages: [FastCaptureOnboardingPage] = [
        FastCaptureOnboardingPage(
            symbol: "bolt.circle.fill",
            title: "A drift, caught instantly",
            text: "Fast Capture opens a small listening space before the thought has to become a note."
        ),
        FastCaptureOnboardingPage(
            symbol: "water.waves",
            title: "Ambient by default",
            text: "It is built for quick fragments: the half-formed thing, the feeling, the visual thread."
        ),
        FastCaptureOnboardingPage(
            symbol: "photo.on.rectangle.angled",
            title: "What you see, what you mean",
            text: "A screenshot shortcut can attach the screen first, then let your voice or words carry the context."
        ),
        FastCaptureOnboardingPage(
            symbol: "button.programmable",
            title: "Action Button",
            text: "Assign Start Fast Capture in Settings.",
            steps: ["Settings", "Action Button", "Shortcut", "Start Fast Capture"]
        ),
        FastCaptureOnboardingPage(
            symbol: "camera.viewfinder",
            title: "Camera Control",
            text: "Use the context shortcut where Camera Control shortcuts are available.",
            steps: ["Shortcuts", "Take Screenshot", "Start Context Capture", "Assign where available"]
        ),
        FastCaptureOnboardingPage(
            symbol: "mic.circle.fill",
            title: "First test",
            text: "Microphone and speech access appear only when a capture actually needs them."
        )
    ]
}

private struct FastCaptureOnboardingPageView: View {
    let page: FastCaptureOnboardingPage

    var body: some View {
        VStack {
            Spacer(minLength: 12)

            GlassCard(padding: 22) {
                VStack(spacing: 18) {
                    Image(systemName: page.symbol)
                        .font(.system(size: 44, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(OceanTheme.accent)
                        .frame(width: 72, height: 72)
                        .background(Color.white.opacity(0.07), in: Circle())

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

                    if !page.steps.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(Array(page.steps.enumerated()), id: \.offset) { index, title in
                                FastCaptureOnboardingStep(number: index + 1, title: title)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 42)
        }
    }
}

private struct FastCaptureOnboardingStep: View {
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
