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
