import AppKit
import SwiftUI

// 보더리스 패널은 기본적으로 key window 가 될 수 없어 텍스트 입력이 막힌다 — 서브클래스로 허용
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 캐릭터용 패널 — 포커스를 갖지 않는다
final class CharacterPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 캐릭터 위에 얹는 투명 이벤트 캐처 — 클릭과 드래그(윈도우 이동)를 직접 구분한다
final class ClickCatcherView: NSView {
    var onClick: (() -> Void)?
    var onMoved: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onPressDown: (() -> Void)?
    var onPressUp: (() -> Void)?
    /// 빠르게 놓았을 때 — 놓는 순간의 속도(pt/s, 화면 좌표)
    var onThrow: ((CGVector) -> Void)?

    /// 이 속도(pt/s)를 넘겨 놓으면 이동이 아니라 던지기로 취급한다
    private let throwSpeedThreshold: CGFloat = 420

    private var downLocation: NSPoint = .zero
    private var dragging = false
    /// 최근 마우스 궤적 — 놓는 순간의 속도 계산용
    private var samples: [(time: TimeInterval, point: NSPoint)] = []

    override func mouseDown(with event: NSEvent) {
        // control-클릭도 우클릭으로 취급 (macOS 관례)
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

    /// 드래그 마지막 0.12초 궤적으로 평균 속도를 구한다. 끌다 멈춘 채 놓으면 nil.
    /// mouseUp 은 실제 손을 뗀 시점보다 늦게 올 수 있으므로(트랙패드 드래그 종료 지연),
    /// mouseUp 시각으로 샘플을 거르지 않고 샘플 윈도우 자체로 계산한다.
    private func releaseVelocity(at time: TimeInterval) -> CGVector? {
        guard let first = samples.first, let last = samples.last,
              time - last.time < 0.35,          // 놓기 한참 전에 이미 멈춰 있었다면 던지기가 아니다
              last.time - first.time > 0.008 else { return nil }
        let dt = CGFloat(last.time - first.time)
        return CGVector(
            dx: (last.point.x - first.point.x) / dt,
            dy: (last.point.y - first.point.y) / dt
        )
    }
}

/// 리스트 패널 오른쪽 아래 구석의 리사이즈 그립 — 화면 좌표 기준으로 윈도우 프레임을 직접 조절한다
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
            height: startSize.height + (startMouse.y - loc.y)  // 아래로 끌면 커진다
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
    private let store = TodoStore()
    private let appState = AppState()
    private let calendarService = CalendarService()

    /// 메뉴가 열려있는 등 일시적으로 자유 이동을 멈춰야 하는 상황
    private var wanderSuspended = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: [
            SettingsKeys.throwEnabled: true,
            SettingsKeys.showCalendar: true,
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
    }

    /// 목록 패널이 떠 있을 때 ⌘1/⌘2/⌘3 으로 탭 전환
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
            return nil   // 이벤트 소비
        }
    }

    @objc private func settingsChanged() {
        updateWander()
        reloadHotKey()
    }

    // MARK: - 캐릭터 패널

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
        characterPanel.hasShadow = false   // 캐릭터가 자체 그림자를 그린다
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
        // 잡고 있는 동안에는 스스로 움직이지 않고, 날아가던 중이면 잡아챈다
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

    // MARK: - 리스트 패널

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
        // 이동은 캐릭터 드래그로만 — 배경 드래그 이동은 아이템 드래그(순서 변경)와 충돌한다
        listPanel.isMovableByWindowBackground = false
        listPanel.hidesOnDeactivate = false
        listPanel.becomesKeyOnlyIfNeeded = true
        listPanel.isReleasedWhenClosed = false

        // 윈도우 크기는 여기(AppKit)가 주도하고, SwiftUI 뷰는 그 크기를 채우기만 한다
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
            calendarService.refresh()   // 열 때마다 최신 일정으로
            // child window 로 붙이면 캐릭터를 끌 때 리스트가 자동으로 따라온다
            characterPanel.addChildWindow(listPanel, ordered: .above)
            listPanel.orderFrontRegardless()
            listPanel.makeKey()
            appState.listVisible = true
        }
        updateWander()   // 목록이 열려있는 동안에는 돌아다니지 않는다
    }

    /// 리스트를 캐릭터 근처(아래 우선, 공간 없으면 위)에 붙인다
    private func repositionList() {
        let charFrame = characterPanel.frame
        let size = listPanel.frame.size
        let screen = characterPanel.screen ?? NSScreen.main
        let vis = screen?.visibleFrame ?? .zero

        var x = charFrame.maxX - size.width  // 오른쪽 모서리 정렬
        var y = charFrame.minY - size.height - 8
        if y < vis.minY { y = charFrame.maxY + 8 }
        x = max(vis.minX + 8, min(x, vis.maxX - size.width - 8))

        listPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - 리스트 크기 조절

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
        f.origin.y = f.maxY - h  // 위 모서리 고정 — 아래·오른쪽으로 늘어난다
        f.size = CGSize(width: w, height: h)
        listPanel.setFrame(f, display: true)
        UserDefaults.standard.set(NSStringFromSize(f.size), forKey: listSizeKey)
    }

    // MARK: - 자유 이동

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

    /// 설정·목록 상태·사용자 조작을 모두 반영해 실제로 움직여야 하는지 결정한다
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
        // 돌아다니려면 목록은 닫는다 (열려 있으면 목록이 캐릭터를 따라다녀 쓰기 어렵다)
        if wanderEnabled, listPanel.isVisible { toggleList() } else { updateWander() }
    }

    @objc private func sendHome() {
        // 제자리에 두라는 뜻이므로 자유 이동은 끈다 (안 그러면 곧바로 다시 걸어나간다)
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

    // MARK: - 던지기

    private func setupThrow() {
        thrower = ThrowController(
            panel: characterPanel,
            onFlight: { [weak self] flying in
                self?.appState.flying = flying
                self?.updateWander()   // 나는 동안에는 배회를 멈추고, 착지하면 재개
            },
            onSettled: { [weak self] in self?.saveFrame() }
        )
    }

    private func startThrow(_ velocity: CGVector) {
        // 설정에서 껐으면 일반 이동으로 처리
        guard UserDefaults.standard.bool(forKey: SettingsKeys.throwEnabled) else {
            saveFrame()
            repositionList()
            return
        }
        // 목록을 매단 채 던지면 목록이 같이 날아다니므로 접는다
        if listPanel.isVisible { toggleList() }
        appState.facingRight = velocity.dx >= 0
        thrower.throwPanel(with: velocity)
    }

    // MARK: - 글로벌 단축키

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
        // 캐릭터가 숨겨져 있으면 먼저 꺼낸다
        if !characterPanel.isVisible {
            characterPanel.orderFrontRegardless()
        }
        thrower.cancel()
        toggleList()
    }

    // MARK: - 설정 창

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(calendar: calendarService)))
            window.title = "DeskBuddy 설정"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 우클릭 메뉴

    private func showContextMenu(_ event: NSEvent) {
        guard let view = characterPanel.contentView else { return }
        let menu = NSMenu()
        menu.delegate = self

        let listItem = NSMenuItem(
            title: listPanel.isVisible ? "할 일 목록 닫기" : "할 일 목록 열기",
            action: #selector(toggleListFromMenu), keyEquivalent: ""
        )
        listItem.target = self
        menu.addItem(listItem)

        menu.addItem(.separator())

        let wanderItem = NSMenuItem(
            title: "자유롭게 돌아다니기", action: #selector(toggleWander), keyEquivalent: ""
        )
        wanderItem.target = self
        wanderItem.state = wanderEnabled ? .on : .off
        menu.addItem(wanderItem)

        let homeItem = NSMenuItem(title: "제자리로 보내기", action: #selector(sendHome), keyEquivalent: "")
        homeItem.target = self
        menu.addItem(homeItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let hideItem = NSMenuItem(title: "캐릭터 숨기기", action: #selector(toggleCharacter), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        menu.addItem(withTitle: "DeskBuddy 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func toggleListFromMenu() {
        toggleList()
    }

    // MARK: - 메뉴바

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "checklist", accessibilityDescription: "DeskBuddy"
        )

        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "캐릭터 보이기 / 숨기기", action: #selector(toggleCharacter), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        let settingsItem = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    // MARK: - 위치 기억

    private let frameKey = "DeskBuddy.characterFrame"

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(characterPanel.frame), forKey: frameKey)
    }

    private func restoreFrame() {
        if let saved = UserDefaults.standard.string(forKey: frameKey) {
            characterPanel.setFrameOrigin(NSRectFromString(saved).origin)
        } else if let screen = NSScreen.main {
            // 기본 위치: 오른쪽 위 구석
            let vis = screen.visibleFrame
            let size = characterPanel.frame.size
            characterPanel.setFrameOrigin(NSPoint(
                x: vis.maxX - size.width - 24,
                y: vis.maxY - size.height - 24
            ))
        }
    }
}

/// 메뉴가 열려있는 동안에는 캐릭터가 움직이지 않게 한다 (메뉴가 붙은 위치가 어긋나는 것을 방지)
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
