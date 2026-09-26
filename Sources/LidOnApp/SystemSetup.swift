import AppKit
import LidOnCore
import SwiftUI

/// 한 번만 하는 관리자 설정 (Homebrew·설치 스크립트로 설치하지 않은 경우 앱에서 마친다)
@MainActor
enum SystemSetup {
    /// macOS가 관리자 암호를 묻는다. 취소하면 nil, 실패하면 오류 문구.
    static func install() -> String? {
        guard let script = StrongMode.installScript(user: NSUserName()) else { return L("Unsupported user name") }
        return runAsAdmin(script)
    }

    /// 규칙 제거 (없으면 암호를 묻지 않는다)
    static func remove() -> String? {
        StrongMode.isInstalled ? runAsAdmin(StrongMode.uninstallScript) : nil
    }

    private static func runAsAdmin(_ script: String) -> String? {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var info: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&info)
        guard let info, (info[NSAppleScript.errorNumber] as? Int) != -128 else { return nil }
        return info[NSAppleScript.errorMessage] as? String ?? L("Something went wrong")
    }
}

/// LidOn 완전히 제거: 시스템 설정(sudoers 규칙), 에이전트 연결, 로그인 항목, 명령어 링크, 기록, 앱
@MainActor
enum AppUninstaller {
    /// 설정의 "LidOn 제거…" 버튼
    static func confirmAndUninstall(model: AppModel) {
        if let _ = Uninstall.brewCaskroom {
            let a = NSAlert()
            a.messageText = L("Installed with Homebrew")
            a.informativeText = L("Run this in Terminal to remove LidOn and its system setting (copied to the clipboard):") + "\n\n" + Uninstall.brewCommand
            a.addButton(withTitle: L("OK"))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Uninstall.brewCommand, forType: .string)
            a.runModal()
            return
        }
        let a = NSAlert()
        a.messageText = L("Uninstall LidOn?")
        a.informativeText = L("This removes LidOn, its system setting, agent connections, history and settings. You'll be asked for your password.")
        a.addButton(withTitle: L("Uninstall"))
        a.addButton(withTitle: L("Cancel"))
        a.buttons.first?.hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return }
        uninstall(model: model, moveAppToTrash: true)
    }

    /// 앱이 휴지통으로 옮겨졌을 때: 남는 것들도 지울지 묻는다
    static func offerCleanupAfterTrash(model: AppModel) {
        let a = NSAlert()
        a.messageText = L("LidOn was moved to the Trash")
        a.informativeText = L("Also remove its system setting, agent connections, history and settings? You'll be asked for your password.")
        a.addButton(withTitle: L("Remove"))
        a.addButton(withTitle: L("Keep"))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        uninstall(model: model, moveAppToTrash: false)
    }

    private static func uninstall(model: AppModel, moveAppToTrash: Bool) {
        if let error = SystemSetup.remove() {
            let e = NSAlert()
            e.messageText = L("Could not remove the system setting")
            e.informativeText = error
            e.runModal()
            return
        }
        // 암호 창을 취소했다면 규칙이 남아 있다 → 멈춘다
        guard !StrongMode.isInstalled else { return }
        model.shutdown()
        _ = model.settings.setLaunchAtLogin(false)
        Uninstall.removeAgents()
        Uninstall.removeCLILinks(appBundle: Bundle.main.bundleURL)
        Uninstall.removeSupportFiles()
        if moveAppToTrash { try? FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil) }
        exit(0)
    }
}

/// 설정이 끝나지 않았을 때 메뉴·안내 창에 보여 주는 카드
struct SystemSetupCard: View {
    @State private var done = StrongMode.isInstalled
    @State private var error: String?

    var body: some View {
        if !done {
            Card(highlighted: true) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        IconBadge(symbol: "lock.shield.fill", color: Theme.amber, size: 26)
                        Text("Finish setup").font(.body.weight(.semibold))
                        Spacer(minLength: 0)
                        Button("Allow…") {
                            error = SystemSetup.install()
                            done = StrongMode.isInstalled
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    Text("Enter your password once so the Mac stays awake even if you plug in or unplug a charger or display with the lid closed.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error {
                        Text(error).font(.caption).foregroundStyle(Theme.coral)
                    }
                }
            }
        }
    }
}
