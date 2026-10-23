import SwiftUI
import SwiftData

/// A page's way back from a swiped delete or archive: the one removal its
/// Undo toast offers. A new removal settles the one before it; the window
/// running out, the page closing and the app going to the background settle
/// the last. Settling a delete is the existing `deleteNodeSafely`; if the app
/// is killed first, the thought is left archived, not lost.
@MainActor
@Observable
final class ThoughtRemovals {
    /// As long as a capture can be taken back (`CaptureSession.undoWindow`).
    static let undoWindow: Duration = .seconds(10)

    private(set) var pending: ThoughtRemoval?
    @ObservationIgnored private var window: Task<Void, Never>?

    func delete(_ node: Node) {
        begin(.delete(node))
    }

    func archive(_ node: Node) {
        begin(.archive(node))
    }

    /// The thought is back where it was.
    func undo() {
        guard let removal = pending else { return }
        close()
        removal.undo()
        try? removal.node.modelContext?.save()
    }

    /// The way back closes: a delete goes for good, an archive stays.
    func settle() {
        guard let removal = pending else { return }
        close()
        if removal.kind == .delete, let context = removal.node.modelContext {
            context.deleteNodeSafely(removal.node)
        }
    }

    private func begin(_ removal: ThoughtRemoval) {
        settle()
        try? removal.node.modelContext?.save()
        pending = removal
        AccessibilityNotification.Announcement(removal.message).post()
        window = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.settle()
        }
    }

    private func close() {
        window?.cancel()
        window = nil
        pending = nil
    }
}

/// The swipe's circles, glyph only (the names stay for VoiceOver): a dark
/// slate that keeps or restores, and a deep red that deletes. Darker and a
/// touch more saturated than the system's, so they sit with the matte
/// tiles; without a tint they would take the app's near-white accent.
enum SwipeTint {
    static let archive = Color(red: 0.21, green: 0.24, blue: 0.30)
    static let delete = Color(red: 0.50, green: 0.11, blue: 0.10)
}

extension ThoughtRemoval {
    /// What the toast says, and what VoiceOver hears.
    var message: String {
        switch kind {
        case .delete: String(localized: "Thought deleted")
        case .archive: String(localized: "Thought archived")
        }
    }
}

extension View {
    /// A thought's row in a list: swipe left for Archive and Delete, swipe
    /// all the way to delete, as in Notes: the system's own swipe and
    /// motion. VoiceOver gets the same two as actions on the row.
    func thoughtSwipeActions(_ node: Node, removals: ThoughtRemovals) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { removals.delete(node) } label: {
                Label("Delete", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .tint(SwipeTint.delete)
            Button { removals.archive(node) } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .labelStyle(.iconOnly)
            .tint(SwipeTint.archive)
        }
        // SwiftUI hands these to VoiceOver last first: the rotor reads
        // Archive, then Delete, the way the discs read.
        .accessibilityActions {
            Button("Delete") { removals.delete(node) }
            Button("Archive") { removals.archive(node) }
        }
    }

    /// The page's Undo toast, floating at the bottom of the page.
    func thoughtRemovalToast(_ removals: ThoughtRemovals) -> some View {
        overlay(alignment: .bottom) {
            ZStack {
                if let removal = removals.pending {
                    UndoToast(message: removal.message) { removals.undo() }
                        .id(removal.id)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
            .padding(.bottom, 12)
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: removals.pending?.id)
        }
    }

    /// Settles the page's removals when the page closes or the app goes to
    /// the background. On the page's `NavigationStack`, so opening a thought
    /// from the page does not count as closing it.
    func settlesThoughtRemovals(_ removals: ThoughtRemovals) -> some View {
        modifier(SettleThoughtRemovals(removals: removals))
    }
}

private struct SettleThoughtRemovals: ViewModifier {
    let removals: ThoughtRemovals
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onDisappear { removals.settle() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { removals.settle() }
            }
    }
}
