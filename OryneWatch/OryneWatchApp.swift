import SwiftUI
import AppIntents

@main
struct OryneWatchApp: App {
    private let model: WatchCaptureModel

    init() {
        let queue = TakeQueue()
        let cloud = CloudInbox.makeIfAvailable()
        let sync = TakeSync(queue: queue, link: PhoneLink(), cloud: cloud)
        let model = WatchCaptureModel(queue: queue, sync: sync)
        self.model = model
        // The Action Button and Siri reach the same model the screen shows.
        AppDependencyManager.shared.add { model }
        sync.start()
        #if DEBUG
        model.applyDemoEnvironment()
        WatchSelfTest.runIfRequested(model: model, cloudAvailable: cloud != nil)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchCaptureView(model: model)
                .onOpenURL { url in
                    // The complication: same rule as the Action Button.
                    guard WatchDeepLink.isCatch(url) else { return }
                    Task { await model.toggle() }
                }
        }
        .backgroundTask(.appRefresh(TakeSync.refreshIdentifier)) { [model] in
            await model.backgroundRefresh()
        }
    }
}
