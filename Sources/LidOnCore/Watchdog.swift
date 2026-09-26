import Darwin
import Foundation

/// 앱이 강제 종료되거나 멈춰도 "뚜껑 닫힘 잠자기"를 반드시 복구하는 감시 프로세스.
///
/// 앱은 `LidOn --watchdog`으로 자신을 한 번 더 실행하고, 표준 입력 파이프로 하트비트를 보낸다.
/// - 파이프가 닫히면(앱 종료/크래시/강제 종료) → 즉시 복구 후 종료
/// - 하트비트가 `hangTimeout` 동안 없으면(앱 멈춤) → 복구 (앱이 살아나면 다시 적용한다)
/// - 시스템 발열이 '위험' 단계면 → 앱 상태와 무관하게 복구
public enum Watchdog {
    public static let argument = "--watchdog"
    public static let heartbeatInterval: TimeInterval = 2
    public static let hangTimeout: TimeInterval = 30

    public static var logURL: URL { LidOnPaths.supportDir.appendingPathComponent("watchdog.log") }

    /// 진단용 기록 (최근 200줄 유지)
    static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        var lines = ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: true)
        lines = lines.suffix(199)
        try? (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n") + line).write(to: logURL, atomically: true, encoding: .utf8)
    }

    public static func run() -> Never {
        signal(SIGINT, SIG_IGN)
        signal(SIGHUP, SIG_IGN)
        signal(SIGPIPE, SIG_IGN)

        let lid = LidControl()
        let lock = NSLock()
        var lastBeat = Date()

        func restore(_ why: String) {
            let ok = lid.setLidSleepDisabled(false)
            log("restored lid sleep (\(why), ok=\(ok))")
        }
        func restoreAndExit(_ why: String) -> Never {
            restore(why)
            exit(0)
        }

        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        signal(SIGTERM, SIG_IGN)
        term.setEventHandler { restoreAndExit("SIGTERM") }
        term.resume()

        Thread.detachNewThread {
            var b: UInt8 = 0
            while true {
                let n = read(STDIN_FILENO, &b, 1)
                if n <= 0 { restoreAndExit("app exited") }   // EOF: 앱이 사라짐
                lock.lock()
                lastBeat = Date()
                lock.unlock()
            }
        }

        var restoredForHang = false
        while true {
            Thread.sleep(forTimeInterval: 5)
            lock.lock()
            let silent = Date().timeIntervalSince(lastBeat)
            lock.unlock()

            // 부모가 launchd로 바뀌었다면 앱이 이미 사라진 것
            if getppid() == 1 { restoreAndExit("orphaned") }

            if silent > hangTimeout {
                if !restoredForHang {
                    restore("app not responding")
                    restoredForHang = true
                }
            } else {
                restoredForHang = false
            }
            if ProcessInfo.processInfo.thermalState == .critical {
                restore("critical temperature")
            }
        }
    }
}
