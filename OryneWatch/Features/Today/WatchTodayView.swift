import SwiftUI

/// Today's resurfaced thought (watch redesign spec §1): the same pick as the
/// phone and the widget, its name and the first lines of its reading. Tap
/// opens it, text first. As on its page, a machine summary wears the
/// phone's "Summary" label and the user's own words keep their serif
/// (PHILOSOPHY §3).
struct WatchTodayView: View {
    let row: WristRow

    var body: some View {
        NavigationLink(value: row) {
            VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                Text("Today")
                    .oceanText(OceanWatchType.label)
                    .foregroundStyle(OceanTheme.mist)
                if let title = row.title {
                    Text(title)
                        .oceanText(OceanWatchType.title)
                        .foregroundStyle(OceanTheme.foam)
                        .lineLimit(3)
                }
                if let reading = row.reading {
                    if row.readingIsSummary {
                        // Nearer the words it names than the title above.
                        Label("Summary", systemImage: "sparkles")
                            .oceanText(OceanWatchType.label)
                            .foregroundStyle(OceanTheme.mist)
                            .padding(.top, OceanSpacing.tight)
                    }
                    Text(reading)
                        .oceanText(row.readingIsSummary ? OceanWatchType.body : OceanWatchType.serif)
                        .foregroundStyle(row.readingIsSummary ? OceanTheme.text : OceanTheme.coolWords)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding(.horizontal)
        }
        .buttonStyle(.plain)
        .background(OceanTheme.abyss.ignoresSafeArea())
    }
}
