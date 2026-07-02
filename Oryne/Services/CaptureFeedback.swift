import AudioToolbox
import CoreHaptics
import UIKit

/// The quiet confirmation that the Ocean received a capture: a soft two-note
/// chime (OceanReceived.caf) and a swell-shaped haptic, fired at the instant
/// the PostCaptureMoment appears. Foreground, on-screen captures only; the
/// background App Intent paths stay silent.
///
/// Deliberately outside the AVAudioSession choreography owned by
/// AudioRecorder, LiveTranscriber and AudioPlayerView: the chime goes through
/// AudioServicesPlaySystemSound, which never configures or activates the
/// shared session and falls silent with the ring/silent switch. Everything
/// here is best-effort; no error ever reaches or delays the save path.
@MainActor
enum CaptureFeedback {
    enum Keys {
        static let sound = "captureFeedback.sound"
        static let haptics = "captureFeedback.haptics"
    }

    static func released() {
        if isEnabled(Keys.sound) { playChime() }
        if isEnabled(Keys.haptics) { playSwell() }
    }

    /// Both toggles default ON: an absent key means enabled.
    private static func isEnabled(_ key: String) -> Bool {
        let defaults = FastCapturePreferences.defaults
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    // MARK: Sound

    private static var chimeID: SystemSoundID = 0
    private static var chimeLoadAttempted = false

    private static func playChime() {
        if !chimeLoadAttempted {
            chimeLoadAttempted = true
            if let url = Bundle.main.url(forResource: "OceanReceived", withExtension: "caf") {
                var id: SystemSoundID = 0
                if AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError {
                    chimeID = id
                }
            }
        }
        guard chimeID != 0 else { return }
        AudioServicesPlaySystemSound(chimeID)
    }

    // MARK: Haptics

    private static var engine: CHHapticEngine?
    private static var engineNeedsStart = true

    private static func playSwell() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            fallbackSuccess()
            return
        }
        do {
            let engine = try preparedEngine()
            let player = try engine.makePlayer(with: swellPattern())
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallbackSuccess()
        }
    }

    private static func preparedEngine() throws -> CHHapticEngine {
        let running: CHHapticEngine
        if let engine {
            running = engine
        } else {
            let fresh = try CHHapticEngine()
            fresh.playsHapticsOnly = true
            // The system stops idle engines (and stops/resets them across
            // backgrounding); don't fight it, just restart lazily next time.
            fresh.stoppedHandler = { _ in
                Task { @MainActor in engineNeedsStart = true }
            }
            fresh.resetHandler = {
                Task { @MainActor in engineNeedsStart = true }
            }
            engine = fresh
            running = fresh
        }
        if engineNeedsStart {
            try running.start()
            engineNeedsStart = false
        }
        return running
    }

    /// A soft ocean swell: one continuous event whose intensity rises fast
    /// and decays slowly, staying low-sharpness throughout, never a tap.
    private static func swellPattern() throws -> CHHapticPattern {
        let swell = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            ],
            relativeTime: 0,
            duration: 0.5
        )
        let intensity = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0.00, value: 0.0),
                .init(relativeTime: 0.09, value: 1.0),
                .init(relativeTime: 0.22, value: 0.55),
                .init(relativeTime: 0.50, value: 0.0)
            ],
            relativeTime: 0
        )
        // Additive sharpness modifier: effective sharpness eases 0.35 -> 0.15.
        let sharpness = CHHapticParameterCurve(
            parameterID: .hapticSharpnessControl,
            controlPoints: [
                .init(relativeTime: 0.00, value: 0.05),
                .init(relativeTime: 0.50, value: -0.15)
            ],
            relativeTime: 0
        )
        return try CHHapticPattern(events: [swell], parameterCurves: [intensity, sharpness])
    }

    private static func fallbackSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
