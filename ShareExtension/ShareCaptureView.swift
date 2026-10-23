import SwiftUI

/// The capture sheet inside the share extension, on the app's own water
/// and surfaces (the design system's shared layer is compiled in; nothing
/// heavier). A preview of what arrived, then a field for a few words.
struct ShareCaptureView: View {
    let payload: SharePayload
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var note: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OceanSpacing.block) {
                    preview
                    VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                        Text("Add a note")
                            .font(OceanType.eyebrow)
                            .foregroundStyle(OceanTheme.mist)
                        TextField("Why does this matter?", text: $note, axis: .vertical)
                            .textFieldStyle(.plain)
                            .focused($focused)
                            .lineLimit(2...6)
                            .font(OceanType.body)
                            .foregroundStyle(OceanTheme.foam)
                            .tint(OceanTheme.accent)
                            .padding(.vertical, OceanSpacing.gap)
                            .padding(.horizontal, OceanSpacing.insetCompact)
                            .frame(minHeight: OceanControlSize.height)
                            .background(OceanTheme.fill, in: RoundedRectangle(cornerRadius: OceanRadius.field, style: .continuous))
                    }
                }
                .padding(.horizontal, OceanSpacing.gutterCompact)
                .padding(.vertical, OceanSpacing.inset)
            }
            .background(OceanBackground())
            .navigationTitle("Drift into Ocean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(note) }.fontWeight(.semibold)
                }
            }
        }
        .tint(OceanTheme.accent)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var preview: some View {
        if let data = payload.imageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable().scaledToFit()
                .frame(maxHeight: OceanSize.hero + OceanSpacing.section)
                .clipShape(RoundedRectangle(cornerRadius: OceanRadius.media, style: .continuous))
        }
        if let url = payload.urlString {
            Label(url, systemImage: "link")
                .font(OceanType.meta)
                .foregroundStyle(OceanTheme.mist)
                .lineLimit(2)
        }
        if let text = payload.text, !text.isEmpty {
            Text(text)
                .font(OceanType.body)
                .lineSpacing(OceanType.bodyLeading)
                .foregroundStyle(OceanTheme.foam)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OceanSpacing.inset)
                .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)))
        }
    }
}
