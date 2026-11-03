import SwiftUI

/// The capture sheet inside the share extension, on the app's own water
/// and surfaces (the design system's shared layer is compiled in; nothing
/// heavier). A preview of what arrived, then a field for a few words.
struct ShareCaptureView: View {
    let payload: SharePayload
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var note: String = ""
    @State private var width: CGFloat = 0
    @FocusState private var focused: Bool

    /// The app's page margin (OceanSpacing.gutter), taken from this sheet's
    /// own width: an extension cannot reach the app's windows.
    private var gutter: CGFloat {
        width >= OceanSpacing.gutterBreakpoint ? OceanSpacing.gutterWide : OceanSpacing.gutterCompact
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OceanSpacing.block) {
                    preview
                    VStack(alignment: .leading, spacing: OceanSpacing.afterLabel) {
                        // The app's section label (OceanSectionLabel), which
                        // the extension does not compile.
                        Text("Add a note")
                            .oceanText(OceanType.sectionLabel)
                            .foregroundStyle(OceanTheme.mist)
                            .padding(.leading, OceanSpacing.hairline)
                            .accessibilityAddTraits(.isHeader)
                        TextField("Why does this matter?", text: $note, prompt: Text(verbatim: ""), axis: .vertical)
                            .textFieldStyle(.plain)
                            .focused($focused)
                            .lineLimit(2...6)
                            .oceanFieldText(OceanType.inputWords)
                            .foregroundStyle(OceanTheme.foam)
                            .tint(OceanTheme.accent)
                            // The app's oceanPrompt, inline: the note is the
                            // user's words in New York, so its own prompt
                            // would set Oryne's question in the serif.
                            .overlay(alignment: .topLeading) {
                                if note.isEmpty {
                                    Text("Why does this matter?")
                                        .oceanText(OceanType.body)
                                        .foregroundStyle(OceanTheme.mist)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(.vertical, OceanSpacing.gap)
                            .padding(.horizontal, OceanSpacing.insetCompact)
                            .frame(minHeight: OceanControlSize.height)
                            .background(OceanTheme.fill, in: RoundedRectangle(cornerRadius: OceanRadius.field, style: .continuous))
                    }
                }
                .padding(.horizontal, gutter)
                .padding(.top, OceanSpacing.gap)
                .padding(.bottom, OceanSpacing.section)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .background(OceanBackground())
            .navigationTitle("Drift into Ocean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(note) }
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
                .frame(maxHeight: OceanSize.hero)
                .clipShape(RoundedRectangle(cornerRadius: OceanRadius.media, style: .continuous))
        }
        if let url = payload.urlString {
            Label(url, systemImage: "link")
                .oceanText(OceanType.secondary)
                .foregroundStyle(OceanTheme.text)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        if let text = payload.text, !text.isEmpty {
            Text(text)
                .oceanText(OceanType.body)
                .foregroundStyle(OceanTheme.foam)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OceanSpacing.inset)
                .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)))
        }
    }
}
