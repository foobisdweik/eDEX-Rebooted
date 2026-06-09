import EdexRenderingSupport
import SwiftUI

struct EdexTerminalAesthetic: View {
    let theme: NativeTheme
    let vh: Double

    var body: some View {
        GeometryReader { proxy in
            let metrics = TerminalAestheticMetrics(surfaceHeight: Double(proxy.size.height), vh: vh)
            ZStack {
                // Scanlines
                Canvas { ctx, size in
                    guard size.width.isFinite, size.width > 0,
                          size.height.isFinite, size.height > 0 else { return }
                    let count = metrics.scanlineCount(forHeight: Double(size.height))
                    guard count > 0 else { return }
                    var path = Path()
                    for i in 0..<count {
                        let y = Double(i) * metrics.scanlineSpacing
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    ctx.stroke(path,
                               with: .color(.black.opacity(metrics.scanlineOpacity)),
                               lineWidth: metrics.scanlineThickness)
                }
                // Accent edge glow (legacy `0 0 0.6vh rgba(accent,0.6)`)
                Rectangle()
                    .strokeBorder(theme.accent.opacity(metrics.glowOpacity), lineWidth: 1)
                    .blur(radius: metrics.glowRadius)
            }
        }
        .allowsHitTesting(false)
    }
}
