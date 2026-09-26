import LidOnCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            GeneralTab(settings: settings).tabItem { Label("General", systemImage: "gearshape") }
            SafetyTab(settings: settings).tabItem { Label("Safety", systemImage: "thermometer.medium") }
            AgentsTab(model: model, settings: settings).tabItem { Label("Agents", systemImage: "sparkles") }
            NotificationsTab(model: model, settings: settings).tabItem { Label("Notifications", systemImage: "bell") }
            HistoryTab(model: model).tabItem { Label("History", systemImage: "clock") }
            AboutTab(model: model).tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 520)
        .tint(Theme.teal)
    }
}

private struct Footnote: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack {
                // step을 주면 눈금이 촘촘하게 그려지므로 값만 반올림한다
                Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                Text(format(value)).monospacedDigit().frame(width: 52, alignment: .trailing)
            }
        }
    }
}

// MARK: - 일반

struct GeneralTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.fnGesture) { SettingLabel("Hold Fn (🌐) while closing the lid to keep running", symbol: "globe", color: Theme.teal) }
                Toggle(isOn: $settings.showAnimation) { SettingLabel("Show full-screen animation", symbol: "sparkles.rectangle.stack.fill", color: Theme.indigo) }
                Toggle(isOn: $settings.hotkeyEnabled) {
                    HStack(spacing: 10) {
                        IconBadge(symbol: "command", color: .orange)
                        Text(L("Global shortcut %@ toggles LidOn", HotKey.display))
                    }
                }
            } header: { Text("How to turn on") }
            LanguageSection()
            Section {
                Toggle(isOn: $settings.lockOnClose) { SettingLabel("Lock screen and turn off display when the lid closes", symbol: "lock.fill", color: .gray) }
                Toggle(isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 })) {
                    SettingLabel("Launch at login", symbol: "power", color: Theme.teal)
                }
            } footer: {
                Footnote("Launch at login works best when LidOn is in the Applications folder.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct LanguageSection: View {
    @State private var selection = AppLanguage.current
    private let launched = AppLanguage.current

    var body: some View {
        Section {
            Picker(selection: $selection) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(verbatim: lang == .system ? "\(lang.nativeName) (\(Self.systemLanguageName))" : lang.nativeName)
                        .tag(lang)
                }
            } label: {
                SettingLabel("Language", symbol: "character.bubble.fill", color: .blue)
            }
            .onChange(of: selection) { _, lang in AppLanguage.apply(lang) }
            if selection != launched {
                HStack {
                    Text("Restart LidOn to apply the new language.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Now") { Relauncher.relaunch() }
                }
            }
        }
    }

    /// 시스템 언어 중 LidOn이 지원하는 첫 번째 언어 (없으면 영어)
    static var systemLanguageName: String {
        let supported = ["en", "ko"]
        let global = UserDefaults(suiteName: UserDefaults.globalDomain)?.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        let first = global.lazy.compactMap { Locale(identifier: $0).language.languageCode?.identifier }.first(where: supported.contains)
        return first == "ko" ? "한국어" : "English"
    }
}

enum Relauncher {
    /// 잠깐 뒤에 앱을 다시 열고 지금 인스턴스를 종료한다
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}

// MARK: - 안전장치

struct SafetyTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.thermalGuard) { SettingLabel("Heat protection", symbol: "flame.fill", color: Theme.coral) }
                if settings.thermalGuard {
                    SliderRow(title: "Battery temperature limit", value: $settings.maxBatteryTemp,
                              range: 35...55, step: 1) { "\(Int($0))°C" }
                }
            } footer: {
                Footnote("Sleeps when macOS reports the Mac is hot, or when the battery reaches the limit.")
            }
            Section {
                Toggle(isOn: $settings.batteryGuard) { SettingLabel("Battery protection", symbol: "battery.25percent", color: .green) }
                if settings.batteryGuard {
                    SliderRow(title: "Minimum battery", value: $settings.minBattery, range: 5...50, step: 5) {
                        "\(Int($0))%"
                    }
                }
                Picker(selection: $settings.maxHours) {
                    Text("No limit").tag(0.0)
                    ForEach([1.0, 2.0, 4.0, 8.0, 12.0, 24.0], id: \.self) { h in
                        Text(Fmt.duration(h * 3600)).tag(h)
                    }
                } label: {
                    SettingLabel("Maximum run time", symbol: "hourglass", color: .purple)
                }
            } footer: {
                Footnote("Even if every safeguard is off, a watchdog restores normal sleep if LidOn crashes or the Mac reaches a critical temperature. Never run a closed Mac inside a bag.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 에이전트

struct AgentsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    @State private var message: String?
    @State private var isError = false
    @State private var refresh = 0

    private var cli: String { CLIInstaller.bundledCLI.path }

    var body: some View {
        Form {
            Section {
                agentRow("Claude Code", symbol: "asterisk", color: Color(red: 0.85, green: 0.47, blue: 0.34), connected: AgentSetup.isInClaude && AgentSetup.isSkillInstalled(.claude),
                         connect: { try AgentSetup.installSkill(.claude); try AgentSetup.addToClaude(cli: cli) },
                         disconnect: { try AgentSetup.uninstallSkill(.claude); try AgentSetup.removeFromClaude() })
                agentRow("Codex", symbol: "chevron.left.forwardslash.chevron.right", color: Color(white: 0.2), connected: AgentSetup.isInCodex,
                         connect: { try AgentSetup.addToCodex(cli: cli) },
                         disconnect: { try AgentSetup.removeFromCodex() })
                agentRow("Cursor", symbol: "cursorarrow.rays", color: Color(white: 0.45), connected: AgentSetup.isInCursor,
                         connect: { try AgentSetup.addToCursor(cli: cli) },
                         disconnect: { try AgentSetup.removeFromCursor() })
                LabeledContent {
                    Button("Copy config") { copy(AgentSetup.mcpJSONSnippet(cli: cli), L("MCP config copied")) }
                } label: {
                    SettingLabel("Other MCP clients", symbol: "puzzlepiece.extension.fill", color: .blue)
                }
                if let m = message {
                    Text(m).font(.caption).foregroundStyle(isError ? .red : .green).textSelection(.enabled)
                }
            } header: { Text("Connect agents") } footer: {
                Footnote("Agents get four tools: keep_awake (with a reason and time limit), allow_sleep, lidon_status and notify. A request is released when the agent calls allow_sleep, when its time runs out (max 12 hours), or when the agent session ends. Claude Code and Codex also get a skill that tells them when to use them (instead of caffeinate). Config files are backed up with a .lidon-backup extension.")
            }
            Section {
                LabeledContent("CLAUDE.md / AGENTS.md") {
                    Button("Copy instructions") { copy(AgentSetup.agentDocs, L("Instructions copied")) }
                }
            } header: { Text("For other agents") } footer: {
                Footnote("Paste these into a project's CLAUDE.md or AGENTS.md so any agent can use the lidon command (lidon run, lidon keep, lidon notify).")
            }
        }
        .formStyle(.grouped)
        .id(refresh)
    }

    private func agentRow(_ name: String, symbol: String, color: Color, connected: Bool,
                          connect: @escaping () throws -> Void, disconnect: @escaping () throws -> Void) -> some View {
        LabeledContent {
            HStack {
                Label(connected ? L("Connected") : L("Not connected"),
                      systemImage: connected ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(connected ? .green : .secondary)
                Button(connected ? L("Disconnect") : L("Connect")) {
                    do {
                        try connected ? disconnect() : connect()
                        isError = false
                        message = connected ? L("%@ disconnected", name) : L("%@ connected — start a new session to use LidOn", name)
                    } catch {
                        isError = true
                        message = "\(error)"
                    }
                    refresh += 1
                }
            }
        } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: symbol, color: color)
                Text(verbatim: name)
            }
        }
    }

    private func copy(_ text: String, _ done: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        isError = false
        message = done
    }
}

// MARK: - 알림

struct NotificationsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @State private var testResult: Bool?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.notifyLocal) { SettingLabel("Show a Mac notification when a session ends", symbol: "bell.badge.fill", color: Theme.coral) }
                    .onChange(of: settings.notifyLocal) { _, on in if on { Notifier.requestPermission() } }
            }
            Section {
                Picker(selection: $settings.webhookKind) {
                    Text("Off").tag(WebhookKind.none)
                    Text(verbatim: "ntfy").tag(WebhookKind.ntfy)
                    Text(verbatim: "Slack").tag(WebhookKind.slack)
                    Text(verbatim: "Discord").tag(WebhookKind.discord)
                    Text("Custom JSON").tag(WebhookKind.json)
                } label: {
                    SettingLabel("Service", symbol: "iphone.radiowaves.left.and.right", color: .green)
                }
                if settings.webhookKind != .none {
                    TextField("Webhook URL", text: $settings.webhookURL, prompt: Text(verbatim: placeholder))
                    HStack {
                        Button("Send test") {
                            testing = true
                            testResult = nil
                            model.sendTestWebhook { ok in
                                testing = false
                                testResult = ok
                            }
                        }
                        .disabled(testing || settings.webhookURL.isEmpty)
                        if testing { ProgressView().controlSize(.small) }
                        if let ok = testResult {
                            Label(ok ? L("Sent") : L("Failed"), systemImage: ok ? "checkmark.circle" : "xmark.circle")
                                .foregroundStyle(ok ? .green : .red)
                        }
                    }
                }
            } header: { Text("Phone notifications") } footer: {
                Footnote("Sent when an agent calls notify, and when work finishes or a safeguard puts the closed Mac to sleep. The Mac waits up to 6 seconds for delivery. With ntfy, install the ntfy app and subscribe to your topic.")
            }
        }
        .formStyle(.grouped)
    }

    private var placeholder: String {
        switch settings.webhookKind {
        case .ntfy: return "https://ntfy.sh/my-lidon-topic"
        case .slack: return "https://hooks.slack.com/services/…"
        case .discord: return "https://discord.com/api/webhooks/…"
        default: return "https://…"
        }
    }
}

// MARK: - 기록

struct HistoryTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.history.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "clock",
                                       description: Text("Close the lid while LidOn is armed to start one."))
            } else {
                summary
                Table(model.history) {
                    TableColumn("Started") { r in
                        Text(Fmt.dateTime(r.start))
                    }
                    .width(min: 125, ideal: 140)
                    TableColumn("Duration") { r in Text(Fmt.duration(r.duration)).monospacedDigit() }
                        .width(min: 60, ideal: 75)
                    TableColumn("Battery") { r in Text(Fmt.battery(r) ?? "—").monospacedDigit() }
                        .width(80)
                    TableColumn("Max temp") { r in
                        Text(r.maxBatteryTemp.map { String(format: "%.1f°C", $0) } ?? "—").monospacedDigit()
                    }
                    .width(60)
                    TableColumn("Ended because") { r in Text(Fmt.reason(r)).lineLimit(1) }
                }
                HStack {
                    Spacer()
                    Button("Clear history", role: .destructive) { model.clearHistory() }
                }
            }
        }
        .padding()
    }

    private var summary: some View {
        let total = model.history.reduce(0) { $0 + $1.duration }
        let drains = model.history.compactMap { r -> Double? in
            guard let a = r.batteryStart, let b = r.batteryEnd, r.duration >= 600, a >= b else { return nil }
            return Double(a - b) / (r.duration / 3600)
        }
        return HStack(spacing: 10) {
            StatTile(icon: "clock.arrow.circlepath", value: "\(model.history.count)", title: L("Sessions"), color: Theme.teal)
            StatTile(icon: "hourglass", value: Fmt.duration(total), title: L("Total time"), color: Theme.indigo)
            if !drains.isEmpty {
                StatTile(icon: "battery.50percent", value: L("%.1f%%/h", drains.reduce(0, +) / Double(drains.count)),
                         title: L("Avg. battery use"), color: Theme.amber)
            }
        }
    }
}

// MARK: - 정보

struct AboutTab: View {
    @ObservedObject var model: AppModel
    @State private var cliMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: AppModel.version)
                LabeledContent("Lid control") { check(model.lid.isAvailable && model.lid.hasLid) }
                LabeledContent("Watchdog") { check(model.watchdog.isRunning) }
                LabeledContent("Terminal connection") { check(model.ipcError == nil) }
            } header: { Text("Status") }
            Section {
                LabeledContent("Command") { Text(verbatim: "lidon").font(.body.monospaced()) }
                Button("Install lidon command") { cliMessage = CLIInstaller.install() }
                if let m = cliMessage { Text(m).font(.caption).textSelection(.enabled) }
            } header: { Text("Terminal") } footer: {
                Footnote("Example: lidon run -- npm test  ·  lidon on --for 2h  ·  lidon status")
            }
            Section {
                Button("Uninstall LidOn…", role: .destructive) { AppUninstaller.confirmAndUninstall(model: model) }
            } footer: {
                Footnote("Removes LidOn together with its system setting (the pmset rule added at install), agent connections, history and settings.")
            }
            Section {
                Footnote("LidOn is free and open source. It uses an undocumented macOS interface, so please test again after major macOS updates.")
            }
        }
        .formStyle(.grouped)
    }

    private func check(_ ok: Bool) -> some View {
        Label(ok ? L("OK") : L("Not available"), systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(ok ? .green : .orange)
    }
}

enum CLIInstaller {
    static var bundledCLI: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/lidon") }

    /// 쓰기 가능한 PATH 디렉터리에 심볼릭 링크를 만든다.
    static func install() -> String {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: bundledCLI.path) else { return L("The lidon command is missing from this build.") }
        let home = fm.homeDirectoryForCurrentUser.path
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin"] {
            if dir.hasPrefix(home) { try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true) }
            guard fm.isWritableFile(atPath: dir) else { continue }
            let link = "\(dir)/lidon"
            try? fm.removeItem(atPath: link)
            do {
                try fm.createSymbolicLink(atPath: link, withDestinationPath: bundledCLI.path)
                var msg = L("Installed: %@", link)
                if dir.hasPrefix(home) { msg += "\n" + L("Add %@ to your PATH.", dir) }
                return msg
            } catch { continue }
        }
        return L("Could not install. Run: sudo ln -sf '%@' /usr/local/bin/lidon", bundledCLI.path)
    }
}
