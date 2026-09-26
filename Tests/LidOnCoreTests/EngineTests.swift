import XCTest
@testable import LidOnCore

final class EngineTests: XCTestCase {
    var t0 = Date(timeIntervalSince1970: 1_000_000)
    var engine = Engine()
    var now: Date!
    var lid = false
    var fn = false
    var interrupt = false

    override func setUp() {
        engine = Engine()
        now = t0
        lid = false
        fn = false
        interrupt = false
        requests = []
    }

    @discardableResult
    func step(after dt: TimeInterval = 0.1, power: PowerStatus? = nil) -> [EngineEvent] {
        now = now.addingTimeInterval(dt)
        return engine.step(EngineInput(now: now, fnDown: fn, fnInterrupted: interrupt, lidClosed: lid, power: power,
                                       requests: requests))
    }

    func ended(_ events: [EngineEvent]) -> SessionRecord? {
        for case let .ended(r) in events { return r }
        return nil
    }

    // MARK: - Fn 제스처

    func testShortFnPressDoesNotArm() {
        fn = true
        step(); step()               // 0.2초
        XCTAssertFalse(engine.fnArmed)
        fn = false
        step()
        XCTAssertTrue(engine.armTriggers(now: now).isEmpty)
        XCTAssertFalse(engine.wantsLidSleepDisabled(now: now))
    }

    func testFnHoldThenCloseLidSeals() {
        fn = true
        step()
        let ev = step(after: 0.5)
        XCTAssertEqual(ev, [.fnArmed])
        XCTAssertTrue(engine.wantsLidSleepDisabled(now: now))
        lid = true
        let ev2 = step()
        XCTAssertTrue(ev2.contains(.fnDisarmed))
        XCTAssertTrue(ev2.contains(.sealed([.fn])))
        XCTAssertTrue(engine.isSealed)
        fn = false
        step(after: 60)
        XCTAssertTrue(engine.isSealed, "Fn을 떼도 봉인은 유지된다")
        XCTAssertTrue(engine.wantsLidSleepDisabled(now: now))
    }

    func testFnReleasedWithinThreeSecondsStillSeals() {
        fn = true
        step(); step(after: 0.5)
        fn = false
        step()                       // 손을 뗌
        lid = true
        XCTAssertTrue(step(after: 2.8).contains(.sealed([.fn])), "Fn을 떼고 3초 안에 닫으면 계속 실행")
    }

    func testFnReleasedJustBeforeLidClosesStillSeals() {
        fn = true
        step(); step(after: 0.5)
        fn = false
        step(after: 0.3)             // 뚜껑을 닫는 순간 손을 뗌
        lid = true
        let ev = step(after: 0.5)
        XCTAssertTrue(ev.contains(.sealed([.fn])))
    }

    func testFnReleasedLongBeforeLidClosesDoesNotSeal() {
        fn = true
        step(); step(after: 0.5)
        fn = false
        step()                       // 손을 뗌
        step(after: 3.5)             // 유예 시간(3초)이 지난 뒤
        lid = true
        let ev = step()
        XCTAssertFalse(engine.isSealed)
        XCTAssertTrue(ev.isEmpty)
        XCTAssertFalse(engine.wantsLidSleepDisabled(now: now))
    }

    // MARK: - Fn 취소 (다른 키, 마우스)

    func testOtherInputWhileHoldingFnCancels() {
        fn = true
        step(); step(after: 0.5)
        XCTAssertTrue(engine.fnArmed)
        interrupt = true
        XCTAssertEqual(step(), [.fnCancelled])
        interrupt = false
        XCTAssertFalse(engine.wantsLidSleepDisabled(now: now))
        // Fn을 계속 누르고 있어도 다시 켜지지 않는다
        step(after: 1)
        XCTAssertFalse(engine.fnArmed)
        lid = true
        XCTAssertFalse(step().contains(.sealed([.fn])))
    }

    func testFnMustBeReleasedAfterCancel() {
        fn = true
        step(); step(after: 0.5)
        interrupt = true
        step()
        interrupt = false
        fn = false
        step()                       // 뗐다가
        XCTAssertFalse(engine.wantsLidSleepDisabled(now: now), "취소는 유예 시간도 없앤다")
        fn = true
        step(); step(after: 0.5)     // 다시 누르면 다시 켜진다
        XCTAssertTrue(engine.fnArmed)
    }

    func testInputDuringGraceCancels() {
        fn = true
        step(); step(after: 0.5)
        fn = false
        step()                       // 유예 시간 시작
        XCTAssertTrue(engine.fnGestureActive(now: now))
        interrupt = true             // 마우스를 움직임
        XCTAssertEqual(step(after: 0.5), [.fnCancelled])
        interrupt = false
        lid = true
        XCTAssertFalse(step(after: 0.5).contains(.sealed([.fn])), "취소된 뒤에는 3초 안에 닫아도 잠든다")
        XCTAssertFalse(engine.wantsLidSleepDisabled(now: now))
    }

    func testFnShortcutNeverArms() {
        // Fn+E(이모지)처럼 Fn과 다른 키를 함께 누르면 켜지지 않는다 (안내도 뜨지 않았으므로 취소 이벤트도 없다)
        fn = true
        step()
        interrupt = true
        XCTAssertTrue(step(after: 0.1).isEmpty)
        interrupt = false
        step(after: 1)
        XCTAssertFalse(engine.fnArmed)
    }

    func testFnDisabledInSettings() {
        engine.config.fnGesture = false
        fn = true
        step(); step(after: 1)
        XCTAssertFalse(engine.fnArmed)
    }

    func testOpeningLidEndsFnSession() {
        fn = true
        step(); step(after: 0.5)
        lid = true
        step()
        fn = false
        lid = false
        let r = ended(step(after: 600))
        XCTAssertEqual(r?.reason, .lidOpened)
        XCTAssertEqual(r?.triggers, [.fn])
        XCTAssertEqual(r?.duration ?? 0, 600, accuracy: 0.001)
        XCTAssertFalse(engine.wantsLidSleepDisabled(now: now))
    }

    // MARK: - 수동 모드

    func testManualSurvivesLidOpen() {
        _ = engine.setManual(true, now: now)
        lid = true
        XCTAssertTrue(step().contains(.sealed([.manual])))
        lid = false
        XCTAssertEqual(ended(step())?.reason, .lidOpened)
        XCTAssertTrue(engine.manualOn, "뚜껑을 열어도 수동 모드는 유지")
        XCTAssertTrue(engine.wantsLidSleepDisabled(now: now))
    }

    func testManualTimerEndsSession() {
        _ = engine.setManual(true, until: now.addingTimeInterval(3600), now: now)
        lid = true
        step()
        XCTAssertNil(ended(step(after: 3000)))
        let r = ended(step(after: 700))
        XCTAssertEqual(r?.reason, .timerEnded)
        XCTAssertFalse(engine.manualOn)
        XCTAssertFalse(engine.wantsLidSleepDisabled(now: now))
    }

    func testManualOffWhileSealed() {
        _ = engine.setManual(true, now: now)
        lid = true
        step()
        let ev = engine.setManual(false, now: now)
        XCTAssertEqual(ended(ev)?.reason, .manualOff)
    }

    func testLidClosedWithoutArmingNeverDisablesSleep() {
        lid = true
        step()
        XCTAssertFalse(engine.wantsLidSleepDisabled(now: now))
        // 뚜껑이 닫힌 뒤에 켜도 (봉인 전이므로) 잠자기를 막지 않는다
        _ = engine.setManual(true, now: now)
        XCTAssertFalse(engine.wantsLidSleepDisabled(now: now))
    }

    // MARK: - 안전장치

    func testThermalSafeguard() {
        _ = engine.setManual(true, now: now)
        lid = true
        step(power: PowerStatus(batteryPercent: 80, onAC: false, batteryTempC: 32, thermal: .nominal))
        XCTAssertNil(ended(step(after: 5, power: PowerStatus(batteryPercent: 80, onAC: false, batteryTempC: 33, thermal: .fair))))
        let r = ended(step(after: 5, power: PowerStatus(batteryPercent: 79, onAC: false, batteryTempC: 36, thermal: .serious)))
        XCTAssertEqual(r?.reason, .thermal)
        XCTAssertEqual(r?.maxThermal, .serious)
        XCTAssertEqual(r?.batteryStart, 80)
        XCTAssertEqual(r?.batteryEnd, 79)
        XCTAssertFalse(engine.manualOn, "안전장치가 작동하면 수동 모드도 꺼진다")
        XCTAssertFalse(engine.wantsLidSleepDisabled(now: now))
    }

    func testBatteryTemperatureSafeguard() {
        engine.config.maxBatteryTemp = 40
        _ = engine.setManual(true, now: now)
        lid = true
        step(power: PowerStatus(batteryPercent: 80, onAC: true, batteryTempC: 35))
        let r = ended(step(after: 5, power: PowerStatus(batteryPercent: 80, onAC: true, batteryTempC: 40.2)))
        XCTAssertEqual(r?.reason, .batteryTemp)
        XCTAssertEqual(r?.maxBatteryTemp ?? 0, 40.2, accuracy: 0.001)
    }

    func testThermalGuardCanBeDisabled() {
        engine.config.thermalGuard = false
        _ = engine.setManual(true, now: now)
        lid = true
        step()
        XCTAssertNil(ended(step(after: 5, power: PowerStatus(batteryTempC: 50, thermal: .serious))))
    }

    func testLowBatteryOnlyOnBattery() {
        _ = engine.setManual(true, now: now)
        lid = true
        step()
        XCTAssertNil(ended(step(after: 5, power: PowerStatus(batteryPercent: 5, onAC: true))))
        XCTAssertEqual(ended(step(after: 5, power: PowerStatus(batteryPercent: 10, onAC: false)))?.reason, .lowBattery)
    }

    func testRefusesToSealWhenAlreadyTooHot() {
        step(power: PowerStatus(thermal: .critical))
        _ = engine.setManual(true, now: now)
        lid = true
        let ev = step()
        XCTAssertEqual(ev, [.refusedToSeal(.thermal)])
        XCTAssertFalse(engine.isSealed)
        XCTAssertFalse(engine.wantsLidSleepDisabled(now: now))
    }

    func testMaxDuration() {
        engine.config.maxDuration = 7200
        _ = engine.setManual(true, now: now)
        lid = true
        step()
        XCTAssertNil(ended(step(after: 7000)))
        XCTAssertEqual(ended(step(after: 300))?.reason, .maxDuration)
    }

    // MARK: - 에이전트/터미널 요청

    var requests: [String] = []

    @discardableResult
    func stepR(after dt: TimeInterval = 0.1, power: PowerStatus? = nil) -> [EngineEvent] {
        now = now.addingTimeInterval(dt)
        return engine.step(EngineInput(now: now, fnDown: fn, lidClosed: lid, power: power, requests: requests))
    }

    func testRequestArmsAndSeals() {
        requests = ["running tests"]
        stepR()
        XCTAssertEqual(engine.armTriggers(now: now), [.request])
        XCTAssertTrue(engine.wantsLidSleepDisabled(now: now))
        lid = true
        XCTAssertTrue(stepR().contains(.sealed([.request])))
    }

    func testSessionEndsWhenLastRequestIsReleased() {
        requests = ["build", "tests"]
        stepR()
        lid = true
        stepR()
        requests = ["tests"]
        XCTAssertNil(ended(stepR(after: 600)))
        requests = []
        let r = ended(stepR())
        XCTAssertEqual(r?.reason, .requestFinished)
        XCTAssertEqual(r?.requests, ["build", "tests"])
        XCTAssertFalse(engine.wantsLidSleepDisabled(now: now))
    }

    func testRequestAddedWhileSealedIsRecorded() {
        _ = engine.setManual(true, now: now)
        lid = true
        stepR()
        requests = ["migration"]
        stepR(after: 60)
        let r = ended(engine.setManual(false, now: now))
        XCTAssertNil(r, "요청이 남아 있으면 수동을 꺼도 유지")
        requests = []
        XCTAssertEqual(ended(stepR())?.requests, ["migration"])
    }

    func testManualKeepsRunningAfterRequestEnds() {
        requests = ["job"]
        _ = engine.setManual(true, now: now)
        lid = true
        XCTAssertTrue(stepR().contains(.sealed([.manual, .request])))
        requests = []
        XCTAssertNil(ended(stepR(after: 3600)), "사용자가 켠 수동 토글이 우선")
        XCTAssertTrue(engine.isSealed)
    }

    func testFnSessionIgnoresRequestEnd() {
        requests = ["job"]
        fn = true
        stepR(); stepR(after: 0.5)
        lid = true
        stepR()
        fn = false
        interrupt = false
        requests = []
        XCTAssertNil(ended(stepR(after: 600)), "Fn으로 닫았다면 뚜껑을 열 때까지 유지")
    }

    func testSafeguardStillAppliesToRequests() {
        requests = ["job"]
        stepR()
        lid = true
        stepR()
        XCTAssertEqual(ended(stepR(after: 5, power: PowerStatus(thermal: .serious)))?.reason, .thermal)
        XCTAssertFalse(engine.wantsLidSleepDisabled(now: now), "요청이 남아 있어도 뚜껑이 닫힌 채 안전장치가 이긴다")
    }

    // MARK: - 시스템 잠자기

    func testSystemSleepEndsSession() {
        _ = engine.setManual(true, now: now)
        lid = true
        step()
        let ev = engine.systemWillSleep(now: now)
        XCTAssertEqual(ended(ev)?.reason, .systemSlept)
        XCTAssertFalse(engine.isSealed)
    }
}

final class ParserTests: XCTestCase {
    func testDurations() {
        XCTAssertEqual(DurationParser.parse("90"), 5400)
        XCTAssertEqual(DurationParser.parse("90m"), 5400)
        XCTAssertEqual(DurationParser.parse("2h"), 7200)
        XCTAssertEqual(DurationParser.parse("1h30m"), 5400)
        XCTAssertEqual(DurationParser.parse("1.5h"), 5400)
        XCTAssertEqual(DurationParser.parse("45s"), 45)
        XCTAssertNil(DurationParser.parse(""))
        XCTAssertNil(DurationParser.parse("abc"))
        XCTAssertNil(DurationParser.parse("2x"))
        XCTAssertNil(DurationParser.parse("1h30"))
        XCTAssertNil(DurationParser.parse("0"))
    }

}

final class AgentSetupTests: XCTestCase {
    let cli = "/Applications/LidOn.app/Contents/Helpers/lidon"

    func testCodexBlockReplacementKeepsOtherSettings() {
        let toml = """
        model = "gpt-5"

        [mcp_servers.lidon]
        command = "/old/lidon"
        args = ["mcp"]

        [mcp_servers.lidon.env]
        DEBUG = "1"

        [mcp_servers.other]
        command = "x"
        """
        let out = AgentSetup.removingCodexBlock(toml)
        XCTAssertFalse(out.contains("/old/lidon"))
        XCTAssertFalse(out.contains("DEBUG"))
        XCTAssertTrue(out.contains("model = \"gpt-5\""))
        XCTAssertTrue(out.contains("[mcp_servers.other]"))
    }

    func testSnippets() {
        XCTAssertEqual(AgentSetup.claudeAddArguments(cli: cli), ["mcp", "add", "--scope", "user", "lidon", "--", cli, "mcp"])
        XCTAssertTrue(AgentSetup.claudeAddCommand(cli: "/a b/lidon").contains("'/a b/lidon' mcp"))
        XCTAssertTrue(AgentSetup.codexSnippet(cli: cli).contains("command = \"\(cli)\""))
        let json = try! JSONSerialization.jsonObject(with: Data(AgentSetup.mcpJSONSnippet(cli: cli).utf8)) as! [String: Any]
        let server = (json["mcpServers"] as! [String: Any])["lidon"] as! [String: Any]
        XCTAssertEqual(server["command"] as? String, cli)
        XCTAssertEqual(server["args"] as? [String], ["mcp"])
    }

    func testClaudePermissionRuleKeepsOtherSettings() {
        let user: [String: Any] = ["model": "opus", "permissions": ["allow": ["Bash(git status)"], "deny": ["Read(.env)"]]]
        let s = AgentSetup.allowingLidOnTools(in: user)
        let perms = s["permissions"] as! [String: Any]
        XCTAssertEqual(perms["allow"] as? [String], ["Bash(git status)", "mcp__lidon"])
        XCTAssertEqual(perms["deny"] as? [String], ["Read(.env)"])
        XCTAssertEqual(s["model"] as? String, "opus")
        XCTAssertEqual((AgentSetup.allowingLidOnTools(in: s)["permissions"] as! [String: Any])["allow"] as? [String],
                       ["Bash(git status)", "mcp__lidon"], "두 번 넣어도 중복되지 않는다")
        XCTAssertEqual(NSDictionary(dictionary: AgentSetup.removingLidOnTools(from: s)), NSDictionary(dictionary: user))
        XCTAssertTrue(AgentSetup.removingLidOnTools(from: AgentSetup.allowingLidOnTools(in: [:])).isEmpty)
    }

    func testLegacyHooksAreRemovedButOthersKept() {
        let legacy: [String: Any] = ["type": "command", "command": "'/x/lidon' hook claude", "async": true]
        let mine: [String: Any] = ["type": "command", "command": "say done"]
        let s: [String: Any] = ["theme": "dark", "hooks": [
            "Stop": [["hooks": [mine]], ["hooks": [legacy]]],
            "UserPromptSubmit": [["hooks": [legacy]]],
        ]]
        let out = AgentSetup.removingLegacyHooks(from: s)
        let hooks = out["hooks"] as! [String: Any]
        XCTAssertNil(hooks["UserPromptSubmit"])
        XCTAssertEqual((hooks["Stop"] as! [Any]).count, 1)
        XCTAssertEqual(out["theme"] as? String, "dark")
        XCTAssertNil(AgentSetup.removingLegacyHooks(from: ["hooks": ["Stop": [["hooks": [legacy]]]]])["hooks"])
    }

    /// 앱에 내장된 스킬이 plugin/skills/lidon/SKILL.md와 같아야 한다 (scripts/gen-skill.py)
    func testEmbeddedSkillMatchesPluginFile() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(contentsOf: root.appendingPathComponent("plugin/skills/lidon/SKILL.md"), encoding: .utf8)
        XCTAssertEqual(LidOnSkill.markdown.trimmingCharacters(in: .whitespacesAndNewlines),
                       file.trimmingCharacters(in: .whitespacesAndNewlines),
                       "SKILL.md가 바뀌었다면 scripts/gen-skill.py를 실행하세요")
        XCTAssertTrue(file.hasPrefix("---\nname: lidon\ndescription: "))
    }
}
