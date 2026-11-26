import SwiftUI

/// Reusable Reaction Picker matching Android's reactionBar pattern
/// Shows a horizontal bar of 6 emoji reactions with spring animations
struct ReactionPicker: View {
	let messageId: String
	let currentReaction: String?
	let reactionCounts: [String: Int]
	let isMine: Bool
	let onReact: (String) -> Void
	let onDismiss: () -> Void

	// Android REACTIONS: like, love, haha, wow, sad, angry
	private let reactions: [(key: String, emoji: String, title: String)] = [
		("like", "👍", "Thích"),
		("love", "❤️", "Yêu thích"),
		("haha", "😂", "Haha"),
		("wow", "😮", "Wow"),
		("sad", "😢", "Buồn"),
		("angry", "😡", "Phẫn nộ")
	]

	var body: some View {
		HStack(spacing: 0) {
			ForEach(Array(reactions.enumerated()), id: \.element.key) { index, reaction in
				ReactionButton(
					reaction: reaction,
					isSelected: currentReaction == reaction.key,
					count: reactionCounts[reaction.key] ?? 0,
					animationDelay: Double(index) * 0.03,
					onTap: {
						onReact(reaction.key)
						onDismiss()
					}
				)
			}
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 6)
		.background(
			RoundedRectangle(cornerRadius: 99, style: .continuous)
				.fill(KinnectTheme.surfaceElevated)
				.shadow(color: Color.black.opacity(0.25), radius: 12, y: 4)
				.overlay(
					RoundedRectangle(cornerRadius: 99, style: .continuous)
						.stroke(KinnectTheme.borderSoft, lineWidth: 0.8)
				)
		)
	}
}

private struct ReactionPressButtonStyle: ButtonStyle {
	let hasAppeared: Bool
	let animationDelay: Double

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.scaleEffect(configuration.isPressed ? 1.35 : (hasAppeared ? 1.0 : 0.85))
			.animation(
				.spring(response: 0.35, dampingFraction: 0.55)
				.delay(animationDelay),
				value: hasAppeared
			)
			.animation(.spring(response: 0.2, dampingFraction: 0.5), value: configuration.isPressed)
	}
}

/// Individual reaction button with unified spring press animation
private struct ReactionButton: View {
	let reaction: (key: String, emoji: String, title: String)
	let isSelected: Bool
	let count: Int
	let animationDelay: Double
	let onTap: () -> Void

	@State private var hasAppeared = false

	var body: some View {
		Button(action: onTap) {
			VStack(spacing: 2) {
				Text(reaction.emoji)
					.font(.system(size: 24))

				// Reaction count badge (only show if > 0)
				if count > 0 {
					Text("\(count)")
						.font(.system(size: 9, weight: .bold))
						.foregroundColor(KinnectTheme.textSecondary)
						.padding(.horizontal, 4)
						.padding(.vertical, 1)
						.background(
							Capsule()
								.fill(KinnectTheme.surface)
						)
						.transition(.scale.combined(with: .opacity))
				}
			}
			.frame(width: 46, height: 48)
			.contentShape(Rectangle())
		}
		.buttonStyle(ReactionPressButtonStyle(hasAppeared: hasAppeared, animationDelay: animationDelay))
		.accessibilityLabel("\(reaction.title) \(count > 0 ? "\(count) người" : "")")
		.accessibilityAddTraits(isSelected ? .isSelected : [])
		.onAppear {
			hasAppeared = true
		}
	}
}

/// Reaction summary view shown on message bubble (matching Android reaction summary)
struct ReactionSummary: View {
	let reactions: [String: Int]
	let myReaction: String?
	let maxVisible: Int = 3

	private let reactionOrder = ["like", "love", "haha", "wow", "sad", "angry"]

	private var activeReactionKeys: [String] {
		let ordered = reactionOrder.filter { (reactions[$0] ?? 0) > 0 }
		let extra = reactions.keys.filter { !reactionOrder.contains($0) && (reactions[$0] ?? 0) > 0 }.sorted()
		return ordered + extra
	}

	var body: some View {
		let visibleKeys = Array(activeReactionKeys.prefix(maxVisible))
		if !visibleKeys.isEmpty {
			HStack(spacing: 4) {
				ForEach(visibleKeys, id: \.self) { key in
					let count = reactions[key] ?? 0
					HStack(spacing: 2) {
						Text(DirectMessageItem.emoji(for: key))
							.font(.system(size: 12))
						if count > 1 {
							Text("\(count)")
								.font(.system(size: 10, weight: .semibold))
								.foregroundColor(myReaction == key ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
						}
					}
					.padding(.horizontal, 6)
					.padding(.vertical, 2)
					.background(
						Capsule()
							.fill(myReaction == key ? KinnectTheme.accentSoft : KinnectTheme.surfaceElevated)
							.overlay(
								Capsule()
									.stroke(myReaction == key ? KinnectTheme.accentBright.opacity(0.5) : KinnectTheme.borderSoft, lineWidth: 0.8)
							)
					)
				}

				// Show "+N" if more reactions exist
				let totalCount = reactions.values.reduce(0, +)
				let shownCount = visibleKeys.reduce(0) { $0 + (reactions[$1] ?? 0) }
				if totalCount > shownCount {
					Text("+\(totalCount - shownCount)")
						.font(.system(size: 10, weight: .semibold))
						.foregroundColor(KinnectTheme.textSecondary)
						.padding(.horizontal, 5)
						.padding(.vertical, 2)
						.background(
							Capsule()
								.fill(KinnectTheme.surfaceElevated)
						)
				}
			}
			.transition(.opacity.combined(with: .move(edge: .top)))
		}
	}
}

/// Floating reaction badge on message bubble (iOS Tapback style)
struct FloatingReactionBadge: View {
	let reaction: String
	let isMine: Bool

	var body: some View {
		Text(DirectMessageItem.emoji(for: reaction))
			.font(.system(size: 13))
			.padding(.horizontal, 6)
			.padding(.vertical, 3)
			.background(
				Capsule()
					.fill(KinnectTheme.surfaceElevated)
					.shadow(color: Color.black.opacity(0.35), radius: 3, y: 1)
					.overlay(Capsule().stroke(KinnectTheme.borderSoft, lineWidth: 0.8))
			)
			.offset(x: isMine ? -8 : 8, y: -10)
			.transition(.scale.combined(with: .opacity))
	}
}