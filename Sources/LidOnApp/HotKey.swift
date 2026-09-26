import Carbon.HIToolbox

/// 전역 단축키 ⌃⌥⌘L. Carbon 핫키는 손쉬운 사용 권한이 필요 없다.
final class HotKey {
    static let display = "⌃⌥⌘L"
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static var action: (() -> Void)?

    func register(_ action: @escaping () -> Void) {
        unregister()
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4C49_444E), id: 1)   // 'LIDN'
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey | cmdKey), id,
                            GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        ref = nil
        handlerRef = nil
    }
}
