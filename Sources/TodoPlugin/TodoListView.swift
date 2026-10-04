import DeskBuddyCore
import DeskBuddyMacUI
import SwiftUI
import TodoAPI
import UniformTypeIdentifiers

/// What's typed into the to-do input. Kept outside the view because switching tabs or opening
/// a to-do's detail tears the input down, and the text should still be there on the way back.
@MainActor
@Observable
final class TodoDraft {
    var title = ""
}

/// The input above the To Do tab
struct TodoInputBar: View {
    let store: TodoStore
    @Bindable var draft: TodoDraft
    @Environment(\.listPanelVisible) private var listVisible
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
            TextField(strings.s("list.add_placeholder"), text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
                .onSubmit {
                    store.add(draft.title)
                    draft.title = ""
                    focused = true
                }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        // Focus as soon as the list opens or this tab is picked (click or ⌘1) so typing works immediately
        .onAppear { focused = true }
        .onChange(of: listVisible) { _, visible in
            if visible {
                focused = true
            }
        }
    }
}

/// The To Do tab
struct ActiveTodoList: View {
    let store: TodoStore
    let slots: SlotRegistry

    @Environment(\.listPage) private var listPage
    @State private var draggedID: UUID?

    private var activeTodos: [Todo] { store.activeTodos }

    var body: some View {
        let accessories = slots.contributions(to: TodoSlots.rowAccessory)
        ScrollView {
            LazyVStack(spacing: 2) {
                if activeTodos.isEmpty {
                    Text(strings.s("list.empty_state"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 16)
                }
                ForEach(activeTodos) { todo in
                    TodoRow(todo: todo, store: store, accessories: accessories) {
                        listPage.present(TodoDetailPage(id: todo.id, store: store))
                    }
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
}

/// The Done tab
struct CompletedTodoList: View {
    let store: TodoStore

    @Environment(\.listPage) private var listPage

    private var completedGroups: [CompletedGroup] { store.completedGroups }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                if completedGroups.isEmpty {
                    Text(strings.s("list.nothing_completed_yet"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                ForEach(completedGroups) { group in
                    Section {
                        ForEach(group.items) { todo in
                            TodoRow(todo: todo, store: store) {
                                listPage.present(TodoDetailPage(id: todo.id, store: store))
                            }
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

/// A to-do's detail as a list panel page. Looks the to-do up on every render so changes made
/// elsewhere show up, and goes back to the list if the to-do is deleted while open.
struct TodoDetailPage: View {
    let id: UUID
    let store: TodoStore

    @Environment(\.listPage) private var listPage

    var body: some View {
        if let todo = store.todos.first(where: { $0.id == id }) {
            TodoDetailView(todo: todo, store: store) { listPage.dismiss() }
        } else {
            Color.clear.onAppear { listPage.dismiss() }
        }
    }
}

/// The completion history rows in Settings
struct HistorySettingsRows: View {
    let store: TodoStore

    @State private var confirmingDelete = false

    // Every row is label-plus-trailing-control, matching the rest of the form
    var body: some View {
        LabeledContent(strings.s("settings.history_total")) {
            Text(strings.f("settings.history_count", store.completedTodos.count))
                .foregroundStyle(.secondary)
        }

        if store.hiddenCompletedCount > 0 {
            LabeledContent(strings.s("settings.history_hidden_label")) {
                HStack(spacing: 8) {
                    Text(strings.f("settings.history_count", store.hiddenCompletedCount))
                        .foregroundStyle(.secondary)
                    Button(strings.s("settings.history_restore")) { store.restoreClearedHistory() }
                }
            }
        }

        LabeledContent(strings.s("settings.history_delete_label")) {
            // Ellipsis: macOS convention for an action that asks first
            Button(strings.s("settings.history_delete_button"), role: .destructive) {
                confirmingDelete = true
            }
            .disabled(store.completedTodos.isEmpty)
        }
        .confirmationDialog(
            strings.f("settings.history_confirm_title", store.completedTodos.count),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(strings.s("settings.history_confirm_delete"), role: .destructive) {
                store.deleteCompleted()
            }
            Button(strings.s("settings.cancel"), role: .cancel) {}
        } message: {
            Text(strings.s("settings.history_confirm_message"))
        }
    }
}

struct TodoRow: View {
    let todo: Todo
    let store: TodoStore
    /// Shown after the title. Only the To Do tab passes these.
    var accessories: [TodoRowAccessory] = []
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
                ForEach(accessories, id: \.id) { accessory in
                    accessory.content(todo.id).swiftUI
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
        var text = strings.f("list.tooltip_added",
                       todo.createdAt.formatted(date: .abbreviated, time: .shortened),
                       todo.createdAt.relativeText)
        if todo.isDone {
            text += "\n" + strings.f("list.tooltip_completed",
                               todo.completionDate.formatted(date: .abbreviated, time: .shortened),
                               todo.completionDate.relativeText)
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
                        Text(strings.s("list.list"))
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
                .help(strings.s("settings.delete"))
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

                    TextField(strings.s("list.title"), text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .focused($titleFocused)
                        .onSubmit { store.updateTitle(todo.id, title) }
                }

                // Created / completed timestamps
                VStack(alignment: .leading, spacing: 6) {
                    timestamp("clock", strings.s("list.added"), todo.createdAt)
                    if todo.isDone {
                        timestamp("checkmark.circle", strings.s("list.completed"), todo.completionDate)
                    }
                }

                // Memo
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.s("list.memo"))
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
