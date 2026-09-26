import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// 홍보용 이미지: 데모 GIF와 소셜 미리보기 (`LidOn --render-media <폴더>`).
/// 앱 안의 맥북 뷰를 그대로 렌더링한다.
enum PromoMedia {
    @MainActor
    static func render(to dir: String) -> Bool {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return renderDemoGIF(to: url.appendingPathComponent("demo.gif"))
            && renderPNG(SocialCard(), to: url.appendingPathComponent("social-preview.png"))
    }

    /// 4.8초 반복: 열림 → 닫힘(빛이 계속 남아 있음 = 실행 중) → 열림
    @MainActor
    private static func renderDemoGIF(to url: URL) -> Bool {
        let fps = 15.0, seconds = 4.8
        let frames = Int(fps * seconds)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil) else { return false }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for i in 0..<frames {
            let t = Double(i) / fps
            let renderer = ImageRenderer(content: DemoFrame(t: t))
            renderer.scale = 1
            guard let cg = renderer.cgImage else { return false }
            CGImageDestinationAddImage(dest, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary)
        }
        return CGImageDestinationFinalize(dest)
    }

    @MainActor
    private static func renderPNG<V: View>(_ view: V, to url: URL) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}

/// 데모 GIF 한 장면
private struct DemoFrame: View {
    let t: Double

    /// 뚜껑: 0.8초 열림 → 1.0초 닫힘 → 2.0초 닫힌 채 실행 → 1.0초 열림
    private var lid: Double {
        func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
        switch t {
        case ..<0.8: return 0
        case ..<1.8: return ease((t - 0.8) / 1.0)
        case ..<3.8: return 1
        default: return 1 - ease(min(1, (t - 3.8) / 1.0))
        }
    }

    /// 닫힌 동안 아래에서 번지는 "실행 중" 빛
    private var glow: Double {
        guard t >= 1.8, t < 3.8 else { return 0 }
        return min(1, (t - 1.8) / 0.4, (3.8 - t) / 0.3) * (0.85 + 0.15 * sin((t - 1.8) * 2 * .pi / 1.6))
    }

    private var caption: (String, String) {
        switch t {
        case ..<1.8: return ("Close the lid.", "Hold Fn — or let your AI agent ask for it")
        case ..<3.8: return ("Still running.", "Builds, tests and agents keep going")
        default: return ("Open it. Nothing stopped.", "Normal sleep is back automatically")
        }
    }

    var body: some View {
        let running = t >= 1.8 && t < 3.8
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.16), Color(red: 0.03, green: 0.04, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.teal.opacity(running ? 0.55 : 0.3), .clear], center: UnitPoint(x: 0.5, y: 0.52),
                           startRadius: 0, endRadius: 330)
            VStack(spacing: 22) {
                MacBookShape(width: 380, lid: lid, glow: glow)
                VStack(spacing: 6) {
                    Text(caption.0).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(caption.1).font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                }
            }
            .offset(y: 8)
            // 실행 중 표시
            HStack(spacing: 8) {
                Circle().fill(running ? Theme.mint : Color(white: 0.45)).frame(width: 9, height: 9)
                    .shadow(color: running ? Theme.mint : .clear, radius: 6)
                Text(verbatim: running ? "LidOn · running with the lid closed" : "LidOn")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.08)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
        }
        .frame(width: 720, height: 460)
    }
}

/// GitHub·SNS 링크 미리보기 (1280×640)
private struct SocialCard: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.10, blue: 0.18), Color(red: 0.03, green: 0.04, blue: 0.09)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Theme.teal.opacity(0.45), .clear], center: UnitPoint(x: 0.72, y: 0.5),
                           startRadius: 0, endRadius: 520)
            HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 22) {
                    Text(verbatim: "LidOn")
                        .font(.system(size: 92, weight: .heavy, design: .rounded))
                        .accentGradientText()
                    Text(verbatim: "Close the lid.\nKeep working.")
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(verbatim: "Free macOS menu bar app that keeps your MacBook — and your AI coding agents — running with the lid closed.")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 520, alignment: .leading)
                    HStack(spacing: 10) {
                        ForEach(["Free & open source", "No sudo", "MCP for agents"], id: \.self) { tag in
                            Text(verbatim: tag)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.mint)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Capsule().fill(Theme.mint.opacity(0.12)))
                                .overlay(Capsule().strokeBorder(Theme.mint.opacity(0.4), lineWidth: 1))
                        }
                    }
                }
                MacBookShape(width: 520, lid: 0)
            }
            .padding(.horizontal, 70)
        }
        .frame(width: 1280, height: 640)
    }
}
