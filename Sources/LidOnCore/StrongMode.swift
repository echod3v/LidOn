import Foundation

/// 강력 모드: macOS의 잠자기 차단 스위치(`pmset -a disablesleep`)를 LidOn이 실행 중일 때만 켠다.
///
/// 기본 방식(`kPMSetClamshellSleepState`)은 powerd와 같은 비트를 나눠 써서, 뚜껑이 닫힌 채 충전기·디스플레이가
/// 바뀌면 powerd가 비트를 덮어쓰고 Mac이 잠든다. `disablesleep`은 커널이 모든 잠자기를 거부하게 하지만 root가 필요하다.
/// 그래서 사용자가 한 번 관리자 암호를 넣으면 이 두 명령만 암호 없이 실행하도록 sudoers 규칙을 설치한다.
///
/// `disablesleep`은 재부팅 후에도 남으므로, 켤 때 표시 파일을 만들고 앱 시작·종료와 워치독 복구 때 반드시 끈다.
public enum StrongMode {
    public static let sudoersPath = "/etc/sudoers.d/lidon"
    private static let pmset = "/usr/bin/pmset"

    private static var markerURL: URL { LidOnPaths.supportDir.appendingPathComponent("disablesleep.on") }

    /// 규칙이 설치돼 있는가 (/etc/sudoers.d는 누구나 목록을 볼 수 있다)
    public static var isInstalled: Bool { FileManager.default.fileExists(atPath: sudoersPath) }

    /// 잠자기 차단 스위치를 켜거나 끈다. 규칙이 없으면 아무것도 하지 않고 false.
    @discardableResult
    public static func set(_ on: Bool) -> Bool {
        guard isInstalled else { return false }
        if on { FileManager.default.createFile(atPath: markerURL.path, contents: nil) }
        let ok = run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", on ? "1" : "0"])
        if !on && ok { try? FileManager.default.removeItem(at: markerURL) }
        return ok
    }

    /// 이전에 켜 둔 채로 끝났다면 끈다 (앱 시작, 워치독 복구)
    public static func restoreIfNeeded() {
        if FileManager.default.fileExists(atPath: markerURL.path) { set(false) }
    }

    /// 지금 macOS의 잠자기 차단 스위치가 켜져 있는가
    public static var isSleepDisabled: Bool {
        let p = Process()
        let out = Pipe()
        p.executableURL = URL(fileURLWithPath: pmset)
        p.arguments = ["-g"]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return text.split(separator: "\n").contains { $0.contains("SleepDisabled") && $0.hasSuffix("1") }
    }

    /// 관리자 권한으로 실행할 설치 스크립트: 문법을 검사한 뒤 root 소유 0440으로 넣는다
    public static func installScript(user: String) -> String? {
        guard !user.isEmpty, user.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else { return nil }
        let rule = "\(user) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 1, \(pmset) -a disablesleep 0"
        return """
        set -e
        tmp=$(/usr/bin/mktemp)
        /usr/bin/printf '%s\\n' '# LidOn stronger mode: lets LidOn toggle pmset disablesleep while it runs' '\(rule)' > "$tmp"
        /usr/sbin/visudo -cf "$tmp" >/dev/null
        /usr/bin/install -m 0440 -o root -g wheel "$tmp" \(sudoersPath)
        /bin/rm -f "$tmp"
        """
    }

    /// 관리자 권한으로 실행할 제거 스크립트: 스위치를 끄고 규칙을 지운다
    public static var uninstallScript: String {
        "\(pmset) -a disablesleep 0; /bin/rm -f \(sudoersPath)"
    }

    private static func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
