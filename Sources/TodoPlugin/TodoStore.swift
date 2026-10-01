import DeskBuddyCore
import Foundation
import Observation
import TodoAPI

struct Todo: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isDone = false
    var createdAt = Date()
    var memo: String?
    /// When the item was completed — used to group by date in the Done tab
    var completedAt: Date?
}

extension Todo {
    /// Completion time — legacy data has no completedAt, so fall back to the creation time
    var completionDate: Date { completedAt ?? createdAt }
}

/// A group of completed items bucketed by day in the Done tab
struct CompletedGroup: Identifiable {
    let id: Date        // Midnight of that day
    let title: String   // "Today" / "Yesterday" / "Aug 7 (Thu)"
    let items: [Todo]
}

@MainActor
@Observable
final class TodoStore {
    var todos: [Todo] = [] {
        didSet { scheduleSave() }
    }

    /// Completions at or before this moment are hidden from the Done tab. The items
    /// themselves stay in `todos`, so the Calendar heatmap keeps counting them and the
    /// clear is undoable; `deleteCompleted()` is the destructive counterpart.
    ///
    /// Stored as a watermark rather than a per-item flag on purpose: a new non-optional
    /// field on `Todo` would make the synthesized decoder throw on every existing
    /// todos.json, and `load()` swallows that error — every item would silently vanish.
    var historyClearedAt: Date? {
        didSet {
            if let at = historyClearedAt {
                defaults.set(at.timeIntervalSinceReferenceDate, forKey: Self.historyClearedAtKey)
            } else {
                defaults.removeObject(forKey: Self.historyClearedAtKey)
            }
        }
    }

    /// The folder the CLI reads todos.json from when the app is not running
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeskBuddy", isDirectory: true)
    }

    private static let historyClearedAtKey = "DeskBuddy.historyClearedAt"

    /// Where deletions are announced
    @ObservationIgnored private let events: EventBus
    @ObservationIgnored private let defaults: UserDefaults
    private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// Keeps the to-dos in `directory`/todos.json and the Done-tab watermark in `defaults`
    init(directory: URL, defaults: UserDefaults, events: EventBus) {
        self.events = events
        self.defaults = defaults
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("todos.json")

        // Migrate data from the FloatingTodo era
        let legacy = directory.deletingLastPathComponent().appendingPathComponent("FloatingTodo/todos.json")
        if !FileManager.default.fileExists(atPath: fileURL.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.copyItem(at: legacy, to: fileURL)
        }

        // If this goes through didSet, it only writes the same value back
        historyClearedAt = (defaults.object(forKey: Self.historyClearedAtKey) as? Double)
            .map(Date.init(timeIntervalSinceReferenceDate:))
        load()
    }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.insert(Todo(title: trimmed), at: 0)
    }

    func toggle(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].isDone.toggle()
        // Done/undone items live in separate tabs, so keep the array order as-is (preserves manual ordering in the To Do tab)
        todos[i].completedAt = todos[i].isDone ? Date() : nil
    }

    func remove(_ todo: Todo) {
        guard todos.contains(where: { $0.id == todo.id }) else { return }
        todos.removeAll { $0.id == todo.id }
        events.emit(TodoDeleted(id: todo.id))
    }

    /// Move the dragged item to the target item's position
    func move(_ draggedID: UUID, to targetID: UUID) {
        guard draggedID != targetID,
              let from = todos.firstIndex(where: { $0.id == draggedID }),
              let to = todos.firstIndex(where: { $0.id == targetID }) else { return }
        let item = todos.remove(at: from)
        todos.insert(item, at: to)
    }

    func updateTitle(_ id: UUID, _ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].title = trimmed
    }

    func updateMemo(_ id: UUID, _ memo: String) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].memo = memo.isEmpty ? nil : memo
    }

    /// Hides everything completed so far from the Done tab. Reversible.
    func clearCompletedFromList() {
        historyClearedAt = Date()
    }

    /// Brings hidden completions back into the Done tab.
    func restoreClearedHistory() {
        historyClearedAt = nil
    }

    /// Removes completed items for good. There is no undo and no backup — the next
    /// save overwrites todos.json with what is left.
    func deleteCompleted() {
        let deleted = completedTodos.map(\.id)
        todos.removeAll { $0.isDone }
        historyClearedAt = nil   // nothing left to hide
        for id in deleted { events.emit(TodoDeleted(id: id)) }
    }

    // MARK: - Per-tab lists

    var activeTodos: [Todo] { todos.filter { !$0.isDone } }

    var completedTodos: [Todo] { todos.filter { $0.isDone } }

    /// Completed items still shown in the Done tab
    var visibleCompleted: [Todo] {
        guard let cutoff = historyClearedAt else { return completedTodos }
        return completedTodos.filter { $0.completionDate > cutoff }
    }

    var hiddenCompletedCount: Int { completedTodos.count - visibleCompleted.count }

    /// Groups the visible completed items by day, newest first
    var completedGroups: [CompletedGroup] {
        let calendar = Calendar.current
        let done = visibleCompleted
            .sorted { $0.completionDate > $1.completionDate }
        let grouped = Dictionary(grouping: done) { calendar.startOfDay(for: $0.completionDate) }
        return grouped.keys.sorted(by: >).map { day in
            CompletedGroup(id: day, title: Self.dayTitle(day, calendar: calendar), items: grouped[day] ?? [])
        }
    }

    private static func dayTitle(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return L.s("date.today") }
        if calendar.isDateInYesterday(day) { return L.s("date.yesterday") }
        // Built per call so the format and locale follow the current app language
        let f = DateFormatter()
        f.locale = L.locale
        f.dateFormat = L.s("date.day_format")
        return f.string(from: day)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Todo].self, from: data) else { return }
        todos = decoded
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = todos
        let url = fileURL
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
extension TodoStore: TodoService {
    var active: [TodoSummary] {
        activeTodos.map(\.summary)
    }

    func todo(_ id: UUID) -> TodoSummary? {
        todos.first { $0.id == id }?.summary
    }

    func completed(on day: Date) -> [TodoSummary] {
        let calendar = Calendar.current
        return completedTodos
            .filter { calendar.isDate($0.completionDate, inSameDayAs: day) }
            .sorted { $0.completionDate > $1.completionDate }
            .map(\.summary)
    }
}

private extension Todo {
    var summary: TodoSummary {
        TodoSummary(id: id, title: title, isDone: isDone, createdAt: createdAt,
                    completedAt: isDone ? completionDate : nil, hasMemo: memo?.isEmpty == false)
    }
}
