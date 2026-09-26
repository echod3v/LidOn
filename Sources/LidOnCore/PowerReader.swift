import Foundation
import IOKit
import IOKit.ps

public enum PowerReader {
    public static func read() -> PowerStatus {
        var s = PowerStatus(thermal: ThermalLevel(ProcessInfo.processInfo.thermalState))
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for src in list {
                guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
                      (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
                if let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 {
                    s.batteryPercent = cur * 100 / max
                }
                s.onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                s.charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            }
        }
        let batt = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBattery"))
        if batt != 0 {
            // 섭씨 × 100 단위
            if let t = IORegistryEntryCreateCFProperty(batt, "Temperature" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int, t > 0 {
                s.batteryTempC = Double(t) / 100.0
            }
            IOObjectRelease(batt)
        }
        return s
    }
}

/// 전원(충전기 연결·해제)이 바뀌면 메인 스레드에서 알려준다
public final class PowerSourceObserver {
    private var source: CFRunLoopSource?
    private let handler: () -> Void

    public init(_ handler: @escaping () -> Void) {
        self.handler = handler
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<PowerSourceObserver>.fromOpaque(ctx).takeUnretainedValue().handler()
        }, ctx)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
    }
}
