import SwiftUI

struct ShortVideoItem: Identifiable {
    let id: String
    let author: KinnectUser
    let title: String
    let caption: String
    let videoUrl: String
    let durationSec: Int
    var likesCount: Int
    var commentsCount: Int
    var isLiked: Bool

    static func from(_ dict: [String: Any]) -> ShortVideoItem {
        let authDict = dict["author"] as? [String: Any] ?? [:]
        return ShortVideoItem(
            id: dict["id"] as? String ?? UUID().uuidString,
            author: KinnectUser.from(authDict),
            title: dict["title"] as? String ?? "",
            caption: dict["caption"] as? String ?? "",
            videoUrl: dict["videoUrl"] as? String ?? "",
            durationSec: dict["durationSec"] as? Int ?? 15,
            likesCount: dict["likesCount"] as? Int ?? 0,
            commentsCount: dict["commentsCount"] as? Int ?? 0,
            isLiked: dict["liked"] as? Bool ?? false
        )
    }
}

struct ShortsVideoView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var shortsTab: String = "for" // "for" (Đề xuất) | "following" (Đang theo dõi)
    @State private var items: [ShortVideoItem] = []
    @State private var currentIndex: Int = 0
    @State private var isLoading = false
    @State private var showCommentsSheet = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if items.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    KinnectIcon(glyph: .video, size: 48, tint: KinnectTheme.textSecondary)
                    Text("Chưa có video ngắn")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Các video ngắn thịnh hành sẽ hiển thị tại đây.")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !items.isEmpty {
                // Vertical pager / scroll of video cards
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        shortVideoCard(item, at: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .top)
            }

            // Top transparent floating bar (Đề xuất · Đang theo dõi) - Parity with Android 1.2.12
            HStack(spacing: 24) {
                Spacer()
                tabHeaderButton(id: "following", title: "Đang theo dõi")
                tabHeaderButton(id: "for", title: "Đề xuất")
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.7), Color.black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )
        }
        .task {
            await loadShorts()
        }
        .sheet(isPresented: $showCommentsSheet) {
            if currentIndex < items.count {
                ShortCommentsSheet(item: items[currentIndex])
            }
        }
    }

    private func tabHeaderButton(id: String, title: String) -> some View {
        let isSelected = shortsTab == id
        return Button {
            shortsTab = id
            Task { await loadShorts() }
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                if isSelected {
                    Capsule()
                        .fill(KinnectTheme.accentBright)
                        .frame(width: 24, height: 3)
                } else {
                    Capsule()
                        .fill(Color.clear)
                        .frame(width: 24, height: 3)
                }
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func shortVideoCard(_ item: ShortVideoItem, at index: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Background Video Stage / Preview placeholder
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.08, blue: 0.22),
                            Color(red: 0.05, green: 0.03, blue: 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    VStack(spacing: 12) {
                        KinnectIcon(glyph: .video, size: 54, selected: true, tint: KinnectTheme.accentBright.opacity(0.4))
                        Text(item.title.isEmpty ? "Video Kinnect Shorts" : item.title)
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                )

            // Right Action Column (Like, Comment, Share)
            HStack(alignment: .bottom) {
                // Bottom left: Author info & Caption
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        KinnectAvatarView(
                            name: item.author.name,
                            avatarURL: item.author.avatarUrl,
                            colorHex: item.author.avatarColor,
                            size: 40,
                            isOnline: false
                        )
                        Text(item.author.name)
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }

                    if !item.caption.isEmpty {
                        Text(item.caption)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.95))
                            .lineLimit(3)
                            .shadow(radius: 2)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        Text("Âm thanh gốc — \(item.author.name)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)

                Spacer()

                // Right Action Sidebar
                VStack(spacing: 18) {
                    // Like button
                    Button {
                        toggleLike(at: index)
                    } label: {
                        VStack(spacing: 4) {
                            KinnectIcon(
                                glyph: .heart,
                                size: 28,
                                selected: item.isLiked,
                                tint: item.isLiked ? KinnectTheme.danger : .white
                            )
                            Text("\(item.likesCount)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(item.isLiked ? "Bỏ thích video" : "Thích video")

                    // Comments button
                    Button {
                        showCommentsSheet = true
                    } label: {
                        VStack(spacing: 4) {
                            KinnectIcon(glyph: .comment, size: 28, selected: true, tint: .white)
                            Text("\(item.commentsCount)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Bình luận")

                    // Share button
                    Button {
                        appState.showToast("Đã sao chép liên kết video!")
                    } label: {
                        VStack(spacing: 4) {
                            KinnectIcon(glyph: .share, size: 28, tint: .white)
                            Text("Chia sẻ")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Chia sẻ video")
                }
                .padding(.trailing, 12)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleLike(at index: Int) {
        guard index < items.count else { return }
        items[index].isLiked.toggle()
        items[index].likesCount += items[index].isLiked ? 1 : -1
    }

    private func loadShorts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/shorts?feed=\(shortsTab)",
                method: "GET"
            )
            if let arr = res["shorts"] as? [[String: Any]] {
                self.items = arr.map(ShortVideoItem.from)
            }
        } catch {
            appState.showToast("Không thể tải video: \(error.localizedDescription)")
        }
    }
}

struct ShortCommentsSheet: View {
    let item: ShortVideoItem
    @Environment(\.dismiss) private var dismiss
    @State private var commentText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            KinnectAvatarView(name: "Bạn bè", avatarURL: "", colorHex: "#9B51E0", size: 36, isOnline: false)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("kinnect_user")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                Text("Video rất hay và sáng tạo!")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                            }
                        }
                        .listRowBackground(KinnectTheme.surface)
                    } header: {
                        Text("\(item.commentsCount) bình luận")
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(KinnectTheme.background)

                HStack(spacing: 8) {
                    TextField("Thêm bình luận...", text: $commentText)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 18).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(.white)

                    KinnectIconButton(glyph: .send, label: "Gửi", tint: KinnectTheme.accentBright) {
                        commentText = ""
                    }
                }
                .padding(12)
                .background(KinnectTheme.surface)
            }
            .navigationTitle("Bình luận")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { dismiss() }
                        .foregroundColor(KinnectTheme.accentBright)
                }
            }
        }
    }
}
