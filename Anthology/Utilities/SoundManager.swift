import AudioToolbox
import Foundation

/// Plays brief iOS system sounds for session events. AudioServicesPlaySystemSound
/// respects the physical ringer switch — silent mode silences these. That's the
/// right default; ignoring silent (AudioServicesPlayAlertSound) would feel rude.
///
/// Default OFF — users opt-in from Settings. Sounds are more disruptive than
/// haptics and not everyone wants them.
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    static let userDefaultsKey = "anthology.sound.enabled"

    /// Apple's bundled SystemSoundIDs. Chosen for being short, distinct,
    /// non-alarming, and reasonably modern.
    /// Reference: <https://github.com/TUNER88/iOSSystemSoundsLibrary>
    private struct Sounds {
        static let waiting: SystemSoundID = 1306   // Anticipate — soft drum
        static let idle:    SystemSoundID = 1057   // Tink — light positive
        static let success: SystemSoundID = 1322   // Bloom — gentle chime
        static let warning: SystemSoundID = 1336   // FoundDevice — soft chirp
        static let error:   SystemSoundID = 1073   // BurnerCallback — soft alert
    }

    private init() {
        // Default OFF. Sounds are opt-in.
        if UserDefaults.standard.object(forKey: Self.userDefaultsKey) == nil {
            UserDefaults.standard.set(false, forKey: Self.userDefaultsKey)
        }
    }

    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: Self.userDefaultsKey)
    }

    private func play(_ id: SystemSoundID) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(id)
    }

    // Convenience playback for the four meaningful states.
    func waiting() { play(Sounds.waiting) }
    func idle()    { play(Sounds.idle) }
    func success() { play(Sounds.success) }
    func error()   { play(Sounds.error) }

    func sessionStatusTransition(from: SessionStatus?, to: SessionStatus) {
        guard from != to else { return }
        switch to {
        case .waiting: waiting()
        case .idle:    idle()
        case .error:   error()
        case .dead:    error()
        case .exited:  error()
        case .running: break
        }
    }

    /// Lets the Settings UI play the "waiting" sound when the user toggles
    /// it on — gives them a one-shot preview of what they'll hear.
    func previewWaiting() {
        AudioServicesPlaySystemSound(Sounds.waiting)
    }
}
