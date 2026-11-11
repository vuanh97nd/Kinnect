import SwiftUI
import UIKit

/// Native Material 3 Bottom Navigation Bar matching Android 1.2.12 MainActivity (lines 473-515)
/// Height: 68pt, background: CARD, top 1px border.
/// 5 items:
/// - Bảng tin (house)
/// - Khám phá (compass)
/// - Tạo (Center Material 3 squircle FAB 46x40pt, gradient #7B43F7 -> #ED45AA, corner radius 16pt, white +)
/// - Video (play/clapperboard, label always visible below icon)
/// - Live (radio)
/// Active tabs feature the Google Pixel M3 pill highlight shape (64x32pt, PRIMARY_SOFT) behind the icon.
struct KinnectBottomBar: View {
    @Binding var selectedTab: KinnectNavTab
    var onCreateTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Tab 1: Bảng tin
            tabButton(
                tab: .feed,
                title: "Bảng tin",
                glyph: .feed,
                systemImage: "house.fill"
            )

            // Tab 2: Khám phá
            tabButton(
                tab: .discover,
                title: "Khám phá",
                glyph: .discover,
                systemImage: "magnifyingglass"
            )

            // Tab 3: Center FAB "Tạo" (Google Material 3 squircle FAB matching Android line 481-491)
            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                onCreateTap()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
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
                        .frame(width: 46, height: 40)
                        .shadow(color: Color(red: 0x7B / 255.0, green: 0x43 / 255.0, blue: 0xF7 / 255.0).opacity(0.35), radius: 4, y: 2)

                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tạo nội dung")

            // Tab 4: Video (Explicit "Video" label below icon)
            tabButton(
                tab: .video,
                title: "Video",
                glyph: .video,
                systemImage: "play.rectangle.fill"
            )

            // Tab 5: Live
            tabButton(
                tab: .live,
                title: "Live",
                glyph: .live,
                systemImage: "dot.radiowaves.left.and.right"
            )
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .frame(height: 64)
        .background(KinnectTheme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(
            Divider().background(KinnectTheme.borderSoft),
            alignment: .top
        )
    }

    private func tabButton(
        tab: KinnectNavTab,
        title: String,
        glyph: KinnectGlyph,
        systemImage: String
    ) -> some View {
        let isSelected = (selectedTab == tab)
        return Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            selectedTab = tab
        } label: {
            VStack(spacing: 2) {
                // Google Pixel Material 3 Pill highlight shape (64x32pt, PRIMARY_SOFT)
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(KinnectTheme.accentSoft)
                            .frame(width: 60, height: 30)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .frame(width: 60, height: 30)
                    }

                    KinnectIcon(
                        glyph: glyph,
                        size: 22,
                        selected: isSelected,
                        tint: isSelected ? KinnectTheme.accentBright : KinnectTheme.textSecondary
                    )
                }
                .frame(width: 60, height: 30)

                // Label 12sp matching Android line 501
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

