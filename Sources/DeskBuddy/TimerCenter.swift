import AppKit

/// A pomodoro-style countdown timer, optionally linked to a to-do.
struct BuddyTimer: Identifiable, Codable, Equatable {
    var id = UUID()
    var label: String
    var todoID: UUID?
    var duration: TimeInterval
    /// Absolute fire time while running (survives app restarts)
    var endDate: Date?
    /// Remaining seconds while paused
    var pausedRemaining: TimeInterval?

    var isRunning: Bool { endDate != nil }

    func remaining(at now: Date) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        return pausedRemaining ?? duration
    }

    func progress(at now: Date) -> Double {
        duration > 0 ? remaining(at: now) / duration : 0
    }
}

/// Owns all timers: ticking, firing, and persistence.
/// Runs its own loop so timers fire even while the list panel is closed.
@MainActor
final class TimerCenter: ObservableObject {
    @Published private(set) var timers: [BuddyTimer] = [] {
        didSet { save() }
    }

    /// Called once per expired timer (bubble + sound are wired in AppDelegate)
    var onFire: ((BuddyTimer) -> Void)?

    private var task: Task<Void, Never>?
    private let storageKey = "DeskBuddy.timers"

    init() {
        restore()
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func start(minutes: Int, label: String, todoID: UUID? = nil) {
        guard minutes > 0 else { return }
        let duration = TimeInterval(minutes * 60)
        timers.append(BuddyTimer(
            label: label,
            todoID: todoID,
            duration: duration,
            endDate: Date().addingTimeInterval(duration)
        ))
    }

    func pause(_ id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }),
              let end = timers[i].endDate else { return }
        timers[i].pausedRemaining = max(0, end.timeIntervalSinceNow)
        timers[i].endDate = nil
    }

    func resume(_ id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }),
              let remaining = timers[i].pausedRemaining else { return }
        timers[i].endDate = Date().addingTimeInterval(remaining)
        timers[i].pausedRemaining = nil
    }

    func cancel(_ id: UUID) {
        timers.removeAll { $0.id == id }
    }

    /// Link or unlink a to-do on an existing timer.
    /// The label stays as the short duration name — the to-do title only shows in tooltips.
    func link(_ id: UUID, todoID: UUID?) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[i].todoID = todoID
    }

    private func tick() {
        // Hold fire until AppDelegate has wired onFire — otherwise a timer that
        // expired while the app was closed would be consumed without notifying
        guard onFire != nil else { return }
        let now = Date()
        let fired = timers.filter { $0.isRunning && $0.remaining(at: now) <= 0 }
        guard !fired.isEmpty else { return }
        timers.removeAll { timer in fired.contains { $0.id == timer.id } }
        for timer in fired { onFire?(timer) }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(timers) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? [BuddyTimer](from: data) else { return }
        timers = decoded
    }
}

private extension Array where Element == BuddyTimer {
    init?(from data: Data) {
        guard let decoded = try? JSONDecoder().decode([BuddyTimer].self, from: data) else { return nil }
        self = decoded
    }
}
