import Foundation

struct Todo: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isDone = false
    var createdAt = Date()
    var memo: String?
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

        // FloatingTodo 시절 데이터 마이그레이션
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
        // 완료 항목은 목록 아래로 보낸다
        let item = todos.remove(at: i)
        if item.isDone {
            todos.append(item)
        } else {
            let firstDone = todos.firstIndex(where: { $0.isDone }) ?? todos.endIndex
            todos.insert(item, at: firstDone)
        }
    }

    func remove(_ todo: Todo) {
        todos.removeAll { $0.id == todo.id }
    }

    /// 드래그 중인 항목을 대상 항목 자리로 이동
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