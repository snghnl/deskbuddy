import AppKit
import DeskBuddyCore
import SwiftUI

/// The panel that opens under the buddy. It owns the tab bar, the ⋯ menu and the page shown
/// over everything; what the tabs hold comes from features through `CoreSlots.listTabs`.
struct ListPanelView: View {
    @ObservedObject var appState: AppState
    let slots: SlotRegistry
    @AppStorage(SettingsKeys.liquidGlass) private var liquidGlass = false

    private var tabs: [ListTab] { slots.contributions(to: CoreSlots.listTabs) }
    private var selectedTab: ListTab? { tabs.first { $0.id == appState.tab } ?? tabs.first }

    var body: some View {
        Group {
            if let page = appState.listPage {
                page
            } else {
                tabPage
            }
        }
        // Tabs open pages through this; plugins outside the panel go through Buddy.openList
        .environment(\.listPage, ListPageAction(present: { appState.listPage = $0 }, dismiss: { appState.listPage = nil }))
        .environment(\.listPanelVisible, appState.listVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .buddyBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Shows the resize grip (the actual drag handling is done by ResizeGripView)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(.degrees(-45))
                .foregroundStyle(.tertiary)
                .padding(7)
        }
        // The list always opens on the first tab
        .onChange(of: appState.listVisible) { _, visible in
            if visible {
                appState.tab = tabs.first?.id
            }
        }
        // Outermost, so the background above and every tab's content see it
        .environment(\.glassEnabled, liquidGlass && Appearance.supportsGlass)
    }

    private var tabPage: some View {
        VStack(spacing: 0) {
            header
            if let toolbar = selectedTab?.toolbar {
                toolbar().id(selectedTab?.id)
            }
            Divider().opacity(0.4)
            // Keyed by tab, so two tabs never share view state
            selectedTab?.content().id(selectedTab?.id)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                tabButton(tab).help(index < 9 ? "⌘\(index + 1)" : "")
            }
            Spacer(minLength: 0)
            menu
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 7)
    }

    private func tabButton(_ tab: ListTab) -> some View {
        let selected = tab.id == selectedTab?.id
        let count = tab.count()
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { appState.tab = tab.id }
        } label: {
            HStack(spacing: 4) {
                Text(tab.title())
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

    private var menu: some View {
        Menu {
            let items = slots.contributions(to: CoreSlots.listMenu).filter { $0.isVisible() }
            ForEach(items, id: \.id) { item in
                Button(item.title()) { item.action() }
                    .disabled(!item.isEnabled())
            }
            if !items.isEmpty {
                Divider()
            }
            Button(strings.s("app.quit")) { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
