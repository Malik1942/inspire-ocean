import SwiftUI
import PhotosUI

/// The pictures on the composer's card and the loads behind their quiet
/// tiles. Every way a picture arrives comes through here: the + panel's
/// strip, All Photos, the camera, the Action Button's screenshot and
/// Undo. The rules (pick order, the room left, a send that waits for
/// pictures still loading) are `CapturePictureSlots`; this runs the loads
/// off the main actor and fills the places they hold.
@MainActor
@Observable
final class CapturePictureLoader {
    private var state = CapturePictureSlots<CaptureImage>(limit: Node.maxImages)
    /// The loads behind the loading tiles, so a tile's ✕ can let them go.
    @ObservationIgnored private var loadTasks: [UUID: Task<Void, Never>] = [:]

    /// Bumped when a send that waited for pictures can go: the last of
    /// them landed, or a loading tile's ✕ let the rest go. The composer
    /// sends then, if it still holds the card.
    private(set) var sendReadyCount = 0

    /// The card's places in pick order: pictures, and quiet tiles for the
    /// ones still loading.
    var slots: [CapturePictureSlots<CaptureImage>.Slot] { state.slots }
    /// The pictures that have landed, in order.
    var images: [CaptureImage] { state.pictures }
    var isLoading: Bool { state.isLoading }
    /// A send is waiting for pictures still loading.
    var sendWaiting: Bool { state.sendWaiting }
    /// Pictures the thought can still take (`Node.maxImages` in all).
    var room: Int { state.room }

    /// Picked photos join the card in the order picked, each shrunk to the
    /// attachment size first, as many as the thought has room for; a quiet
    /// tile holds each one's place meanwhile. Returns how many fit.
    @discardableResult
    func attach(_ items: [PhotosPickerItem]) -> Int {
        guard let reservation = state.reserve(items.count) else { return 0 }
        let fits = Array(items.prefix(reservation.count))
        load(reservation) { await ImageDownsampler.attachmentData(from: fits) }
        return reservation.count
    }

    /// The camera's shot, shrunk off the main actor like a picked photo.
    func attachShot(_ shot: UIImage) {
        guard let reservation = state.reserve(1) else { return }
        load(reservation) {
            let data = await Task.detached {
                shot.jpegData(compressionQuality: 0.9).flatMap {
                    ImageDownsampler.downsample($0, maxPixel: ImageDownsampler.Size.attachment)
                }
            }.value
            return [data].compactMap { $0 }
        }
    }

    /// The Action Button's screenshot, the card's first picture, decoded
    /// once, off the main actor. Returns once it is on the card.
    func attachScreenshot(_ data: Data, animation: Animation) async {
        let shot = await CaptureImage.make(from: [data])
        withAnimation(animation) {
            if let reservation = state.reserve(1, atFront: true) {
                state.fill(reservation.id, with: shot)
            }
        }
    }

    /// Undo: the pictures come back through their loading tiles, decoded
    /// off the main actor; a send meanwhile waits for them.
    func restore(_ datas: [Data]) {
        replace(with: [])
        guard let reservation = state.reserve(datas.count) else { return }
        load(reservation) { datas }
    }

    /// Starts over with these pictures (a draft brought back, the next
    /// thought): nothing loading, no send waiting.
    func replace(with images: [CaptureImage]) {
        letGoOfLoads()
        state.replace(with: images)
    }

    /// A picture's ✕.
    func remove(_ id: CaptureImage.ID) {
        withAnimation(.snappy) { state.remove(id) }
    }

    /// A loading tile's ✕: the pictures still on their way are let go, and
    /// a send that was waiting for them goes with what has landed.
    func cancelLoading() {
        letGoOfLoads()
        let ready = withAnimation(.snappy) { state.cancelLoading() }
        if ready { sendReadyCount &+= 1 }
    }

    /// The send was tapped: true when it can go now. With pictures still
    /// loading it waits for them (`sendReadyCount`).
    func requestSend() -> Bool {
        state.requestSend()
    }

    /// The composer closed: a send that was waiting no longer goes.
    func callOffSend() {
        state.callOffSend()
    }

    /// Loads `reservation`'s pictures and puts them in its places. Loaded
    /// pictures take their tiles' places; a send that waited goes once the
    /// last one is in.
    private func load(_ reservation: CapturePictureSlots<CaptureImage>.Reservation, datas: @escaping () async -> [Data]) {
        let id = reservation.id
        loadTasks[id] = Task {
            let fresh = await CaptureImage.make(from: await datas())
            // Let go by a loading tile's ✕: its tiles are already gone.
            guard !Task.isCancelled else { return }
            loadTasks[id] = nil
            let ready = withAnimation(.snappy) { state.fill(id, with: fresh) }
            if ready { sendReadyCount &+= 1 }
        }
    }

    private func letGoOfLoads() {
        loadTasks.values.forEach { $0.cancel() }
        loadTasks = [:]
    }
}
