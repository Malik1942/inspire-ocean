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
        VStack(spacing: OceanSpacing.gap) {
            ScrollView {
                VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                    if let title = model.row.title {
                        Text(title)
                            .oceanText(OceanWatchType.title)
                            .foregroundStyle(OceanTheme.foam)
                    }
                    reading
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scenePadding(.horizontal)
            }
            if model.audio == .phoneAway || model.audio == .failed {
                // The failure is the control: it stays until tapped, and
                // the tap tries again. The reading above it stays whole.
                noticeButton
            } else if model.audio != .none {
                // Below the words, not over them: the watch toolbar draws
                // on top of a short reading.
                playControl
            }
        }
        .background(OceanTheme.abyss.ignoresSafeArea())
        .onAppear { model.appeared() }
        .onDisappear {
            // Wrist-down disappears this screen after the scene leaves
            // .active. That path already stopped playback and keeps the
            // fetched file; only a pop while the app is up deletes it.
            if scenePhase == .active { model.leave() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.sceneBecameActive()
            } else {
                model.sceneWentInactive()
            }
        }
    }

    @ViewBuilder private var reading: some View {
        if let reading = model.row.reading {
            if model.row.readingIsSummary {
                // Nearer the words it names than the title above.
                Label("Summary", systemImage: "sparkles")
                    .oceanText(OceanWatchType.label)
                    .foregroundStyle(OceanTheme.mist)
                    .padding(.top, OceanSpacing.tight)
            }
            Text(reading)
                .oceanText(model.row.readingIsSummary ? OceanWatchType.body : OceanWatchType.serif)
                .foregroundStyle(model.row.readingIsSummary ? OceanTheme.text : OceanTheme.coolWords)
            if model.row.continues {
                Text("Continues on iPhone")
                    .oceanText(OceanWatchType.meta)
                    .foregroundStyle(OceanTheme.mist)
            }
        } else if model.row.isVoice && !model.row.hasTranscript {
            Text("Not transcribed yet")
                .oceanText(OceanWatchType.meta)
                .foregroundStyle(OceanTheme.mist)
        }
    }

    /// The failure, in place of play. It stays until tapped, and the tap
    /// tries again (PHILOSOPHY §5: failure never fades on its own).
    private var noticeButton: some View {
        Button { Task { await model.togglePlay() } } label: {
            Group {
                if model.audio == .phoneAway {
                    Text("Your iPhone isn't nearby")
                } else {
                    Text("Couldn't get the audio")
                }
            }
            .oceanText(OceanWatchType.body)
            .foregroundStyle(OceanTheme.foam)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .scenePadding(.horizontal)
    }

    private var playControl: some View {
        HStack(spacing: OceanSpacing.gap) {
            if model.audio == .fetching {
                Text("Getting audio…")
                    .oceanText(OceanWatchType.meta)
                    .foregroundStyle(OceanTheme.mist)
            } else {
                Button { Task { await model.togglePlay() } } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .oceanText(OceanWatchType.strong)
                        .foregroundStyle(OceanTheme.foam)
                        .frame(width: OceanControlSize.height, height: OceanControlSize.height)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isPlaying ? Text("Pause") : Text("Play"))
                if model.isPlayerOnThis {
                    Text(verbatim: "\(Self.time(model.player.elapsed)) / \(Self.time(model.player.duration))")
                        .monospacedDigit()
                        .oceanText(OceanWatchType.meta)
                        .foregroundStyle(OceanTheme.mist)
                }
            }
        }
    }

    private static func time(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
