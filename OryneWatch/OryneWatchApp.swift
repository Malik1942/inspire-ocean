import SwiftUI

@main
struct OryneWatchApp: App {
    private let model: WatchCaptureModel

    init() {
        let queue = TakeQueue()
        let cloud = CloudInbox.makeIfAvailable()
        let sync = TakeSync(queue: queue, link: PhoneLink(), cloud: cloud)
        let model = WatchCaptureModel(queue: queue, sync: sync)
        self.model = model
        sync.start()
        #if DEBUG
        model.applyDemoEnvironment()
        WatchSelfTest.runIfRequested(model: model, cloudAvailable: cloud != nil)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchCaptureView(model: model)
        }
        .backgroundTask(.appRefresh(TakeSync.refreshIdentifier)) { [model] in
            await model.backgroundRefresh()
        }
    }
}
