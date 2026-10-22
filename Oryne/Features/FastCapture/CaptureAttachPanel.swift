import SwiftUI
import UIKit
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .frame(maxHeight: .infinity)
                // Concentric with the panel's corner, as the card's tiles are.
                .clipShape(RoundedRectangle(cornerRadius: CaptureAttachments.tileRadius, style: .continuous))
                .onChange(of: selection) { _, items in
                    if let item = items.first { onPick(item) }
                }
            }
            VStack(spacing: 0) {
                if CameraPicker.isAvailable {
                    row("Camera", systemImage: "camera", action: onCamera)
                }
                row("All Photos", systemImage: "photo.on.rectangle", action: onLibrary)
            }
        }
        // The card's own inset and glass: the two read as one family.
        .padding(FastCaptureLayout.cardInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OceanBarBackground(cornerRadius: FastCaptureLayout.cardRadius, style: .continuous))
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body)
                .foregroundStyle(OceanTheme.foam)
                .frame(maxWidth: .infinity, minHeight: OceanControlSize.height, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The system camera, for one photo. `UIImagePickerController` is still
/// the only system camera screen an app can present.
struct CameraPicker: UIViewControllerRepresentable {
    /// The shot, or nil when the camera was closed without one.
    var onFinish: (UIImage?) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
