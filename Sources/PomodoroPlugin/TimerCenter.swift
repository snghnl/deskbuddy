import AppKit
import DeskBuddyCore
import Observation
import os

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
@Observable
final class TimerCenter {
    private(set) var timers: [BuddyTimer] = [] {
        didSet { save() }
    }

    /// Called once per expired timer (sound and bubble are wired by PomodoroPlugin)
    @ObservationIgnored var onFire: ((BuddyTimer) -> Void)?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let storage: PluginStorage
    @ObservationIgnored private let log: Logger
    private static let storageKey = "timers"

    init(storage: PluginStorage, log: Logger) {
        self.storage = storage
        self.log = log
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

    /// Drops the link from every timer that points at `todoID`, e.g. once that to-do is deleted.
    /// The timers keep running under their own labels.
    func unlinkAll(from todoID: UUID) {
        for i in timers.indices where timers[i].todoID == todoID {
            timers[i].todoID = nil
        }
    }

    private func tick() {
        // Hold fire until the plugin has wired onFire — otherwise a timer that
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
        do {
            try storage.set(timers, forKey: Self.storageKey)
        } catch {
            log.error("Could not save timers: \(String(describing: error), privacy: .public)")
        }
    }

    /// Timers that cannot be read are moved aside, not overwritten, and the plugin starts with none
    private func restore() {
        do {
            timers = try storage.get([BuddyTimer].self, forKey: Self.storageKey) ?? []
        } catch {
            let aside = try? storage.setAside(Self.storageKey)
            log.error("Could not read timers, so starting without them. They were moved to \(aside?.path ?? "nowhere", privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
