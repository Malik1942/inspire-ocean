import AVFAudio
import Speech

/// Mic + speech recognition authorization, requested once before the first
/// recording. This harness has its own Info.plist usage strings (see
/// project.yml) — unrelated to Oryne's real ones.
enum Permissions {
    /// Returns a human-readable problem description, or nil if both are granted.
    static func requestAll() async -> String? {
        let micGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else {
            return "Microphone access denied — enable it in Settings > BilingualSpike."
        }

        let speechStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            return "Speech recognition not authorized (status \(speechStatus.rawValue)) — enable it in Settings > BilingualSpike."
        }

        return nil
    }
}
