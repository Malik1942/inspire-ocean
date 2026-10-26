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
        VStack(alignment: .leading, spacing: OceanSpacing.tight) {
            Group {
                if let title = row.title {
                    Text(title)
                } else {
                    Text(row.caughtAt, style: .time)
                }
            }
            // The wrist's title role: the meta line's size in the serif.
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(OceanTheme.foam)
            .lineLimit(2)
            HStack(spacing: OceanSpacing.tight) {
                Text(row.caughtAt, format: .relative(presentation: .named))
                if let duration = row.duration {
                    Text(verbatim: String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60))
                }
            }
            .font(OceanType.note)
            .foregroundStyle(OceanTheme.mist)
            if row.isWaiting {
                Text("Waiting for iPhone")
                    .font(OceanType.note)
                    .foregroundStyle(OceanTheme.mist)
            }
        }
    }
}
