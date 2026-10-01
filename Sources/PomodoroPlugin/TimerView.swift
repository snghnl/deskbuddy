import DeskBuddyCore
import SwiftUI
import TodoAPI

/// Timer tab — pomodoro-style circular timers, several can run at once.
/// Each timer card manages its own to-do link and has an always-visible remove button.
struct TimerTabView: View {
    let timers: TimerCenter
    /// nil when the to-do feature is not there — timers then simply cannot be linked
    let todos: (any TodoService)?

    @State private var customMinutes = ""

    private let presets = [25, 50, 5, 10]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                addSection
                Divider().opacity(0.4)

                if timers.timers.isEmpty {
                    Text(L.s("timer.empty"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    // Half-second cadence keeps every ring and countdown in sync
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                                  alignment: .center, spacing: 12) {
                            ForEach(timers.timers) { timer in
                                TimerCard(timer: timer, now: context.date, timers: timers, todos: todos)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - New timer controls

    private var addSection: some View {
        HStack(spacing: 6) {
            ForEach(presets, id: \.self) { minutes in
                Button {
                    timers.start(minutes: minutes, label: L.f("timer.min_chip", minutes))
                } label: {
                    Text(L.f("timer.min_chip", minutes))
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            TextField(L.s("timer.custom_placeholder"), text: $customMinutes)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 32)
                .multilineTextAlignment(.center)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                .onSubmit(startCustom)
            Button(L.s("timer.start"), action: startCustom)
                .font(.system(size: 11))
                .disabled(Int(customMinutes) == nil)
        }
    }

    private func startCustom() {
        guard let minutes = Int(customMinutes), minutes > 0 else { return }
        timers.start(minutes: minutes, label: L.f("timer.min_chip", minutes))
        customMinutes = ""
    }
}

// MARK: - Timer card

/// Circular ring (tap to pause/resume) + per-timer link menu + remove button
private struct TimerCard: View {
    let timer: BuddyTimer
    let now: Date
    let timers: TimerCenter
    let todos: (any TodoService)?

    @State private var hoveringRing = false

    private var linkedTodo: TodoSummary? {
        timer.todoID.flatMap { todos?.todo($0) }
    }

    var body: some View {
        VStack(spacing: 5) {
            ring

            HStack(spacing: 4) {
                linkMenu
                Button {
                    timers.cancel(timer.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L.s("timer.cancel"))
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: timer.progress(at: now))
                .stroke(
                    timer.isRunning ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Hovering instantly swaps in the linked to-do's title (system tooltips are too slow)
            let showTitle = hoveringRing && linkedTodo != nil
            VStack(spacing: 1) {
                Text(timeText)
                    .font(.system(size: showTitle ? 12 : 16, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(timer.isRunning ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                if showTitle, let linkedTodo {
                    Text(linkedTodo.title)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 62)
                } else if !timer.isRunning {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: 88, height: 88)
        .contentShape(Circle())
        // Tap the ring to pause/resume
        .onTapGesture {
            timer.isRunning ? timers.pause(timer.id) : timers.resume(timer.id)
        }
        .onHover { hoveringRing = $0 }
        .animation(.easeOut(duration: 0.12), value: hoveringRing)
        .help(timer.isRunning ? L.s("timer.pause") : L.s("timer.resume"))
    }

    /// Always shows the short duration label; the linked to-do's title appears only as a hover tooltip
    @ViewBuilder
    private var linkMenu: some View {
        if let todos {
            Menu {
                if timer.todoID != nil {
                    Button(L.s("timer.unlink")) {
                        timers.link(timer.id, todoID: nil)
                    }
                    Divider()
                }
                ForEach(todos.active) { todo in
                    Button(todo.title) {
                        timers.link(timer.id, todoID: todo.id)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    // Accent-colored link icon signals a linked timer at a glance
                    Image(systemName: "link")
                        .font(.system(size: 8, weight: timer.todoID == nil ? .regular : .bold))
                        .foregroundStyle(timer.todoID == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    durationLabel
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(linkedTodo?.title ?? L.s("timer.link"))
        } else {
            durationLabel
        }
    }

    private var durationLabel: some View {
        Text(timer.label)
            .font(.system(size: 10))
            .lineLimit(1)
            .foregroundStyle(.secondary)
    }

    private var timeText: String {
        let total = Int(timer.remaining(at: now).rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

/// The timer icon on the To Do row of a to-do with a linked timer — accented while one runs
struct TimerStateIcon: View {
    let timers: TimerCenter
    let todoID: UUID

    var body: some View {
        let linked = timers.timers.filter { $0.todoID == todoID }
        if !linked.isEmpty {
            let running = linked.contains { $0.isRunning }
            Image(systemName: "timer")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(running ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .help(running ? L.s("timer.running") : L.s("timer.pause"))
        }
    }
}
