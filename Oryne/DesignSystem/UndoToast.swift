import SwiftUI

/// The way back after a thought is deleted or archived: what happened, and
/// Undo. `OceanToast`, the one toast, with the removal's own words.
struct UndoToast: View {
    /// Already localized: VoiceOver announces the same words.
    let message: String
    var onUndo: () -> Void

    var body: some View {
        OceanToast(message: message, actionTitle: "Undo", action: onUndo)
    }
}
