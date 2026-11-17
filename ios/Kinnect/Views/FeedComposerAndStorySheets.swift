import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct PostComposerSheet: View {
    let onPosted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var text = ""
    @State private var visibility = "public"
    @State private var photo: PhotosPickerItem?
    @State private var video: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var videoURL: URL?
    @State private var mediaDataURL = ""
    @State private var isSubmitting = false
    @State private var loadingMedia = false
    @State private var showCamera = false
    @State private var showMusic = false
    @State private var musicTitle = ""
    @State private var musicURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        KinnectAvatarView(name: appState.currentUser?.name ?? "Bạn",
                            avatarURL: appState.currentUser?.avatarUrl ?? "",
                            colorHex: appState.currentUser?.avatarColor ?? "#7C3AED", size: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(appState.currentUser?.name ?? "Bạn").font(.headline)
                            Menu {
                                Button("Mọi thành viên") { visibility = "public" }
                                Button("Người theo dõi") { visibility = "followers" }
                            } label: {
                                Label(visibility == "public" ? "Mọi thành viên" : "Người theo dõi",
                                      systemImage: visibility == "public" ? "globe" : "person.2")
                                    .font(.caption.bold())
                            }
                        }
                        Spacer()
                    }
                    TextField("Bạn đang nghĩ gì?", text: $text, axis: .vertical)
                        .font(KinnectTheme.scaled(18)).lineLimit(6...16)
                        .onChange(of: text) { value in if value.count > 2000 { text = String(value.prefix(2000)) } }
                    if loadingMedia { ProgressView("Đang chuẩn bị media…") }
                    if let previewImage {
                        Image(uiImage: previewImage).resizable().scaledToFit().frame(maxHeight: 360)
                    }
                    if let videoURL {
                        ShortClipPlayer(path: videoURL.absoluteString, active: true).frame(height: 320)
                    }
                    Button { showMusic = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                            Text(musicTitle.isEmpty ? "Thêm nhạc" : musicTitle)
                                .lineLimit(1)
                            Spacer()
                            if !musicTitle.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    }
                    .buttonStyle(.plain)
                    if !mediaDataURL.isEmpty || videoURL != nil || musicURL != nil {
                        Button("Gỡ media & nhạc", role: .destructive) {
                            previewImage = nil; videoURL = nil; mediaDataURL = ""
                            musicTitle = ""; musicURL = nil; photo = nil; video = nil
                        }
                    }
                }
                .padding(16)
            }
            .background(KinnectTheme.background)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 0) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Ảnh", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 52)
                    }
                    PhotosPicker(selection: $video, matching: .videos) {
                        Label("Video", systemImage: "video").frame(maxWidth: .infinity, minHeight: 52)
                    }
                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
                        else { appState.showToast("Thiết bị chưa có camera khả dụng.") }
                    } label: {
                        Label("Chụp/quay", systemImage: "camera").frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
                .font(.subheadline).background(KinnectTheme.surfaceElevated)
                .disabled(loadingMedia || isSubmitting)
            }
            .navigationTitle("Bài viết mới").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Đóng")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Đang đăng…" : "Đăng") { Task { await submitPost() } }
                        .font(.subheadline.bold())
                        .disabled(isSubmitting || loadingMedia || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mediaDataURL.isEmpty && videoURL == nil && musicURL == nil))
                }
            }
        }
        .onChange(of: photo) { item in
            guard let item else { return }
            Task {
                loadingMedia = true
                defer { loadingMedia = false }
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    useImage(image)
                } else { appState.showToast("Không đọc được ảnh đã chọn.") }
            }
        }
        .onChange(of: video) { item in
            guard let item else { return }
            Task {
                loadingMedia = true
                defer { loadingMedia = false }
                do {
                    if let movie = try? await item.loadTransferable(type: KinnectMovieTransferable.self) {
                        videoURL = movie.url; previewImage = nil; mediaDataURL = ""
                        return
                    }
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        appState.showToast("Không đọc được video đã chọn.")
                        return
                    }
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kinnect-Post-\(UUID().uuidString).mov")
                    try data.write(to: url)
                    videoURL = url; previewImage = nil; mediaDataURL = ""
                } catch { appState.showToast(error.localizedDescription) }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            KinnectComposerCamera { image, movie in
                if let image { useImage(image) }
                if let movie { videoURL = movie; previewImage = nil; mediaDataURL = "" }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showMusic) {
            NavigationStack {
                StudioMusicPickerSheet(selectedTrack: $musicTitle) { title, url in
                    musicTitle = title; musicURL = url
                }
            }
        }
    }

    private func useImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.72), data.count <= 20 * 1024 * 1024 else {
            appState.showToast("Ảnh vượt quá giới hạn 20 MB."); return
        }
        previewImage = image; videoURL = nil
        mediaDataURL = "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    private func submitPost() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var media = mediaDataURL
            if let videoURL {
                let project = StudioVideoProject(sourceURL: videoURL)
                project.musicURL = musicURL; project.musicTitle = musicTitle
                let output = try await project.exportVideo()
                let data = try Data(contentsOf: output)
                guard data.count <= 20 * 1024 * 1024 else {
                    appState.showToast("Video vượt quá giới hạn 20 MB."); return
                }
                media = "data:video/mp4;base64,\(data.base64EncodedString())"
            } else if let musicURL {
                let stillURL = try await KinnectStillVideo.makeCardVideo(
                    image: previewImage,
                    text: previewImage == nil ? text : "",
                    backgroundColorHex: "#1E1B4B"
                )
                let project = StudioVideoProject(sourceURL: stillURL)
                project.musicURL = musicURL; project.musicTitle = musicTitle
                let output = try await project.exportVideo()
                let data = try Data(contentsOf: output)
                guard data.count <= 20 * 1024 * 1024 else {
                    appState.showToast("Video nhạc vượt quá giới hạn 20 MB."); return
                }
                media = "data:video/mp4;base64,\(data.base64EncodedString())"
            }
            _ = try await KinnectAPIClient.shared.requestJSON("/api/posts", method: "POST",
                body: KinnectWriteBody.post(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                           visibility: visibility, mediaDataURL: media),
                requestId: "post_\(UUID().uuidString)")
            onPosted(); dismiss()
        } catch { appState.showToast(error.localizedDescription) }
    }
}

struct StoryMusicTrack: Identifiable {
    let id: String
    let title: String
    let artist: String
}

struct StoryComposerSheet: View {
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var text = ""
    @State private var backgroundColor = "#7C3AED"
    @State private var selectedMediaItem: PhotosPickerItem?
    @State private var imageDataURL = ""
    @State private var previewImage: UIImage?
    @State private var selectedVideoName: String?
    @State private var selectedMusic: StoryMusicTrack?
    @State private var showMusicSheet = false
    @State private var isSubmitting = false

    private let colors = ["#7C3AED", "#EC4899", "#2563EB", "#059669", "#D97706"]
    @State private var storyMusicTitle = ""
    @State private var storyMusicURL: URL?
    @State private var storyVideoURL: URL?
    @State private var storyMediaLoading = false
    @State private var storyMusicPlayer: AVPlayer?
    @State private var isStoryMusicPaused = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Two prominent creation tiles (100% Android parity MainActivity lines 6140-6152: "Quay tin" & "Ảnh kèm nhạc")
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedMediaItem, matching: .videos) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "video.fill")
                                        .font(KinnectTheme.scaled(20))
                                        .foregroundColor(.white)
                                }
                                Text("Quay tin")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                Text("Camera · Nhạc · Hiệu ứng")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            .frame(maxWidth: .infinity, minHeight: 110)
                            .background(KinnectTheme.storyPurpleGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }

                        PhotosPicker(selection: $selectedMediaItem, matching: .images) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "photo.fill")
                                        .font(KinnectTheme.scaled(20))
                                        .foregroundColor(.white)
                                }
                                Text("Ảnh kèm nhạc")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                Text("Chọn ảnh · thêm bài hát")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 110)
                            .background(KinnectTheme.storyBlueGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }

                    // 24-hour visibility note (Android line 6154 parity)
                    Text("Tin hiển thị 24 giờ cho những người theo dõi bạn.")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    // Main Story Canvas Preview
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(KinnectTheme.serverColor(backgroundColor))
                            .frame(height: 280)

                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                        }

                        if let storyVideoURL {
                            ShortClipPlayer(path: storyVideoURL.absoluteString, active: true).frame(height: 280)
                        } else if let videoName = selectedVideoName {
                            VStack(spacing: 8) {
                                Image(systemName: "video.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white)
                                Text(videoName)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.black.opacity(0.5)))
                            }
                        }

                        // Music overlay badge
                        if let music = selectedMusic {
                            VStack {
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "music.note")
                                            .font(.caption.bold())
                                        Text(music.artist.isEmpty ? music.title : "\(music.title) — \(music.artist)")
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                        Button {
                                            selectedMusic = nil
                                            storyMusicTitle = ""
                                            storyMusicURL = nil
                                            stopStoryMusicPreview()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                        }
                                    }
                                    .padding(.horizontal, 10) // spacing-ok: viền capsule nút đóng story
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.black.opacity(0.65)))
                                    .foregroundColor(.white)

                                    Spacer()
                                }
                                .padding(12)
                                Spacer()
                            }
                        }

                        TextField("Nhập nội dung tin 24h...", text: $text, axis: .vertical)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                            .padding(20)
                            .background(previewImage != nil || selectedVideoName != nil ? Color.black.opacity(0.4) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Color Palette Selector
                    HStack(spacing: 12) {
                        ForEach(colors, id: \.self) { hex in
                            Circle()
                                .fill(KinnectTheme.serverColor(hex))
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle().stroke(Color.white, lineWidth: backgroundColor == hex ? 3 : 0)
                                )
                                .onTapGesture {
                                    backgroundColor = hex
                                }
                        }
                    }

                    Button { showMusicSheet = true } label: {
                        Label(storyMusicTitle.isEmpty ? "Thêm nhạc" : storyMusicTitle, systemImage: "music.note")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(isSubmitting || storyMediaLoading)
                    if storyMediaLoading { ProgressView("Đang chuẩn bị media…") }

                    // Photo/Video Picker Button
                    PhotosPicker(selection: $selectedMediaItem, matching: .any(of: [.images, .videos])) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Chọn ảnh hoặc video từ máy")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.accentBright)
                    }
                    .onChange(of: selectedMediaItem) { item in
                        guard let item else { return }
                        Task {
                            storyMediaLoading = true
                            defer { storyMediaLoading = false }
                            let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
                            if !isMovie,
                               let data = try? await item.loadTransferable(type: Data.self),
                               let uiImg = UIImage(data: data),
                               let jpeg = uiImg.jpegData(compressionQuality: 0.72) {
                                guard jpeg.count <= 20 * 1024 * 1024 else {
                                    appState.showToast("Ảnh vượt quá giới hạn 20 MB."); return
                                }
                                previewImage = uiImg
                                selectedVideoName = nil
                                storyVideoURL = nil
                                imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                                return
                            }
                            var resolvedURL: URL?
                            if let movie = try? await item.loadTransferable(type: KinnectMovieTransferable.self) {
                                resolvedURL = movie.url
                            } else if let data = try? await item.loadTransferable(type: Data.self) {
                                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kinnect-Story-\(UUID().uuidString).mov")
                                try? data.write(to: url)
                                resolvedURL = url
                            }
                            if let url = resolvedURL {
                                let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                                guard sizeBytes <= 20 * 1024 * 1024 else {
                                    appState.showToast("Video vượt quá giới hạn 20 MB."); return
                                }
                                stopStoryMusicPreview()
                                storyVideoURL = url
                                previewImage = nil
                                selectedVideoName = "Đã chọn video 24h (\(max(1, sizeBytes / 1024 / 1024)) MB)"
                                if let rawData = try? Data(contentsOf: url) {
                                    imageDataURL = "data:video/mp4;base64,\(rawData.base64EncodedString())"
                                } else {
                                    imageDataURL = ""
                                }
                            } else {
                                appState.showToast("Không đọc được ảnh hoặc video đã chọn.")
                            }
                        }
                    }

                    Button {
                        Task { await createStory() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Đăng tin 24h")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(KinnectTheme.primaryGradient)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isSubmitting || storyMediaLoading || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageDataURL.isEmpty && storyVideoURL == nil && storyMusicURL == nil))
                }
                .padding(16)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Tạo tin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { stopStoryMusicPreview(); dismiss() }
                }
            }
            .onDisappear { stopStoryMusicPreview() }
            .sheet(isPresented: $showMusicSheet) {
                NavigationStack {
                    StudioMusicPickerSheet(selectedTrack: $storyMusicTitle) { title, url in
                        selectedMusic = title.isEmpty ? nil : StoryMusicTrack(id: url?.absoluteString ?? title, title: title, artist: "")
                        storyMusicTitle = title
                        storyMusicURL = url
                        if let url, storyVideoURL == nil {
                            startStoryMusicPreview(url: url)
                        } else {
                            stopStoryMusicPreview()
                        }
                    }
                }
            }
        }
    }

    private func startStoryMusicPreview(url: URL) {
        stopStoryMusicPreview()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVPlayer(url: url)
        player.volume = 1.0
        storyMusicPlayer = player
        isStoryMusicPaused = false
        player.play()
    }

    private func stopStoryMusicPreview() {
        storyMusicPlayer?.pause()
        storyMusicPlayer = nil
    }

    private func createStory() async {
        stopStoryMusicPreview()
        isSubmitting = true
        defer { isSubmitting = false }
        let reqId = "story_\(UUID().uuidString)"
        do {
            var media = imageDataURL
            let source: URL?
            if let storyVideoURL {
                source = storyVideoURL
            } else if storyMusicURL != nil {
                source = try await KinnectStillVideo.makeCardVideo(
                    image: previewImage,
                    text: previewImage == nil ? text : "",
                    backgroundColorHex: backgroundColor
                )
            } else {
                source = nil
            }
            if let source {
                let project = StudioVideoProject(sourceURL: source)
                project.musicURL = storyMusicURL
                project.musicTitle = storyMusicTitle
                let output = try await project.exportVideo()
                let data = try Data(contentsOf: output)
                guard data.count <= 20 * 1024 * 1024 else { throw KinnectAPIError.serverMessage("Tin vượt quá giới hạn 20 MB.") }
                media = "data:video/mp4;base64,\(data.base64EncodedString())"
            }
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/stories",
                method: "POST",
                body: KinnectWriteBody.story(
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    colorHex: backgroundColor,
                    mediaDataURL: media
                ),
                requestId: reqId
            )
            onCreated()
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct StoryDetailSheet: View {
    let story: StoryItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewers: [KinnectUser] = []
    @State private var isMuted: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    KinnectAvatarView(
                        name: story.author.name,
                        avatarURL: story.author.avatarUrl,
                        colorHex: story.author.avatarColor,
                        size: 40
                    )
                    VStack(alignment: .leading) {
                        Text(story.author.name)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Text("Lượt xem: \(max(story.viewsCount, viewers.count))")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    Spacer()
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(KinnectTheme.serverColor(story.backgroundColor))
                        .frame(maxWidth: .infinity, minHeight: 340)

                    if !story.imageUrl.isEmpty {
                        let isStoryVideo = story.mediaKind.lowercased() == "video"
                            || story.imageUrl.lowercased().contains(".mp4")
                            || story.imageUrl.lowercased().contains(".mov")
                        if isStoryVideo {
                            ShortClipPlayer(path: story.imageUrl, active: true, muted: isMuted)
                                .frame(maxWidth: .infinity, minHeight: 340, maxHeight: 460)
                                .clipShape(RoundedRectangle(cornerRadius: 22))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        isMuted.toggle()
                                    } label: {
                                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.white)
                                            .frame(width: 38, height: 38)
                                            .background(Circle().fill(Color.black.opacity(0.55)))
                                    }
                                    .padding(12)
                                }
                        } else {
                            KinnectMediaTile(path: story.imageUrl, kind: story.mediaKind)
                        }
                    }

                    if !story.text.isEmpty {
                        Text(story.text)
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .kinnectMultiline()
                            .padding(24)
                            .background(Color.black.opacity(story.imageUrl.isEmpty ? 0 : 0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                if !viewers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Người đã xem (\(viewers.count))")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(viewers) { viewer in
                                    HStack(spacing: 6) {
                                        KinnectAvatarView(
                                            name: viewer.name,
                                            avatarURL: viewer.avatarUrl,
                                            colorHex: viewer.avatarColor,
                                            size: 26
                                        )
                                        Text(viewer.name)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 10) // spacing-ok: viền capsule tên người xem story
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(16)
            .background(KinnectTheme.storyBackdropDark.ignoresSafeArea())
            .navigationTitle("Tin 24h")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .statusBarHidden(false)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task {
                _ = try? await KinnectAPIClient.shared.requestJSON(
                    "/api/stories/\(story.id)/view",
                    method: "POST",
                    body: [:],
                    requestId: "view_story_\(story.id)"
                )
                if story.author.id == appState.currentUser?.id,
                   let res = try? await KinnectAPIClient.shared.requestJSON("/api/stories/\(story.id)/viewers") {
                    let raw = res["viewers"] as? [[String: Any]] ?? []
                    self.viewers = raw.map { dict in
                        if let u = dict["user"] as? [String: Any] {
                            return KinnectUser.from(u)
                        }
                        return KinnectUser.from(dict)
                    }
                }
            }
        }
    }
}
