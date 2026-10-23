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
                .font(OceanType.body)
                .foregroundStyle(text.isEmpty ? OceanTheme.hint : OceanTheme.mist)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OceanSpacing.insetCompact)
                .padding(.vertical, OceanSpacing.gap)
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
        .frame(minHeight: minHeight, maxHeight: maxHeight)
        .background(OceanTheme.fill, in: RoundedRectangle(cornerRadius: OceanRadius.field, style: .continuous))
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
        // A step less than the live preview: TextEditor keeps its own inner
        // margins, so the words land on the same line as the preview's.
        .padding(.horizontal, OceanSpacing.gap)
        .padding(.vertical, OceanSpacing.snug)
        .background(OceanTheme.fill, in: RoundedRectangle(cornerRadius: OceanRadius.field, style: .continuous))
    }

    private var baseEditor: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .font(OceanType.body)
            .foregroundStyle(OceanTheme.foam)
            .overlay(alignment: .topLeading) {
                if text.trimmed.isEmpty {
                    Text(placeholder)
                        .font(OceanType.body)
                        .foregroundStyle(OceanTheme.hint)
                        // TextEditor's own text inset, so the placeholder sits
                        // exactly where the first typed word lands.
                        .padding(.top, OceanSpacing.gap)
                        .padding(.leading, OceanSpacing.tight + 1)
                        .allowsHitTesting(false)
                }
            }
    }
}
