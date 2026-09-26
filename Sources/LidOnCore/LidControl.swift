import Foundation
import IOKit
import IOKit.pwr_mgt

/// 커널(IOPMrootDomain)의 "뚜껑 닫힘 잠자기"를 제어한다.
///
/// `kPMSetClamshellSleepState`(selector 12)는 root 권한 없이 호출할 수 있지만,
/// 호출한 프로세스가 죽어도 커널 상태가 **그대로 남는다**. 그래서 LidOn은 워치독 프로세스로 이를 복구한다.
/// 또한 powerd가 같은 비트를 덮어쓸 수 있으므로(외부 디스플레이 연결/해제 등) 켜져 있는 동안 주기적으로 다시 적용한다.
public final class LidControl {
    private static let kPMSetClamshellSleepState: UInt32 = 12
    /// iokit_family_msg(sub_iokit_powermanagement, 0x100)
    public static let kIOPMMessageClamshellStateChange: natural_t = 0xE003_4100

    private let rootDomain: io_service_t
    private var connection: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var onLidChange: (() -> Void)?

    public init() {
        rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        if rootDomain != 0 {
            IOServiceOpen(rootDomain, mach_task_self_, 0, &connection)
        }
    }

    deinit {
        if notifier != 0 { IOObjectRelease(notifier) }
        if let p = notifyPort { IONotificationPortDestroy(p) }
        if connection != 0 { IOServiceClose(connection) }
        if rootDomain != 0 { IOObjectRelease(rootDomain) }
    }

    public var isAvailable: Bool { connection != 0 }

    /// true면 뚜껑을 닫아도 잠자기하지 않는다. false로 되돌리면, 뚜껑이 닫혀 있는 경우 즉시 잠자기한다.
    @discardableResult
    public func setLidSleepDisabled(_ disabled: Bool) -> Bool {
        guard connection != 0 else { return false }
        var input: [UInt64] = [disabled ? 1 : 0]
        return IOConnectCallScalarMethod(connection, Self.kPMSetClamshellSleepState, &input, 1, nil, nil) == KERN_SUCCESS
    }

    public var hasLid: Bool { property("AppleClamshellState") != nil }
    public var isLidClosed: Bool { (property("AppleClamshellState") as? Bool) ?? false }

    private func property(_ key: String) -> Any? {
        guard rootDomain != 0 else { return nil }
        return IORegistryEntryCreateCFProperty(rootDomain, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// 뚜껑 상태가 바뀌면 즉시(메인 큐에서) 알려준다. 폴링보다 빠르고 전력 소모가 적다.
    public func observeLid(_ handler: @escaping () -> Void) {
        guard rootDomain != 0, notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        onLidChange = handler
        IONotificationPortSetDispatchQueue(port, .main)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddInterestNotification(port, rootDomain, kIOGeneralInterest, { refcon, _, messageType, _ in
            guard let refcon, messageType == LidControl.kIOPMMessageClamshellStateChange else { return }
            Unmanaged<LidControl>.fromOpaque(refcon).takeUnretainedValue().onLidChange?()
        }, refcon, &notifier)
    }
}

/// 유휴 잠자기 방지 assertion. 프로세스가 죽으면 powerd가 자동으로 해제한다.
public final class IdleSleepAssertion {
    private var id: IOPMAssertionID = 0

    public init() {}

    public var isHeld: Bool { id != 0 }

    public func set(_ on: Bool, reason: String) {
        if on, id == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
        } else if !on, id != 0 {
            IOPMAssertionRelease(id)
            id = 0
        }
    }
}

public enum SystemActions {
    /// 즉시 화면 잠금 (login.framework의 비공개 함수)
    public static func lockScreen() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let sym = dlsym(h, "SACLockScreenImmediate") else { return }
        typealias Fn = @convention(c) () -> Int32
        _ = unsafeBitCast(sym, to: Fn.self)()
    }

    public static func sleepDisplay() { run("/usr/bin/pmset", ["displaysleepnow"]) }
    public static func sleepNow() { run("/usr/bin/pmset", ["sleepnow"]) }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
