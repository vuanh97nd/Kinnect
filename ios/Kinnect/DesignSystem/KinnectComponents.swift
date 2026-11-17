// KinnectComponents.swift
// Thư viện component dùng chung. Mọi giá trị lấy từ KinnectTokens.swift (sinh từ design/tokens.json).
// Quy ước: KHÔNG hardcode màu/font/khoảng cách trong file view — dùng component ở đây.

import SwiftUI

// MARK: - Button

enum KButtonKind {
    case primary, secondary, ghost, danger
}

struct KButton: View {
    let title: String
    var kind: KButtonKind = .primary
    var fullWidth: Bool = false
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: KTSpace.sm) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(foreground)
                }
                Text(title)
                    .font(KTType.body)
                    .fontWeight(.semibold)
            }
            .foregroundColor(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: KTLayout.touchTargetMin)
            .padding(.horizontal, KTSpace.lg)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: KTRadius.sm)
                    .strokeBorder(borderColor, lineWidth: kind == .secondary ? 1 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: KTRadius.sm))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: KTRadius.sm))
        }
        .buttonStyle(.plain)
        .animation(KTMotion.animation(KTMotion.fast, reduceMotion: reduceMotion), value: isEnabled)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return KTColor.onAccent
        case .secondary: return KTColor.textPrimary
        case .ghost: return KTColor.accent
        case .danger: return KTColor.onAccent
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return KTColor.accent
        case .secondary: return .clear
        case .ghost: return .clear
        case .danger: return KTColor.danger
        }
    }

    private var borderColor: Color {
        kind == .secondary ? KTColor.border : .clear
    }
}

// MARK: - Card

struct KCard<Content: View>: View {
    var padding: CGFloat = KTSpace.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KTColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: KTRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: KTRadius.md)
                    .strokeBorder(KTColor.border, lineWidth: 1)
            )
    }
}

// MARK: - Setting row

struct KRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var trailing: String? = nil
    var showsChevron: Bool = true
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }

    private var content: some View {
        HStack(spacing: KTSpace.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(KTColor.accent)
                    .frame(width: 36, height: 36)
                    .background(KTColor.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: KTRadius.sm))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(KTType.body).foregroundColor(KTColor.textPrimary)
                if let subtitle {
                    Text(subtitle).font(KTType.meta).foregroundColor(KTColor.textTertiary)
                }
            }
            Spacer(minLength: KTSpace.sm)
            if let trailing {
                Text(trailing).font(KTType.meta).foregroundColor(KTColor.textTertiary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(KTColor.textTertiary)
            }
        }
        .frame(minHeight: KTLayout.touchTargetMin)
        .contentShape(Rectangle())
    }
}

// MARK: - Input

struct KInput: View {
    let placeholder: String
    @Binding var text: String
    var error: String? = nil
    var isSecure: Bool = false

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KTSpace.xs) {
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(KTType.body)
            .foregroundColor(KTColor.textPrimary)
            .focused($focused)
            .padding(.horizontal, KTSpace.md)
            .frame(minHeight: KTLayout.touchTargetMin)
            .background(KTColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: KTRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: KTRadius.sm)
                    .strokeBorder(error == nil ? KTColor.border : KTColor.danger, lineWidth: focused || error != nil ? 1.5 : 1)
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            if let error {
                Text(error)
                    .font(KTType.meta)
                    .foregroundColor(KTColor.danger)
                    .accessibilityLabel("Lỗi: \(error)")
            }
        }
    }
}

// MARK: - Empty state

struct KEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: KTSpace.md) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(KTColor.accent)
                .frame(width: 56, height: 56)
                .background(KTColor.accentSoft)
                .clipShape(Circle())
            Text(title)
                .font(KTType.body)
                .fontWeight(.semibold)
                .foregroundColor(KTColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(KTType.meta)
                .foregroundColor(KTColor.textTertiary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                KButton(title: actionTitle, kind: .primary, action: action)
                    .padding(.top, KTSpace.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KTSpace.xxl)
        .padding(.horizontal, KTSpace.lg)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Skeleton

struct KSkeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(KTColor.surfaceElevated)
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, KTColor.border.opacity(0.6), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: phase * geo.size.width * 1.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: height / 2))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Top bar
// Thanh tiêu đề dùng chung. Mọi số lấy từ KTLayout để iPhone và Android
// (UiMetrics.java) không trôi khỏi nhau. Tỷ lệ icon:gap:lề = 20:12:16.

struct KTopBar<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var leadingSystemImage: String? = nil
    var leadingLabel: String = "Quay lại"
    var onLeadingTap: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: KTLayout.headerIconGap) {
            if let leadingSystemImage, let onLeadingTap {
                KTopBarIcon(systemName: leadingSystemImage, label: leadingLabel, action: onLeadingTap)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(KTType.titleS)
                    .foregroundColor(KTColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle {
                    Text(subtitle)
                        .font(KTType.meta)
                        .foregroundColor(KTColor.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.horizontal, KTLayout.headerSidePadding)
        .frame(height: KTLayout.headerHeight)
    }
}

/// Icon 20pt nhìn, 44pt vùng chạm. Không dùng cỡ khác cho thanh tiêu đề.
struct KTopBarIcon: View {
    let systemName: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: KTLayout.headerIconSize, weight: .semibold))
                .foregroundColor(KTColor.textPrimary)
                .frame(width: KTLayout.touchTargetMin, height: KTLayout.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Segmented control
// Bản branded thay cho Picker(.segmented) của hệ thống: iOS vẽ tab đang chọn bằng
// xám nên trông như bị vô hiệu, và trái hẳn ngôn ngữ "chip tím" của phần còn lại.

struct KSegmented<T: Hashable>: View {
    let options: [T]
    let title: (T) -> String
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(KTType.label)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(isSelected ? KTColor.accent : KTColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(isSelected ? KTColor.accentSoft : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: KTRadius.xs))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(KTColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: KTRadius.sm))
    }
}

// MARK: - Section header

struct KSectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(KTType.label)
                .foregroundColor(KTColor.textTertiary)
                .textCase(.uppercase)
            Spacer()
            if let trailing {
                Text(trailing).font(KTType.label).foregroundColor(KTColor.accent)
            }
        }
        .padding(.top, KTSpace.xl)
        .padding(.bottom, KTSpace.sm)
        .accessibilityAddTraits(.isHeader)
    }
}
