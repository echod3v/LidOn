import Darwin
import Foundation

public enum LidOnPaths {
    public static let bundleID = "dev.lidon.LidOn"

    public static var supportDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LidOn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir
    }

    public static var socket: String { supportDir.appendingPathComponent("lidon.sock").path }
    public static var lockFile: String { supportDir.appendingPathComponent("app.lock").path }
}

// MARK: - 메시지

public struct IPCRequest: Codable, Sendable {
    public var cmd: String
    public var minutes: Double?
    /// hold를 소유한 프로세스. 이 프로세스가 끝나면 hold가 풀린다.
    public var pid: Int32?
    public var label: String?
    /// hold / release 대상 ID
    public var id: String?
    // cmd == "notify"
    public var title: String?
    public var message: String?

    public init(cmd: String, minutes: Double? = nil, pid: Int32? = nil, label: String? = nil, id: String? = nil,
                title: String? = nil, message: String? = nil) {
        self.cmd = cmd
        self.minutes = minutes
        self.pid = pid
        self.label = label
        self.id = id
        self.title = title
        self.message = message
    }
}

public struct StatusSnapshot: Codable, Sendable {
    public var state: String            // idle | armed | sealed
    public var triggers: [Trigger]
    public var lidClosed: Bool
    /// 뚜껑이 있는 Mac(MacBook)인가. 이전 버전 앱에는 없는 값이다.
    public var hasLid: Bool?
    public var manualOn: Bool
    public var manualUntil: Date?
    public var power: PowerStatus
    public var holds: [Hold]
    /// 휴대폰 알림(웹훅)이 설정되어 있는가
    public var phoneNotifications: Bool
    public var version: String

    public init(state: String, triggers: [Trigger], lidClosed: Bool, hasLid: Bool, manualOn: Bool, manualUntil: Date?,
                power: PowerStatus, holds: [Hold], phoneNotifications: Bool, version: String) {
        self.hasLid = hasLid
        self.state = state
        self.triggers = triggers
        self.lidClosed = lidClosed
        self.manualOn = manualOn
        self.manualUntil = manualUntil
        self.power = power
        self.holds = holds
        self.phoneNotifications = phoneNotifications
        self.version = version
    }
}

public struct IPCResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String?
    public var status: StatusSnapshot?

    public init(ok: Bool, message: String? = nil, status: StatusSnapshot? = nil) {
        self.ok = ok
        self.message = message
        self.status = status
    }
}

enum IPCCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - 소켓 공통

private func makeAddress(_ path: String) -> sockaddr_un? {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    guard bytes.count < capacity else { return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { dst in
        dst.copyBytes(from: bytes)
        dst[bytes.count] = 0
    }
    return addr
}

private func readLine(_ fd: Int32, limit: Int = 1 << 20) -> Data {
    var data = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while data.count < limit {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { break }
        data.append(buf, count: n)
        if buf[..<n].contains(10) { break }
    }
    if let nl = data.firstIndex(of: 10) { data = data[..<nl] }
    return data
}

private func writeAll(_ fd: Int32, _ data: Data) {
    data.withUnsafeBytes { raw in
        var off = 0
        while off < raw.count {
            let n = write(fd, raw.baseAddress! + off, raw.count - off)
            if n <= 0 { return }
            off += n
        }
    }
}

private func setTimeouts(_ fd: Int32, seconds: Int) {
    var tv = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
}

// MARK: - 서버 (앱)

/// 한 연결당 JSON 한 줄 요청 → JSON 한 줄 응답. 같은 사용자의 프로세스만 허용한다.
public final class IPCServer {
    private let path: String
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "lidon.ipc")
    private let handler: (IPCRequest, @escaping (IPCResponse) -> Void) -> Void

    /// handler는 메인 스레드에서 호출되고, 응답은 나중에(예: 웹훅 전송 뒤) reply로 보낼 수 있다.
    public init(path: String = LidOnPaths.socket,
                handler: @escaping (IPCRequest, @escaping (IPCResponse) -> Void) -> Void) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var addr = makeAddress(path) else { throw POSIXError(.EINVAL) }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard ok, listen(fd, 16) == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        chmod(path, 0o600)
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let c = accept(self.fd, nil, nil)
            // 느린 요청(notify)이 다른 요청을 막지 않도록 연결마다 따로 처리
            if c >= 0 { DispatchQueue.global(qos: .userInitiated).async { self.serve(c) } }
        }
        src.resume()
        source = src
    }

    public func stop() {
        source?.cancel()
        if fd >= 0 { close(fd) }
        unlink(path)
    }

    private func serve(_ c: Int32) {
        defer { close(c) }
        setTimeouts(c, seconds: 3)
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(c, &peerUID, &peerGID) == 0, peerUID == getuid() else { return }

        let response: IPCResponse
        if let req = try? IPCCoding.decoder.decode(IPCRequest.self, from: readLine(c)) {
            let done = DispatchSemaphore(value: 0)
            let box = ResponseBox()
            DispatchQueue.main.async {
                self.handler(req) { r in
                    box.set(r)
                    done.signal()
                }
            }
            response = done.wait(timeout: .now() + 15) == .success
                ? (box.get() ?? IPCResponse(ok: false, message: "no response"))
                : IPCResponse(ok: false, message: "LidOn did not respond in time")
        } else {
            response = IPCResponse(ok: false, message: "invalid request")
        }
        var out = (try? IPCCoding.encoder.encode(response)) ?? Data()
        out.append(10)
        writeAll(c, out)
    }
}

private final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: IPCResponse?
    func set(_ v: IPCResponse) { lock.lock(); value = v; lock.unlock() }
    func get() -> IPCResponse? { lock.lock(); defer { lock.unlock() }; return value }
}

// MARK: - 클라이언트 (CLI)

public enum IPCClient {
    public enum Failure: Error { case notRunning, badResponse }

    public static func send(_ req: IPCRequest, path: String = LidOnPaths.socket, timeout: Int = 5) throws -> IPCResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var addr = makeAddress(path) else { throw Failure.notRunning }
        defer { close(fd) }
        setTimeouts(fd, seconds: timeout)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard ok else { throw Failure.notRunning }
        var data = try IPCCoding.encoder.encode(req)
        data.append(10)
        writeAll(fd, data)
        guard let res = try? IPCCoding.decoder.decode(IPCResponse.self, from: readLine(fd)) else {
            throw Failure.badResponse
        }
        return res
    }
}

// MARK: - 시간 문자열

public enum DurationParser {
    /// "90" (분), "90m", "2h", "1h30m", "45s", "1.5h" → 초
    public static func parse(_ s: String) -> TimeInterval? {
        let str = s.trimmingCharacters(in: .whitespaces).lowercased()
        guard !str.isEmpty else { return nil }
        if let minutes = Double(str) { return minutes > 0 ? minutes * 60 : nil }
        var total: TimeInterval = 0
        var number = ""
        var sawUnit = false
        for ch in str {
            if ch.isNumber || ch == "." {
                number.append(ch)
            } else {
                guard let v = Double(number) else { return nil }
                switch ch {
                case "h": total += v * 3600
                case "m": total += v * 60
                case "s": total += v
                default: return nil
                }
                number = ""
                sawUnit = true
            }
        }
        guard number.isEmpty, sawUnit, total > 0 else { return nil }
        return total
    }
}

// MARK: - 공용 클라이언트 (CLI, MCP 서버)

extension IPCClient {
    /// 앱에 요청을 보낸다. 앱이 꺼져 있으면 백그라운드로 실행하고 최대 10초 기다린다.
    public static func request(_ req: IPCRequest, timeout: Int = 5) throws -> IPCResponse {
        if let r = try? send(req, timeout: timeout) { return r }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-b", LidOnPaths.bundleID]
        open.standardOutput = FileHandle.nullDevice
        open.standardError = FileHandle.nullDevice
        try? open.run()
        open.waitUntilExit()
        guard open.terminationStatus == 0 else { throw Failure.notRunning }
        for _ in 0..<50 {
            usleep(200_000)
            if let r = try? send(req, timeout: timeout) { return r }
        }
        throw Failure.notRunning
    }
}

extension StatusSnapshot {
    /// 사람과 에이전트가 읽을 요약 (영어, CLI와 MCP 공용)
    public var summary: String {
        let stateText = ["idle": "Idle — the Mac sleeps normally when the lid closes",
                         "armed": "Armed — closing the lid keeps the Mac running",
                         "sealed": "Running with the lid closed"][state] ?? state
        var lines = ["LidOn \(version): \(stateText)"]
        if !triggers.isEmpty { lines.append("  because: \(triggers.map(\.rawValue).joined(separator: ", "))") }
        if manualOn {
            lines.append("  manual:  on" + (manualUntil.map { " until " + Self.time($0) } ?? ""))
        }
        if hasLid == false {
            lines.append("  lid:     none (desktop Mac — no need to keep it awake for the lid)")
        } else {
            lines.append("  lid:     \(lidClosed ? "closed" : "open") (MacBook)")
        }
        var battery = power.batteryPercent.map { "\($0)%" } ?? "—"
        if power.onAC { battery += power.charging ? " (charging)" : " (on power)" }
        lines.append("  battery: \(battery)" + (power.batteryTempC.map { String(format: ", %.1f°C", $0) } ?? ""))
        lines.append("  thermal: \(["nominal", "fair", "serious", "critical"][power.thermal.rawValue])")
        for h in holds {
            var line = "  request: [\(h.id)] \(h.label)"
            if let u = h.until { line += " (until \(Self.time(u)), \(Self.remaining(u)))" }
            if let p = h.pid { line += " (while pid \(p) runs)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// "expires in 42 min" — 에이전트는 시계를 보지 않으므로 남은 시간을 함께 알려 준다
    public static func remaining(_ until: Date, now: Date = Date()) -> String {
        let m = Int((until.timeIntervalSince(now) / 60).rounded(.up))
        if m <= 0 { return "expired" }
        return m >= 60 ? "expires in \(m / 60)h \(m % 60)m" : "expires in \(m) min"
    }

    public static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
