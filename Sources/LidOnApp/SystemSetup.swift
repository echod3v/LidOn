import AppKit
import LidOnCore
import SwiftUI

/// 한 번만 하는 관리자 설정 (Homebrew·설치 스크립트로 설치하지 않은 경우 앱에서 마친다)
@MainActor
enum SystemSetup {
    /// macOS가 관리자 암호를 묻는다. 취소하면 nil, 실패하면 오류 문구.
    static func install() -> String? {
        guard let script = StrongMode.installScript(user: NSUserName()) else { return L("Unsupported user name") }
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var info: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&info)
        guard let info, (info[NSAppleScript.errorNumber] as? Int) != -128 else { return nil }
        return info[NSAppleScript.errorMessage] as? String ?? L("Something went wrong")
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
