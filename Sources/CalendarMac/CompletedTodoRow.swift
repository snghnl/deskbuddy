import CalendarPlugin
import DeskBuddyCore
import SwiftUI
import TodoAPI

/// A to-do in the selected day's list. Looks like a row of the Done tab, but acts through
/// TodoService, since only the to-do feature may change to-dos.
struct CompletedTodoRow: View {
    let todo: TodoSummary
    let todos: any TodoService

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                todos.toggle(todo.id)
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(todo.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Text(todo.title)
                    .font(.system(size: 12))
                    .strikethrough(todo.isDone, color: .secondary)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                    .lineLimit(2)
                if todo.hasMemo {
                    Image(systemName: "note.text")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { todos.show(todo.id) }

            if let completedAt = todo.completedAt, !hovering {
                Text(completedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            if hovering {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Button {
                    todos.remove(todo.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(hovering ? Color.primary.opacity(0.06) : .clear)
        )
        .onHover { hovering = $0 }
        .help(tooltip)
    }

    private var tooltip: String {
        var text = strings.f("list.tooltip_added",
                       todo.createdAt.formatted(date: .abbreviated, time: .shortened),
                       Self.relative(todo.createdAt))
        if let completedAt = todo.completedAt {
            text += "\n" + strings.f("list.tooltip_completed",
                               completedAt.formatted(date: .abbreviated, time: .shortened),
                               Self.relative(completedAt))
        }
        return text
    }

    /// "3 hours ago"
    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}
