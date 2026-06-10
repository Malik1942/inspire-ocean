import SwiftUI

/// Minimal, self-contained capture sheet shown inside the share extension.
/// Kept independent of the app's design system so the extension stays light.
struct ShareCaptureView: View {
    let payload: SharePayload
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var note: String = ""
    @FocusState private var focused: Bool

    private let deep = Color(red: 0.04, green: 0.10, blue: 0.22)
    private let accent = Color(red: 0.45, green: 0.82, blue: 0.92)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add a note")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        TextField("Why does this matter?", text: $note, axis: .vertical)
                            .focused($focused)
                            .padding(12)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                            .lineLimit(2...6)
                    }
                }
                .padding()
            }
            .background(
                LinearGradient(colors: [Color(red: 0.02, green: 0.05, blue: 0.12), deep],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            )
            .navigationTitle("Drift into Ocean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel).tint(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(note) }.tint(accent).fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var preview: some View {
        if let data = payload.imageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable().scaledToFit()
                .frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        if let url = payload.urlString {
            Label(url, systemImage: "link")
                .font(.callout).foregroundStyle(accent).lineLimit(2)
        }
        if let text = payload.text, !text.isEmpty {
            Text(text)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
