import SwiftUI

/// Today's resurfaced thought (watch redesign spec §1): the same pick as the
/// phone and the widget, its name and the first lines of its reading. Tap
/// opens it, text first.
struct WatchTodayView: View {
    let row: WristRow

    var body: some View {
        NavigationLink(value: row) {
            VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                Text("Today")
                    .font(OceanType.eyebrow)
                    .foregroundStyle(OceanTheme.mist)
                if let title = row.title {
                    Text(title)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(OceanTheme.foam)
                        .lineLimit(3)
                }
                if let reading = row.reading {
                    Text(reading)
                        .font(OceanType.meta)
                        .foregroundStyle(OceanTheme.text)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .background(OceanTheme.abyss.ignoresSafeArea())
    }
}
