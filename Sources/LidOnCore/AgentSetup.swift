import Foundation

/// 에이전트(Claude Code, Codex, Cursor 등)가 LidOn을 직접 쓸 수 있게 연결한다.
/// 모두 `lidon mcp`(stdio MCP 서버)를 등록하는 방식이며, 설정 파일을 바꾸기 전에 `.lidon-backup`으로 백업한다.
public enum AgentSetup {
    public static let serverName = "lidon"

    /// CLAUDE.md / AGENTS.md에 붙여 넣을 안내 (`lidon agent-docs`, 설정 → 에이전트)
    public static let agentDocs = """
    ## Keeping this Mac awake (LidOn)

    This Mac runs LidOn. A MacBook normally sleeps when its lid closes, which stops long work.
    Use LidOn — not caffeinate or pmset — whenever the Mac must stay awake. On a MacBook, do it on your own (no need to ask)
    before work that may take about 5 minutes or more (installs, builds, full test suites, downloads, migrations, multi-step
    tasks) and mention it in one line; also when the user asks ("keep it awake for 10 minutes") or steps away. caffeinate does
    not keep a MacBook running with the lid closed. Let it sleep again when done:

    - If the LidOn MCP tools are available: call `keep_awake` (with a reason and minutes) before the work,
      `notify` with a one-line result if the user stepped away, and `allow_sleep` when finished.
    - Otherwise use the `lidon` command:
      - `lidon run -- <command>` for a single long command (releases itself when the command exits)
      - `lidon keep --for 2h --reason "<what>"` → prints an id; `lidon release <id>` when done
      - `lidon notify "<result>"` to tell the user
    - Never leave a request active after the work is done, and never work around LidOn's heat/battery safeguards.
    """

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    // MARK: - 붙여 넣을 설정 조각

    public static func claudeAddArguments(cli: String) -> [String] {
        ["mcp", "add", "--scope", "user", serverName, "--", cli, "mcp"]
    }

    public static func claudeAddCommand(cli: String) -> String {
        "claude " + claudeAddArguments(cli: cli).map(shellQuote).joined(separator: " ")
    }

    public static func codexSnippet(cli: String) -> String {
        """
        [mcp_servers.\(serverName)]
        command = "\(tomlEscape(cli))"
        args = ["mcp"]
        """
    }

    public static func mcpJSONSnippet(cli: String) -> String {
        let obj: [String: Any] = ["mcpServers": [serverName: ["command": cli, "args": ["mcp"]]]]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Claude Code

    /// 스킬을 읽는 위치: Claude Code는 ~/.claude/skills, Codex(와 Agent Skills 표준을 따르는 도구)는 ~/.agents/skills
    public enum SkillHome: CaseIterable {
        case claude, agents
        var path: String { self == .claude ? ".claude/skills/lidon/SKILL.md" : ".agents/skills/lidon/SKILL.md" }
    }

    public static func skillURL(_ where: SkillHome) -> URL { home.appendingPathComponent(`where`.path) }

    public static func isSkillInstalled(_ where: SkillHome) -> Bool {
        FileManager.default.fileExists(atPath: skillURL(`where`).path)
    }

    public static func installSkill(_ where: SkillHome) throws {
        let url = skillURL(`where`)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(LidOnSkill.markdown.utf8).write(to: url, options: .atomic)
    }

    public static func uninstallSkill(_ where: SkillHome) throws {
        let dir = skillURL(`where`).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }

    /// `claude` 실행 파일 찾기 (GUI 앱은 셸 PATH를 물려받지 않으므로 흔한 위치도 찾아본다)
    public static func findClaude() -> String? {
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs += [home.appendingPathComponent(".local/bin").path, home.appendingPathComponent(".claude/local").path,
                 "/opt/homebrew/bin", "/usr/local/bin"]
        return dirs.map { "\($0)/claude" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Claude Code 사용자 설정(~/.claude.json)에 lidon MCP 서버가 있는가 (읽기만 한다)
    public static var isInClaude: Bool {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".claude.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = obj["mcpServers"] as? [String: Any] else { return false }
        return servers[serverName] != nil
    }

    // MARK: Claude Code 권한 — LidOn 도구를 묻지 않고 쓸 수 있게 (에이전트가 알아서 켜려면 필요)

    public static var claudeSettingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    /// 서버 단위 규칙: LidOn MCP 도구 4개만 해당한다 (셸 명령 `lidon run`은 포함하지 않는다)
    public static let claudePermissionRule = "mcp__\(serverName)"

    static func allowingLidOnTools(in settings: [String: Any]) -> [String: Any] {
        var s = settings
        var perms = s["permissions"] as? [String: Any] ?? [:]
        var allow = perms["allow"] as? [String] ?? []
        if !allow.contains(claudePermissionRule) { allow.append(claudePermissionRule) }
        perms["allow"] = allow
        s["permissions"] = perms
        return s
    }

    static func removingLidOnTools(from settings: [String: Any]) -> [String: Any] {
        var s = settings
        guard var perms = s["permissions"] as? [String: Any], var allow = perms["allow"] as? [String] else { return s }
        allow.removeAll { $0 == claudePermissionRule }
        perms["allow"] = allow.isEmpty ? nil : allow
        s["permissions"] = perms.isEmpty ? nil : perms
        return s
    }

    /// 이전 버전(에이전트 자동 감지)이 설치한 `lidon hook claude` 훅을 지운다. 다른 훅은 그대로 둔다.
    static func removingLegacyHooks(from settings: [String: Any]) -> [String: Any] {
        var s = settings
        guard var hooks = s["hooks"] as? [String: Any] else { return s }
        func isLegacy(_ h: Any) -> Bool {
            guard let cmd = (h as? [String: Any])?["command"] as? String else { return false }
            return cmd.contains("lidon") && cmd.hasSuffix(" hook claude")
        }
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            let kept: [Any] = groups.compactMap { g in
                guard var group = g as? [String: Any], let list = group["hooks"] as? [Any] else { return g }
                let rest = list.filter { !isLegacy($0) }
                if rest.count == list.count { return g }
                if rest.isEmpty { return nil }
                group["hooks"] = rest
                return group
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        s["hooks"] = hooks.isEmpty ? nil : hooks
        return s
    }

    public static var isClaudeToolsAllowed: Bool {
        guard let s = try? loadJSON(claudeSettingsURL) else { return false }
        return ((s["permissions"] as? [String: Any])?["allow"] as? [String] ?? []).contains(claudePermissionRule)
    }

    public static func allowClaudeTools() throws {
        let current = try loadJSON(claudeSettingsURL)
        let updated = allowingLidOnTools(in: removingLegacyHooks(from: current))
        guard !NSDictionary(dictionary: updated).isEqual(to: current) else { return }
        try writeJSON(updated, to: claudeSettingsURL)
    }

    public static func disallowClaudeTools() throws {
        guard isClaudeToolsAllowed else { return }
        try writeJSON(removingLidOnTools(from: try loadJSON(claudeSettingsURL)), to: claudeSettingsURL)
    }

    /// `claude mcp add`로 등록한다. ~/.claude.json은 Claude Code가 계속 쓰는 파일이라 직접 고치지 않는다.
    @discardableResult
    public static func addToClaude(cli: String) throws -> String {
        guard let claude = findClaude() else {
            throw SetupError("Claude Code CLI (`claude`) was not found. Run this in a terminal:\n\(claudeAddCommand(cli: cli))")
        }
        _ = run(claude, ["mcp", "remove", "--scope", "user", serverName])   // 경로가 바뀐 경우 다시 등록
        let (status, output) = run(claude, claudeAddArguments(cli: cli))
        guard status == 0 else { throw SetupError("`claude mcp add` failed: \(output)") }
        try allowClaudeTools()
        return output
    }

    public static func removeFromClaude() throws {
        try disallowClaudeTools()
        guard let claude = findClaude() else { throw SetupError("Claude Code CLI (`claude`) was not found") }
        _ = run(claude, ["mcp", "remove", "--scope", "user", serverName])
    }

    // MARK: - Codex (~/.codex/config.toml)

    public static var codexConfigURL: URL { home.appendingPathComponent(".codex/config.toml") }

    public static var isCodexMCPInstalled: Bool {
        ((try? String(contentsOf: codexConfigURL, encoding: .utf8)) ?? "").contains("[mcp_servers.\(serverName)]")
    }

    /// MCP 서버와 스킬이 모두 있어야 연결된 것으로 본다 (스킬이 없으면 Codex가 도구를 쓸 계기를 모른다)
    public static var isInCodex: Bool { isCodexMCPInstalled && isSkillInstalled(.agents) }

    /// Codex: MCP 서버(~/.codex/config.toml) + 스킬(~/.agents/skills/lidon)
    public static func addToCodex(cli: String) throws {
        try installSkill(.agents)
        let current = (try? String(contentsOf: codexConfigURL, encoding: .utf8)) ?? ""
        var text = removingCodexBlock(current).trimmingCharacters(in: .newlines)
        text += (text.isEmpty ? "" : "\n\n") + codexSnippet(cli: cli) + "\n"
        try write(text, to: codexConfigURL)
    }

    public static func removeFromCodex() throws {
        try uninstallSkill(.agents)
        guard let current = try? String(contentsOf: codexConfigURL, encoding: .utf8) else { return }
        try write(removingCodexBlock(current), to: codexConfigURL)
    }

    /// `[mcp_servers.lidon]`과 그 하위 테이블(`[mcp_servers.lidon.env]` 등)을 제거한다
    static func removingCodexBlock(_ toml: String) -> String {
        var out: [Substring] = []
        var skipping = false
        for line in toml.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") {
                skipping = t == "[mcp_servers.\(serverName)]" || t.hasPrefix("[mcp_servers.\(serverName).")
            }
            if !skipping { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Cursor (~/.cursor/mcp.json)

    public static var cursorConfigURL: URL { home.appendingPathComponent(".cursor/mcp.json") }

    public static var isInCursor: Bool {
        guard let obj = try? loadJSON(cursorConfigURL) else { return false }
        return (obj["mcpServers"] as? [String: Any])?[serverName] != nil
    }

    public static func addToCursor(cli: String) throws {
        var obj = try loadJSON(cursorConfigURL)
        var servers = obj["mcpServers"] as? [String: Any] ?? [:]
        servers[serverName] = ["command": cli, "args": ["mcp"]]
        obj["mcpServers"] = servers
        try writeJSON(obj, to: cursorConfigURL)
    }

    public static func removeFromCursor() throws {
        var obj = try loadJSON(cursorConfigURL)
        guard var servers = obj["mcpServers"] as? [String: Any], servers[serverName] != nil else { return }
        servers[serverName] = nil
        obj["mcpServers"] = servers
        try writeJSON(obj, to: cursorConfigURL)
    }

    // MARK: - 공용

    public struct SetupError: Error, CustomStringConvertible {
        public let description: String
        init(_ d: String) { description = d }
    }

    static func loadJSON(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SetupError("\(url.path) is not valid JSON; nothing was changed")
        }
        return obj
    }

    static func writeJSON(_ obj: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try write(String(decoding: data, as: UTF8.self) + "\n", to: url)
    }

    static func write(_ text: String, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("lidon-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
        }
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    static func run(_ exe: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "\(error)") }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func shellQuote(_ s: String) -> String {
        s.allSatisfy { $0.isLetter || $0.isNumber || "-_/.=".contains($0) } ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func tomlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
