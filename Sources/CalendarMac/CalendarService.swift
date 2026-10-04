import AppKit
import CalendarPlugin
import DeskBuddyCore
import EventKit

/// Reads today's events from the macOS calendar (including Google accounts) via EventKit.
/// macOS handles syncing, so we only need to follow local DB changes (EKEventStoreChanged).
@MainActor
@Observable
final class CalendarService: CalendarSource {
    private(set) var access: CalendarAccess
    /// Incremented whenever the calendar DB changes — views observing this value call events(on:) again
    private(set) var revision = 0

    private let store = EKEventStore()
    @ObservationIgnored private var changeObserver: NSObjectProtocol?

    init() {
        access = Self.currentAccess()

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private static func currentAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            access = Self.currentAccess()
            refresh()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh() {
        revision += 1
    }

    /// Days in the given month that have events (normalized to midnight) — for the calendar grid's dots
    func eventDays(inMonthOf month: Date) -> Set<Date> {
        guard access == .authorized else { return [] }
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return Set(store.events(matching: predicate).map { cal.startOfDay(for: $0.startDate) })
    }

    /// Events on a specific day (all-day events first, the rest in time order)
    func events(on day: Date) -> [CalendarEvent] {
        guard access == .authorized else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .map { event in
                CalendarEvent(
                    id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? strings.s("calendar.no_title"),
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: event.calendar.cgColor.flatMap(EventColor.init(cgColor:))
                )
            }
            .sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                return $0.start < $1.start
            }
    }
}

private extension EventColor {
    init?(cgColor: CGColor) {
        guard let rgb = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else { return nil }
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}
