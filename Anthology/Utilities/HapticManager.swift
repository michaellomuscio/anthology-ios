import UIKit
import CoreHaptics

/// Centralized haptic feedback. Uses **Core Haptics** custom patterns on
/// devices that support them (iPhone XS+) for noticeably stronger and
/// longer-feeling buzzes than UIKit's stock impact generators. Falls back
/// to UIKit's UIImpact / UINotification / UISelectionFeedbackGenerator on
/// older / non-haptic hardware.
///
/// Set the `anthology.haptics.enabled` UserDefaults key to false to silence
/// every call.
@MainActor
final class HapticManager {
    static let shared = HapticManager()

    static let userDefaultsKey = "anthology.haptics.enabled"

    private var engine: CHHapticEngine?
    private let supportsCustomHaptics: Bool

    // UIKit fallbacks for non-haptic hardware (iPhone 8 and older).
    private let selectionGen = UISelectionFeedbackGenerator()
    private let lightGen = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGen = UIImpactFeedbackGenerator(style: .heavy)
    private let notifGen = UINotificationFeedbackGenerator()

    private init() {
        supportsCustomHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

        if supportsCustomHaptics {
            do {
                let e = try CHHapticEngine()
                try e.start()
                // The engine resets after audio interruptions (calls, Siri, etc.)
                // — re-arm it so subsequent plays still work.
                e.resetHandler = { [weak self] in
                    try? self?.engine?.start()
                }
                // Stops on app background. We restart before every play, so this
                // is just a place to log if needed.
                e.stoppedHandler = { _ in }
                self.engine = e
            } catch {
                NSLog("[haptics] CHHapticEngine setup failed: \(error)")
            }
        }

        // Default ON. Users can turn off in Settings.
        if UserDefaults.standard.object(forKey: Self.userDefaultsKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.userDefaultsKey)
        }
    }

    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: Self.userDefaultsKey)
    }

    func prepare() {
        // Prepare UIKit generators in case we fall back.
        selectionGen.prepare()
        lightGen.prepare()
        mediumGen.prepare()
        heavyGen.prepare()
        notifGen.prepare()
        // Make sure the CH engine is up after a background/foreground cycle.
        try? engine?.start()
    }

    // MARK: - Core Haptics pattern playback

    /// Play a custom CH pattern. Returns false if the device doesn't support
    /// custom haptics OR the playback failed — the caller can then fall back
    /// to UIKit. Calling `try engine.start()` before every play is the Apple-
    /// recommended idempotent way to recover from a backgrounded engine.
    @discardableResult
    private func playCustom(_ events: [CHHapticEvent]) -> Bool {
        guard supportsCustomHaptics, let engine else { return false }
        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            NSLog("[haptics] playCustom failed: \(error)")
            return false
        }
    }

    /// Convenience: build a transient (instantaneous) tap event.
    private static func tap(intensity: Float, sharpness: Float, at time: TimeInterval = 0) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    /// Convenience: build a continuous (sustained vibration) event.
    private static func sustained(intensity: Float, sharpness: Float, at time: TimeInterval = 0, duration: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time,
            duration: duration
        )
    }

    // MARK: - Public API (compatible with the prior surface)
    //
    // Each method tries the Core Haptics custom pattern first; on failure
    // (older hardware, engine error) it falls through to UIKit's stock
    // generators so something still happens.

    func selection() {
        guard enabled else { return }
        if !playCustom([
            // A brief, distinct double-tap — much more felt than UISelection
            // on iPhone 16 Pro, where the stock selection feedback is so subtle
            // it can be missed entirely.
            Self.tap(intensity: 0.9, sharpness: 0.7, at: 0),
            Self.tap(intensity: 0.7, sharpness: 0.7, at: 0.06),
        ]) {
            selectionGen.selectionChanged()
            selectionGen.prepare()
        }
    }

    func light() {
        guard enabled else { return }
        if !playCustom([
            Self.sustained(intensity: 1.0, sharpness: 0.6, at: 0, duration: 0.12),
        ]) {
            lightGen.impactOccurred(intensity: 1.0)
            lightGen.prepare()
        }
    }

    func medium() {
        guard enabled else { return }
        if !playCustom([
            Self.sustained(intensity: 1.0, sharpness: 0.5, at: 0, duration: 0.20),
        ]) {
            mediumGen.impactOccurred(intensity: 1.0)
            mediumGen.prepare()
        }
    }

    func heavy() {
        guard enabled else { return }
        if !playCustom([
            // Strong, long, slightly rumbly. ~0.4s feels like a real buzz, not
            // a polite click.
            Self.sustained(intensity: 1.0, sharpness: 0.35, at: 0, duration: 0.42),
        ]) {
            heavyGen.impactOccurred(intensity: 1.0)
        }
    }

    func soft() {
        guard enabled else { return }
        if !playCustom([
            Self.sustained(intensity: 0.8, sharpness: 0.2, at: 0, duration: 0.18),
        ]) {
            mediumGen.impactOccurred(intensity: 0.6)
        }
    }

    func rigid() {
        guard enabled else { return }
        if !playCustom([
            Self.tap(intensity: 1.0, sharpness: 1.0, at: 0),
        ]) {
            heavyGen.impactOccurred(intensity: 1.0)
        }
    }

    /// Success — two ascending taps + a soft release. "Task done."
    func success() {
        guard enabled else { return }
        if !playCustom([
            Self.tap(intensity: 0.9, sharpness: 0.7, at: 0),
            Self.tap(intensity: 1.0, sharpness: 0.85, at: 0.13),
            Self.sustained(intensity: 0.7, sharpness: 0.4, at: 0.20, duration: 0.18),
        ]) {
            notifGen.notificationOccurred(.success)
            notifGen.prepare()
        }
    }

    /// Warning — one strong sustained pulse + a follow-up tap. "Look at this."
    /// Used for waiting → user needs to make a decision. Long enough that you
    /// can't ignore it but not aggressive.
    func warning() {
        guard enabled else { return }
        if !playCustom([
            Self.sustained(intensity: 1.0, sharpness: 0.5, at: 0, duration: 0.40),
            Self.tap(intensity: 1.0, sharpness: 0.8, at: 0.50),
        ]) {
            notifGen.notificationOccurred(.warning)
            notifGen.prepare()
        }
    }

    /// Error — three rapid sharp taps. "Something broke."
    func error() {
        guard enabled else { return }
        if !playCustom([
            Self.tap(intensity: 1.0, sharpness: 0.95, at: 0),
            Self.tap(intensity: 1.0, sharpness: 0.95, at: 0.09),
            Self.tap(intensity: 1.0, sharpness: 0.95, at: 0.18),
            Self.sustained(intensity: 0.9, sharpness: 0.6, at: 0.25, duration: 0.20),
        ]) {
            notifGen.notificationOccurred(.error)
            notifGen.prepare()
        }
    }

    // MARK: - Session-status transitions

    /// Fires the right haptic for a session status change. Same gating as
    /// before — repeat events (server re-emits the same status) don't fire.
    func sessionStatusTransition(from: SessionStatus?, to: SessionStatus) {
        guard from != to else { return }
        switch to {
        case .waiting: warning()
        case .idle:    success()
        case .error:   error()
        case .dead:    error()
        case .exited:  error()
        case .running: break
        }
    }
}
