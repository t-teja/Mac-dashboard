import Carbon
import Foundation

/// Carbon hotkey. Default is off until someone turns it on in Settings.
final class HotkeyCenter {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if hotKeyID.signature == OSType(0x4852_484B) {
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { center.onPress?() }
            }
            return noErr
        }, 1, &eventType, pointer, &handler)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4852_484B), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }
}
