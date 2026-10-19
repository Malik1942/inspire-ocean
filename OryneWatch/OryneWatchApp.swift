import SwiftUI

@main
struct OryneWatchApp: App {
    private let queue: TakeQueue
    private let sync: TakeSync

    init() {
        let queue = TakeQueue()
        let cloud = CloudInbox.makeIfAvailable()
        let sync = TakeSync(queue: queue, link: PhoneLink(), cloud: cloud)
        self.queue = queue
        self.sync = sync
        sync.start()
        #if DEBUG
        WatchSelfTest.runIfRequested(sync: sync, cloudAvailable: cloud != nil)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            OceanTheme.abyss.ignoresSafeArea()
        }
        .backgroundTask(.appRefresh(TakeSync.refreshIdentifier)) { [sync] in
            await sync.flush()
        }
    }
}
