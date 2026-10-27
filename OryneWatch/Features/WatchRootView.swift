import SwiftUI

/// The wrist's vertical pages (watch redesign spec §1): Capture, where the
/// app always opens; Today, when a thought is rising today; and Recent. The
/// Crown or a swipe moves between them; a thought opens on top, and the
/// system's edge swipe comes back. Any recording entry (the Action Button,
/// the complication, Siri) brings Capture back first.
struct WatchRootView: View {
    let model: WatchCaptureModel
    let library: WristLibrary
    let link: PhoneLink

    private enum Page: Hashable {
        case capture, today, recent
    }

    @State private var page: Page = .capture
    @State private var path: [WristRow] = []

    var body: some View {
        let rows = recentRows
        let today = todayRow
        NavigationStack(path: $path) {
            TabView(selection: $page) {
                WatchCaptureView(model: model).tag(Page.capture)
                if let today {
                    WatchTodayView(row: today).tag(Page.today)
                }
                if !rows.isEmpty {
                    WatchRecentView(rows: rows).tag(Page.recent)
                }
            }
            .tabViewStyle(.verticalPage)
            .navigationDestination(for: WristRow.self) { row in
                WatchThoughtView(model: WatchThoughtModel(row: row, queue: model.queue, player: model.player, link: link))
            }
        }
        .onChange(of: model.stage) { _, stage in
            guard stage == .starting || stage == .recording else { return }
            path = []
            page = .capture
        }
        #if DEBUG
        .onAppear(perform: applyDemoPage)
        #endif
    }

    private var recentRows: [WristRow] {
        WristRecent.rows(queue: model.queue.state, snapshot: library.snapshot) { model.queue.hasAudio($0) }
    }

    private var todayRow: WristRow? {
        WristRecent.today(snapshot: library.snapshot, queue: model.queue.state, now: .now) { model.queue.hasAudio($0) }
    }

    #if DEBUG
    /// Screenshot seam: `ORYNE_WATCH_PAGE=today|recent|thought` opens that
    /// page; `thought` opens Today's thought, else the newest take.
    private func applyDemoPage() {
        switch ProcessInfo.processInfo.environment["ORYNE_WATCH_PAGE"] {
        case "today": page = .today
        case "recent": page = .recent
        case "thought": if let row = todayRow ?? recentRows.first { path = [row] }
        default: break
        }
    }
    #endif
}
