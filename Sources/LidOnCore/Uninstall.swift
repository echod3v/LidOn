import Foundation

/// LidOn 제거 (앱의 "LidOn 제거…", 휴지통으로 옮겼을 때, `lidon uninstall`).
/// 관리자 권한이 필요한 sudoers 규칙 제거는 호출하는 쪽이 한다 (앱: 암호 창, CLI: sudo).
public enum Uninstall {
    /// Homebrew로 설치했다면 그 Caskroom 경로 (그렇다면 `brew uninstall --zap --cask lidon`으로 지우는 게 맞다)
    public static var brewCaskroom: String? {
        ["/opt/homebrew/Caskroom/lidon", "/usr/local/Caskroom/lidon"].first { FileManager.default.fileExists(atPath: $0) }
    }

    public static let brewCommand = "brew uninstall --zap --cask lidon"

    /// 에이전트 연결(Claude Code·Codex·Cursor 설정과 스킬)을 모두 지운다
    public static func removeAgents() {
        if AgentSetup.isInClaude { try? AgentSetup.removeFromClaude() }
        try? AgentSetup.uninstallSkill(.claude)
        if AgentSetup.isCodexMCPInstalled { try? AgentSetup.removeFromCodex() }
        try? AgentSetup.uninstallSkill(.agents)
        if AgentSetup.isInCursor { try? AgentSetup.removeFromCursor() }
    }

    /// PATH에 만든 `lidon` 링크 중 이 앱을 가리키는 것만 지운다
    public static func removeCLILinks(appBundle: URL) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin"] {
            let link = "\(dir)/lidon"
            guard let dest = try? fm.destinationOfSymbolicLink(atPath: link),
                  dest.hasPrefix(appBundle.path) || dest.contains("LidOn.app/Contents/Helpers/lidon") else { continue }
            try? fm.removeItem(atPath: link)
        }
    }

    /// 기록·상태·로그와 설정값
    public static func removeSupportFiles() {
        try? FileManager.default.removeItem(at: LidOnPaths.supportDir)
        let prefs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(LidOnPaths.bundleID).plist")
        try? FileManager.default.removeItem(at: prefs)
    }
}
