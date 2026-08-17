import SwiftUI

/// 완료 기록을 월 달력으로 보여주는 탭.
/// 완료가 많은 날일수록 칸이 진해지고, 날짜를 누르면 그날 완료한 항목이 아래에 나온다.
struct CalendarTabView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var calendar: CalendarService
    let onSelect: (UUID) -> Void

    @AppStorage(SettingsKeys.showCalendar) private var showEvents = true
    @State private var month: Date
    @State private var selectedDay: Date

    private let cal = Calendar.current

    init(store: TodoStore, calendar: CalendarService, onSelect: @escaping (UUID) -> Void) {
        self.store = store
        self.calendar = calendar
        self.onSelect = onSelect
        let cal = Calendar.current
        _month = State(initialValue: cal.dateInterval(of: .month, for: Date())?.start ?? Date())
        _selectedDay = State(initialValue: cal.startOfDay(for: Date()))
    }

    private var completedByDay: [Date: [Todo]] {
        Dictionary(grouping: store.todos.filter { $0.isDone }) {
            cal.startOfDay(for: $0.completionDate)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                monthHeader
                weekdayRow
                grid
                Divider().opacity(0.4)
                dayDetail
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 월 이동

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()
            Text(month.formatted(.dateTime.year().month(.wide)))
                .font(.system(size: 11, weight: .semibold))
            Spacer()

            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: month) {
            month = next
        }
    }

    // MARK: - 달력 그리드

    private var orderedWeekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        return (0..<7).map { symbols[(cal.firstWeekday - 1 + $0) % 7] }
    }

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 앞쪽 빈칸(nil) + 이 달의 날짜들
    private var monthDays: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<range.count {
            cells.append(cal.date(byAdding: .day, value: offset, to: interval.start))
        }
        return cells
    }

    private var grid: some View {
        let days = monthDays
        // revision 을 읽어 캘린더 DB 변경 시 점 표시가 갱신되게 한다
        let eventDays = (showEvents && calendar.revision >= 0) ? calendar.eventDays(inMonthOf: month) : []
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
            ForEach(days.indices, id: \.self) { i in
                if let day = days[i] {
                    dayCell(day, hasEvent: eventDays.contains(day))
                } else {
                    Color.clear.frame(height: 26)
                }
            }
        }
    }

    private func dayCell(_ day: Date, hasEvent: Bool) -> some View {
        let count = completedByDay[day]?.count ?? 0
        let isToday = cal.isDateInToday(day)
        let isSelected = day == selectedDay
        return Button {
            selectedDay = day
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(count > 0
                          ? Color.accentColor.opacity(min(0.1 + Double(count) * 0.13, 0.55))
                          : .clear)
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: 1.2)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
                }
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 10, weight: isToday ? .bold : .regular))
                    .foregroundStyle(count > 0 ? .primary : .secondary)
                if hasEvent {
                    // 일정이 있는 날 표시
                    Circle()
                        .fill(.secondary)
                        .frame(width: 3, height: 3)
                        .offset(y: 8.5)
                }
            }
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help([count > 0 ? "\(count)개 완료" : nil, hasEvent ? "일정 있음" : nil]
            .compactMap { $0 }.joined(separator: " · "))
    }

    // MARK: - 선택한 날짜의 일정 + 완료 목록

    private var dayDetail: some View {
        let items = (completedByDay[selectedDay] ?? [])
            .sorted { $0.completionDate > $1.completionDate }
        // revision 을 읽어 캘린더 DB 변경 시 이 뷰가 다시 그려지게 한다
        let events = (showEvents && calendar.revision >= 0) ? calendar.events(on: selectedDay) : []

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(selectedDay.formatted(.dateTime.month(.defaultDigits).day().weekday(.short)))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if !items.isEmpty {
                    Text("\(items.count)개 완료")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 2)

            if !events.isEmpty {
                eventSection(events)
                    .padding(.bottom, 4)
            }

            if items.isEmpty {
                Text(events.isEmpty ? "이 날엔 기록이 없어요" : "이 날엔 완료한 일이 없어요")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            } else {
                ForEach(items) { todo in
                    TodoRow(todo: todo, store: store) { onSelect(todo.id) }
                }
            }
        }
    }

    // MARK: - 일정 섹션

    private func eventSection(_ events: [CalendarEvent]) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let isToday = cal.isDateInToday(selectedDay)
            let timed = events.filter { !$0.isAllDay }
            let nextID = isToday
                ? (timed.first { $0.start <= now && now < $0.end } ?? timed.first { $0.start > now })?.id
                : nil

            VStack(alignment: .leading, spacing: 2) {
                ForEach(events) { event in
                    eventRow(event, now: now, isToday: isToday, isNext: event.id == nextID)
                }
            }
        }
    }

    private func eventRow(_ event: CalendarEvent, now: Date, isToday: Bool, isNext: Bool) -> some View {
        let past = isToday && !event.isAllDay && event.end <= now
        let ongoing = isToday && !event.isAllDay && event.start <= now && now < event.end
        return HStack(spacing: 6) {
            Circle()
                .fill(event.color)
                .frame(width: 5, height: 5)
            Text(event.isAllDay ? "종일" : event.start.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11, weight: isNext ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(isNext ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            Text(event.title)
                .font(.system(size: 12, weight: isNext ? .medium : .regular))
                .foregroundStyle(isNext ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
            Spacer(minLength: 0)
            if isNext {
                Text(ongoing ? "진행 중" : relative(to: event.start, from: now))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(ongoing ? Color.green.opacity(0.8) : Color.accentColor.opacity(0.85)))
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .opacity(past ? 0.4 : 1)
        .help(event.isAllDay
              ? event.title
              : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened)) \(event.title)")
    }

    /// "5분 후", "2시간 30분 후" — 오늘 안의 일정만 다루므로 단순 계산으로 충분하다
    private func relative(to date: Date, from now: Date) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes < 1 { return "곧 시작" }
        if minutes < 60 { return "\(minutes)분 후" }
        return "\(minutes / 60)시간 \(minutes % 60 == 0 ? "" : "\(minutes % 60)분 ")후"
    }
}
