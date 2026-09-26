import Darwin
import Foundation
import LidOnCore

/// `lidon mcp` — 에이전트가 직접 LidOn을 제어하는 stdio MCP 서버.
///
/// 한 줄에 JSON-RPC 메시지 하나(stdout), 로그는 stderr.
/// `keep_awake` 요청은 이 서버 프로세스(= 에이전트 세션)에 묶이므로, 에이전트가 끝나면 자동으로 풀린다.
enum MCPServer {
    static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    static var holdID: String { "mcp-\(getpid())" }

    static let tools: [[String: Any]] = [
        [
            "name": "keep_awake",
            "title": "Keep the Mac awake",
            "description": """
            Keep this MacBook awake / prevent sleep for a set time, even if the user closes the lid. \
            Call it on your own, without asking, before work that may take about 5 minutes or more \
            (installs, builds, full test suites, downloads, data processing, long multi-step tasks), and mention it in one short line. \
            Also use it for any request like "keep my Mac awake" or "don't let it sleep for 10 minutes" (use exactly the time asked). \
            Use this instead of caffeinate or pmset — those do not keep a MacBook running with the lid closed. \
            For your own work you cannot see a clock, so choose minutes generously (about twice your estimate); the response says \
            when the request expires, and calling again replaces the reason and time. \
            LidOn itself puts the Mac to sleep if it overheats or the battery runs low, so you do not need to monitor that. \
            Always call allow_sleep when the work is done or has failed. Released automatically when this session ends.
            """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "reason": ["type": "string", "description": "What you are doing, shown to the user (e.g. \"running the full test suite\")"],
                    "minutes": ["type": "number", "minimum": 1, "maximum": 720, "description": "How long to keep the Mac awake (default 60, max 720)"],
                ],
                "required": ["reason"],
            ],
            "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false],
        ],
        [
            "name": "allow_sleep",
            "title": "Let the Mac sleep",
            "description": "Release your keep_awake request when the work is finished (or failed). If the lid is closed and nothing else keeps the Mac awake, it goes to sleep.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
            "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false],
        ],
        [
            "name": "lidon_status",
            "title": "LidOn status",
            "description": "Show whether the lid is closed, battery level and temperature, thermal state, and active keep-awake requests.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "notify",
            "title": "Notify the user",
            "description": "Send the user a short notification on this Mac and, if they set it up in LidOn, on their phone. Use it when long work finishes or needs their attention while they are away. Keep it to one or two lines. The response says where it was actually delivered; if it did not reach their phone, also report the result in your reply.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "message": ["type": "string", "description": "What happened (e.g. \"All 412 tests passed\")"],
                    "title": ["type": "string", "description": "Optional short title"],
                ],
                "required": ["message"],
            ],
            "annotations": ["readOnlyHint": false, "destructiveHint": false, "openWorldHint": true],
        ],
    ]

    static func run() -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        signal(SIGPIPE, SIG_IGN)
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let msg = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            if let reply = handle(msg) { send(reply) }
        }
        // 에이전트가 연결을 닫았다 → 이 세션의 요청 해제 (프로세스 종료 감시로도 풀리지만 즉시 정리)
        _ = try? IPCClient.send(IPCRequest(cmd: "release", id: holdID), timeout: 1)
        exit(0)
    }

    static func handle(_ msg: [String: Any]) -> [String: Any]? {
        guard let method = msg["method"] as? String else { return nil }   // 응답 메시지 등은 무시
        let id = msg["id"]
        let params = msg["params"] as? [String: Any] ?? [:]
        guard let id else { return nil }   // 알림(notifications/*)에는 답하지 않는다

        func result(_ r: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": r] }
        func error(_ code: Int, _ message: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
        }

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            let version = requested.flatMap { supportedVersions.contains($0) ? $0 : nil } ?? supportedVersions[0]
            return result([
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "lidon", "title": "LidOn", "version": "1.0.0"],
                "instructions": "LidOn keeps this MacBook running even if the lid is closed. Before work that may take about 5 minutes or more, call keep_awake on your own (no need to ask) and mention it briefly; call allow_sleep when done. When the user asks to keep the Mac awake or prevent sleep, call keep_awake instead of using caffeinate or pmset.",
            ])
        case "ping":
            return result([:])
        case "tools/list":
            return result(["tools": tools])
        case "tools/call":
            guard let name = params["name"] as? String else { return error(-32602, "Missing tool name") }
            let args = params["arguments"] as? [String: Any] ?? [:]
            let (text, isError) = callTool(name, args)
            return result(["content": [["type": "text", "text": text]], "isError": isError])
        case "resources/list":
            return result(["resources": [Any]()])
        case "prompts/list":
            return result(["prompts": [Any]()])
        default:
            return error(-32601, "Method not found: \(method)")
        }
    }

    static func callTool(_ name: String, _ args: [String: Any]) -> (String, Bool) {
        do {
            switch name {
            case "keep_awake":
                let reason = (args["reason"] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                let minutes = (args["minutes"] as? NSNumber)?.doubleValue ?? 60
                let r = try IPCClient.request(IPCRequest(cmd: "hold", minutes: minutes, pid: getpid(),
                                                         label: reason.isEmpty ? "Agent task" : reason, id: holdID))
                guard r.ok, let st = r.status else { return (r.message ?? "LidOn refused the request", true) }
                return (keepAwakeReply(st), false)
            case "allow_sleep":
                let r = try IPCClient.request(IPCRequest(cmd: "release", id: holdID))
                return (r.message ?? "Released", !r.ok)
            case "lidon_status":
                let r = try IPCClient.request(IPCRequest(cmd: "status"))
                guard let s = r.status else { return (r.message ?? "No status", true) }
                var text = s.summary
                text += "\n  phone notifications: " + (s.phoneNotifications ? "set up" : "not set up")
                if let mine = s.holds.first(where: { $0.id == holdID }) {
                    text += "\nYour keep_awake request: \"\(mine.label)\"" + (mine.until.map { ", " + StatusSnapshot.remaining($0) } ?? "")
                } else {
                    text += "\nYou have no active keep_awake request."
                }
                return (text, false)
            case "notify":
                guard let message = args["message"] as? String, !message.isEmpty else { return ("message is required", true) }
                // 휴대폰 전송 결과를 기다린다 (최대 약 6초)
                let r = try IPCClient.request(IPCRequest(cmd: "notify", title: args["title"] as? String, message: message), timeout: 12)
                return (r.message ?? "Sent", !r.ok)
            default:
                return ("Unknown tool: \(name)", true)
            }
        } catch {
            return ("LidOn is not running and could not be started. Ask the user to open LidOn.app.", true)
        }
    }

    /// keep_awake 응답: 만료 시각, 다음에 할 일, 지금 알아 둘 경고
    static func keepAwakeReply(_ st: StatusSnapshot) -> String {
        let mine = st.holds.first { $0.id == holdID }
        var lines = ["Keeping the Mac awake for \"\(mine?.label ?? "Agent task")\"."]
        if let u = mine?.until {
            lines.append("It \(StatusSnapshot.remaining(u)) (at \(StatusSnapshot.time(u))). If the work may run longer, call keep_awake again before then.")
        }
        lines.append("When the work is done or has failed: if the user stepped away, call notify with the result; then call allow_sleep.")
        lines.append("LidOn will put the Mac to sleep by itself if it overheats or the battery runs low (10% when unplugged), and tell the user.")
        var warnings: [String] = []
        let p = st.power
        if let b = p.batteryPercent, !p.onAC {
            if b <= 20 {
                warnings.append("Battery is at \(b)% and not charging — the Mac may sleep before long work finishes. Suggest the user plug in.")
            } else if b <= 40 {
                warnings.append("Battery is at \(b)% and not charging. For long work, suggest the user plug in.")
            }
        }
        if p.thermal >= .fair {
            warnings.append("The Mac is already warm (thermal: \(["nominal", "fair", "serious", "critical"][p.thermal.rawValue])).")
        }
        if !st.phoneNotifications {
            warnings.append("Phone notifications are not set up in LidOn, so notify only reaches the Mac screen. If the user is leaving, tell them in your reply.")
        }
        if st.lidClosed { lines.append("The lid is already closed; the Mac keeps running.") }
        if st.hasLid == false {
            lines.append("Note: this Mac has no lid (desktop). LidOn still prevents idle sleep, but you only need it here when the user asks.")
        }
        if !warnings.isEmpty { lines.append("Warnings:\n- " + warnings.joined(separator: "\n- ")) }
        return lines.joined(separator: "\n")
    }

    static func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
}
