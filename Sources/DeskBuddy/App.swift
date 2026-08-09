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

    private var downLocation: NSPoint = .zero
    private var dragging = false

    override func mouseDown(with event: NSEvent) {
        downLocation = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let loc = event.locationInWindow
        let dx = loc.x - downLocation.x
        let dy = loc.y - downLocation.y
        if !dragging && hypot(dx, dy) < 3 { return }
        dragging = true
        window.setFrameOrigin(NSPoint(x: window.frame.origin.x + dx, y: window.frame.origin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            onMoved?()
        } else {
            onClick?()
        }
        dragging = false
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
    private let store = TodoStore()
    private let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupCharacterPanel()
        setupListPanel()
        setupStatusItem()
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
        let hosting = NSHostingView(rootView: TodoListView(store: store))
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
            // child window 로 붙이면 캐릭터를 끌 때 리스트가 자동으로 따라온다
            characterPanel.addChildWindow(listPanel, ordered: .above)
            listPanel.orderFrontRegardless()
            listPanel.makeKey()
            appState.listVisible = true
        }
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
