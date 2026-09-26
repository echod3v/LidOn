import Foundation
import LidOnCore

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
func L(_ key: String, _ args: CVarArg...) -> String { String(format: NSLocalizedString(key, comment: ""), arguments: args) }

/// 앱 언어. "system"이면 macOS 언어 설정을 따른다 (지원하지 않는 언어면 영어).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, ko
    var id: String { rawValue }

    static let defaultsKey = "appLanguage"

    /// 언어 이름은 번역하지 않고 그 언어로 보여 준다
    var nativeName: String {
        switch self {
        case .system: return L("System")
        case .en: return "English"
        case .ko: return "한국어"
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    /// 앱이 실제로 쓰고 있는 언어 (실행할 때 정해진다)
    static var active: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// macOS는 실행할 때 AppleLanguages로 앱 언어를 정한다. 다음 실행부터 적용된다.
    static func apply(_ lang: AppLanguage) {
        let d = UserDefaults.standard
        d.set(lang.rawValue, forKey: defaultsKey)
        if lang == .system {
            d.removeObject(forKey: "AppleLanguages")
        } else {
            d.set([lang.rawValue], forKey: "AppleLanguages")
        }
    }

    /// 날짜·시간·기간 표시에 쓰는 로케일: 앱 언어 + 사용자 지역
    static var locale: Locale {
        Locale(languageCode: .init(active), languageRegion: Locale.current.region)
    }
}

enum Fmt {
    static func time(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.locale))
    }

    static func dateTime(_ d: Date) -> String {
        d.formatted(Date.FormatStyle().month(.abbreviated).day().hour().minute().locale(AppLanguage.locale))
    }

    static func duration(_ t: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        var cal = Calendar.current
        cal.locale = AppLanguage.locale
        f.calendar = cal
        f.allowedUnits = t >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .short
        f.zeroFormattingBehavior = .dropLeading
        return f.string(from: max(t, 60)) ?? ""
    }

    static func thermal(_ t: ThermalLevel) -> String {
        switch t {
        case .nominal: return L("Normal")
        case .fair: return L("Warm")
        case .serious: return L("Hot")
        case .critical: return L("Critical")
        }
    }

    static func trigger(_ t: Trigger) -> String {
        switch t {
        case .fn: return L("Fn gesture")
        case .manual: return L("Manual")
        case .request: return L("Agent request")
        }
    }

    static func reason(_ r: SessionRecord) -> String {
        switch r.reason {
        case .lidOpened: return L("Lid opened")
        case .thermal: return L("Mac got too hot (%@)", thermal(r.maxThermal))
        case .batteryTemp: return L("Battery temperature %.1f°C", r.maxBatteryTemp ?? 0)
        case .lowBattery: return L("Low battery (%d%%)", r.batteryEnd ?? 0)
        case .maxDuration: return L("Maximum run time reached")
        case .requestFinished: return L("Agent work finished")
        case .manualOff: return L("Turned off")
        case .timerEnded: return L("Timer ended")
        case .systemSlept: return L("Mac went to sleep")
        }
    }

    static func battery(_ r: SessionRecord) -> String? {
        guard let a = r.batteryStart, let b = r.batteryEnd else { return nil }
        return "\(a)% → \(b)%"
    }
}
