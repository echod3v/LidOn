import AppKit
import SwiftUI

/// Fn을 누르고 있을 때 / 수동으로 켰을 때 보여주는 전체 화면 애니메이션
final class OverlayController {
    private var windows: [NSWindow] = []
    private var hideWork: DispatchWorkItem?
    private(set) var isShowing = false

    func show(title: String, subtitle: String, symbol: String = "laptopcomputer", autoHide: TimeInterval? = nil) {
        hideWork?.cancel()
        if isShowing { hide(animated: false) }
        isShowing = true
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.contentView = NSHostingView(rootView: OverlayView(title: title, subtitle: subtitle, symbol: symbol))
            w.setFrame(screen.frame, display: false)
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; w.animator().alphaValue = 1 }
            windows.append(w)
        }
        if let t = autoHide {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: work)
        }
    }

    func hide(animated: Bool = true) {
        hideWork?.cancel()
        guard isShowing else { return }
        isShowing = false
        let ws = windows
        windows = []
        guard animated else { ws.forEach { $0.orderOut(nil) }; return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ws.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { ws.forEach { $0.orderOut(nil) } })
    }
}

struct OverlayView: View {
    let title: String
    let subtitle: String
    let symbol: String
    @State private var appear = false

    /// Fn 안내(뚜껑 닫는 동작을 보여 줌)인가, 켜짐 확인인가
    private var isFnHint: Bool { symbol == "laptopcomputer" }

    var body: some View {
        ZStack {
            BehindWindowBlur()
            Color.black.opacity(0.45)
            // 가운데에서 번지는 빛
            RadialGradient(colors: [Theme.mint.opacity(0.28), Theme.teal.opacity(0.08), .clear],
                           center: .center, startRadius: 0, endRadius: 520)
                .scaleEffect(appear ? 1 : 0.6)

            VStack(spacing: 34) {
                ZStack {
                    StatusOrb(state: .armed, size: isFnHint ? 280 : 190, symbol: isFnHint ? "" : "bolt.fill")
                        .opacity(isFnHint ? 0.5 : 1)
                    if isFnHint {
                        LaptopGlyph(width: 220, animating: true)
                            .offset(y: 4)
                    }
                }
                .scaleEffect(appear ? 1 : 0.7)
                .opacity(appear ? 1 : 0)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .multilineTextAlignment(.center)
                .offset(y: appear ? 0 : 16)
                .opacity(appear ? 1 : 0)

                if isFnHint {
                    FnKeycap()
                        .offset(y: appear ? 0 : 20)
                        .opacity(appear ? 1 : 0)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { appear = true }
        }
    }
}

/// 눌려 있는 Fn(🌐) 키
private struct FnKeycap: View {
    @State private var pressed = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "fn").font(.system(size: 15, weight: .semibold, design: .rounded))
                Image(systemName: "globe").font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 58, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.mint.opacity(0.9), lineWidth: 1.5))
            .shadow(color: Theme.mint.opacity(pressed ? 0.8 : 0.3), radius: pressed ? 16 : 6)
            .scaleEffect(pressed ? 0.94 : 1)
            .offset(y: pressed ? 2 : 0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pressed = true }
        }
    }
}
