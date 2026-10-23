import SwiftUI

/// The wrist screens (spec §1), all from OceanTheme: near monochrome and
/// matte. The one circle is a flat control disc, never a lit orb.
struct WatchCaptureView: View {
    let model: WatchCaptureModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        ZStack {
            OceanTheme.abyss.ignoresSafeArea()
            switch model.stage {
            case .idle: idle
            case .starting: ProgressView().tint(OceanTheme.accent)
            case .recording: recording
            case .caught: caught
            case .denied: denied
            case .failed: failed
            case .nothingCaught: nothingCaught
            }
        }
        .animation(OceanMotion.lift, value: model.stage)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await model.sceneBecameActive() }
            } else {
                model.sceneBecameInactive()
            }
        }
    }

    // MARK: Idle

    private var idle: some View {
        VStack(spacing: OceanSpacing.gap) {
            Button { Task { await model.begin() } } label: { disc(symbol: "waveform") }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Catch a whisper"))
            statusLine
            if let title = model.lastTitle {
                // A thought's title is New York on the phone: the meta
                // line's size in the serif, the wrist's own role.
                Text("Last: \(title)")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder private var statusLine: some View {
        switch model.statusLine {
        case .empty: EmptyView()
        case .waiting(let count): caption(Text("\(count) waiting for iPhone"))
        case .onItsWay: caption(Text("On its way"))
        case .inOcean: caption(Text("In your Ocean"))
        }
    }

    // MARK: Recording

    private var recording: some View {
        VStack(spacing: OceanSpacing.gap) {
            if !luminanceReduced {
                Text("Listening…")
                    .font(OceanType.note)
                    .foregroundStyle(OceanTheme.mist)
                WatchWaveform(level: model.recorder.level)
                    .frame(height: 22)
            }
            Button { Task { await model.finish() } } label: { disc(symbol: "stop.fill") }
                .buttonStyle(.plain)
                .handGestureShortcut(.primaryAction)   // Double Tap stops the take
                .accessibilityLabel(Text("Stop and catch"))
                .opacity(luminanceReduced ? 0 : 1)     // Always On dims to the timer alone
            Text(Self.timeString(model.recorder.elapsed))
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(OceanTheme.foam.opacity(luminanceReduced ? 0.6 : 1))
        }
    }

    // MARK: Caught

    private var caught: some View {
        VStack(spacing: OceanSpacing.gap) {
            Image(systemName: "checkmark")
                .font(OceanType.glyphLarge)
                .foregroundStyle(OceanTheme.accent)
            Text("Caught")
                .font(OceanType.tileTitle)
                .foregroundStyle(OceanTheme.foam)
            Button { model.undo() } label: {
                Text("Undo")
                    .font(OceanType.control)
                    .foregroundStyle(OceanTheme.foam)
                    .padding(.horizontal, OceanSpacing.controlInset)
                    .frame(minHeight: OceanControlSize.height)
                    // The phone's Secondary control: the raised surface, no rim.
                    .background(OceanSurface(shape: Capsule(), raised: true))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Undo this take"))
        }
    }

    // MARK: Failure states

    private var denied: some View {
        VStack(spacing: OceanSpacing.gap) {
            Image(systemName: "mic.slash")
                .font(OceanType.glyphLarge)
                .foregroundStyle(OceanTheme.mist)
            Text("Allow the microphone for Oryne in Settings on your watch.")
                .font(OceanType.meta)
                .foregroundStyle(OceanTheme.text)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private var failed: some View {
        Button { Task { await model.begin() } } label: {
            VStack(spacing: OceanSpacing.gap) {
                Image(systemName: "exclamationmark.triangle")
                    .font(OceanType.glyphLarge)
                    .foregroundStyle(OceanTheme.mist)
                Text("Couldn't start. Tap to try again.")
                    .font(OceanType.meta)
                    .foregroundStyle(OceanTheme.foam)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    /// Stays until tapped: a failure never fades on its own. The whole
    /// screen is the button.
    private var nothingCaught: some View {
        Button { model.dismissNotice() } label: {
            Text("Nothing was caught")
                .font(OceanType.meta)
                .foregroundStyle(OceanTheme.foam)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Pieces

    private func caption(_ text: Text) -> some View {
        text
            .font(OceanType.note)
            .foregroundStyle(OceanTheme.mist)
            .multilineTextAlignment(.center)
    }

    /// The flat control disc: matte fill, no rim light, no gloss.
    private func disc(symbol: String) -> some View {
        ZStack {
            Circle().fill(OceanTheme.current)
            Image(systemName: symbol)
                // Scales with the disc, as the phone's does (art-directed).
                .font(.system(size: Self.discSize * 0.34, weight: .semibold))
                .foregroundStyle(OceanTheme.foam)
        }
        .frame(width: Self.discSize, height: Self.discSize)
    }

    /// The wrist's one control disc: the phone's picture tile size.
    private static let discSize: CGFloat = OceanSize.pictureTile

    private static func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

/// The phone's listening waveform, scaled to the wrist. Reduce Motion stills
/// it to bars that follow the input level only.
private struct WatchWaveform: View {
    let level: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: OceanSpacing.hairline + 1) { // art-directed: the waveform's bars
                ForEach(0..<13, id: \.self) { i in
                    let swing = reduceMotion ? 0.6 : 0.3 + 0.7 * abs(sin(t * 4 + Double(i) * 0.5))
                    Capsule()
                        .fill(OceanTheme.accent.opacity(0.9))
                        .frame(width: 3, height: max(3, swing * (5 + level * 22)))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
