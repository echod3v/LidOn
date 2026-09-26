import Foundation
import LidOnCore

/// 워치독 프로세스를 띄우고 하트비트를 보낸다. 워치독이 죽으면 다시 띄운다.
final class WatchdogLauncher {
    private var process: Process?
    private var pipe: Pipe?
    private var timer: Timer?
    private var stopping = false
    private(set) var restarts = 0

    var isRunning: Bool { process?.isRunning ?? false }

    func start() {
        spawn()
        // 메인 런루프 타이머: 메인 스레드가 멈추면 하트비트도 멈춘다 → 워치독이 복구
        timer = Timer.scheduledTimer(withTimeInterval: Watchdog.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.beat()
        }
    }

    func stop() {
        stopping = true
        timer?.invalidate()
        try? pipe?.fileHandleForWriting.close()   // EOF → 워치독이 복구 후 종료
    }

    private func spawn() {
        guard !stopping, let exe = Bundle.main.executableURL else { return }
        let p = Process()
        let pipe = Pipe()
        p.executableURL = exe
        p.arguments = [Watchdog.argument]
        p.standardInput = pipe
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let self, !self.stopping else { return }
                self.restarts += 1
                self.spawn()
            }
        }
        do {
            try p.run()
            process = p
            self.pipe = pipe
        } catch {
            NSLog("LidOn: watchdog failed to start: \(error)")
        }
    }

    private func beat() {
        guard let h = pipe?.fileHandleForWriting else { return }
        do { try h.write(contentsOf: Data([1])) } catch { /* terminationHandler가 재시작한다 */ }
    }
}
