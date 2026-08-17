import Foundation

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
final class TodoStore: ObservableObject {
    @Published var todos: [Todo] = [] {
        didSet { scheduleSave() }
    }

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("DeskBuddy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("todos.json")

        // Migrate data from the FloatingTodo era
        let legacy = support.appendingPathComponent("FloatingTodo/todos.json")
        if !FileManager.default.fileExists(atPath: fileURL.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.copyItem(at: legacy, to: fileURL)
        }

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
        todos.removeAll { $0.id == todo.id }
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

    func clearCompleted() {
        todos.removeAll { $0.isDone }
    }

    // MARK: - Per-tab lists

    var activeTodos: [Todo] { todos.filter { !$0.isDone } }

    /// Groups completed items by day, newest first
    var completedGroups: [CompletedGroup] {
        let calendar = Calendar.current
        let done = todos
            .filter { $0.isDone }
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