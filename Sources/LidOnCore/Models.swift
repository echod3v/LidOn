import Foundation

public enum ThermalLevel: Int, Codable, Comparable, Sendable {
    case nominal, fair, serious, critical

    public init(_ s: ProcessInfo.ThermalState) {
        switch s {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }

    public static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }
}

public struct PowerStatus: Equatable, Codable, Sendable {
    public var batteryPercent: Int?
    public var onAC: Bool
    public var charging: Bool
    public var batteryTempC: Double?
    public var thermal: ThermalLevel

    public init(batteryPercent: Int? = nil, onAC: Bool = true, charging: Bool = false,
                batteryTempC: Double? = nil, thermal: ThermalLevel = .nominal) {
        self.batteryPercent = batteryPercent
        self.onAC = onAC
        self.charging = charging
        self.batteryTempC = batteryTempC
        self.thermal = thermal
    }
}

/// 무엇이 LidOn을 켰는가
public enum Trigger: String, Codable, CaseIterable, Sendable {
    case fn        // Fn을 누른 채 뚜껑을 닫음
    case manual    // 메뉴 토글 / 단축키 / `lidon on`
    case request   // 에이전트나 터미널의 요청 (MCP keep_awake, `lidon keep`, `lidon run`)
}

/// 세션이 끝난 이유
public enum EndReason: String, Codable, Sendable {
    case lidOpened
    case thermal
    case batteryTemp
    case lowBattery
    case maxDuration
    case requestFinished   // 에이전트가 allow_sleep을 호출했거나, 명령이 끝났거나, 요청 시간이 지남
    case manualOff
    case timerEnded
    case systemSlept

    /// 이 이유로 끝나면 Mac이 잠자기에 들어간다 (뚜껑이 닫혀 있으므로)
    public var putsMacToSleep: Bool { self != .lidOpened && self != .systemSlept }
    public var isSafeguard: Bool { [.thermal, .batteryTemp, .lowBattery, .maxDuration].contains(self) }
}

public struct SessionRecord: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var start: Date
    public var end: Date
    public var triggers: [Trigger]
    public var reason: EndReason
    public var batteryStart: Int?
    public var batteryEnd: Int?
    public var maxBatteryTemp: Double?
    public var maxThermal: ThermalLevel
    /// 세션 중에 있었던 에이전트/터미널 요청의 사유
    public var requests: [String]?

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public init(start: Date, end: Date, triggers: [Trigger], reason: EndReason, batteryStart: Int?, batteryEnd: Int?,
                maxBatteryTemp: Double?, maxThermal: ThermalLevel, requests: [String]? = nil) {
        self.start = start
        self.end = end
        self.triggers = triggers
        self.reason = reason
        self.batteryStart = batteryStart
        self.batteryEnd = batteryEnd
        self.maxBatteryTemp = maxBatteryTemp
        self.maxThermal = maxThermal
        self.requests = requests
    }
}

/// 에이전트나 터미널이 "깨워 둬"라고 요청한 것.
/// - pid가 있으면 그 프로세스가 끝날 때 자동으로 풀린다 (`lidon run`, MCP 서버 = 에이전트 세션)
/// - until이 있으면 그 시각에 풀린다 (에이전트가 해제를 잊어도 안전)
public struct Hold: Codable, Hashable, Sendable {
    public let id: String
    public var pid: Int32?
    public var label: String
    public var until: Date?
    public var since: Date

    public init(id: String, pid: Int32?, label: String, until: Date?, since: Date = Date()) {
        self.id = id
        self.pid = pid
        self.label = label
        self.until = until
        self.since = since
    }
}
