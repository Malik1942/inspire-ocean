import SwiftUI

/// One thought on the wrist (watch redesign spec §1): its name, a short
/// reading, and its recording. The Crown scrolls; play sits in the bottom
/// toolbar while the words stay on screen. A machine summary wears the
/// phone's "Summary" label (PHILOSOPHY §3).
struct WatchThoughtView: View {
    @State private var model: WatchThoughtModel
    @Environment(\.scenePhase) private var scenePhase

    init(model: WatchThoughtModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                if let title = model.row.title {
                    Text(title)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(OceanTheme.foam)
                }
                notice
                reading
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
        .background(OceanTheme.abyss.ignoresSafeArea())
        .toolbar {
            if model.audio != .none {
                ToolbarItemGroup(placement: .bottomBar) {
                    playControl
                }
            }
        }
        .onAppear { model.appeared() }
        .onDisappear { model.leave() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.sceneWentInactive() }
        }
    }

    @ViewBuilder private var reading: some View {
        if let reading = model.row.reading {
            if model.row.readingIsSummary {
                Label("Summary", systemImage: "sparkles")
                    .font(OceanType.eyebrow)
                    .foregroundStyle(OceanTheme.mist)
            }
            Text(reading)
                .font(OceanType.body)
                .foregroundStyle(OceanTheme.text)
            if model.row.continues {
                Text("Continues on iPhone")
                    .font(OceanType.note)
                    .foregroundStyle(OceanTheme.mist)
            }
        } else if model.row.isVoice {
            Text("Not transcribed yet")
                .font(OceanType.meta)
                .foregroundStyle(OceanTheme.mist)
        }
    }

    /// Stays until tapped.
    @ViewBuilder private var notice: some View {
        switch model.audio {
        case .phoneAway: noticeButton(Text("Your iPhone isn't nearby"))
        case .failed: noticeButton(Text("Couldn't get the audio"))
        default: EmptyView()
        }
    }

    private func noticeButton(_ text: Text) -> some View {
        Button { model.dismissNotice() } label: {
            text
                .font(OceanType.meta)
                .foregroundStyle(OceanTheme.foam)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var playControl: some View {
        if model.audio == .fetching {
            Text("Getting audio…")
                .font(OceanType.note)
                .foregroundStyle(OceanTheme.mist)
        } else {
            Button { Task { await model.togglePlay() } } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(model.isPlaying ? Text("Pause") : Text("Play"))
            if model.isPlayerOnThis {
                Text(verbatim: "\(Self.time(model.player.elapsed)) / \(Self.time(model.player.duration))")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(OceanTheme.mist)
            }
        }
    }

    private static func time(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
