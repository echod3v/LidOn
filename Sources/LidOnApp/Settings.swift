import Foundation
import LidOnCore
import ServiceManagement

enum WebhookKind: String, CaseIterable, Identifiable {
    case none, ntfy, slack, discord, json
    var id: String { rawValue }
}

/// 사용자 설정. 값이 바뀌면 UserDefaults에 저장되고 `onChange`가 호출된다.
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard
    var onChange: (() -> Void)?

    // 일반
    @Published var fnGesture: Bool { didSet { save("fnGesture", fnGesture) } }
    @Published var showAnimation: Bool { didSet { save("showAnimation", showAnimation) } }
    @Published var lockOnClose: Bool { didSet { save("lockOnClose", lockOnClose) } }
    @Published var hotkeyEnabled: Bool { didSet { save("hotkeyEnabled", hotkeyEnabled) } }
    // 안전장치
    @Published var thermalGuard: Bool { didSet { save("thermalGuard", thermalGuard) } }
    @Published var maxBatteryTemp: Double { didSet { save("maxBatteryTemp", maxBatteryTemp) } }
    @Published var batteryGuard: Bool { didSet { save("batteryGuard", batteryGuard) } }
    @Published var minBattery: Double { didSet { save("minBattery", minBattery) } }
    @Published var maxHours: Double { didSet { save("maxHours", maxHours) } }
    // 알림
    @Published var notifyLocal: Bool { didSet { save("notifyLocal", notifyLocal) } }
    @Published var webhookKind: WebhookKind { didSet { save("webhookKind", webhookKind.rawValue) } }
    @Published var webhookURL: String { didSet { save("webhookURL", webhookURL) } }

    init() {
        d.register(defaults: [
            "fnGesture": true, "showAnimation": true, "lockOnClose": true, "hotkeyEnabled": true,
            "thermalGuard": true, "maxBatteryTemp": 45.0, "batteryGuard": true, "minBattery": 10.0, "maxHours": 0.0,
            "notifyLocal": true, "webhookKind": WebhookKind.none.rawValue, "webhookURL": "",
        ])
        fnGesture = d.bool(forKey: "fnGesture")
        showAnimation = d.bool(forKey: "showAnimation")
        lockOnClose = d.bool(forKey: "lockOnClose")
        hotkeyEnabled = d.bool(forKey: "hotkeyEnabled")
        thermalGuard = d.bool(forKey: "thermalGuard")
        maxBatteryTemp = d.double(forKey: "maxBatteryTemp")
        batteryGuard = d.bool(forKey: "batteryGuard")
        minBattery = d.double(forKey: "minBattery")
        maxHours = d.double(forKey: "maxHours")
        notifyLocal = d.bool(forKey: "notifyLocal")
        webhookKind = WebhookKind(rawValue: d.string(forKey: "webhookKind") ?? "") ?? .none
        webhookURL = d.string(forKey: "webhookURL") ?? ""
    }

    private func save(_ key: String, _ value: Any) {
        d.set(value, forKey: key)
        onChange?()
    }

    var engineConfig: EngineConfig {
        var c = EngineConfig()
        c.fnGesture = fnGesture
        c.thermalGuard = thermalGuard
        c.maxBatteryTemp = maxBatteryTemp
        c.batteryGuard = batteryGuard
        c.minBattery = Int(minBattery)
        c.maxDuration = maxHours * 3600
        return c
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { _ = setLaunchAtLogin(newValue) }
    }

    /// 로그인 시 자동 실행을 켜거나 끈다. 실패하면 이유를 돌려준다.
    @discardableResult
    func setLaunchAtLogin(_ on: Bool) -> String? {
        objectWillChange.send()
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            NSLog("LidOn: launch at login failed: \(error)")
            return error.localizedDescription
        }
    }

    /// 사람이 읽을 상태 (CLI용, 영어)
    static var launchAtLoginStatus: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "on"
        case .requiresApproval: return "waiting for approval in System Settings → General → Login Items"
        case .notRegistered: return "off"
        case .notFound: return "unavailable (move LidOn to the Applications folder)"
        @unknown default: return "unknown"
        }
    }
}
