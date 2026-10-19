import SwiftUI

@main
struct OryneWatchApp: App {
    init() {
        #if DEBUG
        WatchSelfTest.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            OceanTheme.abyss.ignoresSafeArea()
        }
    }
}
