import Foundation

/// The pictures on the composer's card, in the order they were picked.
/// Each pick holds its place from the moment it is picked (a quiet tile
/// while it loads), so a slow load never lands behind a later, faster one.
/// A send tapped while pictures are still loading waits for them.
///
/// Pure rules: the composer's `CapturePictureLoader` runs the loads and
/// the card draws the slots.
struct CapturePictureSlots<Picture: Identifiable> where Picture.ID == UUID {

    /// One place on the card.
    enum Slot: Identifiable {
        /// Held for a picture still loading, by the load that brings it.
        case loading(id: UUID, load: UUID)
        case picture(Picture)

        var id: UUID {
            switch self {
            case .loading(let id, _): id
            case .picture(let picture): picture.id
            }
        }

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    /// The places held for one load: the pictures picked together.
    struct Reservation {
        /// The load's id, which fills its places when it lands.
        let id: UUID
        /// How many of the picks fit.
        let count: Int
    }

    /// Pictures a thought can hold, loading ones included.
    let limit: Int
    private(set) var slots: [Slot]
    /// The send was tapped while pictures were still loading: it goes once
    /// they are in, so a release never leaves one behind.
    private(set) var sendWaiting = false

    init(limit: Int, pictures: [Picture] = []) {
        self.limit = limit
        slots = pictures.map(Slot.picture)
    }

    /// The pictures that have landed, in order.
    var pictures: [Picture] {
        slots.compactMap { slot in
            if case .picture(let picture) = slot { return picture }
            return nil
        }
    }

    var loadingCount: Int { slots.filter(\.isLoading).count }
    var isLoading: Bool { slots.contains(where: \.isLoading) }

    /// Pictures the thought can still take.
    var room: Int { max(0, limit - slots.count) }

    /// Holds places for `count` picks, as many as there is room for, after
    /// the rest (or before them: the Action Button's screenshot is the
    /// card's first picture). Nil when none fit.
    mutating func reserve(_ count: Int, atFront: Bool = false) -> Reservation? {
        let fits = min(count, room)
        guard fits > 0 else { return nil }
        let load = UUID()
        let places = (0..<fits).map { _ in Slot.loading(id: UUID(), load: load) }
        slots.insert(contentsOf: places, at: atFront ? 0 : slots.endIndex)
        return Reservation(id: load, count: fits)
    }

    /// A load landed: its pictures take its places in order, and places
    /// left over (pictures that couldn't be read) go. A load let go lands
    /// on nothing. True when a send was waiting and nothing loads now: it
    /// goes. Either way the wait is over once nothing loads, so a later
    /// load (an Undo's) never sends on its own.
    @discardableResult
    mutating func fill(_ load: UUID, with pictures: [Picture]) -> Bool {
        let places = slots.indices.filter { index in
            if case .loading(_, let owner) = slots[index] { return owner == load }
            return false
        }
        guard !places.isEmpty else { return false }
        for (place, picture) in zip(places, pictures) {
            slots[place] = .picture(picture)
        }
        for place in places.dropFirst(pictures.count).reversed() {
            slots.remove(at: place)
        }
        return endWaitIfLoaded()
    }

    /// A loading tile's ✕: every place still loading goes. True when a send
    /// was waiting for them: it goes now with what landed.
    mutating func cancelLoading() -> Bool {
        slots.removeAll(where: \.isLoading)
        return endWaitIfLoaded()
    }

    /// The send was tapped: true when it can go now, false when it waits
    /// for the pictures still loading.
    mutating func requestSend() -> Bool {
        guard isLoading else { return true }
        sendWaiting = true
        return false
    }

    /// The composer closed: a send that was waiting no longer goes.
    mutating func callOffSend() {
        sendWaiting = false
    }

    /// A picture's ✕.
    mutating func remove(_ id: UUID) {
        slots.removeAll { $0.id == id }
    }

    /// Starts over with these pictures: nothing loading, no send waiting.
    mutating func replace(with pictures: [Picture]) {
        slots = pictures.map(Slot.picture)
        sendWaiting = false
    }

    private mutating func endWaitIfLoaded() -> Bool {
        guard !isLoading else { return false }
        defer { sendWaiting = false }
        return sendWaiting
    }
}
