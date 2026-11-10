import SwiftUI

/// How pages open in Oryne: they rise. A thought, a current, Archived and
/// every task (edit, grow a branch, move, merge, settings, capture) come
/// up as sheets and pull down to leave; nothing slides in from the side.
/// Inside a sheet, a thought's branches and neighbours open in place: the
/// page crossfades to the next thought, with a back tool where the
/// system's would be, so the whole product moves one way.
///
/// Beside a split page (iPhone Duo) these stand in halves instead
/// (`closePane`, `BesidePages`), and in the leading half the stack lets go
/// of the room it keeps for the toolbar column (`paneEdges`).
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
        .paneEdges()
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
    /// Closes the half a thought or a current stands in beside a split page
    /// (iPhone Duo's inner display, turned): what leaving does there, where
    /// a sheet would be dismissed. nil in a sheet.
    @Entry var closePane: (() -> Void)? = nil
    /// Which half that is; nil in a sheet.
    @Entry var paneSide: BigScreen.Side? = nil
    /// Opens a page in the half across from that one, where a sheet would
    /// rise over both (`BesidePages`, `besideSheet`); nil in a sheet.
    @Entry var openBeside: BesidePages.Opener? = nil
}

extension View {
    /// Lets go of the room a navigation stack keeps down its trailing side in
    /// the leading half beside a split page: the upright toolbar column it
    /// keeps that room for stands at the other half's edge, so the page's
    /// words reach their own gutter. Applied inside the stack.
    func paneEdges() -> some View { modifier(PaneEdges()) }
}

private struct PaneEdges: ViewModifier {
    @Environment(\.paneSide) private var paneSide

    func body(content: Content) -> some View {
        content.ignoresSafeArea(.container, edges: paneSide == .leading ? .trailing : [])
    }
}
