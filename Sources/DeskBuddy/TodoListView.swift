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
        // Shows the resize grip (the actual drag handling is done by ResizeGripView)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(.degrees(-45))
                .foregroundStyle(.tertiary)
                .padding(7)
        }
        // Focus the input as soon as the list opens (whether by click or shortcut) so typing works immediately
        .onChange(of: appState.listVisible) { _, visible in
            if visible {
                appState.tab = .active
                inputFocused = true
            }
        }
        // Also allow immediate typing when returning to the To Do tab via ⌘1
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
            tabButton(L.t("할 일", "To Do"), count: activeTodos.count, tab: .active).help("⌘1")
            tabButton(L.t("완료", "Done"), count: doneCount, tab: .done).help("⌘2")
            tabButton(L.t("달력", "Calendar"), count: 0, tab: .calendar).help("⌘3")
            Spacer(minLength: 0)
            Menu {
                // Destructive action that erases history, so require one extra confirmation step
                Menu(L.t("완료 기록 비우기", "Clear Completed History")) {
                    Button(L.t("\(doneCount)개 모두 삭제", "Delete All \(doneCount)"), role: .destructive) {
                        store.clearCompleted()
                    }
                }
                .disabled(doneCount == 0)
                Divider()
                Button(L.t("종료", "Quit")) { NSApp.terminate(nil) }
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
            TextField(L.t("할 일 추가", "Add a to-do"), text: $newTitle)
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
                    Text(L.t("오늘은 뭘 할까요?", "What shall we do today?"))
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
        // Clear the drag state even when dropping outside the rows (in the padding area)
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
                    Text(L.t("아직 완료한 일이 없어요", "Nothing completed yet"))
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

            // Completed items also show the time they were finished
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
        var text = L.t(
            "\(todo.createdAt.formatted(date: .abbreviated, time: .shortened)) 추가 · \(todo.createdAt.relativeText)",
            "Added \(todo.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(todo.createdAt.relativeText)"
        )
        if todo.isDone {
            text += L.t(
                "\n\(todo.completionDate.formatted(date: .abbreviated, time: .shortened)) 완료 · \(todo.completionDate.relativeText)",
                "\nCompleted \(todo.completionDate.formatted(date: .abbreviated, time: .shortened)) · \(todo.completionDate.relativeText)"
            )
        }
        return text
    }
}

/// Swaps positions the moment the dragged item enters another item's area (live reorder)
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

// MARK: - Detail page

private struct TodoDetailView: View {
    let todo: Todo
    let store: TodoStore
    let onBack: () -> Void

    @State private var title: String = ""
    @State private var memo: String = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button(action: commitAndBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L.t("목록", "List"))
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
                .help(L.t("삭제", "Delete"))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 10) {
                // Done toggle + title
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        store.toggle(todo)
                    } label: {
                        Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(todo.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    }
                    .buttonStyle(.plain)

                    TextField(L.t("제목", "Title"), text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .focused($titleFocused)
                        .onSubmit { store.updateTitle(todo.id, title) }
                }

                // Created / completed timestamps
                VStack(alignment: .leading, spacing: 6) {
                    timestamp("clock", L.t("추가", "Added"), todo.createdAt)
                    if todo.isDone {
                        timestamp("checkmark.circle", L.t("완료", "Completed"), todo.completionDate)
                    }
                }

                // Memo
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("메모", "Memo"))
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
    /// Relative time string like "3 hours ago"
    var relativeText: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: self, relativeTo: Date())
    }
}
