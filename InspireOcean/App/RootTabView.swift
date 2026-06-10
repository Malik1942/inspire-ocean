import SwiftUI

/// Primary navigation (§13): Capture · Ocean · Ask · Library.
/// Library is the structured fallback "for accessibility and trust".
struct RootTabView: View {
    @State private var appState = AppState()

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            CaptureView()
                .tabItem { Label("Capture", systemImage: "plus.circle") }
                .tag(OceanTab.capture)

            OceanFieldView()
                .tabItem { Label("Ocean", systemImage: "water.waves") }
                .tag(OceanTab.ocean)

            AskView()
                .tabItem { Label("Ask", systemImage: "bubble.left") }
                .tag(OceanTab.ask)

            LibraryView()
                .tabItem { Label("Library", systemImage: "rectangle.stack") }
                .tag(OceanTab.library)
        }
        .environment(appState)
    }
}
