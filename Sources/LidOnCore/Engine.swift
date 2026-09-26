import Foundation

public struct EngineConfig: Equatable, Sendable {
    public var fnGesture = true
    /// Fn을 이만큼 눌러야 무장된다 (일반적인 Fn 사용과 구분)
    public var fnHoldThreshold: TimeInterval = 0.45
    /// Fn을 뗀 뒤에도 이 시간 안에 뚜껑이 닫히면 봉인한다 (Fn을 떼고 천천히 닫아도 되도록)
    public var fnGrace: TimeInterval = 3
    public var thermalGuard = true
    public var maxBatteryTemp: Double = 45
    public var batteryGuard = true
    public var minBattery = 10
    /// 0이면 제한 없음
    public var maxDuration: TimeInterval = 0

    public init() {}
}

public struct EngineInput: Sendable {
    public var now: Date
    /// Fn(🌐) 키 자체가 눌려 있는가
    public var fnDown: Bool
    /// Fn 제스처 도중(누르는 중·유예 시간) 다른 키, 마우스 이동·클릭·스크롤이 있었는가 → 즉시 취소
    public var fnInterrupted: Bool
    public var lidClosed: Bool
    /// 새로 읽은 전원 상태 (없으면 이전 값 유지)
    public var power: PowerStatus?
    /// 활성화된 에이전트/터미널 요청의 사유 목록
    public var requests: [String]

    public init(now: Date, fnDown: Bool = false, fnInterrupted: Bool = false, lidClosed: Bool, power: PowerStatus? = nil,
                requests: [String] = []) {
        self.fnInterrupted = fnInterrupted
        self.now = now
        self.fnDown = fnDown
        self.lidClosed = lidClosed
        self.power = power
        self.requests = requests
    }
}

public enum EngineEvent: Equatable, Sendable {
    case fnArmed
    /// Fn을 뗐다 (유예 시간 시작) 또는 뚜껑이 닫혀 끝났다
    case fnDisarmed
    /// 다른 입력 때문에 Fn 제스처가 취소됐다
    case fnCancelled
    case sealed(Set<Trigger>)
    /// 무장된 상태로 뚜껑이 닫혔지만 안전장치 조건 때문에 봉인하지 않음
    case refusedToSeal(EndReason)
    case ended(SessionRecord)
}

/// LidOn의 상태 머신. 시스템 호출 없이 입력만으로 동작하므로 테스트할 수 있다.
///
///  대기 ──(Fn 길게 / 수동 토글 / 에이전트·터미널 요청)──▶ 무장
///  무장 ──(뚜껑 닫힘)──▶ 봉인 (뚜껑 닫힌 채 실행 중)
///  봉인 ──(뚜껑 열림 / 안전장치 / 켠 이유가 모두 사라짐)──▶ 대기
public struct Engine: Sendable {
    public struct Session: Equatable, Sendable {
        public var start: Date
        public var triggers: Set<Trigger>
        public var batteryStart: Int?
        public var maxBatteryTemp: Double?
        public var maxThermal: ThermalLevel
        public var requests: [String]
    }

    public var config: EngineConfig
    public private(set) var manualOn = false
    public private(set) var manualUntil: Date?
    public private(set) var fnArmed = false
    public private(set) var lidClosed = false
    public private(set) var session: Session?
    public private(set) var power = PowerStatus()
    public private(set) var requests: [String] = []

    private var fnDownAt: Date?
    private var fnReleasedAt: Date?
    /// 취소된 뒤에는 Fn을 뗐다가 다시 눌러야 다시 켜진다 (Fn+E 같은 단축키가 켜지지 않게)
    private var fnBlocked = false
    private var manualEndedByTimer = false

    public init(config: EngineConfig = EngineConfig(), lidClosed: Bool = false) {
        self.config = config
        self.lidClosed = lidClosed
    }

    public var isSealed: Bool { session != nil }

    /// Fn을 뗀 뒤 유예 시간 안인가
    public func fnInGrace(now: Date) -> Bool {
        fnReleasedAt.map { now.timeIntervalSince($0) < config.fnGrace } ?? false
    }

    /// Fn 제스처가 진행 중인가 (누르는 중·켜짐·유예 시간) — 앱이 방해 입력을 감시할지 정한다
    public func fnGestureActive(now: Date) -> Bool { fnDownAt != nil || fnArmed || fnInGrace(now: now) }

    /// 지금 뚜껑을 닫으면 봉인되게 만드는 이유들
    public func armTriggers(now: Date) -> Set<Trigger> {
        var t = Set<Trigger>()
        if manualOn { t.insert(.manual) }
        if fnArmed || (fnReleasedAt.map { now.timeIntervalSince($0) < config.fnGrace } ?? false) { t.insert(.fn) }
        if !requests.isEmpty { t.insert(.request) }
        return t
    }

    /// 커널의 "뚜껑 닫힘 잠자기"를 꺼야 하는가
    public func wantsLidSleepDisabled(now: Date) -> Bool {
        if session != nil { return true }
        // 뚜껑이 닫혔는데 봉인되지 않았다면 반드시 잠자기를 허용한다
        return !lidClosed && !armTriggers(now: now).isEmpty
    }

    // MARK: - 사용자 동작

    public mutating func setManual(_ on: Bool, until: Date? = nil, now: Date) -> [EngineEvent] {
        manualOn = on
        manualUntil = on ? until : nil
        manualEndedByTimer = false
        return evaluateSession(now: now)
    }

    /// 시스템이 (어떤 이유로든) 잠자기에 들어가려 할 때
    public mutating func systemWillSleep(now: Date) -> [EngineEvent] {
        fnArmed = false
        fnDownAt = nil
        fnReleasedAt = nil
        guard session != nil else { return [] }
        return [.ended(finish(.systemSlept, now: now))]
    }

    // MARK: - 한 단계 진행

    public mutating func step(_ input: EngineInput) -> [EngineEvent] {
        let now = input.now
        var events: [EngineEvent] = []

        if let p = input.power {
            power = p
            if var s = session {
                if let t = p.batteryTempC { s.maxBatteryTemp = max(s.maxBatteryTemp ?? t, t) }
                s.maxThermal = max(s.maxThermal, p.thermal)
                session = s
            }
        }
        requests = input.requests
        if var s = session {
            for r in requests where !s.requests.contains(r) { s.requests.append(r) }
            session = s
        }

        if manualOn, let u = manualUntil, now >= u {
            manualOn = false
            manualUntil = nil
            manualEndedByTimer = true
        }

        // Fn 제스처
        let fnDown = config.fnGesture && input.fnDown

        // 다른 입력이 끼어들면 제스처 전체(누르는 중, 켜짐, 유예 시간)를 즉시 취소한다
        if input.fnInterrupted, fnDownAt != nil || fnArmed || fnInGrace(now: now) {
            let wasVisible = fnArmed || fnInGrace(now: now)
            fnArmed = false
            fnDownAt = nil
            fnReleasedAt = nil
            fnBlocked = fnDown
            if wasVisible { events.append(.fnCancelled) }
        }
        if fnBlocked {
            if !fnDown { fnBlocked = false }
        } else if fnDown {
            if fnDownAt == nil { fnDownAt = now }
            if !fnArmed, !lidClosed, let t = fnDownAt, now.timeIntervalSince(t) >= config.fnHoldThreshold {
                fnArmed = true
                fnReleasedAt = nil
                events.append(.fnArmed)
            }
        } else {
            fnDownAt = nil
            if fnArmed {
                fnArmed = false
                fnReleasedAt = now
                events.append(.fnDisarmed)
            }
        }

        // 뚜껑 상태 변화
        if input.lidClosed != lidClosed {
            lidClosed = input.lidClosed
            if lidClosed {
                events += lidDidClose(now: now)
            } else if session != nil {
                events.append(.ended(finish(.lidOpened, now: now)))
            }
        }

        events += evaluateSession(now: now)
        return events
    }

    private mutating func lidDidClose(now: Date) -> [EngineEvent] {
        let triggers = armTriggers(now: now)
        var events: [EngineEvent] = []
        if fnArmed {
            fnArmed = false
            events.append(.fnDisarmed)
        }
        fnReleasedAt = nil
        guard session == nil, !triggers.isEmpty else { return events }

        if let r = safeguardReason(now: now, start: now) {
            return events + [.refusedToSeal(r)]
        }
        session = Session(start: now, triggers: triggers, batteryStart: power.batteryPercent,
                          maxBatteryTemp: power.batteryTempC, maxThermal: power.thermal, requests: requests)
        return events + [.sealed(triggers)]
    }

    private mutating func evaluateSession(now: Date) -> [EngineEvent] {
        guard let s = session else { return [] }

        if let r = safeguardReason(now: now, start: s.start) {
            return [.ended(finish(r, now: now))]
        }

        // 봉인을 유지할 이유가 남아 있는가.
        // Fn으로 닫았다면 뚜껑을 열 때까지 유지한다. 수동 토글과 요청은 꺼지거나 풀리면 끝난다.
        if !s.triggers.contains(.fn) && !manualOn && requests.isEmpty {
            let reason: EndReason = manualEndedByTimer ? .timerEnded
                : (s.triggers == [.request] ? .requestFinished : .manualOff)
            return [.ended(finish(reason, now: now))]
        }
        return []
    }

    private func safeguardReason(now: Date, start: Date) -> EndReason? {
        if config.thermalGuard {
            if power.thermal >= .serious { return .thermal }
            if let t = power.batteryTempC, t >= config.maxBatteryTemp { return .batteryTemp }
        }
        if config.batteryGuard, !power.onAC, let p = power.batteryPercent, p <= config.minBattery {
            return .lowBattery
        }
        if config.maxDuration > 0, now.timeIntervalSince(start) >= config.maxDuration {
            return .maxDuration
        }
        return nil
    }

    private mutating func finish(_ reason: EndReason, now: Date) -> SessionRecord {
        let s = session!
        session = nil
        manualEndedByTimer = false
        // 뚜껑을 연 경우가 아니라면(= Mac이 잠든다) 수동 모드도 끈다
        if reason != .lidOpened {
            manualOn = false
            manualUntil = nil
        }
        return SessionRecord(start: s.start, end: now, triggers: Trigger.allCases.filter(s.triggers.contains),
                             reason: reason, batteryStart: s.batteryStart, batteryEnd: power.batteryPercent,
                             maxBatteryTemp: s.maxBatteryTemp, maxThermal: s.maxThermal,
                             requests: s.requests.isEmpty ? nil : s.requests)
    }
}
