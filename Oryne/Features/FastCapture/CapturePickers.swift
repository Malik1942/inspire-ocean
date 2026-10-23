import SwiftUI
import UIKit
import PhotosUI

/// The composer's two full pickers, opened from the + panel: the system
/// camera, full screen, for one shot, and All Photos, for as many as the
/// thought has room for. Closing either, with or without a pick, hands
/// the keyboard back to the words (`onClose`).
struct CapturePickers: ViewModifier {
    @Binding var cameraShown: Bool
    @Binding var libraryShown: Bool
    /// Pictures the thought can still take.
    let room: Int
    /// The camera's shot, once it has closed.
    let onShot: (UIImage) -> Void
    /// All Photos' picks, in the order picked.
    let onPick: ([PhotosPickerItem]) -> Void
    let onClose: () -> Void

    @State private var libraryItems: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $cameraShown, onDismiss: onClose) {
                CameraPicker { shot in
                    cameraShown = false
                    if let shot { onShot(shot) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $libraryShown,
                selection: $libraryItems,
                maxSelectionCount: max(room, 1),
                selectionBehavior: .ordered,
                matching: .images
            )
            .onChange(of: libraryItems) { _, items in
                guard !items.isEmpty else { return }
                libraryItems = []
                onPick(items)
            }
            .onChange(of: libraryShown) { _, shown in
                if !shown { onClose() }
            }
    }
}

extension View {
    /// The composer's camera and All Photos pickers.
    func capturePickers(
        cameraShown: Binding<Bool>,
        libraryShown: Binding<Bool>,
        room: Int,
        onShot: @escaping (UIImage) -> Void,
        onPick: @escaping ([PhotosPickerItem]) -> Void,
        onClose: @escaping () -> Void
    ) -> some View {
        modifier(CapturePickers(
            cameraShown: cameraShown,
            libraryShown: libraryShown,
            room: room,
            onShot: onShot,
            onPick: onPick,
            onClose: onClose
        ))
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
