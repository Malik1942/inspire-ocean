import SwiftUI
import PhotosUI

/// What the composer's + shows in the keyboard's place, as Messages does:
/// a strip of the latest photos (a tap attaches one and the keyboard comes
/// back), then Camera and All Photos. The strip is the system's own picker
/// drawn in place, out of process, so Oryne never reads the library and
/// never asks for access. It lives in the overlay, never in a sheet: the
/// embedded picker takes a sheet over (full height, see-through), so inside
/// a current's sheet the panel has only its rows.
struct CaptureAttachPanel: View {
    var showsStrip = true
    var onPick: (PhotosPickerItem) -> Void
    var onCamera: () -> Void
    var onLibrary: () -> Void

    @State private var selection: [PhotosPickerItem] = []
    /// The first tap is the pick: the strip takes no second one while the
    /// panel steps away.
    @State private var picked = false

    private enum Row: Hashable { case camera, library }
    /// VoiceOver moves to the first row when the panel opens: the panel
    /// took the keyboard's place, so that is where the next swipe goes.
    @AccessibilityFocusState private var focusedRow: Row?

    /// Between the strip and the rows.
    private static let spacing: CGFloat = OceanSpacing.gap
    /// The strip never shrinks below a row of thumbnails you can hit.
    private static let leastStripHeight: CGFloat = 120
    /// An iPhone's keyboard, upright or turned, for a width none has shown
    /// at yet.
    static func usualKeyboardHeight(turned: Bool) -> CGFloat { turned ? 207 : 336 }

    /// The least the panel needs: its rows, and the strip when it has one.
    static func leastHeight(showsStrip: Bool) -> CGFloat {
        let rows = CGFloat(CameraPicker.isAvailable ? 2 : 1) * OceanControlSize.height
        let strip = showsStrip ? leastStripHeight + spacing : 0
        return rows + strip + 2 * FastCaptureLayout.cardInset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            if showsStrip {
                PhotosPicker(
                    selection: $selection,
                    maxSelectionCount: 1,
                    selectionBehavior: .continuous,
                    matching: .images
                ) {
                    EmptyView()
                }
                .photosPickerStyle(.compact)
                .photosPickerDisabledCapabilities([.search, .collectionNavigation, .stagingArea, .selectionActions])
                .photosPickerAccessoryVisibility(.hidden, edges: .all)
                .frame(minHeight: Self.leastStripHeight, maxHeight: .infinity)
                // Concentric with the panel's corner, as the card's tiles are.
                .clipShape(RoundedRectangle(cornerRadius: CaptureAttachments.tileRadius, style: .continuous))
                .allowsHitTesting(!picked)
                .onChange(of: selection) { _, items in
                    guard !picked, let item = items.first else { return }
                    picked = true
                    onPick(item)
                }
            }
            VStack(spacing: 0) {
                if CameraPicker.isAvailable {
                    row("Camera", systemImage: "camera", action: onCamera)
                        .accessibilityFocused($focusedRow, equals: .camera)
                }
                row("All Photos", systemImage: "photo.on.rectangle", action: onLibrary)
                    .accessibilityFocused($focusedRow, equals: .library)
            }
            // The panel stands in the keyboard's place, and its height counts
            // on 44 pt rows: their words grow up to the second accessibility
            // size, the largest whose line still fits a row. Past it a long
            // press shows a row's name large.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        // The card's own inset and glass: the two read as one family.
        .padding(FastCaptureLayout.cardInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OceanBarBackground(cornerRadius: FastCaptureLayout.cardRadius, style: .continuous))
        // Taps on its margins stay on the panel instead of reaching open
        // water behind it, which would put the card away.
        .contentShape(RoundedRectangle(cornerRadius: FastCaptureLayout.cardRadius, style: .continuous))
        .task {
            // Once the panel has risen into place, so the row is there to
            // land on.
            try? await Task.sleep(for: .milliseconds(400))
            focusedRow = CameraPicker.isAvailable ? .camera : .library
        }
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(OceanType.body)
                .foregroundStyle(OceanTheme.foam)
                .frame(maxWidth: .infinity, minHeight: OceanControlSize.height, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityShowsLargeContentViewer()
    }
}
