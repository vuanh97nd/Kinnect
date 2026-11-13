import SwiftUI

/// Startup Splash Screen matching Android 1.2.12 MainActivity.splash() (lines 134-152)
/// Centered 96dp Logo K, Kinnect title, and animated interlocking dual rings.
struct KinnectSplashScreen: View {
    @State private var ringOffset: CGFloat = 16
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            KinnectTheme.background.ignoresSafeArea()

            VStack(spacing: 18) {
                // Centered 96x96 Logo K with elevation shadow
                KinnectBrandLogo(size: 96)
                    .shadow(color: KinnectTheme.accent.opacity(0.35), radius: 16, y: 8)
                    .scaleEffect(pulse)

                // App Brand Title
                Text("Kinnect")
                    .font(KinnectTheme.scaled(28, weight: .bold))
                    .foregroundColor(KinnectTheme.accentBright)

                // Animated dual rings (matching Android rings: ACCENT & PINK translation)
                ZStack {
                    Circle()
                        .stroke(KinnectTheme.accentBright, lineWidth: 2.5)
                        .frame(width: 20, height: 20)
                        .offset(x: -ringOffset)

                    Circle()
                        .stroke(Color(red: 0xED / 255.0, green: 0x45 / 255.0, blue: 0xAA / 255.0), lineWidth: 2.5)
                        .frame(width: 20, height: 20)
                        .offset(x: ringOffset)
                }
                .frame(height: 42)
                .padding(.top, 10)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                ringOffset = 5
                pulse = 1.05
            }
        }
    }
}

