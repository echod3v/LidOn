import AppKit
import SwiftUI

// MARK: - 색과 그라데이션

/// LidOn 디자인 시스템. 모든 화면이 같은 색·같은 "빛" 모티프를 쓴다.
enum Theme {
    static let mint = Color(red: 0.36, green: 0.93, blue: 0.78)
    static let teal = Color(red: 0.08, green: 0.62, blue: 0.70)
    static let indigo = Color(red: 0.40, green: 0.42, blue: 0.98)
    static let amber = Color(red: 1.00, green: 0.70, blue: 0.25)
    static let coral = Color(red: 1.00, green: 0.42, blue: 0.40)

    static let accent = LinearGradient(colors: [mint, teal], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func colors(_ state: OrbState) -> [Color] {
        switch state {
        case .idle: return [Color(white: 0.62), Color(white: 0.40)]
        case .armed: return [mint, teal]
        case .sealed: return [indigo, mint]
        }
    }

    static func glow(_ state: OrbState) -> Color {
        switch state {
        case .idle: return .clear
        case .armed: return mint
        case .sealed: return indigo
        }
    }

    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.82)
}

enum OrbState: Equatable {
    case idle, armed, sealed

    init(_ key: String) {
        switch key {
        case "sealed": self = .sealed
        case "armed": self = .armed
        default: self = .idle
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "moon.zzz.fill"
        case .armed: return "bolt.fill"
        case .sealed: return "lock.fill"
        }
    }
}

// MARK: - 상태 구슬

/// 상태를 보여 주는 빛나는 구슬. 대기 = 정지, 준비 = 숨쉬는 민트, 실행 중 = 퍼지는 물결.
/// 애니메이션은 화면에 보일 때만 돈다 (TimelineView).
struct StatusOrb: View {
    var state: OrbState
    var size: CGFloat = 44
    var symbol: String?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: state == .idle)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let colors = Theme.colors(state)
            ZStack {
                // 퍼지는 물결
                if state != .idle {
                    let reach = size < 80 ? 0.32 : 0.75
                    ForEach(0..<3, id: \.self) { i in
                        let phase = ((t / (state == .sealed ? 2.2 : 3.2)) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(colors[0].opacity(0.55 * (1 - phase)), lineWidth: max(1, size * 0.025))
                            .scaleEffect(1 + phase * reach)
                    }
                }
                // 회전하는 테두리 빛
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: [colors[0], colors[1].opacity(0.2), colors[0].opacity(0.9), colors[1], colors[0]],
                                        center: .center, angle: .degrees(state == .idle ? 0 : t * 50)),
                        lineWidth: max(1.5, size * 0.055))
                    .opacity(state == .idle ? 0.35 : 1)
                // 숨쉬는 코어
                let breathe = state == .idle ? 1 : 1 + 0.04 * sin(t * 2.2)
                Circle()
                    .fill(RadialGradient(colors: [colors[0].opacity(0.95), colors[1]], center: .topLeading,
                                         startRadius: 0, endRadius: size * 0.8))
                    .padding(size * 0.13)
                    .scaleEffect(breathe)
                    .shadow(color: Theme.glow(state).opacity(0.7), radius: size * 0.22)
                Image(systemName: symbol ?? state.symbol)
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .animation(Theme.spring, value: state)
    }
}

// MARK: - 노트북 글리프

/// 뚜껑이 3D로 닫혔다 열리는 노트북. "뚜껑을 닫아도 된다"를 동작으로 보여 준다.
struct LaptopGlyph: View {
    var width: CGFloat = 120
    var animating = true
    var tint: Color = Theme.mint

    var body: some View {
        PhaseAnimator(animating ? [0.0, 1.0, 1.0, 0.0] : [0.0]) { lid in
            laptop(lid: lid)
        } animation: { lid in
            lid == 1 ? .easeInOut(duration: 1.0) : .spring(response: 0.9, dampingFraction: 0.8)
        }
        .frame(width: width, height: width * 0.72)
    }

    private func laptop(lid: Double) -> some View {
        let w = width
        return VStack(spacing: 0) {
            // 화면 (아래쪽 모서리를 축으로 접힌다)
            RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: max(1.5, w * 0.022))
                )
                .overlay(
                    // 화면 속 "켜짐" 빛
                    Capsule()
                        .fill(tint)
                        .frame(width: w * 0.22, height: w * 0.035)
                        .shadow(color: tint, radius: w * 0.06)
                        .opacity(1 - lid * 0.4)
                )
                .frame(width: w * 0.78, height: w * 0.5)
                .brightness(-0.25 * lid)
                .scaleEffect(x: 1 - 0.04 * lid, y: 1 - 0.9 * lid, anchor: .bottom)
            // 본체
            UnevenRoundedRectangle(bottomLeadingRadius: w * 0.04, bottomTrailingRadius: w * 0.04, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: w * 0.055)
                .overlay(alignment: .top) {
                    Capsule().fill(.black.opacity(0.25)).frame(width: w * 0.16, height: w * 0.018)
                }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

// MARK: - 카드, 타일, 배지

/// 은은한 유리 카드
struct Card<Content: View>: View {
    var highlighted = false
    var tint: [Color] = [Theme.mint, Theme.teal]
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(highlighted
                          ? AnyShapeStyle(LinearGradient(colors: tint.map { $0.opacity(0.22) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(.quaternary.opacity(0.55)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(highlighted
                                  ? AnyShapeStyle(LinearGradient(colors: tint.map { $0.opacity(0.7) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(.white.opacity(0.08)),
                                  lineWidth: 1)
            }
            .animation(Theme.spring, value: highlighted)
    }
}

/// 작은 상태 타일 (아이콘 + 값 + 이름)
struct StatTile: View {
    var icon: String
    var value: String
    var title: String
    var color: Color = .secondary
    var fraction: Double? = nil

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let f = fraction {
                    Circle().stroke(.quaternary, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(1, f)))
                        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(Theme.spring, value: f)
                }
                Image(systemName: icon)
                    .font(.system(size: fraction == nil ? 15 : 11, weight: .semibold))
                    .foregroundStyle(color)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 28, height: 28)
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.45)))
        .animation(Theme.spring, value: value)
    }
}

/// 시스템 설정 스타일의 색깔 아이콘 배지
struct IconBadge: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.55, weight: .semibold)).foregroundStyle(.white))
    }
}

/// 설정 행 이름: 배지 + 텍스트
struct SettingLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color

    init(_ title: LocalizedStringKey, symbol: String, color: Color) {
        self.title = title
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: symbol, color: color)
            Text(title)
        }
    }
}

/// 둥근 알약 모양 표시 (예: 실행 시간)
struct Pill<Content: View>: View {
    var color: Color = Theme.mint
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1))
            .foregroundStyle(color)
    }
}

/// 창 뒤를 흐리게 보여 주는 배경 (전체 화면 오버레이용)
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.material = .fullScreenUI
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// 그라데이션 글자
extension View {
    func accentGradientText() -> some View {
        overlay(Theme.accent).mask(self)
    }
}
