import AppKit
import SwiftUI

/// 앱 아이콘 그림 — 앱 안의 맥북과 같은 뷰로 그린다 (`LidOn --render-icon <png>`, scripts/make-icon.sh)
struct IconArtwork: View {
    var body: some View {
        ZStack {
            // macOS 아이콘 그리드: 1024 캔버스 안의 824pt 둥근 사각형
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.09, green: 0.17, blue: 0.27), Color(red: 0.04, green: 0.06, blue: 0.13)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(RadialGradient(colors: [Theme.teal.opacity(0.55), Theme.indigo.opacity(0.18), .clear],
                                             center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 430))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 2)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            MacBookShape(width: 600, lid: 0)
                .offset(y: 40)
        }
        .frame(width: 1024, height: 1024)
    }

    @MainActor
    static func render(to path: String) -> Bool {
        let renderer = ImageRenderer(content: IconArtwork())
        renderer.scale = 1
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
