import AppKit
import SwiftUI

/// 전체 화면 안내에 보여 줄 내용. 창을 다시 만들지 않고 내용만 바꿀 수 있게 공유한다.
final class OverlayModel: ObservableObject {
    enum Kind { case fnHint, confirm }

    @Published var kind: Kind = .fnHint
    @Published var title = ""
    @Published var subtitle = ""
    /// Fn을 뗀 뒤 유예 시간 — 이 시각 안에 뚜껑을 닫으면 계속 실행된다
    @Published var deadline: Date?
    @Published var graceDuration: TimeInterval = 3
    /// 다른 입력으로 취소됨 — 잠깐 보여 주고 사라진다
    @Published var cancelled = false

    /// 캡처용 미리보기
    static func preview(_ kind: Kind, _ title: String, _ subtitle: String, deadline: Date? = nil,
                        cancelled: Bool = false) -> OverlayModel {
        let m = OverlayModel()
        m.kind = kind
        m.title = title
        m.subtitle = subtitle
        m.deadline = deadline
        m.graceDuration = 3
        m.cancelled = cancelled
        return m
    }
}

/// Fn을 누르고 있을 때 / 수동으로 켰을 때 보여 주는 전체 화면 안내
final class OverlayController {
    private var windows: [NSWindow] = []
    private var hideWork: DispatchWorkItem?
    private let model = OverlayModel()
    private(set) var isShowing = false

    func show(_ kind: OverlayModel.Kind, title: String, subtitle: String, autoHide: TimeInterval? = nil) {
        hideWork?.cancel()
        withAnimation(Theme.spring) {
            model.kind = kind
            model.title = title
            model.subtitle = subtitle
            model.deadline = nil
            model.cancelled = false
        }
        if !isShowing { present() }
        if let t = autoHide { scheduleHide(after: t) }
    }

    /// Fn을 뗀 뒤: 안내를 바로 닫지 않고 남은 시간을 보여 준다
    func countdown(_ seconds: TimeInterval, subtitle: String) {
        guard isShowing else { return }
        withAnimation(Theme.spring) {
            model.subtitle = subtitle
            model.graceDuration = seconds
            model.deadline = Date().addingTimeInterval(seconds)
        }
        scheduleHide(after: seconds)
    }

    /// 다른 키·마우스 입력으로 취소: 짧게 "취소됨"을 보여 주고 사라진다
    func cancel(title: String, subtitle: String) {
        guard isShowing, !model.cancelled else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            model.cancelled = true
            model.deadline = nil
            model.title = title
            model.subtitle = subtitle
        }
        scheduleHide(after: 0.55)
    }

    func hide(animated: Bool = true) {
        hideWork?.cancel()
        guard isShowing else { return }
        isShowing = false
        let ws = windows
        windows = []
        guard animated else { ws.forEach { $0.orderOut(nil) }; return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ws.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { ws.forEach { $0.orderOut(nil) } })
    }

    private func scheduleHide(after t: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: work)
    }

    private func present() {
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
            w.contentView = NSHostingView(rootView: OverlayView(model: model))
            w.setFrame(screen.frame, display: false)
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; w.animator().alphaValue = 1 }
            windows.append(w)
        }
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @State private var appear = false

    var body: some View {
        ZStack {
            BehindWindowBlur()
            Color.black.opacity(0.5)
            // 가운데 은은한 빛 하나
            RadialGradient(colors: [Theme.teal.opacity(0.35), Theme.indigo.opacity(0.12), .clear],
                           center: .center, startRadius: 0, endRadius: 460)
                .scaleEffect(appear ? 1 : 0.7)

            VStack(spacing: 30) {
                Group {
                    if model.kind == .fnHint {
                        LaptopGlyph(width: 250, motion: .closeOnce, animating: !model.cancelled)
                            .saturation(model.cancelled ? 0.2 : 1)
                            .scaleEffect(model.cancelled ? 0.92 : 1)
                    } else {
                        StatusOrb(state: .armed, size: 150, symbol: "bolt.fill")
                    }
                }
                .scaleEffect(appear ? 1 : 0.85)
                .opacity(appear ? 1 : 0)

                VStack(spacing: 10) {
                    Text(model.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                    Text(model.subtitle)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .contentTransition(.opacity)
                }
                .multilineTextAlignment(.center)
                .offset(y: appear ? 0 : 14)
                .opacity(appear ? 1 : 0)

                if model.kind == .fnHint {
                    FnKeycap(deadline: model.deadline, duration: model.graceDuration, cancelled: model.cancelled)
                        .offset(y: appear ? 0 : 18)
                        .opacity(appear ? 1 : 0)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { appear = true }
        }
    }
}

/// Fn(🌐) 키. 누르고 있는 동안은 숨 쉬듯 빛나고, 뗀 뒤에는 남은 시간이 링으로 줄어든다.
private struct FnKeycap: View {
    var deadline: Date?
    var duration: TimeInterval
    var cancelled = false
    @State private var pulse = false
    @State private var shake: CGFloat = 0

    var body: some View {
        ZStack {
            if let deadline {
                // 남은 시간 링 + 숫자
                TimelineView(.animation) { ctx in
                    let left = max(0, deadline.timeIntervalSince(ctx.date))
                    ZStack {
                        Circle().stroke(.white.opacity(0.12), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: left / max(duration, 0.1))
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(verbatim: "\(Int(left.rounded(.up)))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.mint)
                            .contentTransition(.numericText(countsDown: true))
                            .offset(y: 62)
                    }
                    .frame(width: 88, height: 88)
                }
                .transition(.scale.combined(with: .opacity))
            }
            Group {
                if cancelled {
                    Image(systemName: "xmark").font(.system(size: 22, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    VStack(spacing: 4) {
                        Text(verbatim: "fn").font(.system(size: 15, weight: .semibold, design: .rounded))
                        Image(systemName: "globe").font(.system(size: 14, weight: .medium))
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundStyle(cancelled ? Theme.coral : .white.opacity(deadline == nil ? 0.95 : 0.6))
            .frame(width: 58, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.26), Color(white: 0.14)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(cancelled ? Theme.coral.opacity(0.9) : deadline == nil ? Theme.mint.opacity(0.9) : .white.opacity(0.2),
                                  lineWidth: 1.5)
            )
            .shadow(color: cancelled ? Theme.coral.opacity(0.5)
                        : Theme.mint.opacity(deadline == nil ? (pulse ? 0.7 : 0.25) : 0), radius: pulse ? 16 : 6)
            // 눌려 있는 동안은 살짝 내려가 있고, 떼면 올라온다
            .scaleEffect(deadline == nil ? (pulse ? 0.95 : 0.98) : 1)
            .offset(x: shake, y: deadline == nil && !cancelled ? 2 : 0)
        }
        .onChange(of: cancelled) { _, now in
            guard now else { return }
            // 취소: 좌우로 짧게 흔든다
            withAnimation(.spring(response: 0.12, dampingFraction: 0.25)) { shake = 9 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { shake = 0 }
            }
        }
        .frame(height: 130)
        .animation(Theme.spring, value: deadline)
        .animation(Theme.spring, value: cancelled)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
