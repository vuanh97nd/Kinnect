import SwiftUI

struct KinnectActionSheetItem: Identifiable {
    let id: String
    let title: String
    let glyph: KinnectGlyph
    var isDestructive: Bool = false
    let action: () -> Void

    init(
        id: String? = nil,
        title: String,
        glyph: KinnectGlyph,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id ?? "\(title)|\(glyph.rawValue)|\(isDestructive)"
        self.title = title
        self.glyph = glyph
        self.isDestructive = isDestructive
        self.action = action
    }
}

/// Opaque themed action sheet replacing translucent system confirmationDialog.
struct KinnectActionSheet: View {
    let title: String
    var message: String? = nil
    let items: [KinnectActionSheetItem]
    var cancelTitle: String = L10n.tr("Hủy")
    var onSelectAction: ((@escaping () -> Void) -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    private var destructiveInk: Color {
        colorScheme == .dark
            ? Color(.sRGB, red: 0xFF / 255.0, green: 0x8D / 255.0, blue: 0xA1 / 255.0, opacity: 1.0)
            : Color(.sRGB, red: 0xA3 / 255.0, green: 0x1E / 255.0, blue: 0x43 / 255.0, opacity: 1.0)
    }

    private static let destructiveBadgeFill = Color(
        .sRGB,
        red: 0xB9 / 255.0,
        green: 0x1C / 255.0,
        blue: 0x47 / 255.0,
        opacity: 1.0
    )

    init(
        title: String,
        message: String? = nil,
        items: [KinnectActionSheetItem],
        cancelTitle: String = L10n.tr("Hủy"),
        onSelectAction: ((@escaping () -> Void) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.items = items
        self.cancelTitle = cancelTitle
        self.onSelectAction = onSelectAction
        self.onCancel = onCancel
    }

    static func estimatedHeight(for itemCount: Int, hasMessage: Bool) -> CGFloat {
        let headerHeight: CGFloat = hasMessage ? 104 : 74
        let rowsHeight = CGFloat(max(itemCount, 1)) * 60
        let cancelHeight: CGFloat = 82
        return min(max(headerHeight + rowsHeight + cancelHeight, 240), 580)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(KinnectTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .kinnectMultiline()

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .kinnectMultiline()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()
                .background(KinnectTheme.borderSoft)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            if let onSelectAction {
                                onSelectAction(item.action)
                                dismiss()
                            } else {
                                let action = item.action
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    action()
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(
                                            item.isDestructive
                                                ? Self.destructiveBadgeFill
                                                : KinnectTheme.accentSoft
                                        )
                                        .frame(width: 36, height: 36)

                                    KinnectIcon(
                                        glyph: item.glyph,
                                        size: 20,
                                        tint: item.isDestructive
                                            ? .white
                                            : KinnectTheme.accentBright
                                    )
                                }

                                Text(item.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(
                                        item.isDestructive
                                            ? destructiveInk
                                            : KinnectTheme.textPrimary
                                    )
                                    .kinnectMultiline()
                                    .multilineTextAlignment(.leading)

                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(KinnectTheme.surfaceElevated)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.title)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .clipped()

            Button {
                onCancel?()
                dismiss()
            } label: {
                Text(cancelTitle)
                    .font(.body.weight(.bold))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(KinnectTheme.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(KinnectTheme.border, lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(cancelTitle)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(KinnectTheme.surface.ignoresSafeArea())
    }
}

private struct KinnectActionSheetPresentationModifier: ViewModifier {
    let estimatedHeight: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationDetents([.height(estimatedHeight)])
                .presentationDragIndicator(.visible)
                .presentationBackground(KinnectTheme.surface)
                .presentationCornerRadius(24)
        } else {
            content
                .presentationDetents([.height(estimatedHeight)])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct KinnectActionSheetBoolModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String?
    let cancelTitle: String
    let items: [KinnectActionSheetItem]

    @State private var pendingAction: (() -> Void)? = nil

    func body(content: Content) -> some View {
        let height = KinnectActionSheet.estimatedHeight(
            for: items.count,
            hasMessage: !(message ?? "").isEmpty
        )
        content.sheet(isPresented: $isPresented, onDismiss: {
            let action = pendingAction
            pendingAction = nil
            action?()
        }) {
            KinnectActionSheet(
                title: title,
                message: message,
                items: items,
                cancelTitle: cancelTitle,
                onSelectAction: { action in
                    pendingAction = action
                },
                onCancel: {
                    pendingAction = nil
                }
            )
            .onAppear {
                pendingAction = nil
            }
            .modifier(KinnectActionSheetPresentationModifier(estimatedHeight: height))
        }
    }
}

private struct KinnectActionSheetItemModifier<Item: Identifiable>: ViewModifier {
    @Binding var item: Item?
    let title: (Item) -> String
    let message: ((Item) -> String?)?
    let cancelTitle: String
    let items: (Item) -> [KinnectActionSheetItem]

    @State private var pendingAction: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content.sheet(item: $item, onDismiss: {
            let action = pendingAction
            pendingAction = nil
            action?()
        }) { selected in
            let resolvedItems = items(selected)
            let resolvedMessage = message?(selected)
            let height = KinnectActionSheet.estimatedHeight(
                for: resolvedItems.count,
                hasMessage: !(resolvedMessage ?? "").isEmpty
            )
            KinnectActionSheet(
                title: title(selected),
                message: resolvedMessage,
                items: resolvedItems,
                cancelTitle: cancelTitle,
                onSelectAction: { action in
                    pendingAction = action
                },
                onCancel: {
                    pendingAction = nil
                }
            )
            .onAppear {
                pendingAction = nil
            }
            .modifier(KinnectActionSheetPresentationModifier(estimatedHeight: height))
        }
    }
}

extension View {
    func kinnectActionSheet(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        cancelTitle: String = L10n.tr("Hủy"),
        items: [KinnectActionSheetItem]
    ) -> some View {
        modifier(
            KinnectActionSheetBoolModifier(
                isPresented: isPresented,
                title: title,
                message: message,
                cancelTitle: cancelTitle,
                items: items
            )
        )
    }

    func kinnectActionSheet<Item: Identifiable>(
        item: Binding<Item?>,
        title: @escaping (Item) -> String,
        message: ((Item) -> String?)? = nil,
        cancelTitle: String = L10n.tr("Hủy"),
        items: @escaping (Item) -> [KinnectActionSheetItem]
    ) -> some View {
        modifier(
            KinnectActionSheetItemModifier(
                item: item,
                title: title,
                message: message,
                cancelTitle: cancelTitle,
                items: items
            )
        )
    }
}
