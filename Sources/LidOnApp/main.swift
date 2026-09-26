import AppKit
import LidOnCore

// `LidOn --watchdog`: 앱을 감시하다가 앱이 사라지면 뚜껑 잠자기를 복구하는 모드
if CommandLine.arguments.contains(Watchdog.argument) {
    Watchdog.run()
}

// 파이프가 끊긴 워치독에 쓸 때 앱이 죽지 않도록
signal(SIGPIPE, SIG_IGN)

// 한 번에 하나만 실행 (두 인스턴스가 커널 상태를 두고 싸우지 않도록)
let lockFD = open(LidOnPaths.lockFile, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
if lockFD < 0 { exit(1) }
if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    let myPath = Bundle.main.bundleURL.standardizedFileURL.path
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: LidOnPaths.bundleID).filter {
        $0.processIdentifier != getpid() && $0.bundleURL?.standardizedFileURL.path != myPath
    }
    if others.isEmpty {
        // 같은 앱이 이미 실행 중 → 조용히 끝내지 말고 안내 창을 띄우게 한다
        _ = try? IPCClient.send(IPCRequest(cmd: "reveal"))
        exit(0)
    }
    // 다른 위치의 LidOn(이전 빌드, 옮기기 전 복사본 등) → 종료시키고 이어받는다
    others.forEach { $0.terminate() }
    var acquired = false
    for _ in 0..<60 {
        usleep(100_000)
        if flock(lockFD, LOCK_EX | LOCK_NB) == 0 { acquired = true; break }
    }
    if !acquired {
        others.forEach { $0.forceTerminate() }
        usleep(500_000)
        if flock(lockFD, LOCK_EX | LOCK_NB) != 0 { exit(1) }
    }
}

LidOnApp.main()
