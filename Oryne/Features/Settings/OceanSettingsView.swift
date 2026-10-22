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

    /// Read once per open, off the main thread: the availability query can
    /// take over a second on ineligible hardware.
    @State private var modelStatus: OnDeviceModel.Status?

    @State private var includeVoice = false
    @State private var exportState: ExportState = .idle
    @State private var zipURL: URL?

    private enum ExportState { case idle, building, ready, failed }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FastCaptureOpensWithRows()
                    Toggle("Sound", isOn: $captureSound)
                    Toggle("Haptics", isOn: $captureHaptics)
                } header: {
                    Text("Capture")
                } footer: {
                    Text("From the Action Button, Control Center and the widget. The bar itself always offers both.")
                }
                .listRowBackground(OceanTheme.fill)

                FastCaptureShortcutSection()
                    .listRowBackground(OceanTheme.fill)

                if FastCaptureWatchSection.isAvailable {
                    FastCaptureWatchSection()
                        .listRowBackground(OceanTheme.fill)
                }

                Section {
                    Toggle("Calm Accessibility", isOn: $calmMode)
                } footer: {
                    Text("Stills the water and its light, and makes the capture button tap to start and tap to stop instead of holding. The system Reduce Motion setting stills the water too.")
                }
                .listRowBackground(OceanTheme.fill)

                Section {
                    LabeledContent("Apple Intelligence", value: modelStatusValue)
                    NavigationLink {
                        MemoryRecordsView()
                    } label: {
                        Text("What Oryne knows about you")
                    }
                } footer: {
                    Text(modelStatusFooter)
                }
                .listRowBackground(OceanTheme.fill)
                .task {
                    modelStatus = await Task.detached(priority: .utility) { OnDeviceModel.status }.value
                }

                Section {
                    Toggle("Include voice recordings", isOn: $includeVoice)
                    exportRow
                    // The introduction is meant to be read once and let go,
                    // so the clear affordance is there from the first launch.
                    if !exampleNodes.isEmpty {
                        Button("Clear examples") { pendingClearExamples = true }
                    }
                } header: {
                    Text("Your Ocean")
                } footer: {
                    Text("One zip: a Markdown file per current, a full JSON backup, and your images. Examples stay behind.")
                }
                .listRowBackground(OceanTheme.fill)
            }
            .tint(OceanTheme.accent)
            .listRowSeparatorTint(Color.white.opacity(0.08))
            .scrollContentBackground(.hidden)
            .background(OceanBackground(animated: false))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            // A built archive reflects the toggle at build time; changing it
            // invalidates the archive so the user rebuilds with the new choice.
            .onChange(of: includeVoice) { _, _ in
                exportState = .idle
                zipURL = nil
            }
            .alert(
                "Clear examples?",
                isPresented: $pendingClearExamples
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

    /// "Ready" or "Unavailable"; blank for the beat before the check returns.
    private var modelStatusValue: String {
        switch modelStatus {
        case .ready: String(localized: "Ready")
        case .unavailable: String(localized: "Unavailable")
        case nil: ""
        }
    }

    /// What the model does here, or why it cannot and what stands in. The
    /// same reason a link's note gives, so the two never disagree.
    private var modelStatusFooter: String {
        switch modelStatus {
        case .unavailable(let reason):
            String(localized: "Not available: \(reason). Titles come from your own words, and Ask gives a fixed reading of the thoughts it finds.")
        case .ready, nil:
            String(localized: "Titles, themes, whisper summaries and Ask answers are composed on this device. Nothing leaves it.")
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

    /// One row that walks the archive through its states: export, packing,
    /// share, or try again.
    @ViewBuilder
    private var exportRow: some View {
        switch exportState {
        case .idle:
            Button("Export the Ocean") { buildExport() }
                .disabled(realNodes.isEmpty)
        case .building:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Packing your Ocean…")
                    .foregroundStyle(OceanTheme.mist)
            }
        case .ready:
            if let zipURL {
                ShareLink(item: zipURL) {
                    HStack {
                        Text("Share archive")
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OceanTheme.mist)
                    }
                }
            }
        case .failed:
            HStack {
                Text("Could not pack the archive.")
                    .foregroundStyle(OceanTheme.mist)
                Spacer()
                Button("Try again") { buildExport() }
                    .buttonStyle(.borderless)
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
