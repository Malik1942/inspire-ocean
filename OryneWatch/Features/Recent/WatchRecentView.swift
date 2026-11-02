import SwiftUI

/// The wrist takes, newest first (watch redesign spec §1). The Crown scrolls
/// the list; a row opens its thought.
struct WatchRecentView: View {
    let rows: [WristRow]

    var body: some View {
        List(rows) { row in
            NavigationLink(value: row) {
                RecentRow(row: row)
            }
        }
        .navigationTitle(Text("Recent"))
    }
}

/// A take's name (or the time it was caught, until the phone names it),
/// when and how long, and whether it still waits for the phone.
private struct RecentRow: View {
    let row: WristRow

    var body: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.snug) {
            Group {
                if let title = row.title {
                    Text(title)
                        .oceanText(OceanWatchType.serif)
                } else {
                    Text(row.caughtAt, style: .time)
                        .oceanText(OceanWatchType.body)
                }
            }
            .foregroundStyle(OceanTheme.foam)
            .lineLimit(2)
            // One Text, so the age and the length wrap as one line at
            // larger text sizes.
            (Text(row.caughtAt, format: .relative(presentation: .named)) + Text(verbatim: durationSuffix))
                .oceanText(OceanWatchType.meta)
                .foregroundStyle(OceanTheme.mist)
            if row.isWaiting {
                Text("Waiting for iPhone")
                    .oceanText(OceanWatchType.meta)
                    .foregroundStyle(OceanTheme.mist)
            }
        }
    }

    /// The take's length after its age (" · 1:23"); empty for a thought the
    /// watch holds no take for.
    private var durationSuffix: String {
        guard let duration = row.duration else { return "" }
        return " · " + String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}
