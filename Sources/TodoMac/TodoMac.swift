import DeskBuddyCore
import DeskBuddyMacUI
import Foundation
import SwiftUI
import TodoAPI
import TodoPlugin

/// To-dos on macOS: the To Do and Done tabs, the detail page, the history rows in Settings
package struct TodoMac: TodoPlatform {
    package init() {}

    package func show(_ store: TodoStore, in context: PluginContext) {
        let slots = context.slots
        let draft = TodoDraft()
        slots.contribute(CoreSlots.listTabs, ListTab(
            id: "todo.active", order: 100,
            title: { strings.s("list.to_do") },
            count: { store.activeTodos.count },
            toolbar: { AnyView(TodoInputBar(store: store, draft: draft)) }
        ) {
            ActiveTodoList(store: store, slots: slots)
        })
        slots.contribute(CoreSlots.listTabs, ListTab(
            id: "todo.done", order: 200,
            title: { strings.s("list.done") },
            count: { store.visibleCompleted.count }
        ) {
            CompletedTodoList(store: store)
        })
        slots.contribute(CoreSlots.settingsSections, SettingsSection(
            id: "todo.history", order: 500,
            title: { strings.s("settings.history") },
            footer: { strings.s("settings.history_footer") }
        ) {
            HistorySettingsRows(store: store)
        })
    }

    package func showDetail(of id: UUID, in store: TodoStore, buddy: any Buddy) {
        buddy.openList(on: MacView(TodoDetailPage(id: id, store: store)))
    }
}
