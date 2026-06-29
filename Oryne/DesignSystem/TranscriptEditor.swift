import SwiftUI

/// The transcript surface shared by three moments: the live preview while a
/// whisper is being caught (read-only, words drifting in), the post-capture
/// review (editable, before release), and the node editor (editable, after).
///
/// Deliberately dumb — a binding and a flag; the surrounding card decides
/// everything else.
struct TranscriptEditor: View {
    @Binding var text: String
    var isEditable: Bool = true
    var placeholder: LocalizedStringKey = ""
    var minHeight: CGFloat = 96
    var maxHeight: CGFloat = 200
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        Group {
            if isEditable {
                editor
            } else {
                livePreview
            }
        }
    }

    /// Read-only, kept scrolled to the newest words; dimmed like something
    /// still forming.
    private var livePreview: some View {
        ScrollView {
            (text.isEmpty ? Text(placeholder) : Text(text))
                .font(.callout)
                .foregroundStyle(text.isEmpty ? OceanTheme.faint : OceanTheme.mist)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
        .frame(minHeight: minHeight, maxHeight: maxHeight)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var editor: some View {
        Group {
            if let focus {
                baseEditor.focused(focus)
            } else {
                baseEditor
            }
        }
        .frame(minHeight: minHeight, maxHeight: maxHeight)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var baseEditor: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .foregroundStyle(OceanTheme.foam)
            .overlay(alignment: .topLeading) {
                if text.trimmed.isEmpty {
                    Text(placeholder)
                        .font(.subheadline)
                        .foregroundStyle(OceanTheme.faint)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
    }
}
