import AppKit
import Carbon.HIToolbox

/// Carbon RegisterEventHotKey 기반 글로벌 단축키.
/// NSEvent 글로벌 모니터와 달리 접근성 권한 없이 동작하고, 이벤트를 시스템에서 가로챈다.
@MainActor
final class HotKeyCenter {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// 저장된 설정(keyCode < 0 이면 해제)을 반영한다
    func apply(keyCode: Int, modifierFlags: Int) {
        unregister()
        guard keyCode >= 0 else { return }
        installHandlerIfNeeded()

        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifierFlags))
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }

        let id = EventHotKeyID(signature: OSType(0x4442_4459), id: 1)   // 'DBDY'
        RegisterEventHotKey(UInt32(keyCode), carbon, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                // Carbon 이벤트는 메인 스레드에서 온다
                MainActor.assumeIsolated { center.onTrigger?() }
                return noErr
            },
            1, &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
