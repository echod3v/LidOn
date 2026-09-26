import Darwin
import Foundation
import LidOnCore

let usage = """
lidon — keep your Mac running with the lid closed

USAGE
  lidon status [--json]                  Show current state
  lidon on [--for <duration>]            Turn the manual toggle on (e.g. --for 2h, 90m, 1h30m)
  lidon off                              Turn the manual toggle off
  lidon toggle                           Toggle the manual switch

  lidon run [--reason <text>] -- <command> [args...]
                                         Keep awake while <command> runs, then allow sleep
  lidon keep [--for <duration>] [--reason <text>] [--id <id>]
                                         Keep awake for a while (default 1h, max 12h); prints an id
  lidon release <id>                     Release a keep request
  lidon wait <pid> [--reason <text>]     Keep awake until process <pid> exits
  lidon notify <message> [--title <t>]   Notify the user on this Mac (and phone, if set up)

  lidon login-item [on|off|status]       Launch LidOn at login
  lidon system-setup [--remove]          One-time admin setup so the Mac stays awake even when a charger or
                                         display is plugged in or out with the lid closed (asks for your password)

  lidon mcp                              Run the MCP server for AI agents (stdio)
  lidon setup claude|codex|cursor|all    Connect an agent to LidOn (MCP server + Claude Code skill)
  lidon setup --print                    Print config snippets instead of changing files
  lidon agent-docs                       Instructions to paste into CLAUDE.md / AGENTS.md
  lidon version

EXAMPLES
  lidon run -- npm test
  lidon keep --for 3h --reason "training run"
  lidon on --for 2h
"""

func fail(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("lidon: \(msg)\n".utf8))
    exit(code)
}

func request(_ req: IPCRequest) -> IPCResponse {
    do { return try IPCClient.request(req) } catch { fail("LidOn.app is not installed or did not respond") }
}

/// `--name value` 옵션을 꺼내고 인자 목록에서 지운다
func option(_ name: String, in args: inout [String]) -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count else { fail("\(name) needs a value") }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

func minutes(_ s: String?) -> Double? {
    guard let s else { return nil }
    guard let secs = DurationParser.parse(s) else { fail("invalid duration '\(s)' (try 30m, 2h, 1h30m)") }
    return secs / 60
}

/// 번들 안의 실제 lidon 경로 (심볼릭 링크를 따라간다)
var cliPath: String {
    (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath().path
}

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    print(usage)
    exit(0)
}
args.removeFirst()

switch cmd {
case "status":
    let r = request(IPCRequest(cmd: "status"))
    guard let s = r.status else { fail(r.message ?? "no status") }
    if args.contains("--json") {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        print(String(decoding: try! e.encode(s), as: UTF8.self))
    } else {
        print(s.summary)
        if !StrongMode.isInstalled {
            print("  setup:   not finished — run `lidon system-setup` once so plugging in a charger or display")
            print("           with the lid closed doesn't put the Mac to sleep")
        }
    }

case "on":
    let r = request(IPCRequest(cmd: "on", minutes: minutes(option("--for", in: &args))))
    print(r.message ?? (r.ok ? "on" : "failed"))
    exit(r.ok ? 0 : 1)

case "off", "toggle":
    let r = request(IPCRequest(cmd: cmd))
    print(r.message ?? (r.ok ? cmd : "failed"))
    exit(r.ok ? 0 : 1)

case "keep":
    let m = minutes(option("--for", in: &args)) ?? 60
    let id = option("--id", in: &args)
    let reason = option("--reason", in: &args) ?? (args.isEmpty ? nil : args.joined(separator: " "))
    let r = request(IPCRequest(cmd: "hold", minutes: m, label: reason ?? "Terminal request", id: id))
    print(r.message ?? (r.ok ? "ok" : "failed"))
    exit(r.ok ? 0 : 1)

case "release":
    guard let id = args.first else { fail("usage: lidon release <id>") }
    let r = request(IPCRequest(cmd: "release", id: id))
    print(r.message ?? "")
    exit(r.ok ? 0 : 1)

case "wait":
    let reason = option("--reason", in: &args)
    guard let s = args.first, let pid = Int32(s), kill(pid, 0) == 0 || errno == EPERM else {
        fail("usage: lidon wait <pid> (process must exist)")
    }
    let r = request(IPCRequest(cmd: "hold", pid: pid, label: reason ?? "Waiting for pid \(pid)"))
    print(r.message ?? "")
    exit(r.ok ? 0 : 1)

case "run":
    let reason = option("--reason", in: &args) ?? option("--label", in: &args)
    if let i = args.firstIndex(of: "--") { args = Array(args[(i + 1)...]) }
    guard !args.isEmpty else { fail("usage: lidon run [--reason <text>] -- <command> [args...]") }

    let me = getpid()
    // 이 프로세스(lidon run)가 끝나면 앱이 요청을 풀어 준다
    if let r = try? IPCClient.request(IPCRequest(cmd: "hold", pid: me, label: reason ?? args.joined(separator: " "))), !r.ok {
        FileHandle.standardError.write(Data("lidon: warning: \(r.message ?? "request failed")\n".utf8))
    }
    // Ctrl-C는 자식(같은 프로세스 그룹)이 받는다. lidon은 자식이 끝날 때까지 기다렸다가 요청을 푼다.
    signal(SIGINT, SIG_IGN)
    signal(SIGQUIT, SIG_IGN)
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    child.arguments = args
    do { try child.run() } catch { fail("cannot run \(args[0]): \(error.localizedDescription)", code: 127) }
    child.waitUntilExit()
    _ = try? IPCClient.send(IPCRequest(cmd: "release", pid: me), timeout: 2)
    if child.terminationReason == .uncaughtSignal { exit(128 + child.terminationStatus) }
    exit(child.terminationStatus)

case "notify":
    let title = option("--title", in: &args)
    let message = args.joined(separator: " ")
    guard !message.isEmpty else { fail("usage: lidon notify <message> [--title <title>]") }
    let r: IPCResponse
    do { r = try IPCClient.request(IPCRequest(cmd: "notify", title: title, message: message), timeout: 12) } catch {
        fail("LidOn.app is not installed or did not respond")
    }
    print(r.message ?? "sent")
    exit(r.ok ? 0 : 1)

case "hook":
    // 이전 버전이 설치한 Claude Code 훅이 남아 있어도 조용히 끝낸다 (`lidon setup claude`가 지운다)
    exit(0)

case "login-item":
    let action = args.first ?? "status"
    guard ["on", "off", "status"].contains(action) else { fail("usage: lidon login-item [on|off|status]") }
    let r = request(IPCRequest(cmd: "login-item", label: action))
    print(r.message ?? "")
    exit(r.ok ? 0 : 1)

case "system-setup":
    let remove = args.contains("--remove")
    let user = option("--user", in: &args) ?? ProcessInfo.processInfo.environment["SUDO_USER"] ?? NSUserName()
    if getuid() != 0 {
        // sudo로 자신을 다시 실행한다 (터미널에서 암호를 묻는다)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = [cliPath, "system-setup", "--user", user] + (remove ? ["--remove"] : [])
        do { try p.run() } catch { fail("could not run sudo") }
        p.waitUntilExit()
        exit(p.terminationStatus)
    }
    guard let script = remove ? StrongMode.uninstallScript : StrongMode.installScript(user: user) else {
        fail("run this as your own user, not root (or pass --user <name>)")
    }
    guard StrongMode.runAsRoot(script) else { fail("could not update \(StrongMode.sudoersPath)") }
    print(remove ? "✓ Removed \(StrongMode.sudoersPath)"
                 : "✓ Done. LidOn now keeps the Mac awake even if a charger or display is plugged in or out with the lid closed.")

case "mcp":
    MCPServer.run()

case "setup":
    runSetup(args)

case "agent-docs":
    print(AgentSetup.agentDocs)

case "version", "--version", "-v":
    // CLI는 LidOn.app/Contents/Helpers/lidon 에 있다 → 번들의 Info.plist에서 버전을 읽는다
    let plist = URL(fileURLWithPath: cliPath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
    let cliVersion = (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String) ?? "dev"
    let r = try? IPCClient.send(IPCRequest(cmd: "status"))
    print("lidon \(cliVersion)" + (r?.status.map { " (app \($0.version) running)" } ?? " (app not running)"))

case "help", "--help", "-h":
    print(usage)

default:
    fail("unknown command '\(cmd)'\n\n\(usage)")
}
