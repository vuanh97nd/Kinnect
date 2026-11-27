import SwiftUI

/// Startup Splash Screen matching Android 1.2.12 MainActivity.splash() (lines 134-152)
/// Centered 96dp Logo K, Kinnect title, and animated interlocking dual rings.
struct KinnectSplashScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var ringOffset: CGFloat = 6
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            KinnectTheme.background.ignoresSafeArea()

            VStack(spacing: 18) {
                // Centered 96x96 Logo K with elevation shadow and concentric rings
                KinnectBrandLogo(size: 96)
                    .shadow(color: KinnectTheme.accent.opacity(0.35), radius: 16, y: 8)
                    .background {
                        ZStack {
                            Circle()
                                .stroke(
                                    KinnectTheme.accentBright.opacity(colorScheme == .dark ? 0.24 : 0.16),
                                    lineWidth: 1.5
                                )
                                .frame(width: 132, height: 132)

                            Circle()
                                .stroke(
                                    KinnectTheme.rose.opacity(colorScheme == .dark ? 0.18 : 0.11),
                                    lineWidth: 1.25
                                )
                                .frame(width: 168, height: 168)

                            Circle()
                                .stroke(
                                    KinnectTheme.accentBright.opacity(colorScheme == .dark ? 0.11 : 0.07),
                                    lineWidth: 1
                                )
                                .frame(width: 204, height: 204)
                        }
                        .accessibilityHidden(true)
                    }
                    .scaleEffect(pulse)

                // App Brand Title
                Text("Kinnect")
                    .font(.system(size: 28, weight: .bold))
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
            guard !reduceMotion else {
                ringOffset = 6
                pulse = 1.0
                return
            }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                ringOffset = 4
                pulse = 1.05
            }
        }
    }
}

