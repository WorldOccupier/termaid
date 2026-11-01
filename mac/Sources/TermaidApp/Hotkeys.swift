import AppKit
import Carbon

/// Global ⌥Space (hold to talk) and ⌥T (type) hotkeys via Carbon RegisterEventHotKey.
@MainActor
final class Hotkeys {
    var onVoiceDown: (@MainActor () -> Void)?
    var onVoiceUp: (@MainActor () -> Void)?
    var onType: (@MainActor () -> Void)?

    fileprivate enum HotKeyID: UInt32 {
        case voice = 1
        case type = 2
    }

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []

    func register() {
        let specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler, specs.count, specs, userData, &handlerRef)
        add(keyCode: kVK_Space, id: .voice)
        add(keyCode: kVK_ANSI_T, id: .type)
    }

    private func add(keyCode: Int, id: HotKeyID) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x544D_4448), id: id.rawValue)  // 'TMDH'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
        }
    }

    fileprivate func handle(id: UInt32, pressed: Bool) {
        switch (id, pressed) {
        case (HotKeyID.voice.rawValue, true): onVoiceDown?()
        case (HotKeyID.voice.rawValue, false): onVoiceUp?()
        case (HotKeyID.type.rawValue, true): onType?()
        default: break
        }
    }
}

/// Carbon calls this on the main thread.
private func hotkeyEventHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let hotkeys = Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        hotkeys.handle(id: hotKeyID.id, pressed: pressed)
    }
    return noErr
}
