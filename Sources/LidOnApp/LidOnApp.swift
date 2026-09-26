import AppKit
import LidOnCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    lazy var model = AppModel(settings: settings)

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    private let welcome = WelcomeWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onReveal = { [weak self] in self?.showWelcome() }
        installSignalHandlers()
        if CommandLine.arguments.contains("--debug-windows") {
            showDebugWindows()
        } else if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            showWelcome()
        }
    }

    /// 이미 실행 중인 LidOn을 Finder/Dock/Spotlight에서 다시 열었을 때
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWelcome()
        return false
    }

    func showWelcome() {
        welcome.show(model: model, settings: settings)
    }

    /// 개발용: 메뉴와 설정 화면을 일반 창으로 띄운다.
    /// `--debug-snapshot <dir>`을 함께 주면 각 창을 PNG로 저장한다.
    private var debugWindows: [NSWindow] = []
    private func showDebugWindows() {
        LaptopGlyph.freeze = CommandLine.arguments.contains("--debug-still")
        func tab<V: View>(_ v: V) -> AnyView { AnyView(v.frame(width: 520, height: 500).background(Color(nsColor: .windowBackgroundColor))) }
        let views: [(String, AnyView)] = [
            ("menu", AnyView(MenuView(model: model, settings: settings).background(Color(nsColor: .windowBackgroundColor)))),
            ("general", tab(GeneralTab(settings: settings))),
            ("safety", tab(SafetyTab(settings: settings))),
            ("agents", tab(AgentsTab(model: model, settings: settings))),
            ("notifications", tab(NotificationsTab(model: model, settings: settings))),
            ("history", tab(HistoryTab(model: model))),
            ("about", tab(AboutTab(model: model))),
            ("welcome", AnyView(WelcomeView(model: model, settings: settings) {}.background(Color(nsColor: .windowBackgroundColor)))),
            ("overlay-fn", AnyView(OverlayView(model: .preview(.fnHint, L("Close the lid"),
                                                               L("Keep holding Fn while closing — your work keeps running")))
                .frame(width: 900, height: 620).background(Color.black))),
            ("overlay-countdown", AnyView(OverlayView(model: .preview(.fnHint, L("Close the lid"),
                                                                      L("Fn released — close within %d seconds to keep running", 3),
                                                                      deadline: Date().addingTimeInterval(4.5)))
                .frame(width: 900, height: 620).background(Color.black))),
            ("macbook-half", AnyView(MacBookShape(width: 300, lid: 0.55).padding(30).background(Color.black))),
            ("macbook-closed", AnyView(MacBookShape(width: 300, lid: 1).padding(30).background(Color.black))),
            ("overlay-on", AnyView(OverlayView(model: .preview(.confirm, L("LidOn is on"),
                                                               L("You can close the lid — your work keeps running")))
                .frame(width: 900, height: 620).background(Color.black))),
        ]
        for (i, (title, view)) in views.enumerated() {
            let w = NSWindow(contentRect: NSRect(x: 40 + i * 30, y: 100 + i * 30, width: 400, height: 500),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = title
            w.contentView = NSHostingView(rootView: view)
            w.setContentSize(w.contentView!.fittingSize)
            w.isReleasedWhenClosed = false
            w.orderFrontRegardless()
            debugWindows.append(w)
        }
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--debug-snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            for w in self?.debugWindows ?? [] {
                guard let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: dir.appendingPathComponent("\(w.title).png"))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s) else { return }
        model.handleURL(url)
    }

    /// SIGTERM/SIGINT로 종료돼도 정리한다 (SIGKILL은 워치독이 처리)
    private var signalSources: [DispatchSourceSignal] = []
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.model.shutdown() }
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }
}

struct LidOnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: delegate.model, settings: delegate.settings)
        } label: {
            MenuBarIcon(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: delegate.model, settings: delegate.settings)
        }
    }
}

struct MenuBarIcon: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(systemName: Self.symbol(model.ui))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, options: .repeating, isActive: model.ui.state == "sealed")
    }

    static func symbol(_ ui: UIState) -> String {
        switch ui.state {
        case "sealed": return "lock.laptopcomputer"
        case "armed": return "bolt.circle.fill"
        default: return "laptopcomputer"
        }
    }
}
