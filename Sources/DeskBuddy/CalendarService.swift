import AppKit
import EventKit
import SwiftUI

/// 화면에 그리기 위한 일정 스냅샷 (EKEvent 를 뷰에 직접 노출하지 않는다)
struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
}

enum CalendarAccess {
    case notDetermined   // 아직 물어본 적 없음 — 연동 버튼 표시
    case denied          // 거부됨 — 시스템 설정 안내
    case authorized
}

/// EventKit 으로 macOS 캘린더(구글 계정 포함)의 오늘 일정을 읽는다.
/// 동기화는 macOS 가 담당하므로 여기서는 로컬 DB 변경(EKEventStoreChanged)만 따라가면 된다.
@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var access: CalendarAccess
    /// 캘린더 DB 가 바뀔 때마다 증가 — 이 값을 구독하는 뷰가 events(on:) 을 다시 부르게 한다
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

    /// 해당 월에 일정이 있는 날짜들(자정 기준) — 달력 그리드의 점 표시용
    func eventDays(inMonthOf month: Date) -> Set<Date> {
        guard access == .authorized else { return [] }
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return Set(store.events(matching: predicate).map { cal.startOfDay(for: $0.startDate) })
    }

    /// 특정 날짜의 일정 (하루 종일 일정이 먼저, 나머지는 시간순)
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
                    title: event.title ?? "(제목 없음)",
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
