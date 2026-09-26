import AppKit
import LidOnCore
import SwiftUI

/// 처음 실행했을 때, 그리고 이미 실행 중인 LidOn을 다시 열었을 때 보여주는 안내 창.
/// 메뉴 막대가 꽉 차서 아이콘이 노치 뒤로 숨어도 앱이 켜져 있다는 걸 알 수 있다.
@MainActor
final class WelcomeWindowController {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    func show(model: AppModel, settings: AppSettings) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: WelcomeView(model: model, settings: settings) { [weak w] in w?.close() })
            w.setContentSize(w.contentView!.fittingSize)
            w.center()
            // 닫힌 창에서 애니메이션이 계속 돌지 않도록, 닫으면 내용과 창을 모두 버린다
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w,
                                                                   queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.window?.contentView = nil
                    self?.window = nil
                    if let o = self?.closeObserver { NotificationCenter.default.removeObserver(o) }
                    self?.closeObserver = nil
                }
            }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct WelcomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let close: () -> Void
    @State private var shown = 0

    private let steps: [(String, Color, LocalizedStringKey)] = [
        ("hand.point.up.left.fill", Theme.teal, "Hold Fn (🌐) while closing the lid to keep running."),
        ("sparkles", Theme.indigo, "AI agents can keep the Mac awake themselves — connect them in Settings → Agents."),
        ("terminal.fill", Color(white: 0.35), "In the terminal: lidon run -- <command>"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 히어로: 빛 위에서 뚜껑이 닫혔다 열리는 노트북
            ZStack {
                LinearGradient(colors: [Theme.teal.opacity(0.28), Theme.indigo.opacity(0.14), .clear],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.mint.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 170)
                LaptopGlyph(width: 190)
                    .offset(y: 8)
            }
            .frame(height: 200)
            .clipped()

            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("LidOn is running")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .accentGradientText()
                    Text("Look for the laptop icon in the menu bar.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .center, spacing: 12) {
                            IconBadge(symbol: step.0, color: step.1, size: 28)
                            Text(step.2).font(.callout).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))
                        .opacity(shown > i ? 1 : 0)
                        .offset(y: shown > i ? 0 : 12)
                    }
                }

                SystemSetupCard()

                Card(highlighted: model.ui.manualOn) {
                    HStack(spacing: 10) {
                        IconBadge(symbol: model.ui.manualOn ? "bolt.fill" : "bolt", color: model.ui.manualOn ? Theme.teal : .gray, size: 26)
                        Text("Keep running with lid closed").font(.body.weight(.semibold))
                        Spacer(minLength: 0)
                        Toggle("Keep running with lid closed", isOn: Binding(get: { model.ui.manualOn }, set: { model.setManual($0) }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(Theme.teal)
                    }
                }

                Text("Don't see the icon? Your menu bar may be full — icons can hide behind the camera notch. Quit a few menu bar apps, or open LidOn again to bring up this window.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    SettingsLink { Label("Settings…", systemImage: "gearshape") }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Done", action: close)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.teal)
                }
            }
            .padding(24)
        }
        .frame(width: 440)
        .animation(Theme.spring, value: model.ui.manualOn)
        .onAppear {
            for i in 1...steps.count {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15 + Double(i) * 0.12)) { shown = i }
            }
        }
    }
}
