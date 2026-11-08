import SwiftUI

/// Vector-faithful Kinnect Brand Logo matching Android's kinnect_logo.xml
/// 192x192 viewport with squircle gradient and white 'K' vector strokes.
struct KinnectBrandLogo: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            // Squircle gradient background (#7B43F7 -> #ED45AA)
            RoundedRectangle(cornerRadius: size * (42.0 / 192.0), style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0x7B / 255.0, green: 0x43 / 255.0, blue: 0xF7 / 255.0),
                            Color(red: 0xED / 255.0, green: 0x45 / 255.0, blue: 0xAA / 255.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)

            // Letter K stroke matching M60,48 L60,144 M60,102 L132,54 M60,102 L138,141
            KinnectKVectorShape()
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: size * (24.0 / 192.0),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Kinnect Logo")
    }
}

private struct KinnectKVectorShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = rect.width / 192.0
        // Vertical stem: M60,48 L60,144
        path.move(to: CGPoint(x: 60.0 * scale, y: 48.0 * scale))
        path.addLine(to: CGPoint(x: 60.0 * scale, y: 144.0 * scale))
        // Upper diagonal: M60,102 L132,54
        path.move(to: CGPoint(x: 60.0 * scale, y: 102.0 * scale))
        path.addLine(to: CGPoint(x: 132.0 * scale, y: 54.0 * scale))
        // Lower diagonal: M60,102 L138,141
        path.move(to: CGPoint(x: 60.0 * scale, y: 102.0 * scale))
        path.addLine(to: CGPoint(x: 138.0 * scale, y: 141.0 * scale))
        return path
    }
}
