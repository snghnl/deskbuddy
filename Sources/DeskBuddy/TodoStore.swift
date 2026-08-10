import Foundation

struct Todo: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isDone = false
    var createdAt = Date()
    var memo: String?
    /// 완료한 시각 — 완료 탭에서 날짜별로 묶는 기준
    var completedAt: Date?
}

extension Todo {
    /// 완료 시각 — 예전 데이터엔 completedAt 이 없으므로 생성 시각으로 대체한다
    var completionDate: Date { completedAt ?? createdAt }
}

/// 완료 탭에서 하루 단위로 묶인 그룹
struct CompletedGroup: Identifiable {
    let id: Date        // 그날의 자정
    let title: String   // "오늘" / "어제" / "8월 7일 (목)"
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
        // 완료/미완료는 탭으로 나뉘므로 배열 순서는 그대로 둔다 (할 일 탭의 수동 정렬 유지)
        todos[i].completedAt = todos[i].isDone ? Date() : nil
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

    // MARK: - 탭별 목록

    var activeTodos: [Todo] { todos.filter { !$0.isDone } }

    /// 완료 항목을 최신순으로 하루 단위로 묶는다
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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M월 d일 (E)"
        return f
    }()

    private static func dayTitle(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "오늘" }
        if calendar.isDateInYesterday(day) { return "어제" }
        return dayFormatter.string(from: day)
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