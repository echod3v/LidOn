import AppKit
import Combine
import CoreGraphics
import LidOnCore
import ServiceManagement

/// UI에 보여줄 상태. 실제로 바뀔 때만 게시해서 초당 10번 도는 루프가 화면을 다시 그리지 않게 한다.
struct UIState: Equatable {
    var state = "idle"
    var triggers: [Trigger] = []
    var lidClosed = false
    var manualOn = false
    var manualUntil: Date?
    var power = PowerStatus()
    var sessionStart: Date?
    var lidSleepDisabled = false
}

/// 상태 머신(Engine)과 시스템(커널, 워치독, IPC, 알림)을 이어준다.
@MainActor
final class AppModel: ObservableObject {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    let settings: AppSettings
    private(set) var engine: Engine
    @Published private(set) var ui = UIState()
    @Published private(set) var history: [SessionRecord] = []
    /// 에이전트/터미널 요청 (hold id → hold)
    @Published private(set) var holds: [String: Hold] = [:]
    @Published private(set) var lastMessage: String?
    private var lidSleepDisabled = false
    @Published private(set) var ipcError: String?

    let lid = LidControl()
    let watchdog = WatchdogLauncher()
    private let assertion = SleepAssertion(SleepAssertion.idle)
    private let systemAssertion = SleepAssertion(SleepAssertion.system)
    private var powerObserver: PowerSourceObserver?
    /// 뚜껑이 닫혀 실행 중일 때 1초마다 커널 상태를 다시 적용하는 타이머 (Fn 감지 타이머는 이때 멈춰 있다)
    private var sealTimer: Timer?
    private let overlay = OverlayController()
    private let hotkey = HotKey()
    private var ipc: IPCServer?
    private var holdSources: [Int32: DispatchSourceProcess] = [:]

    /// IPC "reveal" 요청 시 안내 창을 띄운다 (AppDelegate가 설정)
    var onReveal: (() -> Void)?

    private var fastTimer: Timer?
    private var slowTimer: Timer?
    /// 요청 하나가 깨워 둘 수 있는 최대 시간 (에이전트가 해제를 잊어도 안전하도록)
    static let maxRequestMinutes: Double = 12 * 60
    private var lastAssert = Date.distantPast
    /// 마지막 요청이 시간이 다 돼서 풀렸는가 (알림 문구를 구분하기 위해)
    private var expiredRequest: String?
    /// 웹훅을 보내는 동안 잠자기를 잠깐 미룬다 (Mac이 먼저 잠들면 알림이 못 나간다)
    private var releaseHoldUntil: Date?

    init(settings: AppSettings) {
        self.settings = settings
        engine = Engine(config: settings.engineConfig, lidClosed: false)
        loadHistory()

        // 이전 실행이 비정상 종료됐을 수 있으므로 항상 기본 상태에서 시작
        lid.setLidSleepDisabled(false)
        engine = Engine(config: settings.engineConfig, lidClosed: lid.isLidClosed)

        settings.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        watchdog.start()
        lid.observeLid { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        restoreState()
        powerObserver = PowerSourceObserver { [weak self] in
            MainActor.assumeIsolated { self?.powerSourceChanged() }
        }
        startIPC()
        applyHotkey()
        if settings.notifyLocal { Notifier.requestPermission() }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemWillSleep() }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lastAssert = .distantPast
                self?.refresh()
            }
        }

        slowTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        slowTimer?.tolerance = 1
        updateFastTimer()
        refresh()
    }

    // MARK: - 상태 (UI용)

    var isSealed: Bool { engine.isSealed }
    var triggers: Set<Trigger> { engine.armTriggers(now: Date()) }
    var isArmed: Bool { !isSealed && !triggers.isEmpty && !engine.lidClosed }

    var stateKey: String { isSealed ? "sealed" : isArmed ? "armed" : "idle" }

    var snapshot: StatusSnapshot {
        StatusSnapshot(state: stateKey, triggers: Trigger.allCases.filter((engine.session?.triggers ?? triggers).contains),
                       lidClosed: engine.lidClosed, hasLid: lid.hasLid, manualOn: engine.manualOn, manualUntil: engine.manualUntil,
                       power: engine.power, holds: sortedHolds, phoneNotifications: settings.webhookKind != .none,
                       version: Self.version)
    }

    var sortedHolds: [Hold] {
        holds.values.sorted { ($0.since, $0.id) < ($1.since, $1.id) }
    }

    // MARK: - 사용자 동작

    func setManual(_ on: Bool, minutes: Double? = nil) {
        let now = Date()
        handle(engine.setManual(on, until: minutes.map { now.addingTimeInterval($0 * 60) }, now: now))
        if on && settings.showAnimation && !engine.lidClosed {
            overlay.show(.confirm, title: L("LidOn is on"), subtitle: L("You can close the lid — your work keeps running"),
                         autoHide: 1.6)
        }
        apply()
    }

    func toggleManual() { setManual(!engine.manualOn) }

    /// 메뉴에서 에이전트 요청을 직접 취소
    func releaseHold(id: String) { removeHold(id: id) }

    func clearHistory() {
        history = []
        saveHistory()
    }

    func sendTestWebhook(_ done: @escaping (Bool) -> Void) {
        Notifier.webhook(kind: settings.webhookKind, url: settings.webhookURL, title: L("LidOn test"),
                         body: L("Notifications are working."), record: nil, completion: done)
    }

    func shutdown() {
        saveState(force: true)
        overlay.hide(animated: false)
        ipc?.stop()
        assertion.set(false, reason: "")
        systemAssertion.set(false, reason: "")
        lid.setLidSleepDisabled(false)
        watchdog.stop()
    }

    // MARK: - 루프

    private func settingsChanged() {
        engine.config = settings.engineConfig
        applyHotkey()
        updateFastTimer()
        apply()
    }

    private func updateSealTimer(_ needed: Bool) {
        if needed, sealTimer == nil {
            sealTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
            sealTimer?.tolerance = 0.2
        } else if !needed, let t = sealTimer {
            t.invalidate()
            sealTimer = nil
        }
    }

    /// 충전기를 꽂거나 빼면 macOS가 뚜껑 상태를 다시 판단한다 → 곧바로 다시 적용한다
    private func powerSourceChanged() {
        if engine.isSealed {
            EventLog.write("power source changed while running: ac=\(PowerReader.read().onAC) causesSleep=\(lid.clamshellCausesSleep.map(String.init) ?? "?")")
        }
        lastAssert = .distantPast
        refresh()
    }

    /// Fn 감지가 필요할 때만 빠른 타이머를 돌린다 (뚜껑이 닫혀 있으면 멈춰서 전력을 아낀다)
    private func updateFastTimer() {
        let needed = settings.fnGesture && !engine.lidClosed
        if needed, fastTimer == nil {
            fastTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            fastTimer?.tolerance = 0.03
        } else if !needed, let t = fastTimer {
            t.invalidate()
            fastTimer = nil
        }
    }

    /// 수정 키(⌘ ⇧ ⌥ ⌃ Caps Fn)의 키 코드 — 이 키들은 Fn과 함께 눌려 있어도 된다
    private static let modifierKeyCodes: Set<CGKeyCode> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// Fn(🌐) 키의 키 코드: kVK_Function(63), 일부 최신 키보드의 🌐 키(179)
    private static let fnKeyCodes: [CGKeyCode] = [63, 179]
    /// Caps Lock은 켜진 상태가 "눌림"으로 보일 수 있어 제외한다
    private static let capsLock: CGKeyCode = 57

    private static func keyDown(_ key: CGKeyCode) -> Bool {
        CGEventSource.keyState(.hidSystemState, key: key) || CGEventSource.keyState(.combinedSessionState, key: key)
    }

    /// Fn 키 자체가 눌려 있는가.
    /// 수정 키 플래그(flagsState)는 쓰지 않는다 — "마지막 입력의 플래그"라서 화살표·F키를 누르고 떼면 Fn 플래그가 남는다.
    /// 키의 실제 눌림 상태는 입력 모니터링 권한 없이도 정확하다.
    private static func fnKeyDown() -> Bool { fnKeyCodes.contains(where: keyDown) }

    /// Fn 제스처 도중 다른 입력이 있었는가: 다른 키(수정 키 포함), 클릭, 스크롤.
    /// 마우스 이동은 허용한다 (뚜껑을 닫다가 트랙패드를 스치는 일이 흔하다).
    private static func otherInput() -> (Bool, [CGKeyCode]) {
        var keys: [CGKeyCode] = []
        for key in CGKeyCode(0)..<256 where !fnKeyCodes.contains(key) && key != capsLock && keyDown(key) { keys.append(key) }
        let clicked = NSEvent.pressedMouseButtons != 0
        let scrolled = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .scrollWheel) < 0.15
        return (!keys.isEmpty || clicked || scrolled, keys)
    }

    private func tick(power: PowerStatus? = nil) {
        let now = Date()
        let fnKey = settings.fnGesture && Self.fnKeyDown()
        var interrupted = false
        if settings.fnGesture && (fnKey || engine.fnGestureActive(now: now)) {
            let (other, keys) = Self.otherInput()
            interrupted = other
            FnDiagnostics.record(fnKey: fnKey, otherKeys: keys, interrupted: other)
        }
        let input = EngineInput(now: now, fnDown: fnKey, fnInterrupted: interrupted, lidClosed: lid.isLidClosed, power: power,
                                requests: sortedHolds.map(\.label))
        let wasClosed = engine.lidClosed
        handle(engine.step(input))
        if wasClosed != engine.lidClosed { updateFastTimer() }
        apply()
    }

    private func refresh() {
        // 시간이 지났거나 소유 프로세스가 사라진 요청 정리
        // (종료 알림을 못 받는 경우 — 다른 사용자의 프로세스 등 — 도 여기서 잡힌다)
        let now = Date()
        for h in holds.values {
            let expired = h.until.map { now >= $0 } ?? false
            let orphaned = h.pid.map { kill($0, 0) != 0 && errno == ESRCH } ?? false
            if expired || orphaned { removeHold(id: h.id, tickAfter: false, expired: expired) }
        }
        tick(power: PowerReader.read())
    }

    /// 커널 상태를 엔진이 원하는 값으로 맞춘다. 켜져 있는 동안에는 1초마다 다시 적용한다 (powerd가 덮어쓸 수 있으므로).
    private func apply() {
        let now = Date()
        if let until = releaseHoldUntil, now >= until { releaseHoldUntil = nil }
        let want = engine.wantsLidSleepDisabled(now: now) || releaseHoldUntil != nil
        if want != lidSleepDisabled || (want && now.timeIntervalSince(lastAssert) >= 1) {
            let ok = lid.setLidSleepDisabled(want)
            if want && !ok { lastMessage = L("Could not control lid sleep on this Mac") }
            lidSleepDisabled = want
            lastAssert = now
        }
        assertion.set(want, reason: "LidOn: keep running with the lid closed")
        systemAssertion.set(want, reason: "LidOn: keep running with the lid closed")
        updateSealTimer(want && engine.lidClosed)
        publish()
        saveState()
    }

    private func publish() {
        let t = engine.session?.triggers ?? triggers
        let next = UIState(state: stateKey, triggers: Trigger.allCases.filter(t.contains), lidClosed: engine.lidClosed,
                           manualOn: engine.manualOn, manualUntil: engine.manualUntil, power: engine.power,
                           sessionStart: engine.session?.start, lidSleepDisabled: lidSleepDisabled)
        if next != ui { ui = next }
    }

    private func handle(_ events: [EngineEvent]) {
        for e in events {
            switch e {
            case .fnArmed:
                if settings.showAnimation {
                    overlay.show(.fnHint, title: L("Close the lid"), subtitle: L("Keep holding Fn while closing — your work keeps running"))
                }
            case .fnDisarmed:
                if engine.lidClosed {
                    overlay.hide(animated: false)
                } else {
                    // Fn을 뗐어도 유예 시간 안에 닫으면 계속 실행된다 — 남은 시간을 보여 준다
                    let grace = engine.config.fnGrace
                    overlay.countdown(grace, subtitle: L("Fn released — close within %d seconds to keep running", Int(grace)))
                }
            case .fnCancelled:
                overlay.cancel(title: L("Cancelled"), subtitle: L("Another key or a click was used"))
            case .sealed(let t):
                EventLog.write("running with the lid closed (\(t.map(\.rawValue).sorted().joined(separator: ","))), ac=\(engine.power.onAC)")
                overlay.hide(animated: false)
                lastMessage = nil
                if settings.lockOnClose {
                    SystemActions.lockScreen()
                    SystemActions.sleepDisplay()
                }
            case .refusedToSeal(let reason):
                let r = SessionRecord(start: Date(), end: Date(), triggers: [], reason: reason,
                                      batteryStart: nil, batteryEnd: engine.power.batteryPercent,
                                      maxBatteryTemp: engine.power.batteryTempC, maxThermal: engine.power.thermal)
                lastMessage = L("Did not keep running: %@", Fmt.reason(r))
            case .ended(let record):
                EventLog.write("ended: \(record.reason.rawValue)")
                sessionEnded(record)
            }
        }
    }

    private func sessionEnded(_ r: SessionRecord) {
        history.insert(r, at: 0)
        history = Array(history.prefix(100))
        saveHistory()
        lastMessage = Fmt.reason(r)

        let title: String
        var lines = [L("Kept running for %@", Fmt.duration(r.duration))]
        if let reqs = r.requests, !reqs.isEmpty { lines.insert(reqs.joined(separator: ", "), at: 0) }
        if let b = Fmt.battery(r) { lines.append(L("Battery %@", b)) }
        if let t = r.maxBatteryTemp { lines.append(L("Max battery temp %.1f°C", t)) }
        switch r.reason {
        case .lidOpened: title = L("Welcome back")
        case .requestFinished:
            if let label = expiredRequest {
                // 에이전트가 풀기 전에 시간이 다 됐다 — 작업이 끝나지 않았을 수 있다
                title = L("Agent request timed out — Mac is going to sleep")
                lines.insert(L("“%@” ran out of time before the agent released it. The work may be unfinished.", label), at: 0)
            } else {
                title = L("Work finished — Mac is going to sleep")
            }
        default: title = r.reason.isSafeguard ? L("Safeguard: %@", Fmt.reason(r)) : Fmt.reason(r)
        }
        let body = lines.joined(separator: " · ")
        expiredRequest = nil

        if settings.notifyLocal, r.duration >= 60 || r.reason != .lidOpened {
            Notifier.local(title: title, body: body)
        }
        // 뚜껑이 닫혀 곧 잠드는 경우에만 휴대폰으로 알린다. 전송이 끝날 때까지(최대 6초) 잠자기를 미룬다.
        if r.reason.putsMacToSleep, settings.webhookKind != .none {
            releaseHoldUntil = Date().addingTimeInterval(6)
            Notifier.webhook(kind: settings.webhookKind, url: settings.webhookURL, title: title, body: body, record: r) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    self?.releaseHoldUntil = nil
                    self?.apply()
                }
            }
        }
        if r.reason.putsMacToSleep {
            // 커널이 재평가하지 않는 경우를 대비한 보조 수단
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.lid.isLidClosed, !self.lidSleepDisabled, !self.engine.isSealed else { return }
                    SystemActions.sleepNow()
                }
            }
        }
    }

    private func systemWillSleep() {
        // 켜져 있는데 macOS가 "뚜껑 닫힘"을 이유로 재우려 한다 = powerd가 우리 비트를 덮어쓴 경우
        // (뚜껑이 닫힌 채 충전기·디스플레이를 연결). 이 시점은 아직 다크 웨이크라 프로그램이 돌고 있다.
        // 비트를 다시 켜고 시스템 잠자기 방지(전원 연결 시 유효)를 유지하면 커널이 실제 잠자기를 거부한다.
        let reason = lid.lastSleepReason
        if engine.isSealed, engine.lidClosed, reason == "Clamshell Sleep", PowerReader.read().onAC {
            EventLog.write("macOS tried to sleep after a power/display change — keeping it awake")
            lastAssert = .distantPast
            apply()
            return
        }
        if engine.isSealed {
            // 켜져 있는데 잠들었다 — 원인을 찾을 수 있게 남긴다
            EventLog.write("system sleeping while running: reason=\(reason ?? "?") lidDisabled=\(lidSleepDisabled) ac=\(engine.power.onAC) causesSleep=\(lid.clamshellCausesSleep.map(String.init) ?? "?")")
        }
        overlay.hide(animated: false)
        handle(engine.systemWillSleep(now: Date()))
        apply()
    }

    private func applyHotkey() {
        if settings.hotkeyEnabled {
            hotkey.register { [weak self] in MainActor.assumeIsolated { self?.toggleManual() } }
        } else {
            hotkey.unregister()
        }
    }

    // MARK: - CLI / URL 스킴

    private func startIPC() {
        let server = IPCServer { [weak self] req, reply in
            MainActor.assumeIsolated {
                guard let self else { return reply(IPCResponse(ok: false)) }
                if req.cmd == "notify" {
                    self.notify(req, reply: reply)
                } else {
                    reply(self.handleRequest(req))
                }
            }
        }
        do {
            try server.start()
            ipc = server
        } catch {
            ipcError = "\(error)"
        }
    }

    func handleRequest(_ req: IPCRequest) -> IPCResponse {
        switch req.cmd {
        case "status":
            return IPCResponse(ok: true, status: snapshot)
        case "on":
            setManual(true, minutes: req.minutes)
            let msg = req.minutes.map { m -> String in
                let h = Int(m) / 60, mm = Int(m.rounded()) % 60
                return "LidOn is on for " + (h > 0 ? "\(h)h" : "") + (mm > 0 || h == 0 ? "\(mm)m" : "")
            } ?? "LidOn is on"
            return IPCResponse(ok: true, message: msg, status: snapshot)
        case "off":
            setManual(false)
            return IPCResponse(ok: true, message: "LidOn is off", status: snapshot)
        case "toggle":
            toggleManual()
            return IPCResponse(ok: true, message: engine.manualOn ? "LidOn is on" : "LidOn is off", status: snapshot)
        case "hold":
            switch addHold(id: req.id, pid: req.pid, label: req.label, minutes: req.minutes) {
            case .success(let h):
                var msg = "Keeping this Mac awake"
                if let u = h.until {
                    let f = DateFormatter()
                    f.dateFormat = "HH:mm"
                    msg += " until \(f.string(from: u))"
                }
                if let p = h.pid {
                    msg += h.until == nil ? " while pid \(p) runs" : " (released earlier if this session ends)"
                }
                msg += " — \(h.label) [id: \(h.id)]"
                return IPCResponse(ok: true, message: msg, status: snapshot)
            case .failure(let e):
                return IPCResponse(ok: false, message: e.message)
            }
        case "release":
            let before = holds.count
            if let id = req.id { removeHold(id: id) }
            if let pid = req.pid { removeHolds(pid: pid) }
            let released = before - holds.count
            let msg = released > 0
                ? (holds.isEmpty ? "Released. The Mac may sleep when the lid is closed." : "Released. Other requests are still active.")
                : "Nothing to release"
            return IPCResponse(ok: true, message: msg, status: snapshot)
        case "reveal":
            onReveal?()
            return IPCResponse(ok: true)
        case "login-item":
            // lidon login-item on|off|status
            switch req.label ?? "status" {
            case "on", "off":
                if let err = settings.setLaunchAtLogin(req.label == "on") {
                    return IPCResponse(ok: false, message: "Could not change launch at login: \(err)")
                }
            default: break
            }
            let status = AppSettings.launchAtLoginStatus
            if status.hasPrefix("waiting") { SMAppService.openSystemSettingsLoginItems() }
            return IPCResponse(ok: true, message: "Launch at login: \(status)")
        case "quit":
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return IPCResponse(ok: true, message: "LidOn is quitting")
        default:
            return IPCResponse(ok: false, message: "unknown command")
        }
    }

    /// 에이전트/터미널의 알림. 실제로 어디에 전달됐는지 돌려줘서, 에이전트가 사용자에게 제대로 알릴 수 있게 한다.
    private func notify(_ req: IPCRequest, reply: @escaping (IPCResponse) -> Void) {
        let title = req.title ?? "LidOn"
        let body = req.message ?? ""
        Notifier.local(title: title, body: body)
        let unseen = engine.lidClosed
            ? " The lid is closed, so the user will not see the Mac notification until they open it."
            : ""
        guard settings.webhookKind != .none else {
            return reply(IPCResponse(ok: true, message: "Shown as a Mac notification only. Phone notifications are not set up in LidOn."
                                     + unseen + " Also report the result in your reply to the user."))
        }
        Notifier.webhook(kind: settings.webhookKind, url: settings.webhookURL, title: title, body: body, record: nil) { ok in
            reply(ok
                ? IPCResponse(ok: true, message: "Delivered to the user's phone and shown on the Mac.")
                : IPCResponse(ok: false, message: "Phone notification FAILED; shown as a Mac notification only." + unseen
                              + " The user may not see it — also report the result in your reply."))
        }
    }

    /// lidon://on?for=2h, lidon://off, lidon://toggle
    func handleURL(_ url: URL) {
        guard url.scheme == "lidon" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let minutes = items.first { $0.name == "for" }?.value.flatMap(DurationParser.parse).map { $0 / 60 }
        _ = handleRequest(IPCRequest(cmd: url.host ?? "", minutes: minutes))
    }

    struct HoldError: Error { let message: String }

    /// 요청 추가/갱신. pid가 있으면 그 프로세스가 끝날 때, minutes가 있으면 그 시간이 지나면 풀린다.
    private func addHold(id: String?, pid: Int32?, label: String?, minutes: Double?) -> Result<Hold, HoldError> {
        if let pid, !(kill(pid, 0) == 0 || errno == EPERM) {
            return .failure(HoldError(message: "process \(pid) not found"))
        }
        // 언제 풀릴지 알 수 없는 요청은 받지 않는다
        let mins = minutes.map { min(max($0, 1), Self.maxRequestMinutes) } ?? (pid == nil ? 60 : nil)
        let now = Date()
        let hid = id ?? pid.map { "pid-\($0)" } ?? String(UUID().uuidString.prefix(6)).lowercased()
        let text = String((label?.isEmpty == false ? label! : "Agent request").prefix(200))
        var h = holds[hid] ?? Hold(id: hid, pid: pid, label: text, until: nil, since: now)
        h.label = text
        h.until = mins.map { now.addingTimeInterval($0 * 60) }
        holds[hid] = h
        if let pid { watch(pid: pid) }
        tick()
        return .success(holds[hid] ?? h)
    }

    /// 요청한 프로세스가 끝나면 그 요청을 푼다
    private func watch(pid: Int32) {
        guard holdSources[pid] == nil else { return }
        let src = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.removeHolds(pid: pid) }
        }
        src.resume()
        holdSources[pid] = src
        // 등록 직후 프로세스가 이미 끝났을 수 있다
        if kill(pid, 0) != 0 && errno == ESRCH { removeHolds(pid: pid) }
    }

    private func removeHold(id: String, tickAfter: Bool = true, expired: Bool = false) {
        guard let h = holds.removeValue(forKey: id) else { return }
        expiredRequest = expired ? h.label : nil
        if let pid = h.pid, !holds.values.contains(where: { $0.pid == pid }) {
            holdSources.removeValue(forKey: pid)?.cancel()
        }
        if tickAfter { tick() }
    }

    private func removeHolds(pid: Int32) {
        holdSources.removeValue(forKey: pid)?.cancel()
        let ids = holds.values.filter { $0.pid == pid }.map(\.id)
        guard !ids.isEmpty else { return }
        ids.forEach { holds.removeValue(forKey: $0) }
        tick()
    }

    // MARK: - 재시작 전 상태 (업데이트·재실행 뒤 이어 가기)

    private struct SavedState: Codable, Equatable {
        var savedAt = Date()
        var manualOn = false
        var manualUntil: Date?
        var holds: [Hold] = []
        var sessionStart: Date?
        var sessionTriggers: [Trigger]?
    }

    /// 수동 토글과 Fn 세션은 이 시간 안에 다시 켜졌을 때만 이어 간다 (어제 켜 둔 토글이 되살아나지 않도록)
    private static let quickRestart: TimeInterval = 120
    private var stateURL: URL { LidOnPaths.supportDir.appendingPathComponent("state.json") }
    private var lastSaved: SavedState?

    private func currentState() -> SavedState {
        SavedState(manualOn: engine.manualOn, manualUntil: engine.manualUntil, holds: sortedHolds,
                   sessionStart: engine.session?.start, sessionTriggers: engine.session.map { Trigger.allCases.filter($0.triggers.contains) })
    }

    private func saveState(force: Bool = false) {
        var state = currentState()
        if !force, var last = lastSaved {
            last.savedAt = state.savedAt
            if last == state { return }
        }
        state.savedAt = Date()
        lastSaved = state
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(state).write(to: stateURL, options: .atomic)
    }

    /// 앱이 다시 켜졌을 때: 살아 있는 요청은 그대로 되살리고, 방금 전까지 켜져 있던 토글·세션은 이어 간다.
    /// 뚜껑이 닫힌 채 업데이트돼도 Mac이 잠들지 않는다.
    private func restoreState() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: stateURL), let saved = try? dec.decode(SavedState.self, from: data) else { return }
        let now = Date()
        for h in saved.holds {
            if let u = h.until, u <= now { continue }
            if let pid = h.pid, kill(pid, 0) != 0, errno == ESRCH { continue }
            holds[h.id] = h
        }
        holds.values.compactMap(\.pid).forEach(watch(pid:))

        let recent = now.timeIntervalSince(saved.savedAt) < Self.quickRestart
        if recent, let start = saved.sessionStart, let t = saved.sessionTriggers {
            handle(engine.resumeSession(start: start, triggers: Set(t), now: now))
        }
        if recent, saved.manualOn, (saved.manualUntil.map { $0 > now } ?? true) {
            handle(engine.setManual(true, until: saved.manualUntil, now: now))
        }
    }

    // MARK: - 기록

    private var historyURL: URL { LidOnPaths.supportDir.appendingPathComponent("history.json") }

    private func loadHistory() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        // 형식이 바뀐 이전 기록은 건너뛴다
        guard let data = try? Data(contentsOf: historyURL),
              let items = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return }
        history = items.compactMap { item in
            (try? JSONSerialization.data(withJSONObject: item)).flatMap { try? dec.decode(SessionRecord.self, from: $0) }
        }
    }

    private func saveHistory() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(history).write(to: historyURL, options: .atomic)
    }
}

/// Fn 오작동 진단: `defaults write dev.lidon.LidOn debugFn -bool true` 로 켜면
/// ~/Library/Application Support/LidOn/fn-debug.log 에 Fn 플래그가 켜질 때마다 기록한다.
enum FnDiagnostics {
    private static var last = ""
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "debugFn") }

    static func record(fnKey: Bool, otherKeys: [CGKeyCode], interrupted: Bool) {
        guard enabled else { return }
        let line = "fnKey=\(fnKey ? "down" : "up") keys=\(otherKeys.map(String.init).joined(separator: ",")) interrupted=\(interrupted)"
        guard line != last else { return }   // 같은 상태는 한 번만
        last = line
        let url = LidOnPaths.supportDir.appendingPathComponent("fn-debug.log")
        let entry = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(entry.utf8))
            try? h.close()
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }
}

/// 진단 기록: ~/Library/Application Support/LidOn/events.log (최근 200줄만 유지)
enum EventLog {
    static func write(_ line: String) {
        let url = LidOnPaths.supportDir.appendingPathComponent("events.log")
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let stamp = ISO8601DateFormatter().string(from: Date())
        let lines = (old.split(separator: "\n").map(String.init) + ["\(stamp) \(line)"]).suffix(200)
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
