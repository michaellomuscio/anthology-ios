import UIKit

/// Centralized haptic feedback. Fires only when foregrounded (iOS suspends
/// haptics in background) and only when the user hasn't disabled them in
/// Settings. Call `prepare()` on scene-active to warm the generators —
/// first-fire latency drops from ~100ms to ~20ms.
@MainActor
final class HapticManager {
    static let shared = HapticManager()

    static let userDefaultsKey = "anthology.haptics.enabled"

    private let selectionGen = UISelectionFeedbackGenerator()
    private let lightGen = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGen = UIImpactFeedbackGenerator(style: .heavy)
    private let softGen = UIImpactFeedbackGenerator(style: .soft)
    private let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    private let notifGen = UINotificationFeedbackGenerator()

    private init() {
        // Default ON. Users can turn off in Settings.
        if UserDefaults.standard.object(forKey: Self.userDefaultsKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.userDefaultsKey)
        }
    }

    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: Self.userDefaultsKey)
    }

    func prepare() {
        // Warm the generators so the first tap doesn't lag.
        selectionGen.prepare()
        lightGen.prepare()
        mediumGen.prepare()
        notifGen.prepare()
    }

    // MARK: - Primitive feedback

    func selection() {
        guard enabled else { return }
        selectionGen.selectionChanged()
        selectionGen.prepare()
    }

    func light() {
        guard enabled else { return }
        lightGen.impactOccurred()
        lightGen.prepare()
    }

    func medium() {
        guard enabled else { return }
        mediumGen.impactOccurred()
        mediumGen.prepare()
    }

    func heavy() {
        guard enabled else { return }
        heavyGen.impactOccurred()
    }

    func soft() {
        guard enabled else { return }
        softGen.impactOccurred()
    }

    func rigid() {
        guard enabled else { return }
        rigidGen.impactOccurred()
    }

    func success() {
        guard enabled else { return }
        notifGen.notificationOccurred(.success)
        notifGen.prepare()
    }

    func warning() {
        guard enabled else { return }
        notifGen.notificationOccurred(.warning)
        notifGen.prepare()
    }

    func error() {
        guard enabled else { return }
        notifGen.notificationOccurred(.error)
        notifGen.prepare()
    }

    // MARK: - Session-status transitions

    /// Fire the right haptic for a session status change. The from/to pair
    /// gates the call so repeat events (server re-emits the same status)
    /// don't buzz the phone.
    ///
    /// Status mapping (matched to Claude.ai's general feel):
    /// - waiting  → warning  (Claude is asking; user needs to look)
    /// - idle     → success  (task done — gentle confirmation)
    /// - error    → error    (something failed)
    /// - dead     → error    (session exited)
    /// - running  → nothing  (too noisy; "Claude is still working" doesn't deserve a buzz)
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
