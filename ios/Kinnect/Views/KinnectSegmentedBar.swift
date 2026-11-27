import SwiftUI

struct KinnectSegmentedOption<Selection: Hashable>: Identifiable {
    let value: Selection
    let title: String
    var id: Selection { value }
}

/// Accessible segmented control with >= 44pt tap targets and WCAG AA contrast.
struct KinnectSegmentedBar<Selection: Hashable>: View {
    @Binding var selection: Selection
    let options: [KinnectSegmentedOption<Selection>]
    var accessibilityLabel: String = ""

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    init(
        selection: Binding<Selection>,
        options: [KinnectSegmentedOption<Selection>],
        accessibilityLabel: String = ""
    ) {
        self._selection = selection
        self.options = options
        self.accessibilityLabel = accessibilityLabel
    }

    init(
        selection: Binding<Selection>,
        options: [(Selection, String)],
        accessibilityLabel: String = ""
    ) {
        self._selection = selection
        self.options = options.map { KinnectSegmentedOption(value: $0.0, title: $0.1) }
        self.accessibilityLabel = accessibilityLabel
    }

    init(
        selection: Binding<Selection>,
        accessibilityLabel: String = "",
        title: (Selection) -> String = { L10n.tr($0.rawValue) }
    ) where Selection: CaseIterable & RawRepresentable, Selection.RawValue == String {
        self._selection = selection
        self.options = Array(Selection.allCases).map {
            KinnectSegmentedOption(value: $0, title: title($0))
        }
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        let container = HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? KinnectTheme.textPrimary : KinnectTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? KinnectTheme.surface : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isSelected ? KinnectTheme.borderSoft : Color.clear, lineWidth: 1)
                                )
                                .shadow(
                                    color: isSelected
                                        ? Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08)
                                        : Color.clear,
                                    radius: 2,
                                    y: 1
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: KinnectTheme.radiusSM, style: .continuous)
                .fill(KinnectTheme.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: KinnectTheme.radiusSM, style: .continuous)
                        .stroke(KinnectTheme.borderSoft, lineWidth: 1)
                )
        )

        if accessibilityLabel.isEmpty {
            container
                .accessibilityElement(children: .contain)
        } else {
            container
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilityLabel)
        }
    }
}
