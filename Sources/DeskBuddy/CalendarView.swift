import SwiftUI

/// Tab showing completion history as a monthly calendar.
/// Days with more completions are shaded darker; tapping a date lists that day's completed items below.
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

    // MARK: - Month navigation

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

    // MARK: - Calendar grid

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

    /// Leading blank cells (nil) + the days of this month
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
        // Read revision so the event dots refresh when the calendar DB changes
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
                    // Dot marking a day with events
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
        .help([count > 0 ? L.f("calendar.n_completed", count) : nil, hasEvent ? L.s("calendar.has_events") : nil]
            .compactMap { $0 }.joined(separator: " · "))
    }

    // MARK: - Selected day's events + completed items

    private var dayDetail: some View {
        let items = (completedByDay[selectedDay] ?? [])
            .sorted { $0.completionDate > $1.completionDate }
        // Read revision so this view re-renders when the calendar DB changes
        let events = (showEvents && calendar.revision >= 0) ? calendar.events(on: selectedDay) : []

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(selectedDay.formatted(.dateTime.month(.defaultDigits).day().weekday(.short)))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if !items.isEmpty {
                    Text(L.f("calendar.n_completed", items.count))
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
                Text(events.isEmpty
                     ? L.s("calendar.nothing_recorded")
                     : L.s("calendar.nothing_completed"))
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

    // MARK: - Event section

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
            Text(event.isAllDay ? L.s("calendar.all_day") : event.start.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11, weight: isNext ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(isNext ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            Text(event.title)
                .font(.system(size: 12, weight: isNext ? .medium : .regular))
                .foregroundStyle(isNext ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
            Spacer(minLength: 0)
            if isNext {
                Text(ongoing ? L.s("calendar.now") : relative(to: event.start, from: now))
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

    /// "in 5 min", "in 2h 30m" — only handles events within today, so simple math is enough
    private func relative(to date: Date, from now: Date) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes < 1 { return L.s("calendar.starting_soon") }
        if minutes < 60 { return L.f("calendar.in_minutes", minutes) }
        return minutes % 60 == 0
            ? L.f("calendar.in_hours", minutes / 60)
            : L.f("calendar.in_hours_minutes", minutes / 60, minutes % 60)
    }
}
