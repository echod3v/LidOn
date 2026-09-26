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
    /// 화면에 보이지 않을 때는 false로 — 애니메이션을 완전히 멈춘다
    var animated = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: state == .idle || !animated)) { ctx in
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

// MARK: - 맥북 글리프

/// 살짝 위에서 내려다본 맥북. 뚜껑이 힌지를 축으로 접혀 키보드를 덮는다.
/// 좁은 베젤과 노치, 배경화면 화면, 키보드·트랙패드가 보이는 본체, 앞쪽 손가락 홈까지 그린다.
struct LaptopGlyph: View {
    enum Motion {
        /// 열림 → 닫힘 → 닫힌 채 잠깐 → 열림 반복
        case loop
        /// 열려 있다가 한 번 닫히고, 닫힌 채 빛을 내며 머문다 (Fn 안내)
        case closeOnce
    }

    var width: CGFloat = 120
    var motion: Motion = .loop
    /// false면 그 순간의 모습으로 멈춘다
    var animating = true

    /// 캡처용: 뚜껑을 열린 상태로 멈춘다 (`--debug-still`)
    nonisolated(unsafe) static var freeze = false

    @State private var start = Date()
    @State private var frozenAt: Date?

    var body: some View {
        Group {
            if Self.freeze {
                MacBookShape(width: width, lid: 0)
            } else if let f = frozenAt {
                frame(at: f)
            } else {
                // 시간에서 뚜껑 각도를 직접 계산한다 (보일 때만 돈다)
                TimelineView(.animation) { ctx in frame(at: ctx.date) }
            }
        }
        .onAppear {
            start = Date()
            frozenAt = animating ? nil : start
        }
        .onChange(of: animating) { _, on in
            if on { start = Date(); frozenAt = nil } else { frozenAt = Date() }
        }
    }

    private func frame(at date: Date) -> MacBookShape {
        let t = max(0, date.timeIntervalSince(start))
        switch motion {
        case .loop:
            return MacBookShape(width: width, lid: Self.loopLid(at: t))
        case .closeOnce:
            // 0.6초 열린 채 → 1.1초 동안 닫힘 → 닫힌 채 "실행 중" 빛이 숨 쉰다
            let lid = Self.ease(min(1, max(0, (t - 0.6) / 1.1)))
            let on = min(1, max(0, (t - 1.7) / 0.5))
            let glow = on * (0.8 + 0.2 * sin((t - 1.7) * 2 * .pi / 1.8))
            return MacBookShape(width: width, lid: lid, glow: glow)
        }
    }

    static func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }

    /// 5초 주기: 열림 유지 → 닫힘 → 닫힘 유지 → 열림
    static func loopLid(at t: TimeInterval) -> Double {
        let p = t.truncatingRemainder(dividingBy: 5)
        switch p {
        case ..<1.4: return 0
        case ..<2.5: return ease((p - 1.4) / 1.1)
        case ..<3.5: return 1
        default: return 1 - ease((p - 3.5) / 1.5)
        }
    }
}

struct MacBookShape: View {
    let width: CGFloat
    /// 0 = 열림, 1 = 닫힘 (뚜껑이 접힌 각도의 비율)
    let lid: Double
    /// 닫힌 뒤 아래에서 번지는 "실행 중" 빛 (0...1)
    var glow: Double = 0

    var body: some View {
        let w = width
        let lidW = w * 0.78
        let lidH = lidW * 0.645
        let deckH = w * 0.17
        let frontH = w * 0.03

        ZStack(alignment: .top) {
            // 실행 중 빛
            if glow > 0 {
                Ellipse()
                    .fill(RadialGradient(colors: [Theme.mint.opacity(0.75), Theme.teal.opacity(0.3), .clear],
                                         center: .center, startRadius: 0, endRadius: w * 0.55))
                    .frame(width: w * 1.1, height: w * 0.16)
                    .offset(y: lidH + deckH + frontH - w * 0.07)
                    .opacity(glow)
            }

            // 바닥 그림자
            Ellipse()
                .fill(RadialGradient(colors: [.black.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: w * 0.5))
                .frame(width: w * 1.1, height: w * 0.09)
                .offset(y: lidH + deckH + frontH - w * 0.035)

            // 본체 윗면 (키보드·트랙패드)
            MacBookDeck(topWidth: lidW, bottomWidth: w * 0.985)
                .frame(width: w, height: deckH)
                .offset(y: lidH)

            // 뚜껑: 열려 있을 때는 벡터로 선명하게, 움직일 때는 원근을 계산해 그린다
            if lid <= 0.0005 {
                MacBookScreen(width: lidW, height: lidH)
            } else {
                MacBookLid(width: w, lidW: lidW, lidH: lidH, deckH: deckH, fold: lid, texture: MacBookScreen.texture)
                    .frame(width: w * 1.1, height: lidH + deckH)
            }

            // 앞쪽 모서리 + 손가락 홈
            MacBookFront(height: frontH)
                .frame(width: w * 0.985, height: frontH)
                .offset(y: lidH + deckH)
        }
        .frame(width: w * 1.1, height: lidH + deckH + frontH + w * 0.05, alignment: .top)
    }
}

/// 원근을 넣어 접히는 뚜껑.
///
/// 카메라 좌표(아래가 +y, 멀어질수록 +z)에서 열린 뚜껑은 시선과 수직인 평면에 있고, 본체는 힌지에서 카메라 쪽으로 뻗는다.
/// 열린 모습이 `MacBookScreen` + `MacBookDeck`과 정확히 겹치도록 카메라 거리와 본체 각도를 거꾸로 구한다.
/// 뚜껑을 힌지 축으로 돌리면 윗변이 다가오며 넓어지고, 시선과 나란해지는 순간을 지나면 알루미늄 뒷면이 보인다.
private struct MacBookLid: View {
    let width: CGFloat
    let lidW: CGFloat
    let lidH: CGFloat
    let deckH: CGFloat
    let fold: Double
    let texture: Image?

    var body: some View {
        Canvas { ctx, size in
            let k = width * 0.985 / lidW                    // 본체 앞변 / 힌지 너비 = 가까워진 비율
            let yh = lidH * 0.6                             // 힌지의 높이 (시선 아래)
            let c = min(0.95, max(0, (deckH - (k - 1) * yh) / (k * lidH)))
            let s = (1 - c * c).squareRoot()
            let openAngle = acos(-c)                        // 뚜껑과 본체 사이 각도 (90°보다 조금 큼)
            let dist = s * lidH * k / (k - 1)              // 힌지까지의 거리
            let phi = openAngle * min(1, max(0, fold))
            let cx = size.width / 2

            // 뚜껑 위의 한 줄(v: 0 = 힌지, 1 = 윗변)이 화면에 놓이는 높이와 확대 비율
            func project(_ v: CGFloat) -> (y: CGFloat, scale: CGFloat) {
                let z = dist - v * lidH * sin(phi)
                let m = dist / z
                return ((yh - v * lidH * cos(phi)) * m - yh + lidH, m)
            }
            func band(_ a: (y: CGFloat, scale: CGFloat), _ b: (y: CGFloat, scale: CGFloat)) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: cx - lidW / 2 * a.scale, y: a.y))
                p.addLine(to: CGPoint(x: cx + lidW / 2 * a.scale, y: a.y))
                p.addLine(to: CGPoint(x: cx + lidW / 2 * b.scale, y: b.y))
                p.addLine(to: CGPoint(x: cx - lidW / 2 * b.scale, y: b.y))
                p.closeSubpath()
                return p
            }

            let hinge = project(0), top = project(1)
            let progress = phi / openAngle

            if top.y < hinge.y - 0.25 {
                // 화면 쪽: 가로띠로 나눠 각 띠를 제 원근에 맞게 그린다
                guard let texture else { return }
                let img = ctx.resolve(texture)
                let n = 32
                var prev = hinge
                for i in 1...n {
                    let cur = project(CGFloat(i) / CGFloat(n))
                    let v0 = CGFloat(i - 1) / CGFloat(n), v1 = CGFloat(i) / CGFloat(n)
                    let perV = (prev.y - cur.y) / (v1 - v0)
                    let wMid = lidW * (prev.scale + cur.scale) / 2
                    var layer = ctx
                    // 띠 사이에 틈이 보이지 않게 살짝 겹친다
                    layer.clip(to: band((prev.y + 0.4, prev.scale), (cur.y - 0.4, cur.scale)))
                    layer.draw(img, in: CGRect(x: cx - wMid / 2, y: cur.y - (1 - v1) * perV, width: wMid, height: perV))
                    prev = cur
                }
                // 누울수록 화면이 어두워진다
                ctx.fill(band(hinge, top), with: .color(.black.opacity(0.55 * progress)))
            } else if top.y > hinge.y + 0.25 {
                // 뒷면: 알루미늄이 힌지에서부터 본체를 덮어 내려온다
                let shape = band(hinge, top)
                let light = 0.6 + 0.28 * progress
                ctx.fill(shape, with: .linearGradient(
                    Gradient(colors: [Color(white: light - 0.12), Color(white: light), Color(white: min(0.93, light + 0.05))]),
                    startPoint: CGPoint(x: 0, y: hinge.y), endPoint: CGPoint(x: 0, y: top.y)))
                // 뚜껑 앞 모서리 (두께)
                let edgeH = min(top.y - hinge.y, width * 0.008)
                ctx.fill(band((top.y - edgeH, top.scale), top),
                         with: .color(Color(white: 0.5 + 0.2 * progress)))
                var edge = Path()
                edge.move(to: CGPoint(x: cx - lidW / 2 * top.scale, y: top.y))
                edge.addLine(to: CGPoint(x: cx + lidW / 2 * top.scale, y: top.y))
                ctx.stroke(edge, with: .color(Color(white: 0.45)), lineWidth: 0.8)
            } else {
                // 시선과 나란한 순간: 얇은 선
                var edge = Path()
                edge.move(to: CGPoint(x: cx - lidW / 2 * hinge.scale, y: hinge.y))
                edge.addLine(to: CGPoint(x: cx + lidW / 2 * hinge.scale, y: hinge.y))
                ctx.stroke(edge, with: .color(Color(white: 0.55)), lineWidth: 1.2)
            }
        }
    }
}

private struct MacBookScreen: View {
    let width: CGFloat
    let height: CGFloat

    /// 접히는 뚜껑에 입힐 화면 그림 (한 번만 그려 둔다)
    @MainActor static let texture: Image? = {
        let r = ImageRenderer(content: MacBookScreen(width: 600, height: 600 * 0.645))
        r.scale = 2
        return r.cgImage.map { Image(decorative: $0, scale: 2) }
    }()

    var body: some View {
        let w = width
        let outer = UnevenRoundedRectangle(topLeadingRadius: w * 0.045, bottomLeadingRadius: w * 0.012,
                                           bottomTrailingRadius: w * 0.012, topTrailingRadius: w * 0.045, style: .continuous)
        ZStack(alignment: .top) {
            outer.fill(Color(white: 0.04))
            outer.strokeBorder(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.4)], startPoint: .top, endPoint: .bottom),
                               lineWidth: max(0.75, w * 0.006))
            // 화면: LidOn 바탕화면 (코드로 그린 그림)
            MacBookWallpaper()
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: w * 0.028, topTrailingRadius: w * 0.028, style: .continuous))
            .padding(.horizontal, w * 0.022)
            .padding(.top, w * 0.022)
            .padding(.bottom, w * 0.05)
            // 노치
            UnevenRoundedRectangle(bottomLeadingRadius: w * 0.014, bottomTrailingRadius: w * 0.014, style: .continuous)
                .fill(Color(white: 0.04))
                .frame(width: w * 0.14, height: w * 0.042)
                .padding(.top, w * 0.004)
        }
        .frame(width: width, height: height)
    }
}

/// LidOn 바탕화면: 어두운 바탕 위로 빛의 호가 흐른다 (코드로 그린 원본 그림, 외부 이미지 없음).
/// 굵기와 밝기가 다른 선을 겹쳐 흐림 필터 없이도 빛이 번지는 느낌을 낸다.
struct MacBookWallpaper: View {
    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.09), Color(red: 0.06, green: 0.04, blue: 0.16)],
                               startPoint: .top, endPoint: .bottom)
                // 뒤쪽 은은한 빛
                RadialGradient(colors: [Theme.indigo.opacity(0.55), .clear], center: UnitPoint(x: 0.25, y: 0.9),
                               startRadius: 0, endRadius: W * 0.7)
                RadialGradient(colors: [Theme.teal.opacity(0.45), .clear], center: UnitPoint(x: 0.9, y: 0.35),
                               startRadius: 0, endRadius: W * 0.55)
                // 큰 빛의 호
                glowArc(W: W, H: H, size: CGSize(width: W * 1.7, height: H * 1.9), offset: CGPoint(x: W * 0.42, y: H * 0.78),
                        colors: [Theme.indigo, Color(red: 0.75, green: 0.35, blue: 1.0), Theme.mint, Theme.teal.opacity(0)],
                        width: H * 0.2, rotation: -12)
                // 작은 빛의 호
                glowArc(W: W, H: H, size: CGSize(width: W * 1.2, height: H * 1.3), offset: CGPoint(x: -W * 0.45, y: H * 0.72),
                        colors: [Theme.teal.opacity(0), Theme.mint, Color(red: 0.35, green: 0.75, blue: 1.0), Theme.indigo],
                        width: H * 0.12, rotation: 18)
                // 위쪽 옅은 안개
                LinearGradient(colors: [.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center)
            }
            .frame(width: W, height: H)
            .clipped()
        }
    }

    /// 굵은 선 → 가는 선으로 겹쳐 가운데가 가장 밝은 빛의 띠를 만든다
    private func glowArc(W: CGFloat, H: CGFloat, size: CGSize, offset: CGPoint, colors: [Color], width: CGFloat,
                         rotation: Double) -> some View {
        let gradient = AngularGradient(colors: colors + [colors[0]], center: .center)
        return ZStack {
            // 바깥에서 안으로: 넓고 옅은 선부터 좁고 밝은 선까지 (계단이 보이지 않게 촘촘히)
            ForEach(Array([2.6, 2.1, 1.7, 1.35, 1.05, 0.8, 0.55, 0.35].enumerated()), id: \.offset) { i, k in
                Ellipse().stroke(gradient, lineWidth: width * k).opacity(0.1 + Double(i) * 0.1)
            }
            Ellipse().stroke(.white.opacity(0.55), lineWidth: max(0.5, width * 0.08))
        }
        .frame(width: size.width, height: size.height)
        .rotationEffect(.degrees(rotation))
        .offset(x: offset.x, y: offset.y)
    }
}

/// 본체 윗면을 위에서 비스듬히 본 사다리꼴. 키보드와 트랙패드를 원근에 맞춰 그린다.
private struct MacBookDeck: View {
    let topWidth: CGFloat
    let bottomWidth: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let W = size.width, H = size.height
            func x(_ y: CGFloat, _ t: CGFloat) -> CGFloat {
                let row = topWidth + (bottomWidth - topWidth) * (y / H)
                return (W - row) / 2 + row * t
            }
            func quad(_ y0: CGFloat, _ y1: CGFloat, _ t0: CGFloat, _ t1: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: x(y0, t0), y: y0))
                p.addLine(to: CGPoint(x: x(y0, t1), y: y0))
                p.addLine(to: CGPoint(x: x(y1, t1), y: y1))
                p.addLine(to: CGPoint(x: x(y1, t0), y: y1))
                p.closeSubpath()
                return p
            }
            // 알루미늄 윗면
            ctx.fill(quad(0, H, 0, 1), with: .linearGradient(
                Gradient(colors: [Color(white: 0.74), Color(white: 0.88)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
            // 키보드
            let ky0 = H * 0.08, ky1 = H * 0.58
            ctx.fill(quad(ky0, ky1, 0.075, 0.925), with: .color(Color(white: 0.30)))
            let rows = 6
            let widths: [[CGFloat]] = [
                Array(repeating: 1, count: 14),
                Array(repeating: 1, count: 14),
                [1.5] + Array(repeating: 1, count: 12) + [1.5],
                [1.8] + Array(repeating: 1, count: 11) + [2.2],
                [2.3] + Array(repeating: 1, count: 10) + [2.7],
                [1, 1, 1, 1.3, 5.2, 1.3, 1, 1, 1],
            ]
            let rowH = (ky1 - ky0) / CGFloat(rows)
            for r in 0..<rows {
                let y0 = ky0 + CGFloat(r) * rowH + rowH * 0.14
                let y1 = y0 + rowH * (r == 0 ? 0.5 : 0.72)
                let total = widths[r].reduce(0, +)
                var t = 0.085 as CGFloat
                let span = 0.83 as CGFloat
                for kw in widths[r] {
                    let t0 = t + span * 0.006, t1 = t + span * kw / total - span * 0.006
                    ctx.fill(quad(y0, y1, t0, t1), with: .color(Color(white: 0.09)))
                    t += span * kw / total
                }
            }
            // 트랙패드
            let pad = quad(H * 0.64, H * 0.94, 0.33, 0.67)
            ctx.fill(pad, with: .color(Color(white: 0.83)))
            ctx.stroke(pad, with: .color(Color(white: 0.68)), lineWidth: 0.6)
            // 앞 모서리 반사광
            var edge = Path()
            edge.move(to: CGPoint(x: x(H, 0), y: H - 0.5))
            edge.addLine(to: CGPoint(x: x(H, 1), y: H - 0.5))
            ctx.stroke(edge, with: .color(.white.opacity(0.9)), lineWidth: 1)
        }
    }
}

private struct MacBookFront: View {
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: height * 0.9, bottomTrailingRadius: height * 0.9, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.78), Color(white: 0.52)], startPoint: .top, endPoint: .bottom))
            // 손가락 홈
            UnevenRoundedRectangle(bottomLeadingRadius: height * 0.5, bottomTrailingRadius: height * 0.5, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.66)], startPoint: .top, endPoint: .bottom))
                .frame(width: height * 5, height: height * 0.55)
        }
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
