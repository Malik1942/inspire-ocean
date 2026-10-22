import SwiftUI

/// The link the composer's tile shows, sensed from the words, and the
/// links taken off the card. The tile follows the field half a second
/// behind, so a link still being typed never flickers in; a paste, a seed
/// or a draft brought back shows its link at once. A release senses the
/// words afresh (`chosen(in:)`).
@MainActor
@Observable
final class CaptureLinkSensor {
    /// Links taken off the card with the tile's ✕: they stay in the words
    /// as text and are never attached.
    var dismissed: Set<String> = []
    /// The link the tile shows.
    private(set) var sensed: LinkSensing.Sensed?
    @ObservationIgnored private var senseTask: Task<Void, Never>?

    /// The link a release of `text` would attach right now: its first link
    /// the user has not taken off the card.
    func chosen(in text: String) -> LinkSensing.Sensed? {
        LinkSensing.chosen(in: text, dismissed: dismissed)
    }

    /// The tile follows `text` half a second behind; `now` shows its link
    /// at once.
    func sense(_ text: String, now: Bool = false) {
        senseTask?.cancel()
        guard !now else {
            sensed = chosen(in: text)
            return
        }
        senseTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { sensed = chosen(in: text) }
        }
    }

    /// The tile's ✕: the link stays in the words as text and is never
    /// attached; the words' next link, if any, takes the tile.
    func dismiss(_ urlString: String, in text: String) {
        dismissed.insert(urlString)
        withAnimation(.snappy) { sensed = chosen(in: text) }
    }

    /// Lets go of a sense still waiting out its half second.
    func cancelPending() {
        senseTask?.cancel()
    }

    /// The next thought: no tile, nothing taken off.
    func reset() {
        cancelPending()
        dismissed = []
        sensed = nil
    }
}
