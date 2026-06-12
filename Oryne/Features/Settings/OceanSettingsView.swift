import SwiftUI

/// Ocean settings — deliberately small. The first resident is Calm
/// Accessibility Mode; anything that earns a place here later should pass the
/// same bar: a real choice about how the Ocean treats the user, never a
/// preference for its own sake.
struct OceanSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(
        CalmAccessibility.key,
        store: FastCapturePreferences.defaults
    ) private var calmMode = false

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground(animated: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        calmSection
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

                Text("Holds the water still, brightens the words that carry meaning, and widens every touch target. Nothing about your Ocean changes — only how it moves. The system Reduce Motion setting stills the water too.")
                    .font(.caption)
                    .foregroundStyle(OceanTheme.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
