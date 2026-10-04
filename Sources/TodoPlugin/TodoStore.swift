import DeskBuddyCore
import Foundation
import Observation
import TodoAPI

package struct Todo: Identifiable, Codable, Equatable {
    package var id = UUID()
    package var title: String
    package var isDone = false
    package var createdAt = Date()
    package var memo: String?
    /// When the item was completed — used to group by date in the Done tab
    package var completedAt: Date?
}

extension Todo {
    /// Completion time — legacy data has no completedAt, so fall back to the creation time
    package var completionDate: Date { completedAt ?? createdAt }
}

/// A group of completed items bucketed by day in the Done tab
package struct CompletedGroup: Identifiable {
    package let id: Date        // Midnight of that day
    package let title: String   // "Today" / "Yesterday" / "Aug 7 (Thu)"
    package let items: [Todo]
}

@MainActor
@Observable
package final class TodoStore {
    package var todos: [Todo] = [] {
        didSet { scheduleSave() }
    }

    /// Completions at or before this moment are hidden from the Done tab. The items
    /// themselves stay in `todos`, so the Calendar heatmap keeps counting them and the
    /// clear is undoable; `deleteCompleted()` is the destructive counterpart.
    ///
    /// Stored as a watermark rather than a per-item flag on purpose: a new non-optional
    /// field on `Todo` would make the synthesized decoder throw on every existing
    /// todos.json, and every item would end up set aside as unreadable.
    package var historyClearedAt: Date? {
        didSet {
            do {
                if let at = historyClearedAt {
                    try storage.set(at, forKey: Self.historyClearedAtKey)
                } else {
                    try storage.remove(forKey: Self.historyClearedAtKey)
                }
            } catch {
                log.error("Could not save historyClearedAt: \(String(describing: error))")
            }
        }
    }

    /// Storage keys. The CLI reads plugins/todo/todos.json while the app is not running.
    package static let todosKey = "todos"
    private static let historyClearedAtKey = "historyClearedAt"

    /// Where deletions are announced
    @ObservationIgnored private let events: EventBus
    @ObservationIgnored private let storage: PluginStorage
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let log: Log

    package init(storage: PluginStorage, events: EventBus, log: Log) {
        self.events = events
        self.storage = storage
        self.log = log
        // If this goes through didSet, it only writes the same value back
        historyClearedAt = load(Date.self, forKey: Self.historyClearedAtKey)
        // Assigning schedules a save of what was just read, which is harmless
        todos = load([Todo].self, forKey: Self.todosKey) ?? []
    }

    /// Writes a save that is still waiting out its delay, e.g. when the app quits
    package func flush() {
        guard let saveTask else { return }
        saveTask.cancel()
        self.saveTask = nil
        save(todos)
    }

    package func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.insert(Todo(title: trimmed), at: 0)
    }

    package func toggle(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].isDone.toggle()
        // Done/undone items live in separate tabs, so keep the array order as-is (preserves manual ordering in the To Do tab)
        todos[i].completedAt = todos[i].isDone ? Date() : nil
    }

    package func remove(_ todo: Todo) {
        guard todos.contains(where: { $0.id == todo.id }) else { return }
        todos.removeAll { $0.id == todo.id }
        events.emit(TodoDeleted(id: todo.id))
    }

    /// Move the dragged item to the target item's position
    package func move(_ draggedID: UUID, to targetID: UUID) {
        guard draggedID != targetID,
              let from = todos.firstIndex(where: { $0.id == draggedID }),
              let to = todos.firstIndex(where: { $0.id == targetID }) else { return }
        let item = todos.remove(at: from)
        todos.insert(item, at: to)
    }

    package func updateTitle(_ id: UUID, _ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].title = trimmed
    }

    package func updateMemo(_ id: UUID, _ memo: String) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].memo = memo.isEmpty ? nil : memo
    }

    /// Hides everything completed so far from the Done tab. Reversible.
    package func clearCompletedFromList() {
        historyClearedAt = Date()
    }

    /// Brings hidden completions back into the Done tab.
    package func restoreClearedHistory() {
        historyClearedAt = nil
    }

    /// Removes completed items for good. There is no undo and no backup — the next
    /// save overwrites todos.json with what is left.
    package func deleteCompleted() {
        let deleted = completedTodos.map(\.id)
        todos.removeAll { $0.isDone }
        historyClearedAt = nil   // nothing left to hide
        for id in deleted { events.emit(TodoDeleted(id: id)) }
    }

    // MARK: - Per-tab lists

    package var activeTodos: [Todo] { todos.filter { !$0.isDone } }

    package var completedTodos: [Todo] { todos.filter { $0.isDone } }

    /// Completed items still shown in the Done tab
    package var visibleCompleted: [Todo] {
        guard let cutoff = historyClearedAt else { return completedTodos }
        return completedTodos.filter { $0.completionDate > cutoff }
    }

    package var hiddenCompletedCount: Int { completedTodos.count - visibleCompleted.count }

    /// Groups the visible completed items by day, newest first
    package var completedGroups: [CompletedGroup] {
        let calendar = Calendar.current
        let done = visibleCompleted
            .sorted { $0.completionDate > $1.completionDate }
        let grouped = Dictionary(grouping: done) { calendar.startOfDay(for: $0.completionDate) }
        return grouped.keys.sorted(by: >).map { day in
            CompletedGroup(id: day, title: Self.dayTitle(day, calendar: calendar), items: grouped[day] ?? [])
        }
    }

    private static func dayTitle(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return strings.s("date.today") }
        if calendar.isDateInYesterday(day) { return strings.s("date.yesterday") }
        // Built per call so the format and locale follow the current app language
        let f = DateFormatter()
        f.locale = L.locale
        f.dateFormat = strings.s("date.day_format")
        return f.string(from: day)
    }

    /// The stored value, or nil when there is none. One that cannot be read is moved aside
    /// rather than left to be overwritten by the next save, so it can still be recovered.
    private func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        do {
            return try storage.get(type, forKey: key)
        } catch {
            let aside = try? storage.setAside(key)
            log.error("Could not read \(key), so starting without it. It was moved to \(aside?.path ?? "nowhere"): \(String(describing: error))")
            return nil
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = todos
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            saveTask = nil
            save(snapshot)
        }
    }

    private func save(_ todos: [Todo]) {
        do {
            try storage.set(todos, forKey: Self.todosKey)
        } catch {
            log.error("Could not save to-dos: \(String(describing: error))")
        }
    }
}
/// The reads other features get through TodoService
extension TodoStore {
    package var active: [TodoSummary] {
        activeTodos.map(\.summary)
    }

    package func todo(_ id: UUID) -> TodoSummary? {
        todos.first { $0.id == id }?.summary
    }

    package func completed(on day: Date) -> [TodoSummary] {
        let calendar = Calendar.current
        return completedTodos
            .filter { calendar.isDate($0.completionDate, inSameDayAs: day) }
            .sorted { $0.completionDate > $1.completionDate }
            .map(\.summary)
    }
}

private extension Todo {
    package var summary: TodoSummary {
        TodoSummary(id: id, title: title, isDone: isDone, createdAt: createdAt,
                    completedAt: isDone ? completionDate : nil, hasMemo: memo?.isEmpty == false)
    }
}
