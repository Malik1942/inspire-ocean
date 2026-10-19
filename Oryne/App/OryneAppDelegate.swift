import UIKit

/// Receives the iCloud inbox's silent push. The SwiftData mirror handles its
/// own pushes; any notification that isn't the watch inbox subscription is
/// left alone.
final class OryneAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard WatchInboxReader.isInboxPush(userInfo) else { return .noData }
        return await WatchBridge.shared.refresh() ? .newData : .noData
    }
}
