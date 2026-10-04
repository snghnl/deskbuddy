import DeskBuddyCore
import Foundation

/// Checks today's events every 30 seconds and has the buddy mention each one once, at the configured lead time before it starts.
/// The latest alert keeps counting down (n min → n-1 min → … → starting now) until the event starts.
@MainActor
final class EventNotifier {
    private static let alert = SurfaceID("calendar.eventAlert")

    private let calendar: CalendarService
    private let buddy: any Buddy
    private let surfaces: SurfaceManager
    private let settings: PluginSettings
    private var task: Task<Void, Never>?
    private var notifiedIDs: Set<String> = []
    /// The alert currently counting down, with the text last sent for it
    private var countdown: (event: CalendarEvent, message: String)?

    init(calendar: CalendarService, buddy: any Buddy, surfaces: SurfaceManager, settings: PluginSettings) {
        self.calendar = calendar
        self.buddy = buddy
        self.surfaces = surfaces
        self.settings = settings
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.tick() else { return }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Runs one check and returns how long to wait before the next
    private func tick() -> TimeInterval {
        let now = Date()
        refreshCountdown(now)

        if calendar.access == .authorized,
           settings.bool(CalendarSettings.eventAlerts, default: CalendarSettings.eventAlertsDefault) {
            let leadMinutes = max(1, settings.integer(CalendarSettings.eventAlertLead, default: CalendarSettings.eventAlertLeadDefault))
            for event in calendar.events(on: now) where !event.isAllDay {
                let seconds = event.start.timeIntervalSince(now)
                guard seconds > 0, seconds <= Double(leadMinutes) * 60,
                      !notifiedIDs.contains(event.id) else { continue }
                notifiedIDs.insert(event.id)
                let message = Self.message(for: event, now: now)
                countdown = (event, message)
                // Not worth bringing a hidden buddy out for
                if buddy.isVisible { surfaces.present(.bubble(message), id: Self.alert) }
            }
        }

        // While counting down, wake just past the next whole-minute mark so the number flips on time
        guard let countdown else { return 30 }
        let untilFlip = countdown.event.start.timeIntervalSince(now).truncatingRemainder(dividingBy: 60)
        return min(30, max(0, untilFlip) + 0.05)
    }

    private func refreshCountdown(_ now: Date) {
        guard let countdown else { return }
        let message = Self.message(for: countdown.event, now: now)
        if message != countdown.message {
            surfaces.update(Self.alert, to: .bubble(message))
        }
        self.countdown = now < countdown.event.start ? (countdown.event, message) : nil
    }

    /// "n min" is rounded up — it reads n until less than n-1 minutes remain
    private static func message(for event: CalendarEvent, now: Date) -> String {
        let seconds = event.start.timeIntervalSince(now)
        guard seconds > 0 else { return L.f("bubble.event_now", event.title) }
        return L.f("bubble.event_upcoming", Int((seconds / 60).rounded(.up)), event.title)
    }
}
