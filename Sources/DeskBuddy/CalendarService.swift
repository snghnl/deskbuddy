import AppKit
import EventKit
import SwiftUI

/// Event snapshot for rendering (never exposes EKEvent directly to views)
struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
}

enum CalendarAccess {
    case notDetermined   // Never asked yet — show the connect button
    case denied          // Denied — point to System Settings
    case authorized
}

/// Reads today's events from the macOS calendar (including Google accounts) via EventKit.
/// macOS handles syncing, so we only need to follow local DB changes (EKEventStoreChanged).
@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var access: CalendarAccess
    /// Incremented whenever the calendar DB changes — views observing this value call events(on:) again
    @Published private(set) var revision = 0

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

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
                    title: event.title ?? L.s("calendar.no_title"),
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: event.calendar.cgColor.map { Color(cgColor: $0) } ?? .accentColor
                )
            }
            .sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                return $0.start < $1.start
            }
    }
}
