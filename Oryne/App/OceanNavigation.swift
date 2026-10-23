import SwiftUI

/// How pages open in Oryne: they rise. A thought, a current, Archived and
/// every task (edit, grow a branch, move, merge, settings, capture) come
/// up as sheets and pull down to leave; nothing slides in from the side.
/// Inside a sheet, a thought's branches and neighbours open in place: the
/// page crossfades to the next thought, with a back tool where the
/// system's would be, so the whole product moves one way.
struct OceanFadeStack<Root: View>: View {
    /// The thoughts opened from the root, last on top.
    @Binding var path: [Node]
    @ViewBuilder let root: () -> Root

    var body: some View {
        ZStack {
            if let node = path.last {
                NodeDetailContent(node: node)
                    .id(node.id)
                    .transition(.opacity)
            } else {
                root()
                    .transition(.opacity)
            }
        }
        .animation(OceanMotion.standard, value: path.map(\.id))
        .environment(\.openThought) { node in path.append(node) }
        .environment(\.popThought, path.isEmpty ? nil : { _ = path.popLast() })
    }
}

extension EnvironmentValues {
    /// Opens a thought in place on the sheet's fade stack.
    @Entry var openThought: (Node) -> Void = { _ in }
    /// The way back to the thought beneath, when there is one.
    @Entry var popThought: (() -> Void)? = nil
}
