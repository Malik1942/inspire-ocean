import SwiftUI
import AppIntents
import WatchKit

@main
struct OryneWatchApp: App {
    private let model: WatchCaptureModel
    private let library: WristLibrary
    private let link: PhoneLink

    init() {
        // Fetched audio is for one listen; anything left from the last run goes.
        PlaybackCache.clear()
        let queue = TakeQueue()
        let cloud = CloudInbox.makeIfAvailable()
        let link = PhoneLink()
        let library = WristLibrary()
        let sync = TakeSync(queue: queue, link: link, cloud: cloud, library: library) { date in
            WKApplication.shared().scheduleBackgroundRefresh(
                withPreferredDate: date,
                userInfo: TakeSync.refreshIdentifier as NSString
            ) { _ in }
        }
        let model = WatchCaptureModel(queue: queue, sync: sync, player: WatchPlayer())
        self.model = model
        self.library = library
        self.link = link
        // The Action Button and Siri reach the same model the screen shows.
        AppDependencyManager.shared.add { model }
        sync.start()
        #if DEBUG
        model.applyDemoEnvironment(library: library)
        WatchSelfTest.runIfRequested(model: model, cloudAvailable: cloud != nil)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model, library: library, link: link)
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
