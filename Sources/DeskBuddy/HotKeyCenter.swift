import AppKit
import Carbon.HIToolbox

/// Global hotkey based on Carbon RegisterEventHotKey.
/// Unlike an NSEvent global monitor, it works without Accessibility permission and intercepts the event at the system level.
@MainActor
final class HotKeyCenter {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Applies the saved settings (keyCode < 0 means unregister)
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
                // Carbon events arrive on the main thread
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
