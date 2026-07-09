import SwiftUI
import SwiftData

/// Ocean settings — deliberately small. The first resident is Calm
/// Accessibility Mode; anything that earns a place here later should pass the
/// same bar: a real choice about how the Ocean treats the user, never a
/// preference for its own sake.
///
/// Language is intentionally *not* here: Oryne ships English + 简体中文 and
/// follows the standard per-app language control in iOS Settings (Settings ›
/// Oryne › Language), so the device, not a bespoke in-app toggle, is the single
/// place a user changes it.
struct OceanSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(
        CalmAccessibility.key,
        store: FastCapturePreferences.defaults
    ) private var calmMode = false

    @AppStorage(
        CaptureFeedback.Keys.sound,
        store: FastCapturePreferences.defaults
    ) private var captureSound = true

    @AppStorage(
        CaptureFeedback.Keys.haptics,
        store: FastCapturePreferences.defaults
    ) private var captureHaptics = true

    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<Node> { $0.isExample == true && $0.isArchived == false })
    private var exampleNodes: [Node]

    @Query(filter: #Predicate<Node> { $0.isExample == false && $0.isArchived == false })
    private var realNodes: [Node]

    @State private var pendingClearExamples = false

    @State private var includeVoice = false
    @State private var exportState: ExportState = .idle
    @State private var zipURL: URL?

    private enum ExportState { case idle, building, ready, failed }

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground(animated: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        calmSection
                        feedbackSection
                        // Appears only once the user has both examples and real
                        // content, so it never shows before they have started.
                        if !exampleNodes.isEmpty && !realNodes.isEmpty {
                            examplesSection
                        }
                        exportSection
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Clear examples?",
                isPresented: $pendingClearExamples,
                titleVisibility: .visible
            ) {
                Button("Clear examples", role: .destructive) {
                    clearExamples()
                    pendingClearExamples = false
                }
                Button("Cancel", role: .cancel) { pendingClearExamples = false }
            } message: {
                Text("The starter thoughts drift out for good.")
            }
        }
    }

    private var calmSection: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "water.waves.slash")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(OceanTheme.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calm Accessibility")
                            .font(.headline)
                            .foregroundStyle(OceanTheme.foam)
                        Text("The same Ocean, stilled.")
                            .font(.caption)
                            .foregroundStyle(OceanTheme.mist)
                    }
                }

                Toggle(isOn: $calmMode) {
                    Label("Calm Accessibility Mode", systemImage: "figure.mind.and.body")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(OceanTheme.foam)
                }
                .tint(OceanTheme.accent)

                Text("Holds the water still, brightens the words that carry meaning, and widens every touch target. Nothing about your Ocean changes, only how it moves. The system Reduce Motion setting stills the water too.")
                    .font(.caption)
                    .foregroundStyle(OceanTheme.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var feedbackSection: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(OceanTheme.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Capture feedback")
                            .font(.headline)
                            .foregroundStyle(OceanTheme.foam)
                        Text("A quiet sign the Ocean received it.")
                            .font(.caption)
                            .foregroundStyle(OceanTheme.mist)
                    }
                }

                Toggle(isOn: $captureSound) {
                    Label("Sound", systemImage: "speaker.wave.2")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(OceanTheme.foam)
                }
                .tint(OceanTheme.accent)

                Toggle(isOn: $captureHaptics) {
                    Label("Haptics", systemImage: "hand.tap")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(OceanTheme.foam)
                }
                .tint(OceanTheme.accent)

                Text("A soft chime and a gentle swell when a thought is released. The ring/silent switch quiets the chime.")
                    .font(.caption)
                    .foregroundStyle(OceanTheme.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var examplesSection: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(OceanTheme.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Starter examples")
                            .font(.headline)
                            .foregroundStyle(OceanTheme.foam)
                        Text("The thoughts that came with your Ocean.")
                            .font(.caption)
                            .foregroundStyle(OceanTheme.mist)
                    }
                }

                Button(role: .destructive) {
                    pendingClearExamples = true
                } label: {
                    Label("Clear examples", systemImage: "trash")
                        .font(.subheadline.weight(.medium))
                }

                Text("Once you have thoughts of your own, the starter examples can drift out. Yours stay.")
                    .font(.caption)
                    .foregroundStyle(OceanTheme.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Removes every seeded example, including the cultivated branch. A real
    /// branch the user grew off an example is detached first so the cascade
    /// never takes their own thought; then only example roots are deleted
    /// (deleteNodeSafely archives-then-deletes the subtree, cascade-safe).
    private func clearExamples() {
        for node in exampleNodes {
            for child in node.children ?? [] where !child.isExample {
                child.parent = nil
            }
        }
        for root in exampleNodes where root.parent == nil {
            context.deleteNodeSafely(root)
        }
        try? context.save()
    }

    private var exportSection: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.doc")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(OceanTheme.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export the Ocean")
                            .font(.headline)
                            .foregroundStyle(OceanTheme.foam)
                        Text("Your thoughts, ready to take with you.")
                            .font(.caption)
                            .foregroundStyle(OceanTheme.mist)
                    }
                }

                Toggle(isOn: $includeVoice) {
                    Label("Include voice recordings", systemImage: "waveform")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(OceanTheme.foam)
                }
                .tint(OceanTheme.accent)

                switch exportState {
                case .idle:
                    Button { buildExport() } label: {
                        Label("Prepare archive", systemImage: "shippingbox")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(OceanTheme.accent)
                    }
                    .disabled(realNodes.isEmpty)
                case .building:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Packing your Ocean…")
                            .font(.subheadline)
                            .foregroundStyle(OceanTheme.mist)
                    }
                case .ready:
                    if let zipURL {
                        ShareLink(item: zipURL) {
                            Label("Share archive", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(OceanTheme.accent)
                        }
                    }
                case .failed:
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Could not pack the archive.", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(OceanTheme.mist)
                        Button { buildExport() } label: {
                            Label("Try again", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(OceanTheme.accent)
                        }
                    }
                }

                Text("One zip: a Markdown file per current, a full JSON backup, and your images. Examples stay behind.")
                    .font(.caption)
                    .foregroundStyle(OceanTheme.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A built archive reflects the toggle at build time; changing it
            // invalidates the archive so the user rebuilds with the new choice.
            .onChange(of: includeVoice) { _, _ in
                exportState = .idle
                zipURL = nil
            }
        }
    }

    /// Snapshots the export set on the main actor (Node is main-isolated), then
    /// writes files and zips off the main actor so the UI never blocks.
    private func buildExport() {
        exportState = .building
        let snapshots = realNodes.map { OceanExport.snapshot(from: $0) }
        let voice = includeVoice
        Task {
            do {
                let url = try await Task.detached {
                    try OceanExport.buildArchive(from: snapshots, includeVoice: voice)
                }.value
                zipURL = url
                exportState = .ready
            } catch {
                zipURL = nil
                exportState = .failed
            }
        }
    }
}
