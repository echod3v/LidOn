import Foundation
import LidOnCore

func runSetup(_ args: [String]) {
    let target = args.first ?? "--print"
    let cli = cliPath

    if target == "--print" {
        print("""
        # Claude Code (MCP server)
        \(AgentSetup.claudeAddCommand(cli: cli))

        # Skills: ~/.claude/skills/lidon (Claude Code), ~/.agents/skills/lidon (Codex) — installed by `lidon setup claude|codex`

        # Codex: ~/.codex/config.toml
        \(AgentSetup.codexSnippet(cli: cli))

        # Cursor (~/.cursor/mcp.json) and most other MCP clients
        \(AgentSetup.mcpJSONSnippet(cli: cli))
        """)
        return
    }

    let targets = target == "all" ? ["claude", "codex", "cursor"] : [target]
    var failed = false
    for t in targets {
        do {
            switch t {
            case "claude":
                try AgentSetup.installSkill(.claude)
                print("✓ Claude Code skill installed: \(AgentSetup.skillURL(.claude).path)")
                try AgentSetup.addToClaude(cli: cli)
                print("✓ Claude Code MCP server added (user scope)")
                print("✓ LidOn tools allowed without prompts (\(AgentSetup.claudePermissionRule) in ~/.claude/settings.json)")
                print("  Start a new Claude Code session to use it.")
            case "codex":
                try AgentSetup.addToCodex(cli: cli)
                print("✓ Codex: added [mcp_servers.lidon] to \(AgentSetup.codexConfigURL.path)")
                print("✓ Codex skill installed: \(AgentSetup.skillURL(.agents).path). Start a new Codex session to use it.")
            case "cursor":
                try AgentSetup.addToCursor(cli: cli)
                print("✓ Cursor: added lidon to \(AgentSetup.cursorConfigURL.path)")
            default:
                fail("usage: lidon setup claude|codex|cursor|all|--print")
            }
        } catch {
            failed = true
            FileHandle.standardError.write(Data("✗ \(t): \(error)\n".utf8))
        }
    }
    if !cli.hasPrefix("/Applications/") {
        print("note: LidOn is not in /Applications. If you move the app, run `lidon setup` again.")
    }
    if failed { exit(1) }
}
