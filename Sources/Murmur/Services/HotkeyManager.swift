import AppKit
import Carbon

// The Carbon event handler receives an EventHotKeyID to distinguish which hotkey fired.
private func hotkeyEventCallback(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let ptr = userData, let event else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()

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

    DispatchQueue.main.async {
        if hotKeyID.id == 1 {
            manager.onHotkeyFired?()
        } else if hotKeyID.id == 2 {
            manager.onCancelFired?()
        }
    }
    return noErr
}

class HotkeyManager {
    var onHotkeyFired: (() -> Void)?
    var onCancelFired: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var cancelHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    var targetKeyCode: UInt16 {
        let stored = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        return UInt16(stored > 0 ? stored : 2) // default: D
    }

    var targetModifiers: NSEvent.ModifierFlags {
        let raw = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        guard raw > 0 else { return [.command, .shift] }
        return NSEvent.ModifierFlags(rawValue: UInt(raw))
    }

    var cancelKeyCode: UInt16? {
        let stored = UserDefaults.standard.integer(forKey: "cancelHotkeyKeyCode")
        return stored > 0 ? UInt16(stored) : nil
    }

    var cancelModifiers: NSEvent.ModifierFlags {
        let raw = UserDefaults.standard.integer(forKey: "cancelHotkeyModifiers")
        guard raw > 0 else { return [] }
        return NSEvent.ModifierFlags(rawValue: UInt(raw))
    }

    init() {
        register()
    }

    func register() {
        unregister()

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventCallback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        // Main hotkey — id 1
        var mainID = EventHotKeyID(signature: OSType(0x47544444), id: 1)
        RegisterEventHotKey(
            UInt32(targetKeyCode),
            carbonModifiers(from: targetModifiers),
            mainID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        // Cancel hotkey — id 2 (only if configured)
        if let code = cancelKeyCode {
            var cancelID = EventHotKeyID(signature: OSType(0x47544444), id: 2)
            RegisterEventHotKey(
                UInt32(code),
                carbonModifiers(from: cancelModifiers),
                cancelID,
                GetApplicationEventTarget(),
                0,
                &cancelHotKeyRef
            )
        }
    }

    func unregister() {
        if let ref = hotKeyRef       { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let ref = cancelHotKeyRef { UnregisterEventHotKey(ref); cancelHotKeyRef = nil }
        if let h   = eventHandlerRef { RemoveEventHandler(h);       eventHandlerRef = nil }
    }

    func updateHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        UserDefaults.standard.set(Int(keyCode),           forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "hotkeyModifiers")
        unregister(); register()
    }

    func updateCancelHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        UserDefaults.standard.set(Int(keyCode),           forKey: "cancelHotkeyKeyCode")
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "cancelHotkeyModifiers")
        unregister(); register()
    }

    func clearCancelHotkey() {
        UserDefaults.standard.removeObject(forKey: "cancelHotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "cancelHotkeyModifiers")
        unregister(); register()
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    deinit { unregister() }
}
