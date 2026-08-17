import SwiftUI
import UniformTypeIdentifiers

enum TodoTab: Hashable {
    case active, done, calendar
}

struct TodoListView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var appState: AppState
    @ObservedObject var calendar: CalendarService

    @State private var newTitle = ""
    @State private var selectedID: UUID?
    @State private var draggedID: UUID?
    @FocusState private var inputFocused: Bool

    private var tab: TodoTab { appState.tab }

    private var activeTodos: [Todo] { store.activeTodos }
    private var completedGroups: [CompletedGroup] { store.completedGroups }
    private var doneCount: Int { store.todos.count - activeTodos.count }

    var body: some View {
        Group {
            if let id = selectedID, let todo = store.todos.first(where: { $0.id == id }) {
                TodoDetailView(todo: todo, store: store) { selectedID = nil }
            } else {
                listPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
        // 크기 조절 그립 표시 (실제 드래그 처리는 ResizeGripView 가 담당)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(.degrees(-45))
                .foregroundStyle(.tertiary)
                .padding(7)
        }
        // 목록이 열리면(클릭·단축키 모두) 바로 입력할 수 있게 포커스
        .onChange(of: appState.listVisible) { _, visible in
            if visible {
                appState.tab = .active
                inputFocused = true
            }
        }
        // ⌘1 로 할 일 탭에 돌아왔을 때도 바로 입력 가능하게
        .onChange(of: appState.tab) { _, newTab in
            if newTab == .active, appState.listVisible {
                inputFocused = true
            }
        }
    }

    private var listPage: some View {
        VStack(spacing: 0) {
            header
            if tab == .active { input }
            Divider().opacity(0.4)
            switch tab {
            case .active: list
            case .done: completedList
            case .calendar: CalendarTabView(store: store, calendar: calendar) { selectedID = $0 }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            tabButton("할 일", count: activeTodos.count, tab: .active).help("⌘1")
            tabButton("완료", count: doneCount, tab: .done).help("⌘2")
            tabButton("달력", count: 0, tab: .calendar).help("⌘3")
            Spacer(minLength: 0)
            Menu {
                // 기록을 지우는 동작이라 한 단계 더 확인을 받는다
                Menu("완료 기록 비우기") {
                    Button("\(doneCount)개 모두 삭제", role: .destructive) {
                        store.clearCompleted()
                    }
                }
                .disabled(doneCount == 0)
                Divider()
                Button("종료") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 7)
    }

    private func tabButton(_ title: String, count: Int, tab target: TodoTab) -> some View {
        let selected = tab == target
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { appState.tab = target }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(selected ? Color.primary.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var input: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
            TextField("할 일 추가", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($inputFocused)
                .onSubmit {
                    store.add(newTitle)
                    newTitle = ""
                    inputFocused = true
                }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if activeTodos.isEmpty {
                    Text("오늘은 뭘 할까요?")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 16)
                }
                ForEach(activeTodos) { todo in
                    TodoRow(todo: todo, store: store) { selectedID = todo.id }
                        .opacity(draggedID == todo.id ? 0.35 : 1)
                        .onDrag {
                            draggedID = todo.id
                            return NSItemProvider(object: todo.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.plainText],
                            delegate: TodoReorderDelegate(targetID: todo.id, draggedID: $draggedID, store: store)
                        )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 행 바깥(여백)에 놓아도 드래그 상태가 풀리도록
        .onDrop(of: [.plainText], isTargeted: nil) { _ in
            draggedID = nil
            return true
        }
        .animation(.spring(duration: 0.25), value: store.todos)
    }

    private var completedList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                if completedGroups.isEmpty {
                    Text("아직 완료한 일이 없어요")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                ForEach(completedGroups) { group in
                    Section {
                        ForEach(group.items) { todo in
                            TodoRow(todo: todo, store: store) { selectedID = todo.id }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text(group.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("\(group.items.count)")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(.tertiary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.25), value: store.todos)
    }
}

struct TodoRow: View {
    let todo: Todo
    let store: TodoStore
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.toggle(todo)
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
                if todo.memo?.isEmpty == false {
                    Image(systemName: "note.text")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            // 완료 항목은 끝낸 시각을 함께 보여준다
            if todo.isDone, !hovering {
                Text(todo.completionDate.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            if hovering {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Button {
                    store.remove(todo)
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
        var text = "\(todo.createdAt.formatted(date: .abbreviated, time: .shortened)) 추가 · \(todo.createdAt.relativeText)"
        if todo.isDone {
            text += "\n\(todo.completionDate.formatted(date: .abbreviated, time: .shortened)) 완료 · \(todo.completionDate.relativeText)"
        }
        return text
    }
}

/// 드래그한 항목이 다른 항목 위로 들어오는 순간 자리를 바꾼다 (라이브 리오더)
private struct TodoReorderDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    let store: TodoStore

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedID else { return }
        withAnimation(.spring(duration: 0.25)) {
            store.move(dragged, to: targetID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

// MARK: - 상세 페이지

private struct TodoDetailView: View {
    let todo: Todo
    let store: TodoStore
    let onBack: () -> Void

    @State private var title: String = ""
    @State private var memo: String = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack {
                Button(action: commitAndBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("목록")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    store.remove(todo)
                    onBack()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("삭제")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 10) {
                // 완료 토글 + 제목
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        store.toggle(todo)
                    } label: {
                        Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(todo.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    }
                    .buttonStyle(.plain)

                    TextField("제목", text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .focused($titleFocused)
                        .onSubmit { store.updateTitle(todo.id, title) }
                }

                // 추가 · 완료 시각
                VStack(alignment: .leading, spacing: 6) {
                    timestamp("clock", "추가", todo.createdAt)
                    if todo.isDone {
                        timestamp("checkmark.circle", "완료", todo.completionDate)
                    }
                }

                // 메모
                VStack(alignment: .leading, spacing: 4) {
                    Text("메모")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $memo)
                        .font(.system(size: 11))
                        .scrollContentBackground(.hidden)
                        .frame(height: 80)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.05))
                        )
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            title = todo.title
            memo = todo.memo ?? ""
        }
        .onDisappear {
            store.updateTitle(todo.id, title)
            store.updateMemo(todo.id, memo)
        }
    }

    private func timestamp(_ icon: String, _ label: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text("\(label) · \(date.formatted(date: .complete, time: .shortened))")
            } icon: {
                Image(systemName: icon)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            Text(date.relativeText)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.leading, 18)
        }
    }

    private func commitAndBack() {
        store.updateTitle(todo.id, title)
        store.updateMemo(todo.id, memo)
        onBack()
    }
}

extension Date {
    /// "3시간 전" 같은 상대 시간 문자열
    var relativeText: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: self, relativeTo: Date())
    }
}
