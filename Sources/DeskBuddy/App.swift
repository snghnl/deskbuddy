import AppKit
import SwiftUI

// Borderless panels cannot become key windows by default, which blocks text input — allow it via subclass
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Panel for the character — never takes focus
final class CharacterPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Transparent event catcher layered over the character — distinguishes clicks from drags (window moves)
final class ClickCatcherView: NSView {
    var onClick: (() -> Void)?
    var onMoved: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onPressDown: (() -> Void)?
    var onPressUp: (() -> Void)?
    /// Fired on a fast release — the velocity at release time (pt/s, screen coordinates)
    var onThrow: ((CGVector) -> Void)?

    /// Releasing above this speed (pt/s) counts as a throw instead of a move
    private let throwSpeedThreshold: CGFloat = 420

    private var downLocation: NSPoint = .zero
    private var dragging = false
    /// Recent mouse trail — used to compute the release velocity
    private var samples: [(time: TimeInterval, point: NSPoint)] = []

    override func mouseDown(with event: NSEvent) {
        // Treat control-click as right-click (macOS convention)
        if event.modifierFlags.contains(.control) {
            onRightClick?(event)
            return
        }
        downLocation = event.locationInWindow
        dragging = false
        samples = [(event.timestamp, NSEvent.mouseLocation)]
        onPressDown?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let loc = event.locationInWindow
        let dx = loc.x - downLocation.x
        let dy = loc.y - downLocation.y
        if !dragging && hypot(dx, dy) < 3 { return }
        dragging = true
        window.setFrameOrigin(NSPoint(x: window.frame.origin.x + dx, y: window.frame.origin.y + dy))

        samples.append((event.timestamp, NSEvent.mouseLocation))
        samples.removeAll { event.timestamp - $0.time > 0.12 }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            if let velocity = releaseVelocity(at: event.timestamp),
               hypot(velocity.dx, velocity.dy) > throwSpeedThreshold {
                onThrow?(velocity)
            } else {
                onMoved?()
            }
        } else {
            onClick?()
        }
        dragging = false
        samples = []
        onPressUp?()
    }

    /// Average velocity over the last 0.12s of the drag trail. Returns nil if the drag had stopped before release.
    /// mouseUp can arrive later than the actual finger release (trackpad drag-end delay),
    /// so we compute from the sample window itself rather than filtering by the mouseUp timestamp.
    private func releaseVelocity(at time: TimeInterval) -> CGVector? {
        guard let first = samples.first, let last = samples.last,
              time - last.time < 0.35,          // if the pointer stopped well before release, it is not a throw
              last.time - first.time > 0.008 else { return nil }
        let dt = CGFloat(last.time - first.time)
        return CGVector(
            dx: (last.point.x - first.point.x) / dt,
            dy: (last.point.y - first.point.y) / dt
        )
    }
}

/// Resize grip in the bottom-right corner of the list panel — adjusts the window frame directly in screen coordinates
final class ResizeGripView: NSView {
    var onResize: ((CGSize) -> Void)?

    private var startMouse: NSPoint = .zero
    private var startSize: CGSize = .zero

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startSize = window?.frame.size ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = NSEvent.mouseLocation
        onResize?(CGSize(
            width: startSize.width + (loc.x - startMouse.x),
            height: startSize.height + (startMouse.y - loc.y)  // dragging down grows the window
        ))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var characterPanel: CharacterPanel!
    private var listPanel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var wander: WanderController!
    private var thrower: ThrowController!
    private var hotKeys: HotKeyCenter!
    private var settingsWindow: NSWindow?
    private var bubble: BubbleController!
    private var eventNotifier: EventNotifier!
    private let store = TodoStore()
    private let appState = AppState()
    private let calendarService = CalendarService()

    /// Situations where wandering must pause temporarily, e.g. while a menu is open
    private var wanderSuspended = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: [
            SettingsKeys.throwEnabled: true,
            SettingsKeys.showCalendar: true,
            SettingsKeys.eventAlerts: true,
            SettingsKeys.eventAlertLead: 10,
        ])
        setupCharacterPanel()
        setupListPanel()
        setupStatusItem()
        setupWander()
        setupThrow()
        setupHotKeys()

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: .settingsChanged, object: nil
        )

        setupTabShortcuts()
        setupBubble()
    }

    // MARK: - URL scheme (agent integration)

    /// deskbuddy://notify?message=...&autohide=8
    /// deskbuddy://add?title=...&memo=...
    /// deskbuddy://done?id=<uuid>
    /// deskbuddy://toggle
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handleURL(url) }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "deskbuddy" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        func query(_ name: String) -> String? {
            components?.queryItems?.first { $0.name == name }?.value
        }

        switch url.host {
        case "notify":
            guard let message = query("message") ?? query("text"), !message.isEmpty else { return }
            if !characterPanel.isVisible { characterPanel.orderFrontRegardless() }
            let autoHide = query("autohide").flatMap(Double.init)
            bubble.show(message, autoHide: autoHide)   // stays until clicked by default

        case "add":
            guard let title = query("title"), !title.isEmpty else { return }
            store.add(title)
            if let memo = query("memo"), !memo.isEmpty,
               let added = store.todos.first(where: { $0.title == title.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                store.updateMemo(added.id, memo)
            }
            if !characterPanel.isVisible { characterPanel.orderFrontRegardless() }
            bubble.show(L.f("bubble.added", title), autoHide: 5)

        case "done":
            guard let id = query("id"),
                  let todo = store.todos.first(where: { $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame })
            else { return }
            if !todo.isDone { store.toggle(todo) }
            if !characterPanel.isVisible { characterPanel.orderFrontRegardless() }
            bubble.show(L.f("bubble.done", todo.title), autoHide: 5)

        case "toggle":
            if !characterPanel.isVisible { characterPanel.orderFrontRegardless() }
            toggleList()

        default:
            break
        }
    }

    // MARK: - Speech bubble · event alerts

    private func setupBubble() {
        bubble = BubbleController(characterPanel: characterPanel)
        bubble.onVisibleChange = { [weak self] visible in
            self?.appState.talking = visible
        }

        eventNotifier = EventNotifier(calendar: calendarService)
        eventNotifier.onNotify = { [weak self] message in
            guard let self, characterPanel.isVisible else { return }
            bubble.show(message)   // stays until clicked
        }
        eventNotifier.start()
    }

    /// ⌘1/⌘2/⌘3 switch tabs while the list panel is up
    private func setupTabShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  listPanel.isVisible, listPanel.isKeyWindow,
                  event.modifierFlags.intersection([.command, .option, .control]) == .command
            else { return event }

            let tab: TodoTab? = switch event.charactersIgnoringModifiers {
            case "1": .active
            case "2": .done
            case "3": .calendar
            default: nil
            }
            guard let tab else { return event }
            withAnimation(.easeOut(duration: 0.15)) { self.appState.tab = tab }
            return nil   // consume the event
        }
    }

    @objc private func settingsChanged() {
        updateWander()
        reloadHotKey()
        rebuildStatusMenu()                  // reflect a language change
        appState.objectWillChange.send()     // re-render SwiftUI views that observe appState
    }

    // MARK: - Character panel

    private func setupCharacterPanel() {
        characterPanel = CharacterPanel(
            contentRect: NSRect(x: 0, y: 0, width: 76, height: 84),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        characterPanel.level = .floating
        characterPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        characterPanel.isOpaque = false
        characterPanel.backgroundColor = .clear
        characterPanel.hasShadow = false   // the character draws its own shadow
        characterPanel.hidesOnDeactivate = false
        characterPanel.isReleasedWhenClosed = false

        let container = NSView()
        let hosting = NSHostingView(rootView: CharacterView(store: store, appState: appState))
        let catcher = ClickCatcherView()
        catcher.onClick = { [weak self] in self?.toggleList() }
        catcher.onMoved = { [weak self] in
            self?.saveFrame()
            self?.repositionList()
        }
        catcher.onRightClick = { [weak self] event in self?.showContextMenu(event) }
        // While being held the character must not move on its own; if mid-flight, this catches it
        catcher.onPressDown = { [weak self] in
            self?.thrower.cancel()
            self?.suspendWander(true)
        }
        catcher.onPressUp = { [weak self] in self?.suspendWander(false) }
        catcher.onThrow = { [weak self] velocity in self?.startThrow(velocity) }
        for view in [hosting, catcher] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }
        characterPanel.contentView = container

        restoreFrame()
        characterPanel.orderFrontRegardless()
    }

    // MARK: - List panel

    private func setupListPanel() {
        listPanel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: savedListSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        listPanel.level = .floating
        listPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        listPanel.isOpaque = false
        listPanel.backgroundColor = .clear
        listPanel.hasShadow = true
        // Moving is character-drag only — background dragging conflicts with item drag (reordering)
        listPanel.isMovableByWindowBackground = false
        listPanel.hidesOnDeactivate = false
        listPanel.becomesKeyOnlyIfNeeded = true
        listPanel.isReleasedWhenClosed = false

        // AppKit owns the window size; the SwiftUI view just fills whatever it is given
        let container = NSView()
        let hosting = NSHostingView(rootView: TodoListView(store: store, appState: appState, calendar: calendarService))
        hosting.sizingOptions = []
        let grip = ResizeGripView()
        grip.onResize = { [weak self] size in self?.applyListSize(size) }

        hosting.translatesAutoresizingMaskIntoConstraints = false
        grip.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        container.addSubview(grip)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            grip.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            grip.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            grip.widthAnchor.constraint(equalToConstant: 22),
            grip.heightAnchor.constraint(equalToConstant: 22),
        ])
        listPanel.contentView = container
    }

    private func toggleList() {
        if listPanel.isVisible {
            characterPanel.removeChildWindow(listPanel)
            listPanel.orderOut(nil)
            appState.listVisible = false
        } else {
            repositionList()
            calendarService.refresh()   // refresh events every time the list opens
            // As a child window the list follows automatically when the character is dragged
            characterPanel.addChildWindow(listPanel, ordered: .above)
            listPanel.orderFrontRegardless()
            listPanel.makeKey()
            appState.listVisible = true
        }
        updateWander()   // no wandering while the list is open
    }

    /// Positions the list near the character (below preferred, above if there is no room)
    private func repositionList() {
        let charFrame = characterPanel.frame
        let size = listPanel.frame.size
        let screen = characterPanel.screen ?? NSScreen.main
        let vis = screen?.visibleFrame ?? .zero

        var x = charFrame.maxX - size.width  // align right edges
        var y = charFrame.minY - size.height - 8
        if y < vis.minY { y = charFrame.maxY + 8 }
        x = max(vis.minX + 8, min(x, vis.maxX - size.width - 8))

        listPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - List resizing

    private let listSizeKey = "DeskBuddy.listSize"

    private var savedListSize: CGSize {
        if let saved = UserDefaults.standard.string(forKey: listSizeKey) {
            return NSSizeFromString(saved)
        }
        return CGSize(width: 260, height: 380)
    }

    private func applyListSize(_ proposed: CGSize) {
        let w = min(max(proposed.width, 200), 520)
        let h = min(max(proposed.height, 240), 760)
        var f = listPanel.frame
        f.origin.y = f.maxY - h  // keep the top edge fixed — grow down and to the right
        f.size = CGSize(width: w, height: h)
        listPanel.setFrame(f, display: true)
        UserDefaults.standard.set(NSStringFromSize(f.size), forKey: listSizeKey)
    }

    // MARK: - Wandering

    private var wanderEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKeys.wander) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.wander) }
    }

    private func setupWander() {
        wander = WanderController(
            panel: characterPanel,
            onWalk: { [weak self] walking, facingRight in
                self?.appState.walking = walking
                self?.appState.facingRight = facingRight
            },
            onSettled: { [weak self] in self?.saveFrame() }
        )
        updateWander()
    }

    /// Decides whether the character should actually be moving, combining settings, list state, and user interaction
    private func updateWander() {
        let shouldRun = wanderEnabled
            && !wanderSuspended
            && !listPanel.isVisible
            && characterPanel.isVisible
            && !(thrower?.isFlying ?? false)
        if shouldRun {
            wander.start()
        } else {
            wander.stop()
        }
    }

    private func suspendWander(_ suspended: Bool) {
        wanderSuspended = suspended
        updateWander()
    }

    @objc private func toggleWander() {
        wanderEnabled.toggle()
        // Close the list before wandering (an open list would trail the character and be unusable)
        if wanderEnabled, listPanel.isVisible { toggleList() } else { updateWander() }
    }

    @objc private func sendHome() {
        // "Send home" implies staying put, so turn wandering off (otherwise it walks away immediately)
        wanderEnabled = false
        updateWander()

        guard let screen = characterPanel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = characterPanel.frame.size
        characterPanel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24
        ))
        saveFrame()
        repositionList()
    }

    // MARK: - Throwing

    private func setupThrow() {
        thrower = ThrowController(
            panel: characterPanel,
            onFlight: { [weak self] flying in
                guard let self else { return }
                appState.flying = flying
                updateWander()   // pause wandering during flight, resume after landing
                // Fold the bubble while airborne and reopen it at the new position after landing
                if flying { bubble.suspend() } else { bubble.resume() }
            },
            onSettled: { [weak self] in self?.saveFrame() }
        )
    }

    private func startThrow(_ velocity: CGVector) {
        // If disabled in settings, treat it as a normal move
        guard UserDefaults.standard.bool(forKey: SettingsKeys.throwEnabled) else {
            saveFrame()
            repositionList()
            return
        }
        // Close the list first — throwing with it attached would fling the list around too
        if listPanel.isVisible { toggleList() }
        appState.facingRight = velocity.dx >= 0
        thrower.throwPanel(with: velocity)
    }

    // MARK: - Global hotkey

    private func setupHotKeys() {
        hotKeys = HotKeyCenter()
        hotKeys.onTrigger = { [weak self] in self?.hotKeyTriggered() }
        reloadHotKey()
    }

    private func reloadHotKey() {
        let defaults = UserDefaults.standard
        let keyCode = defaults.object(forKey: SettingsKeys.hotkeyKeyCode) as? Int ?? -1
        hotKeys.apply(keyCode: keyCode, modifierFlags: defaults.integer(forKey: SettingsKeys.hotkeyModifiers))
    }

    private func hotKeyTriggered() {
        // Bring the character out first if it is hidden
        if !characterPanel.isVisible {
            characterPanel.orderFrontRegardless()
        }
        thrower.cancel()
        toggleList()
    }

    // MARK: - Settings window

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(calendar: calendarService)))
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.title = L.s("app.settings_title")
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Context menu

    private func showContextMenu(_ event: NSEvent) {
        guard let view = characterPanel.contentView else { return }
        let menu = NSMenu()
        menu.delegate = self

        let listItem = NSMenuItem(
            title: listPanel.isVisible
                ? L.s("app.close_to_do_list")
                : L.s("app.open_to_do_list"),
            action: #selector(toggleListFromMenu), keyEquivalent: ""
        )
        listItem.target = self
        menu.addItem(listItem)

        menu.addItem(.separator())

        let wanderItem = NSMenuItem(
            title: L.s("app.wander_around"), action: #selector(toggleWander), keyEquivalent: ""
        )
        wanderItem.target = self
        wanderItem.state = wanderEnabled ? .on : .off
        menu.addItem(wanderItem)

        let homeItem = NSMenuItem(title: L.s("app.send_home"), action: #selector(sendHome), keyEquivalent: "")
        homeItem.target = self
        menu.addItem(homeItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L.s("app.settings"), action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let hideItem = NSMenuItem(title: L.s("app.hide_character"), action: #selector(toggleCharacter), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        menu.addItem(withTitle: L.s("app.quit_deskbuddy"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func toggleListFromMenu() {
        toggleList()
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "checklist", accessibilityDescription: "DeskBuddy"
        )
        rebuildStatusMenu()
    }

    /// Rebuilt on setup and whenever the language changes
    private func rebuildStatusMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()
        let toggleItem = NSMenuItem(
            title: L.s("app.show_hide_character"),
            action: #selector(toggleCharacter), keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        let settingsItem = NSMenuItem(title: L.s("app.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: L.s("app.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func toggleCharacter() {
        if characterPanel.isVisible {
            if listPanel.isVisible { toggleList() }
            characterPanel.orderOut(nil)
        } else {
            characterPanel.orderFrontRegardless()
        }
        updateWander()
    }

    // MARK: - Position memory

    private let frameKey = "DeskBuddy.characterFrame"

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(characterPanel.frame), forKey: frameKey)
    }

    private func restoreFrame() {
        if let saved = UserDefaults.standard.string(forKey: frameKey) {
            characterPanel.setFrameOrigin(NSRectFromString(saved).origin)
        } else if let screen = NSScreen.main {
            // Default position: top-right corner
            let vis = screen.visibleFrame
            let size = characterPanel.frame.size
            characterPanel.setFrameOrigin(NSPoint(
                x: vis.maxX - size.width - 24,
                y: vis.maxY - size.height - 24
            ))
        }
    }
}

/// Keeps the character still while a menu is open (otherwise the menu's anchor point drifts)
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        suspendWander(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        suspendWander(false)
    }
}

@main
struct DeskBuddyMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
