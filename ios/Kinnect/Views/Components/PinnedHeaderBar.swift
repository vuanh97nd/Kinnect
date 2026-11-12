import SwiftUI

/// Reusable Pinned Header Bar matching Android accountHeader pattern
/// Used across: Notifications, Store, Messages, Friends, Profile
struct PinnedHeaderBar: View {
	let title: String
	let onBack: (() -> Void)?
	let trailingActions: [TrailingAction]
	let showDivider: Bool

	struct TrailingAction {
		let systemImage: String
		let accessibilityLabel: String
		let action: () -> Void
		var badgeCount: Int? = nil
		var badgeColor: Color = .red
	}

	init(
		title: String,
		onBack: (() -> Void)? = nil,
		trailingActions: [TrailingAction] = [],
		showDivider: Bool = true
	) {
		self.title = title
		self.onBack = onBack
		self.trailingActions = trailingActions
		self.showDivider = showDivider
	}

	var body: some View {
		HStack(spacing: 12) {
			// Back Button
			if let onBack = onBack {
				Button(action: onBack) {
					Image(systemName: "arrow.left")
						.font(.system(size: 19, weight: .semibold))
						.foregroundColor(KinnectTheme.textPrimary)
						.frame(width: 44, height: 44)
						.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Quay lại")
			} else {
				// Spacer to maintain alignment when no back button
				Color.clear.frame(width: 44, height: 44)
			}

			// Title
			Text(title)
				.font(.system(size: 18, weight: .bold))
				.foregroundColor(KinnectTheme.textPrimary)
				.lineLimit(1)

			Spacer()

			// Trailing Actions
			HStack(spacing: 8) {
				ForEach(Array(trailingActions.enumerated()), id: \.offset) { _, action in
					Button(action: action.action) {
						ZStack {
							Image(systemName: action.systemImage)
								.font(.system(size: 18, weight: .semibold))
								.foregroundColor(KinnectTheme.textPrimary)
								.frame(width: 38, height: 38)
								.background(Circle().fill(KinnectTheme.surfaceElevated))

							if let count = action.badgeCount, count > 0 {
								Text("\(count > 99 ? "99+" : "\(count)")")
									.font(.system(size: 10, weight: .bold))
									.foregroundColor(.white)
									.padding(.horizontal, 5)
									.padding(.vertical, 1)
									.background(Capsule().fill(action.badgeColor))
									.offset(x: 12, y: -12)
							}
						}
					}
					.buttonStyle(.plain)
					.accessibilityLabel(action.accessibilityLabel)
				}
			}
		}
		.padding(.horizontal, 12)
		.frame(height: 52)
		.background(KinnectTheme.surface.ignoresSafeArea(edges: .top))
		.overlay(
			showDivider ? Divider().background(KinnectTheme.borderSoft) : nil,
			alignment: .bottom
		)
	}
}

// Convenience initializers for common patterns
extension PinnedHeaderBar {
	/// Standard header with back button and optional trailing actions
	static func standard(
		title: String,
		onBack: (() -> Void)? = nil,
		trailingActions: [TrailingAction] = []
	) -> PinnedHeaderBar {
		PinnedHeaderBar(title: title, onBack: onBack, trailingActions: trailingActions)
	}

	/// Header with back, title, and a single trailing action
	static func withAction(
		title: String,
		onBack: (() -> Void)? = nil,
		systemImage: String,
		accessibilityLabel: String,
		action: @escaping () -> Void,
		badgeCount: Int? = nil,
		badgeColor: Color = .red
	) -> PinnedHeaderBar {
		PinnedHeaderBar(
			title: title,
			onBack: onBack,
			trailingActions: [
				TrailingAction(
					systemImage: systemImage,
					accessibilityLabel: accessibilityLabel,
					action: action,
					badgeCount: badgeCount,
					badgeColor: badgeColor
				)
			]
		)
	}

	/// Header with back, title, and two trailing actions
	static func withActions(
		title: String,
		onBack: (() -> Void)? = nil,
		action1: TrailingAction,
		action2: TrailingAction
	) -> PinnedHeaderBar {
		PinnedHeaderBar(
			title: title,
			onBack: onBack,
			trailingActions: [action1, action2]
		)
	}
}