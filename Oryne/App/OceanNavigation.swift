import SwiftUI

/// Where a page can go: the places of the Ocean. Places push, the way a
/// native stack drills in (a thought's page, a current, Archived), with
/// the back swipe and the tab bar stepping away; tasks rise as sheets and
/// pull down (edit, grow a branch, move, merge, settings, capture), always
/// one level deep over a pushed page, never over another sheet. Every
/// tab's stack resolves these the same way (`oceanDestinations`).
enum OceanDestination: Hashable {
    case thought(Node)
    case current(String)
    case archived
}

extension View {
    /// The one resolution of the Ocean's places, on a tab's `NavigationStack`.
    func oceanDestinations(path: Binding<NavigationPath>) -> some View {
        navigationDestination(for: OceanDestination.self) { destination in
            switch destination {
            case .thought(let node): NodeDetailContent(node: node)
            case .current(let key): ClusterStreamView(theme: key, path: path)
            case .archived: ArchivedThoughtsView(path: path)
            }
        }
    }
}
