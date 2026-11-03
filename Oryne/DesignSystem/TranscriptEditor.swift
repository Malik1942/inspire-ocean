import SwiftUI

/// The transcript surface shared by three moments: the live preview while a
/// whisper is being caught (read-only, words drifting in), the post-capture
/// review (editable, before release), and the node editor (editable, after).
///
/// Deliberately dumb — a binding and a flag; the surrounding card decides
/// everything else.
///
/// The user's words are set as they will be kept, in New York
/// (`inputWords`); Oryne's placeholder stays SF. Its height is counted in
/// lines of those words at the current text size, from `minLines` to
/// `maxLines`, so a larger text size gets the same room to write.
struct TranscriptEditor: View {
    @Binding var text: String
    var isEditable: Bool = true
    var placeholder: LocalizedStringKey = ""
    var minLines: Int = 4
    var maxLines: Int = 8
    var focus: FocusState<Bool>.Binding? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    /// TextEditor's own text insets, 8 pt above and below its lines, which
    /// the live preview matches with its padding.
    private static let textInsets: CGFloat = 16 // art-directed: TextEditor's own 8 pt top and bottom insets

    var body: some View {
        Group {
            if isEditable {
                editor
            } else {
                livePreview
            }
        }
    }

    /// The frame that holds `lines` lines of the words, with the text
    /// insets, counted as the editor's text view sets them.
    private func height(lines: Int) -> CGFloat {
        OceanType.inputWords.fieldHeight(ofLines: lines, at: typeSize) + Self.textInsets
    }

    private var lowest: CGFloat { height(lines: minLines) }
    private var tallest: CGFloat { height(lines: maxLines) }

    /// Read-only, kept scrolled to the newest words; dimmed like something
    /// still forming.
    private var livePreview: some View {
        ScrollView {
            (text.isEmpty ? Text(placeholder) : Text(text))
                .oceanText(text.isEmpty ? OceanType.body : OceanType.inputWords)
                .foregroundStyle(OceanTheme.mist)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OceanSpacing.insetCompact)
                .padding(.vertical, OceanSpacing.gap)
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
        .frame(minHeight: lowest, maxHeight: tallest)
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
        .frame(minHeight: lowest, maxHeight: tallest)
        // A step less than the live preview: TextEditor keeps its own inner
        // margins, so the words land on the same line as the preview's.
        .padding(.horizontal, OceanSpacing.gap)
        .padding(.vertical, OceanSpacing.snug)
        .background(OceanTheme.fill, in: RoundedRectangle(cornerRadius: OceanRadius.field, style: .continuous))
    }

    private var baseEditor: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .oceanFieldText(OceanType.inputWords)
            .foregroundStyle(OceanTheme.foam)
            .overlay(alignment: .topLeading) {
                if text.trimmed.isEmpty {
                    Text(placeholder)
                        .oceanText(OceanType.body)
                        .foregroundStyle(OceanTheme.mist)
                        // TextEditor's own text inset, so the placeholder sits
                        // exactly where the first typed word lands.
                        .padding(.top, OceanSpacing.gap) // art-directed: TextEditor's own 8 pt inset and 5 pt line padding
                        .padding(.leading, OceanSpacing.tight + 1) // art-directed: TextEditor's own 8 pt inset and 5 pt line padding
                        .allowsHitTesting(false)
                }
            }
    }
}
