import AVKit
import CoreLocation
import SwiftUI

struct DiscoverView: View {
    let onOpenCamera: () -> Void
    @ObservedObject private var appState = AppState.shared

    enum DiscoverSegment: String, CaseIterable {
        case forYou = "Dành cho bạn"
        case nearby = "Quanh đây"
        case following = "Đang theo dõi"
    }

    @State private var segment: DiscoverSegment = .forYou
    @State private var shorts: [ShortItem] = []
    @State private var people: [KinnectUser] = []
    @State private var posts: [PostItem] = []
    @State private var isLoading = false
    @State private var locationStatusText: String?
    @State private var activeShortComment: ShortItem?

    var body: some View {
        VStack(spacing: 10) {
            // 3 Required Segments: Dành cho bạn - Quanh đây - Đang theo dõi
            Picker("Khám phá", selection: $segment) {
                ForEach(DiscoverSegment.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .onChange(of: segment) { _ in
                Task { await loadCurrentSegment() }
            }

            if let locationStatusText, segment == .nearby {
                HStack(spacing: 6) {
                    KinnectIcon(glyph: .nearby, size: 18, selected: true, tint: KinnectTheme.accentBright)
                    Text(locationStatusText)
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .kinnectMultiline()
                    Spacer()
                }
                .padding(.horizontal, 16)
            }

            ScrollView {
                LazyVStack(spacing: 14) {
                    // Shorts carousel / vertical players
                    if !visibleShorts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                HStack(spacing: 8) {
                                    KinnectIcon(glyph: .video, size: 22, selected: true, tint: KinnectTheme.accentBright)
                                    Text("Video ngắn (Shorts)")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                Button(action: onOpenCamera) {
                                    HStack(spacing: 4) {
                                        KinnectIcon(glyph: .add, size: 16, selected: true, tint: KinnectTheme.accentBright)
                                        Text("Đăng video")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(KinnectTheme.accentBright)
                                    }
                                    .frame(minHeight: 44)
                                }
                                .accessibilityLabel("Đăng video ngắn")
                            }

                            ForEach(visibleShorts) { short in
                                ShortVideoCard(
                                    short: short,
                                    onLike: { Task { await toggleShortLike(short) } },
                                    onComment: { activeShortComment = short },
                                    onReport: {
                                        appState.activeReportContext = UGCReportContext(
                                            targetType: "short",
                                            targetId: short.id,
                                            targetUserId: short.author.id,
                                            targetTitle: short.title.isEmpty ? "Video của \(short.author.name)" : short.title
                                        )
                                    }
                                )
                            }
                        }
                    }

                    // People / Nearby / Following cards
                    if !visiblePeople.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(segment == .nearby ? "Người dùng quanh bạn" : "Gợi ý kết nối")
                                .font(.headline)
                                .foregroundColor(.white)

                            ForEach(visiblePeople) { person in
                                DiscoverPersonCard(
                                    person: person,
                                    isOnline: appState.onlineUserIds.contains(person.id),
                                    onFollowToggle: {
                                        Task { await toggleFollow(person) }
                                    },
                                    onCallVideo: {
                                        Task { await NativeWebRTCManager.shared.startOutgoingCall(targetUser: person, mode: "video") }
                                    }
                                )
                            }
                        }
                    }

                    if !visiblePosts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bài viết nổi bật")
                                .font(.headline)
                                .foregroundColor(.white)

                            ForEach(visiblePosts) { post in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 10) {
                                        KinnectAvatarView(
                                            name: post.author.name,
                                            avatarURL: post.author.avatarUrl,
                                            colorHex: post.author.avatarColor,
                                            size: 36
                                        )
                                        VStack(alignment: .leading) {
                                            Text(post.author.name)
                                                .font(.subheadline.bold())
                                                .foregroundColor(.white)
                                            Text(formatRelativeDate(post.createdAt))
                                                .font(.caption2)
                                                .foregroundColor(KinnectTheme.textSecondary)
                                        }
                                        Spacer()
                                    }
                                    if !post.text.isEmpty {
                                        Text(post.text)
                                            .font(.subheadline)
                                            .foregroundColor(KinnectTheme.textPrimary)
                                            .kinnectMultiline()
                                    }
                                    if !post.imageUrl.isEmpty {
                                        KinnectRemoteImageView(rawURL: post.imageUrl, cornerRadius: 12, maxHeight: 240)
                                    }
                                }
                                .kinnectCard()
                            }
                        }
                    }

                    if isLoading && visibleShorts.isEmpty && visiblePeople.isEmpty {
                        ProgressView().tint(KinnectTheme.accentBright).padding(.vertical, 36)
                    }
                }
                .padding(14)
            }
            .refreshable {
                await loadCurrentSegment()
            }
        }
        .background(KinnectTheme.background)
        .navigationTitle("Khám phá")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCurrentSegment()
        }
        .sheet(item: $activeShortComment) { short in
            ShortCommentsSheet(short: short) {
                Task { await loadCurrentSegment() }
            }
        }
    }

    private var visibleShorts: [ShortItem] {
        shorts.filter { !appState.blockedUserIds.contains($0.author.id) }
    }

    private var visiblePeople: [KinnectUser] {
        people.filter { !appState.blockedUserIds.contains($0.id) && $0.id != appState.currentUser?.id }
    }

    private var visiblePosts: [PostItem] {
        posts.filter { !appState.blockedUserIds.contains($0.author.id) }
    }

    private func loadCurrentSegment() async {
        isLoading = true
        defer { isLoading = false }

        switch segment {
        case .forYou:
            async let discoverTask = KinnectAPIClient.shared.requestJSON("/api/discover")
            async let shortsTask = KinnectAPIClient.shared.requestJSON("/api/shorts")
            if let disc = try? await discoverTask {
                self.people = (disc["people"] as? [[String: Any]] ?? disc["users"] as? [[String: Any]] ?? []).map(KinnectUser.from)
                self.posts = (disc["posts"] as? [[String: Any]] ?? []).map(PostItem.from)
            }
            if let sh = try? await shortsTask {
                self.shorts = (sh["shorts"] as? [[String: Any]] ?? []).map(ShortItem.from)
            }

        case .nearby:
            locationStatusText = "Đang xác định vị trí GPS..."
            if let coord = await MediaPermissionHandler.shared.requestCurrentLocation() {
                locationStatusText = String(format: "Vị trí hiện tại: %.4f, %.4f (bán kính 50km)", coord.latitude, coord.longitude)
                _ = try? await KinnectAPIClient.shared.requestJSON(
                    "/api/me/location",
                    method: "PATCH",
                    body: [
                        "lat": coord.latitude,
                        "lng": coord.longitude
                    ],
                    requestId: "loc_\(Int(Date().timeIntervalSince1970))"
                )
                if let res = try? await KinnectAPIClient.shared.requestJSON(
                    "/api/discover?nearby=1&lat=\(coord.latitude)&lng=\(coord.longitude)&radiusKm=50"
                ) {
                    self.people = (res["people"] as? [[String: Any]] ?? res["users"] as? [[String: Any]] ?? []).map(KinnectUser.from)
                    self.posts = (res["posts"] as? [[String: Any]] ?? []).map(PostItem.from)
                    self.shorts = []
                }
            } else {
                locationStatusText = "Chưa cấp quyền vị trí. Đang hiển thị gợi ý khu vực mặc định."
                if let res = try? await KinnectAPIClient.shared.requestJSON("/api/discover?nearby=1") {
                    self.people = (res["people"] as? [[String: Any]] ?? res["users"] as? [[String: Any]] ?? []).map(KinnectUser.from)
                    self.posts = (res["posts"] as? [[String: Any]] ?? []).map(PostItem.from)
                    self.shorts = []
                }
            }

        case .following:
            if let res = try? await KinnectAPIClient.shared.requestJSON("/api/discover?following=1") {
                self.people = (res["people"] as? [[String: Any]] ?? res["users"] as? [[String: Any]] ?? []).map(KinnectUser.from)
                self.posts = (res["posts"] as? [[String: Any]] ?? []).map(PostItem.from)
            }
            if let sh = try? await KinnectAPIClient.shared.requestJSON("/api/shorts") {
                let all = (sh["shorts"] as? [[String: Any]] ?? []).map(ShortItem.from)
                self.shorts = all.filter { $0.author.isFollowing }
            }
        }
    }

    private func toggleShortLike(_ short: ShortItem) async {
        let reqId = "short_like_\(short.id)_\(Int(Date().timeIntervalSince1970))"
        do {
            if short.liked {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/shorts/\(short.id)/like",
                    method: "DELETE",
                    body: [:],
                    requestId: reqId
                )
            } else {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/shorts/\(short.id)/like",
                    method: "POST",
                    body: [:],
                    requestId: reqId
                )
            }
            await loadCurrentSegment()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func toggleFollow(_ person: KinnectUser) async {
        let reqId = "follow_\(person.id)_\(Int(Date().timeIntervalSince1970))"
        do {
            if person.isFollowing {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/users/\(person.id)/follow",
                    method: "DELETE",
                    body: [:],
                    requestId: reqId
                )
            } else {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/users/\(person.id)/follow",
                    method: "POST",
                    body: [:],
                    requestId: reqId
                )
            }
            await loadCurrentSegment()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

private struct ShortVideoCard: View {
    let short: ShortItem
    let onLike: () -> Void
    let onComment: () -> Void
    let onReport: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                KinnectAvatarView(
                    name: short.author.name,
                    avatarURL: short.author.avatarUrl,
                    colorHex: short.author.avatarColor,
                    size: 38
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(short.author.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    if !short.title.isEmpty {
                        Text(short.title)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                }
                Spacer()
                KinnectIconButton(
                    glyph: .report,
                    label: "Báo cáo video",
                    tint: KinnectTheme.textSecondary,
                    action: onReport
                )
            }

            if let player {
                VideoPlayer(player: player)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(KinnectTheme.surfaceElevated)
                    .frame(height: 240)
                    .overlay(
                        Button {
                            if let url = ServerConfig.resolveURL(short.videoUrl) {
                                let av = AVPlayer(url: url)
                                self.player = av
                                av.play()
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(KinnectTheme.accentBright)
                                Text("Phát video ngắn")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                            }
                        }
                    )
            }

            if !short.caption.isEmpty {
                Text(short.caption)
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textPrimary)
                    .kinnectMultiline()
            }

            HStack(spacing: 16) {
                Button(action: onLike) {
                    HStack(spacing: 6) {
                        KinnectIcon(
                            glyph: .heart,
                            size: 20,
                            selected: short.liked,
                            tint: short.liked ? KinnectTheme.danger : KinnectTheme.textSecondary
                        )
                        Text("\(short.likesCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(short.liked ? KinnectTheme.danger : KinnectTheme.textSecondary)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Thích video")

                Button(action: onComment) {
                    HStack(spacing: 6) {
                        KinnectIcon(glyph: .comment, size: 20, tint: KinnectTheme.textSecondary)
                        Text("\(short.commentsCount) bình luận")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Bình luận video")
                Spacer()
            }
        }
        .kinnectCard()
        .onDisappear {
            player?.pause()
        }
    }
}

private struct DiscoverPersonCard: View {
    let person: KinnectUser
    let isOnline: Bool
    let onFollowToggle: () -> Void
    let onCallVideo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            KinnectAvatarView(
                name: person.name,
                avatarURL: person.avatarUrl,
                colorHex: person.avatarColor,
                size: 48,
                isOnline: isOnline
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(person.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .kinnectMultiline()
                    if let dist = person.distanceKm {
                        Text(String(format: "%.1f km", dist))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(KinnectTheme.accent.opacity(0.3)))
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                }
                if !person.bio.isEmpty {
                    Text(person.bio)
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .kinnectMultiline()
                } else if !person.locationName.isEmpty {
                    Text(person.locationName)
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .kinnectMultiline()
                }
            }

            Spacer()

            KinnectIconButton(
                glyph: .videoCall,
                label: "Gọi video",
                tint: KinnectTheme.accentBright,
                action: onCallVideo
            )

            Button(action: onFollowToggle) {
                Text(person.isFollowing ? "Đang theo dõi" : "Theo dõi")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(person.isFollowing ? AnyShapeStyle(KinnectTheme.surfaceElevated) : AnyShapeStyle(KinnectTheme.primaryGradient))
                    )
                    .foregroundColor(.white)
            }
        }
        .kinnectCard()
    }
}

struct ShortCommentsSheet: View {
    let short: ShortItem
    let onUpdated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var comments: [CommentItem] = []
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(comments) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.author.name)
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                        Text(c.text)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .kinnectMultiline()
                    }
                    .listRowBackground(KinnectTheme.surface)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                HStack(spacing: 8) {
                    TextField("Bình luận video ngắn...", text: $text)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(.white)
                    KinnectIconButton(
                        glyph: .send,
                        label: "Gửi bình luận",
                        tint: KinnectTheme.accentBright
                    ) {
                        Task { await postComment() }
                    }
                }
                .padding(12)
                .background(KinnectTheme.surface)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Bình luận Shorts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textPrimary) {
                        dismiss()
                    }
                }
            }
            .task {
                await load()
            }
        }
    }

    private func load() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/shorts/\(short.id)/comments") {
            self.comments = (res["comments"] as? [[String: Any]] ?? []).map(CommentItem.from)
        }
    }

    private func postComment() async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        text = ""
        let reqId = "short_cmt_\(short.id)_\(UUID().uuidString)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/shorts/\(short.id)/comments",
                method: "POST",
                body: ["text": clean],
                requestId: reqId
            )
            await load()
            onUpdated()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

