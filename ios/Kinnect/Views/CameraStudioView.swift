import AVFoundation
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum StudioEditTool: String, CaseIterable, Identifiable {
    case crop = "Cắt & xoay"
    case color = "Điều chỉnh"
    case beauty = "Làm mịn"
    case audio = "Âm thanh"
    case filters = "Bộ lọc Pro"

    var id: String { rawValue }
}

struct CameraStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    enum CaptureMode: String, CaseIterable {
        case photo = "ẢNH"
        case video = "VIDEO"
        case live = "LIVE"
    }

    enum PublishTarget: String, CaseIterable {
        case shortVideo = "Video"
        case feedPost = "Bài viết"
        case story = "Tin 24h"
    }

    enum CreativeTool: String, CaseIterable {
        case filters = "Bộ lọc"
        case beauty = "Làm đẹp"
        case stickers = "Sticker"
    }

    // Camera / Capture State
    @StateObject private var cameraController = CameraCaptureController()
    @State private var captureMode: CaptureMode = .photo
    @State private var target: PublishTarget = .feedPost
    @State private var isUsingFrontCamera = false
    @State private var isFlashOn = false
    @State private var showMusicPickerSheet = false
    @State private var selectedMusicTrack = ""
    @State private var showStudioProSheet = false
    @State private var showCreateLiveSheet = false
    @State private var studioProAppliedEffect = "Bộ lọc gốc"
    @State private var isUploading = false

    // Creative Tool State (Web & Android Parity)
    @State private var selectedCreativeTool: CreativeTool? = nil
    @State private var activeFilter: String = "none"
    @State private var filterIntensity: Double = 0.8
    @State private var activeSticker: String = "none"
    @State private var beautyValues: [String: Double] = [
        "smooth": 0.5,
        "whiten": 0.3,
        "slim": 0.2,
        "eyes": 0.2,
        "lips": 0.3,
        "blemish": 0.5,
        "blush": 0.2
    ]
    @State private var activeBeautyKey: String = "smooth"

    static let filterPresets: [(id: String, name: String)] = [
        ("none", "Gốc"),
        ("clear", "Trong trẻo"),
        ("milk", "Sữa"),
        ("peach", "Hồng đào"),
        ("warm", "Ấm áp"),
        ("cool", "Mát lạnh"),
        ("film", "Phim cũ"),
        ("mono", "Đen trắng"),
        ("vivid", "Rực rỡ"),
        ("sunset", "Hoàng hôn"),
        ("candy", "Kẹo ngọt"),
        ("mint", "Bạc hà"),
        ("dream", "Mộng mơ"),
        ("retro", "Retro"),
        ("cinema", "Cinema"),
        ("rose", "Rose"),
        ("golden", "Golden"),
        ("ice", "Ice"),
        ("teal", "Teal"),
        ("teal_orange", "Teal & Cam"),
        ("cyberpunk", "Cyberpunk"),
        ("vintage", "Vintage"),
        ("drama", "Kịch tính"),
        ("noir", "Noir"),
        ("beauty_glow", "Glow sáng")
    ]

    static let beautyTools: [(key: String, title: String, icon: String)] = [
        ("smooth", "Mịn da", "sparkles"),
        ("whiten", "Sáng da", "sun.max.fill"),
        ("slim", "Gọn mặt", "face.dashed"),
        ("eyes", "Mắt to", "eye.fill"),
        ("lips", "Môi đầy", "mouth.fill"),
        ("blemish", "Giảm đốm", "wand.and.stars"),
        ("blush", "Má hồng", "heart.fill")
    ]

    static let stickers: [(id: String, name: String, emoji: String)] = [
        ("none", "Không", "🚫"),
        ("glasses", "Kính râm", "🕶️"),
        ("bunny", "Tai thỏ", "🐰"),
        ("cat", "Tai mèo", "🐱"),
        ("dog", "Cún con", "🐶"),
        ("crown", "Vương miện", "👑"),
        ("flowers", "Vòng hoa", "🌸"),
        ("bow", "Nơ xinh", "🎀"),
        ("freckles", "Tàn nhang", "🤎"),
        ("hearts", "Tim bay", "💕"),
        ("sparkle", "Lấp lánh", "✨"),
        ("stars", "Sao xoay", "⭐"),
        ("round_glasses", "Kính tròn", "👓"),
        ("heart_glasses", "Kính tim", "💗"),
        ("butterfly", "Bướm", "🦋"),
        ("halo", "Thiên thần", "😇"),
        ("rainbow", "Cầu vồng", "🌈"),
        ("bubbles", "Bong bóng", "🫧"),
        ("snow", "Tuyết", "❄️"),
        ("confetti", "Lễ hội", "🎉"),
        ("devil", "Tiểu quỷ", "😈"),
        ("mask", "Mặt nạ", "🎭"),
        ("fire", "Hào quang", "🔥"),
        ("music", "Nốt nhạc", "🎵"),
        ("party", "Mũ tiệc", "🥳"),
        ("pixel", "Pixel", "👾"),
        ("retro", "Cổ điển", "🕶️"),
        ("blush", "Má hồng", "☺️")
    ]

    // Media Data
    @State private var originalImage: UIImage?
    @State private var previewImage: UIImage?
    @State private var videoDataURL = ""
    @State private var capturedVideoTempURL: URL?
    @State private var imageDataURL = ""
    @State private var title = ""
    @State private var caption = ""

    // Studio Pro Project Models (Real Photo & Video Editors)
    @StateObject private var photoProject = StudioPhotoProject(originalImage: UIImage())
    @State private var videoProject: StudioVideoProject? = nil
    @State private var selectedTool: StudioEditTool = .color
    @State private var isComparingOriginal = false
    @State private var videoCompositionRevision = UUID().uuidString

    private var isVideoActive: Bool {
        capturedVideoTempURL != nil || !videoDataURL.isEmpty || UIReviewFixture.activeScreen == "camera-studio-video-edit"
    }

    // Pickers
    @State private var selectedLibraryItem: PhotosPickerItem?

    init(initialMode: CaptureMode = .photo) {
        _captureMode = State(initialValue: initialMode)
    }

    var body: some View {
        Group {
            if previewImage == nil && videoDataURL.isEmpty && UIReviewFixture.activeScreen != "camera-studio-edit" {
                // 1. Direct-to-Camera Viewfinder Mode (100% Android StudioActivity Parity)
                cameraViewfinderMode
            } else {
                // 2. Media Edit Mode (Studio Pro top-right, distinct Save, Publish)
                mediaEditMode
            }
        }
        .background(KinnectTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            cameraController.configureIfAuthorized()
            cameraController.start()
            cameraController.onCapturedImage = { uiImg in
                self.originalImage = uiImg
                self.photoProject.originalImage = uiImg
                self.photoProject.resetAll()
                self.previewImage = self.photoProject.render(maxDimension: 900)
                self.target = .feedPost
                if let jpeg = (self.previewImage ?? uiImg).jpegData(compressionQuality: 0.85) {
                    self.imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                }
            }
            cameraController.onCapturedVideoData = { data, tempURL in
                self.capturedVideoTempURL = tempURL
                self.previewImage = nil
                self.originalImage = nil
                self.target = .shortVideo
                let vp = StudioVideoProject(sourceURL: tempURL)
                if !self.selectedMusicTrack.isEmpty {
                    vp.musicTitle = self.selectedMusicTrack
                }
                self.videoProject = vp
                self.syncVideoProjectSliders(to: vp)
                if data.count > 8 * 1024 * 1024 {
                    appState.showToast("Video vượt quá giới hạn 8MB của máy chủ.")
                } else {
                    self.videoDataURL = "data:video/mp4;base64,\(data.base64EncodedString())"
                }
            }
            if UIReviewFixture.activeScreen == "camera-studio-video" {
                captureMode = .video
            }
            if UIReviewFixture.activeScreen == "camera-studio-video-edit" {
                target = .shortVideo
                title = "Video ngắn Kinnect Shorts"
                caption = "Video ngắn quay bằng Camera Studio và phát qua AVPlayer native."
                selectedMusicTrack = "Lofi Chill Sài Gòn"
                if let movieURL = UIReviewFixture.samplePlayableVideoURL() {
                    self.capturedVideoTempURL = movieURL
                    let vp = StudioVideoProject(sourceURL: movieURL)
                    vp.musicTitle = "Lofi Chill Sài Gòn"
                    vp.musicVolume = 0.8
                    vp.originalAudioVolume = 1.0
                    self.videoProject = vp
                    if let d = try? Data(contentsOf: movieURL) {
                        self.videoDataURL = "data:video/mp4;base64,\(d.base64EncodedString())"
                    }
                }
            }
            if UIReviewFixture.activeScreen == "camera-studio-edit" && previewImage == nil {
                let sample = UIReviewFixture.samplePreviewImage()
                originalImage = sample
                photoProject.originalImage = sample
                photoProject.resetAll()
                previewImage = photoProject.render(maxDimension: 900)
                caption = "[Fixture UI] Kiểm thử bảng chỉnh sửa Kinnect Studio với nút Lưu tách riêng."
            }
        }
        .onDisappear {
            cameraController.stop()
        }
        .sheet(isPresented: $showMusicPickerSheet) {
            NavigationStack {
                StudioMusicPickerSheet(
                    selectedTrack: $selectedMusicTrack,
                    onSelectTrack: { title, url in
                        selectedMusicTrack = title
                        videoProject?.musicTitle = title
                        videoProject?.musicURL = url
                    }
                )
            }
        }
        .sheet(isPresented: $showStudioProSheet) {
            NavigationStack {
                StudioProSheet(
                    appliedEffect: $studioProAppliedEffect,
                    onApply: { effect in
                        studioProAppliedEffect = effect
                        if let pack = StudioProPack.allCases.first(where: { $0.rawValue == effect }) {
                            photoProject.proPack = pack
                            updatePhotoPreview()
                        } else if let base = originalImage {
                            let filtered = applyProFilter(named: effect, to: base)
                            self.previewImage = filtered
                            if let jpeg = filtered.jpegData(compressionQuality: 0.85) {
                                self.imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                            }
                        }
                        appState.showToast("Đã áp dụng Studio Pro: '\(effect)'")
                    }
                )
            }
        }
        .sheet(isPresented: $showCreateLiveSheet) {
            CreateLiveRoomSheet(onStarted: {
                cameraController.stop()
                dismiss()
            })
        }
    }

    // MARK: - Direct Camera Viewfinder Mode
    private var cameraViewfinderMode: some View {
        ZStack(alignment: .bottom) {
            // Live Hardware Camera Viewport Layer with fallback
            LiveCameraPreviewView(
                controller: cameraController,
                isFlashOn: $isFlashOn,
                isUsingFrontCamera: $isUsingFrontCamera
            )
            .ignoresSafeArea()

            // AR Face Sticker Overlay on Camera Viewfinder (Web & Android Parity)
            if activeSticker != "none", let s = Self.stickers.first(where: { $0.id == activeSticker }) {
                if let img = stickerImage(for: s.id) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                        .offset(y: stickerOffset(for: activeSticker))
                        .transition(.scale.combined(with: .opacity))
                        .allowsHitTesting(false)
                } else {
                    Text(s.emoji)
                        .font(.system(size: 96))
                        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                        .offset(y: stickerOffset(for: activeSticker))
                        .transition(.scale.combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }

            VStack(spacing: 0) {
                // Top Camera Chrome: Close, Aspect ratio 9:16, Music, Flash
                HStack(spacing: 16) {
                    KinnectIconButton(glyph: .close, label: "Thoát Camera", tint: .white) {
                        cameraController.stop()
                        dismiss()
                    }

                    Spacer()

                    Button {
                        showMusicPickerSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "music.note")
                                .font(.caption2)
                            Text(selectedMusicTrack.isEmpty ? "Thêm nhạc" : selectedMusicTrack)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selectedMusicTrack.isEmpty ? Color.black.opacity(0.45) : KinnectTheme.accent.opacity(0.85)))
                        .foregroundColor(.white)
                    }
                    .accessibilityLabel("Chọn nhạc nền cho bài đăng hoặc video")

                    Spacer()

                    Button {
                        isFlashOn.toggle()
                    } label: {
                        Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.caption)
                            .foregroundColor(isFlashOn ? KinnectTheme.warning : .white)
                            .padding(8)
                            .background(Circle().fill(Color.black.opacity(0.4)))
                    }

                    Text("9:16")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.2)))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer()

                // Bottom Controls: Library Picker, Shutter, Mode Selector
                VStack(spacing: 20) {
                    if cameraController.availableLenses.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(cameraController.availableLenses) { lens in
                                Button {
                                    cameraController.selectLens(lens, position: isUsingFrontCamera ? .front : .back)
                                } label: {
                                    Text(lens.title)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(cameraController.activeLens == lens ? Color.white : Color.black.opacity(0.45)))
                                        .foregroundColor(cameraController.activeLens == lens ? .black : .white)
                                }
                            }
                        }
                    }

                    // Creative Tool Adjustment Drawer (when a tool is selected)
                    if let tool = selectedCreativeTool {
                        creativeDrawer(for: tool)
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Creative Bar (Bộ lọc · Làm đẹp · Sticker) - Web & Android Parity
                    HStack(spacing: 36) {
                        creativeBarPill(tool: .filters, icon: "camera.filters")
                        creativeBarPill(tool: .beauty, icon: "sparkles")
                        creativeBarPill(tool: .stickers, icon: "face.smiling")
                    }
                    .padding(.vertical, 2)

                    HStack(spacing: 36) {
                        // Library Photos Picker
                        PhotosPicker(selection: $selectedLibraryItem, matching: .any(of: [.images, .videos])) {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.18))
                                        .frame(width: 48, height: 48)
                                    KinnectIcon(glyph: .photo, size: 22, tint: .white)
                                }
                                Text("Thư viện")
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.white)
                            }
                        }
                        .onChange(of: selectedLibraryItem) { item in
                            guard let item else { return }
                            Task { await loadMediaFromLibrary(item) }
                        }

                        // Primary Integrated Camera Shutter Button (Captures directly from AVCaptureSession without second picker)
                        Button {
                            if captureMode == .live {
                                showCreateLiveSheet = true
                            } else if captureMode == .video {
                                cameraController.toggleVideoRecording()
                            } else {
                                cameraController.capturePhoto(flash: isFlashOn)
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 76, height: 76)
                                if captureMode == .video && cameraController.isRecordingVideo {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.red)
                                        .frame(width: 34, height: 34)
                                } else {
                                    Circle()
                                        .fill(captureMode == .live ? KinnectTheme.danger : (captureMode == .video ? Color.red : Color.white))
                                        .frame(width: 62, height: 62)
                                }
                            }
                        }
                        .accessibilityLabel("Nút chụp hoặc quay video trực tiếp")

                        // Fast switch to toggle front/back camera
                        Button {
                            isUsingFrontCamera.toggle()
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.18))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "camera.rotate.fill")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                }
                                Text("Đổi góc")
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityLabel("Chuyển camera trước/sau")
                    }

                    // Mode Selector: ẢNH | VIDEO | LIVE (Android 1.2.12 build 118 Parity)
                    HStack(spacing: 28) {
                        ForEach(CaptureMode.allCases, id: \.self) { mode in
                            Button {
                                captureMode = mode
                                if mode == .live {
                                    showCreateLiveSheet = true
                                }
                            } label: {
                                Text(mode.rawValue)
                                    .font(.subheadline.weight(captureMode == mode ? .bold : .medium))
                                    .foregroundColor(captureMode == mode ? KinnectTheme.accentBright : .white.opacity(0.6))
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(
                                        captureMode == mode ?
                                            Capsule().fill(Color.white.opacity(0.15)) :
                                            Capsule().fill(Color.clear)
                                    )
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func creativeBarPill(tool: CreativeTool, icon: String) -> some View {
        let isSelected = selectedCreativeTool == tool
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                selectedCreativeTool = (selectedCreativeTool == tool ? nil : tool)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? KinnectTheme.accentBright : .white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(isSelected ? Color.white.opacity(0.3) : Color.black.opacity(0.45))
                    )
                Text(tool.rawValue)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isSelected ? KinnectTheme.accentBright : .white.opacity(0.9))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func creativeDrawer(for tool: CreativeTool) -> some View {
        VStack(spacing: 12) {
            switch tool {
            case .filters:
                // Filter intensity slider
                if activeFilter != "none" {
                    HStack(spacing: 12) {
                        Text("Độ đậm:")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        Slider(value: $filterIntensity, in: 0...1)
                            .tint(KinnectTheme.accentBright)
                        Text("\(Int(filterIntensity * 100))%")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                            .frame(width: 40)
                    }
                    .padding(.horizontal, 16)
                }

                // Horizontal scroll of filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Self.filterPresets, id: \.id) { f in
                            let isChosen = activeFilter == f.id
                            Button {
                                activeFilter = f.id
                            } label: {
                                VStack(spacing: 4) {
                                    filterThumbnail(for: f.id, initial: String(f.name.prefix(1)), isChosen: isChosen)
                                    Text(f.name)
                                        .font(.caption2.bold())
                                        .foregroundColor(isChosen ? KinnectTheme.accentBright : .white.opacity(0.85))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }

            case .beauty:
                // Active beauty slider
                HStack(spacing: 12) {
                    Text(beautyLabel(for: activeBeautyKey) + ":")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    Slider(
                        value: Binding(
                            get: { beautyValues[activeBeautyKey] ?? 0.5 },
                            set: { beautyValues[activeBeautyKey] = $0 }
                        ),
                        in: 0...1
                    )
                    .tint(KinnectTheme.accentBright)
                    Text("\(Int((beautyValues[activeBeautyKey] ?? 0.5) * 100))%")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                        .frame(width: 40)
                }
                .padding(.horizontal, 16)

                // 7 Beauty Tools from BeautyCatalog
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Self.beautyTools, id: \.key) { b in
                            let isChosen = activeBeautyKey == b.key
                            Button {
                                activeBeautyKey = b.key
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: b.icon)
                                        .font(.headline)
                                        .foregroundColor(isChosen ? KinnectTheme.accentBright : .white)
                                        .frame(width: 48, height: 48)
                                        .background(
                                            Circle().fill(isChosen ? Color.white.opacity(0.25) : Color.black.opacity(0.45))
                                        )
                                    Text(b.title)
                                        .font(.caption2.bold())
                                        .foregroundColor(isChosen ? KinnectTheme.accentBright : .white.opacity(0.85))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }

            case .stickers:
                // Stickers Grid / Row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Self.stickers, id: \.id) { s in
                            let isChosen = activeSticker == s.id
                            Button {
                                activeSticker = s.id
                            } label: {
                                VStack(spacing: 4) {
                                    if let img = stickerImage(for: s.id) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 36, height: 36)
                                            .frame(width: 52, height: 52)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .fill(isChosen ? KinnectTheme.accentBright.opacity(0.35) : Color.black.opacity(0.45))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 14)
                                                            .strokeBorder(isChosen ? KinnectTheme.accentBright : Color.white.opacity(0.2), lineWidth: 2)
                                                    )
                                            )
                                    } else {
                                        Text(s.emoji)
                                            .font(.system(size: 32))
                                            .frame(width: 52, height: 52)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .fill(isChosen ? KinnectTheme.accentBright.opacity(0.35) : Color.black.opacity(0.45))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 14)
                                                            .strokeBorder(isChosen ? KinnectTheme.accentBright : Color.white.opacity(0.2), lineWidth: 2)
                                                    )
                                            )
                                    }
                                    Text(s.name)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(isChosen ? KinnectTheme.accentBright : .white.opacity(0.85))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func filterAssetName(for id: String) -> String {
        let key: String
        switch id {
        case "none": key = "original"
        case "cool": key = "cold"
        case "mono": key = "bw"
        default: key = id
        }
        return "kg20261109_filter_\(key)"
    }

    @ViewBuilder
    private func filterThumbnail(for id: String, initial: String, isChosen: Bool) -> some View {
        let assetName = filterAssetName(for: id)
        ZStack {
            if let uiImg = UIImage(named: assetName) {
                Image(uiImage: uiImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 48, height: 48)
                Text(initial)
                    .font(.headline.bold())
                    .foregroundColor(isChosen ? KinnectTheme.accentBright : .white)
            }
            Circle()
                .strokeBorder(isChosen ? KinnectTheme.accentBright : Color.white.opacity(0.4), lineWidth: isChosen ? 3 : 1)
                .frame(width: 48, height: 48)
        }
    }

    private func stickerImage(for id: String) -> UIImage? {
        let mapping: [String: String] = [
            "bunny": "bunny_ears",
            "cat": "cat_whiskers",
            "dog": "dog_ears",
            "glasses": "neon_glasses",
            "crown": "golden_tiara",
            "flowers": "flower_crown",
            "hearts": "cheek_hearts",
            "sparkle": "sparkle_eyes",
            "halo": "angel_halo",
            "rainbow": "rainbow_paint",
            "stars": "star_confetti",
            "confetti": "star_confetti",
            "butterfly": "butterfly_clip",
            "devil": "cute_devil",
            "mask": "cyber_mask",
            "fire": "fire_aura",
            "music": "music_notes",
            "party": "party_hat",
            "pixel": "pixel_glasses",
            "retro": "retro_shades",
            "blush": "blush_cheeks"
        ]
        let key = mapping[id] ?? id
        return UIImage(named: "kg20261109_sticker_\(key)")
            ?? UIImage(named: "kg20261109_sticker_\(id)")
            ?? UIImage(named: "sticker_\(key)")
            ?? UIImage(named: "sticker_\(id)")
            ?? UIImage(contentsOfFile: Bundle.main.path(forResource: "sticker_\(id)", ofType: "png") ?? "")
            ?? UIImage(contentsOfFile: Bundle.main.path(forResource: "sticker_\(id)", ofType: "jpg") ?? "")
    }

    private func stickerOffset(for id: String) -> CGFloat {
        switch id {
        case "crown", "golden_tiara", "bunny", "bunny_ears", "cat", "cat_whiskers", "dog", "dog_ears", "flowers", "flower_crown", "halo", "angel_halo", "party_hat":
            return -140
        case "glasses", "neon_glasses", "round_glasses", "heart_glasses", "pixel_glasses", "retro_shades", "freckles", "cyber_mask", "mask":
            return -40
        case "hearts", "cheek_hearts", "blush_cheeks", "blush", "sparkle", "sparkle_eyes", "rainbow", "rainbow_paint":
            return -20
        case "lips", "bow":
            return 60
        default:
            return -70
        }
    }

    private func beautyLabel(for key: String) -> String {
        Self.beautyTools.first(where: { $0.key == key })?.title ?? "Cường độ"
    }

    // MARK: - Media Edit Mode (Real Mobile Editor with Parity to Android PhotoEditActivity)
    private var mediaEditMode: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header: Exit (top-left), Studio Pro Heading, Save to Photos, Studio Pro badge
                HStack(spacing: 8) {
                    KinnectIconButton(glyph: .close, label: "Thoát", tint: KinnectTheme.textPrimary) {
                        originalImage = nil
                        previewImage = nil
                        videoDataURL = ""
                        capturedVideoTempURL = nil
                        videoProject = nil
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Studio Pro")
                            .font(.headline.bold())
                            .foregroundColor(.white)
                        Text(capturedVideoTempURL != nil || !videoDataURL.isEmpty ? "Video" : "Ảnh")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }

                    Spacer()

                    if isVideoActive {
                        Button {
                            selectedTool = .audio
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "music.note")
                                    .font(.caption2.bold())
                                Text(videoProject?.musicTitle.isEmpty == false ? videoProject!.musicTitle : (selectedMusicTrack.isEmpty ? "Gán nhạc" : selectedMusicTrack))
                                    .font(.caption2.bold())
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(videoProject?.musicURL != nil || !selectedMusicTrack.isEmpty ? KinnectTheme.accentBright.opacity(0.85) : Color.white.opacity(0.15)))
                            .foregroundColor(.white)
                        }
                        .accessibilityLabel("Gán nhạc nền cho video")
                    }

                    // Studio Pro Template Sheet Trigger
                    Button {
                        showStudioProSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption.bold())
                            Text("Studio Pro")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(KinnectTheme.primaryGradient))
                        .foregroundColor(.white)
                    }
                    .accessibilityLabel("Mở bảng bộ lọc Studio Pro")

                    // Distinct Save Button (directly saves to Photos Library)
                    Button {
                        saveMediaToPhotos()
                    } label: {
                        HStack(spacing: 4) {
                            KinnectIcon(glyph: .save, size: 14, tint: .white)
                            Text("Lưu về máy")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.surfaceElevated))
                    }
                    .accessibilityLabel("Lưu vào thiết bị")
                }
                .padding(.horizontal, 4)

                // Large Media Stage (Zoomable Photo Canvas or Native AVPlayer)
                ZStack(alignment: .bottom) {
                    if let vURL = capturedVideoTempURL ?? (UIReviewFixture.activeScreen == "camera-studio-video-edit" ? UIReviewFixture.samplePlayableVideoURL() : nil) {
                        StudioVideoPlayerView(videoURL: vURL, videoProject: videoProject ?? StudioVideoProject(sourceURL: vURL), revisionId: videoCompositionRevision)
                            .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 340)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        let displayImg = isComparingOriginal
                            ? (originalImage ?? UIReviewFixture.samplePreviewImage())
                            : (previewImage ?? UIReviewFixture.samplePreviewImage())
                        Image(uiImage: displayImg)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 340)
                            .background(Color(red: 0.05, green: 0.04, blue: 0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(KinnectTheme.border, lineWidth: 1)
                            )
                    }

                    // Floating On-Stage Controls (Compare Original & Fit)
                    if capturedVideoTempURL == nil && videoDataURL.isEmpty {
                        HStack {
                            Button {
                                // Tap or hold to compare
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "eye.fill")
                                        .font(.caption2)
                                    Text(isComparingOriginal ? "Đang xem ảnh gốc" : "Giữ xem gốc")
                                        .font(.caption2.bold())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.black.opacity(0.75)))
                                .foregroundColor(isComparingOriginal ? KinnectTheme.accentBright : .white)
                            }
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in isComparingOriginal = true }
                                    .onEnded { _ in isComparingOriginal = false }
                            )
                            .accessibilityLabel("Giữ để xem ảnh gốc")

                            Spacer()

                            Button {
                                photoProject.cropRatio = .original
                                photoProject.rotation = 0
                                photoProject.flipHorizontal = false
                                updatePhotoPreview()
                            } label: {
                                Text("Vừa khung")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.black.opacity(0.75)))
                                    .foregroundColor(.white)
                            }
                            .accessibilityLabel("Vừa khung hình ảnh")
                        }
                        .padding(12)
                    }
                }

                // Studio Editor Tool Selector Strip (Crop & Rotate, Adjust, Smooth, Pro Filters)
                Picker("Công cụ chỉnh sửa", selection: $selectedTool) {
                    ForEach(StudioEditTool.allCases) { tool in
                        Text(tool.rawValue).tag(tool)
                    }
                }
                .pickerStyle(.segmented)

                // Tool Control Panel
                VStack(spacing: 12) {
                    switch selectedTool {
                    case .crop:
                        VStack(alignment: .leading, spacing: 10) {
                            if isVideoActive {
                                HStack {
                                    Text("Cắt thời lượng video (Trim):")
                                        .font(.caption.bold())
                                        .foregroundColor(KinnectTheme.textSecondary)
                                    Spacer()
                                    if let vp = videoProject {
                                        Text(String(format: "%.1fs - %.1fs (%.1fs)", vp.trimIn, vp.trimOut, max(0, vp.trimOut - vp.trimIn)))
                                            .font(.caption.bold())
                                            .foregroundColor(KinnectTheme.accentBright)
                                    }
                                }

                                if let vp = videoProject {
                                    VStack(spacing: 8) {
                                        HStack {
                                            Text(L10n.tr("Điểm đầu"))
                                                .font(.caption2)
                                                .foregroundColor(KinnectTheme.textSecondary)
                                                .frame(width: 50, alignment: .leading)
                                            Slider(value: Binding(get: { vp.trimIn }, set: { vp.trimIn = min($0, max(0, vp.trimOut - 0.5)) }), in: 0...max(1, vp.duration), step: 0.1)
                                                .tint(KinnectTheme.accentBright)
                                        }

                                        HStack {
                                            Text(L10n.tr("Điểm cuối"))
                                                .font(.caption2)
                                                .foregroundColor(KinnectTheme.textSecondary)
                                                .frame(width: 50, alignment: .leading)
                                            Slider(value: Binding(get: { vp.trimOut }, set: { vp.trimOut = max($0, min(vp.duration, vp.trimIn + 0.5)) }), in: 0...max(1, vp.duration), step: 0.1)
                                                .tint(KinnectTheme.accentBright)
                                        }
                                        HStack(spacing: 8) {
                                            Text("Tốc độ")
                                                .font(.caption2)
                                                .foregroundColor(KinnectTheme.textSecondary)
                                            ForEach([0.5, 1.0, 2.0], id: \.self) { rate in
                                                Button {
                                                    vp.playbackRate = rate
                                                    videoCompositionRevision = UUID().uuidString
                                                } label: {
                                                    Text(rate == 1 ? "1x" : String(format: "%.1fx", rate))
                                                        .font(.caption.bold())
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 6)
                                                        .background(Capsule().fill(abs(vp.playbackRate - rate) < 0.01 ? KinnectTheme.accentBright : KinnectTheme.surface))
                                                        .foregroundColor(.white)
                                                }
                                            }
                                        }
                                        TextField("Chữ trên video", text: $photoProject.overlayText)
                                            .padding(8)
                                            .background(RoundedRectangle(cornerRadius: 8).fill(KinnectTheme.surface))
                                            .foregroundColor(.white)
                                            .onChange(of: photoProject.overlayText) { _ in
                                                vp.overlayText = photoProject.overlayText
                                                videoCompositionRevision = UUID().uuidString
                                            }
                                    }
                                }

                                HStack(spacing: 12) {
                                    Button {
                                        photoProject.rotation = (photoProject.rotation + 90) % 360
                                        if let vp = videoProject {
                                            vp.rotation = photoProject.rotation
                                            videoCompositionRevision = UUID().uuidString
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "rotate.right.fill")
                                            Text(String(format: "%@ (%d°)", L10n.tr("Xoay 90°"), photoProject.rotation))
                                                .font(.caption.bold())
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                                        .foregroundColor(.white)
                                    }
                                    Spacer()
                                }
                            } else {
                                Text("Tỉ lệ khung hình:")
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.textSecondary)

                                HStack(spacing: 8) {
                                    ForEach(StudioCropRatio.allCases) { ratio in
                                        Button {
                                            photoProject.cropRatio = ratio
                                            updatePhotoPreview()
                                        } label: {
                                            Text(ratio.rawValue)
                                                .font(.caption.weight(photoProject.cropRatio == ratio ? .bold : .medium))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(photoProject.cropRatio == ratio ? KinnectTheme.accentBright : KinnectTheme.surfaceElevated)
                                                )
                                                .foregroundColor(.white)
                                        }
                                    }
                                }

                                Divider().background(KinnectTheme.border)

                                HStack(spacing: 16) {
                                    Button {
                                        photoProject.rotation = (photoProject.rotation + 90) % 360
                                        updatePhotoPreview()
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "rotate.right.fill")
                                            Text("Xoay 90° (\(photoProject.rotation)°)")
                                        }
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.surfaceElevated))
                                        .foregroundColor(.white)
                                    }

                                    Button {
                                        photoProject.flipHorizontal.toggle()
                                        updatePhotoPreview()
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                                            Text(photoProject.flipHorizontal ? "Đã lật" : "Lật ảnh")
                                        }
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.surfaceElevated))
                                        .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated.opacity(0.6)))

                    case .color:
                        VStack(spacing: 10) {
                            studioSliderRow(name: "Phơi sáng", value: $photoProject.exposure, range: -100...100)
                            studioSliderRow(name: "Vùng sáng", value: $photoProject.highlights, range: -100...100)
                            studioSliderRow(name: "Vùng tối", value: $photoProject.shadows, range: -100...100)
                            studioSliderRow(name: "Tương phản", value: $photoProject.contrast, range: -80...100)
                            studioSliderRow(name: "Độ rực", value: $photoProject.vibrance, range: -100...100)
                            studioSliderRow(name: "Bão hòa", value: $photoProject.saturation, range: -100...100)
                            studioSliderRow(name: "Nhiệt độ", value: $photoProject.warmth, range: -100...100)
                            studioSliderRow(name: "Curve", value: $photoProject.curveAmount, range: 0...100)

                            HStack {
                                Spacer()
                                Button("Đặt lại màu") {
                                    photoProject.resetColor()
                                    updatePhotoPreview()
                                }
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated.opacity(0.6)))

                    case .beauty:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Làm mịn da tự nhiên:")
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)

                            Text("Làm mịn theo tần số chỉ trên má, trán và cằm. Mắt, lông mày, môi và tóc được giữ nguyên khi nhận diện được khuôn mặt.")
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.textSecondary)

                            studioSliderRow(name: "Mức làm mịn", value: $photoProject.smooth, range: 0...100)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated.opacity(0.6)))

                    case .audio:
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "music.note")
                                    .foregroundColor(KinnectTheme.accentBright)
                                Text("Gán nhạc nền & Cân bằng âm thanh:")
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.textSecondary)
                                Spacer()
                            }

                            if isVideoActive, let vp = videoProject {
                                // Music track status card
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(KinnectTheme.accentBright.opacity(0.2))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: vp.musicURL != nil || !selectedMusicTrack.isEmpty ? "music.note.list" : "music.note")
                                            .font(.system(size: 20))
                                            .foregroundColor(KinnectTheme.accentBright)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(vp.musicTitle.isEmpty ? (selectedMusicTrack.isEmpty ? "Chưa chọn nhạc nền" : selectedMusicTrack) : vp.musicTitle)
                                            .font(.subheadline.bold())
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(vp.musicURL != nil || !vp.musicTitle.isEmpty || !selectedMusicTrack.isEmpty ? "Nhạc đã gán • Sẽ trộn vào video khi xuất" : "Nhấn để chọn bài hát hoặc tải từ máy")
                                            .font(.caption2)
                                            .foregroundColor(KinnectTheme.textSecondary)
                                    }

                                    Spacer()

                                    Button {
                                        showMusicPickerSheet = true
                                    } label: {
                                        Text(vp.musicURL != nil || !selectedMusicTrack.isEmpty ? "Đổi bài" : "Chọn nhạc")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Capsule().fill(KinnectTheme.primaryGradient))
                                    }
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surface))

                                if vp.musicURL != nil || !vp.musicTitle.isEmpty || !selectedMusicTrack.isEmpty {
                                    Button(role: .destructive) {
                                        vp.musicURL = nil
                                        vp.musicTitle = ""
                                        selectedMusicTrack = ""
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                            Text("Gỡ bỏ nhạc nền")
                                                .font(.caption.bold())
                                        }
                                        .foregroundColor(KinnectTheme.danger)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                    }
                                }

                                Divider().background(KinnectTheme.border)

                                // Audio volume controls
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: "video.fill")
                                            .font(.caption2)
                                            .foregroundColor(KinnectTheme.textSecondary)
                                        Text("Âm lượng âm thanh gốc: \(Int(vp.originalAudioVolume * 100))%")
                                            .font(.caption2.bold())
                                            .foregroundColor(KinnectTheme.textSecondary)
                                        Spacer()
                                    }
                                    Slider(value: $vp.originalAudioVolume, in: 0...1, step: 0.05)
                                        .tint(KinnectTheme.accentBright)

                                    HStack {
                                        Image(systemName: "music.note")
                                            .font(.caption2)
                                            .foregroundColor(KinnectTheme.accentBright)
                                        Text("Âm lượng nhạc nền: \(Int(vp.musicVolume * 100))%")
                                            .font(.caption2.bold())
                                            .foregroundColor(KinnectTheme.accentBright)
                                        Spacer()
                                    }
                                    Slider(value: $vp.musicVolume, in: 0...1, step: 0.05)
                                        .tint(KinnectTheme.accentBright)
                                }
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "music.note")
                                        .font(.title3)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                    Text("Công cụ âm thanh chỉ áp dụng cho Video đã quay hoặc chọn từ thư viện.")
                                        .font(.caption)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated.opacity(0.6)))

                    case .filters:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Mẫu màu Studio Pro:")
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(StudioProPack.allCases) { pack in
                                        Button {
                                            photoProject.proPack = pack
                                            updatePhotoPreview()
                                        } label: {
                                            Text(pack.rawValue)
                                                .font(.caption.weight(photoProject.proPack == pack ? .bold : .medium))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .fill(photoProject.proPack == pack ? KinnectTheme.accentBright : KinnectTheme.surfaceElevated)
                                                )
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated.opacity(0.6)))
                    }
                }

                // Target Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Đích đăng tải:")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.textSecondary)

                    Picker("Đích đăng", selection: $target) {
                        ForEach(PublishTarget.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Title & Caption
                if target == .shortVideo {
                    TextField("Tiêu đề video ngắn...", text: $title)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(.white)
                }

                TextField("Mô tả / Nội dung bài viết...", text: $caption, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(.white)

                // Publish Action Button
                Button {
                    Task { await publishContent() }
                } label: {
                    HStack(spacing: 8) {
                        Spacer()
                        if isUploading {
                            ProgressView().tint(.white)
                        } else {
                            KinnectIcon(glyph: .send, size: 20, selected: true, tint: .white)
                            Text("Dùng ảnh/video & Đăng ngay")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(KinnectTheme.primaryGradient)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isUploading)
            }
            .padding(16)
            .padding(.bottom, 36)
        }
        .navigationTitle("Chỉnh sửa Studio Pro")
    }

    private func studioSliderRow(name: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(name)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
            Slider(value: value, in: range, step: 1.0) {
                Text(name)
            } onEditingChanged: { editing in
                if !editing {
                    if isVideoActive {
                        if let vp = videoProject ?? (capturedVideoTempURL.map { StudioVideoProject(sourceURL: $0) }) {
                            syncVideoProjectSliders(to: vp)
                            videoCompositionRevision = UUID().uuidString
                        }
                    } else {
                        updatePhotoPreview()
                    }
                }
            }
            .tint(KinnectTheme.accentBright)
        }
    }

    private func updatePhotoPreview() {
        self.previewImage = self.photoProject.render(maxDimension: 900)
        if let jpeg = (self.previewImage ?? self.photoProject.originalImage).jpegData(compressionQuality: 0.85) {
            self.imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        }
    }

    // MARK: - CoreImage Filter Engine
    private func applyProFilter(named effect: String, to input: UIImage) -> UIImage {
        guard let ciInput = CIImage(image: input) else { return input }
        let context = CIContext(options: nil)
        var output: CIImage? = ciInput

        switch effect {
        case "Kinnect Vivid":
            output = ciInput.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.35,
                kCIInputContrastKey: 1.15
            ])
        case "Cinematic Teal & Orange":
            let cc = ciInput.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.2])
            output = cc.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 5200, y: 0)
            ])
        case "Mịn da tự nhiên (Beauty)":
            let blurred = ciInput.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4.5]).cropped(to: ciInput.extent)
            let diff = ciInput.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: blurred])
            let edgeMask = diff.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 2.0, kCIInputBrightnessKey: -0.1])
            output = ciInput.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: blurred,
                kCIInputImageKey: ciInput,
                kCIInputMaskImageKey: edgeMask
            ])
        case "Noir Cổ điển":
            output = ciInput.applyingFilter("CIPhotoEffectNoir")
        case "Ấm áp hoàng hôn":
            output = ciInput.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 7400, y: 0)
            ])
        default:
            output = ciInput
        }

        if let out = output, let cg = context.createCGImage(out, from: out.extent) {
            return UIImage(cgImage: cg, scale: input.scale, orientation: input.imageOrientation)
        }
        return input
    }

    // MARK: - Save Media to Device Camera Roll
    private func syncVideoProjectSliders(to vp: StudioVideoProject) {
        vp.brightness = photoProject.brightness
        vp.exposure = photoProject.exposure
        vp.highlights = photoProject.highlights
        vp.shadows = photoProject.shadows
        vp.contrast = photoProject.contrast
        vp.saturation = photoProject.saturation
        vp.vibrance = photoProject.vibrance
        vp.warmth = photoProject.warmth
        vp.tint = photoProject.tint
        vp.smooth = photoProject.smooth
        vp.sharpness = photoProject.sharpness
        vp.clarity = photoProject.clarity
        vp.curveAmount = photoProject.curveAmount
        vp.grain = photoProject.grain
        vp.proTemplate = photoProject.proTemplate
        vp.proPack = photoProject.proPack
        vp.overlayText = photoProject.overlayText
    }

    private func saveMediaToPhotos() {
        if isVideoActive {
            guard let vp = videoProject ?? (capturedVideoTempURL.map { StudioVideoProject(sourceURL: $0) }) else {
                appState.showToast(L10n.tr("Không tìm thấy video để lưu."))
                return
            }
            syncVideoProjectSliders(to: vp)
            Task {
                var targetURL = vp.sourceURL
                if vp.hasEdits {
                    do {
                        appState.showToast(L10n.tr("Đang xuất video qua Studio Pro..."))
                        targetURL = try await vp.exportVideo()
                    } catch {
                        appState.showToast("Không thể xuất video: \(error.localizedDescription)")
                        return
                    }
                }
                PhotoSaveCoordinator.shared.onComplete = { success, error in
                    if success {
                        appState.showToast(L10n.tr("Đã lưu video đã chỉnh sửa vào Album ảnh trên thiết bị."))
                    } else {
                        appState.showToast("Không thể lưu video: \(error?.localizedDescription ?? "Lỗi quyền truy cập")")
                    }
                }
                UISaveVideoAtPathToSavedPhotosAlbum(
                    targetURL.path,
                    PhotoSaveCoordinator.shared,
                    #selector(PhotoSaveCoordinator.video(_:didFinishSavingWithError:contextInfo:)),
                    nil
                )
            }
        } else {
            let img = previewImage ?? photoProject.originalImage
            PhotoSaveCoordinator.shared.onComplete = { success, error in
                if success {
                    appState.showToast(L10n.tr("Đã lưu ảnh vào Album ảnh trên thiết bị."))
                } else {
                    appState.showToast("Không thể lưu ảnh: \(error?.localizedDescription ?? "Lỗi quyền truy cập")")
                }
            }
            UIImageWriteToSavedPhotosAlbum(
                img,
                PhotoSaveCoordinator.shared,
                #selector(PhotoSaveCoordinator.image(_:didFinishSavingWithError:contextInfo:)),
                nil
            )
        }
    }

    private func loadMediaFromLibrary(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            if let uiImg = UIImage(data: data) {
                self.originalImage = uiImg
                self.previewImage = uiImg
                self.capturedVideoTempURL = nil
                self.videoDataURL = ""
                self.target = .feedPost
                if let jpeg = uiImg.jpegData(compressionQuality: 0.75) {
                    self.imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                }
            } else {
                if data.count > 8 * 1024 * 1024 {
                    appState.showToast("Video vượt quá giới hạn 8MB.")
                    return
                }
                // Save to persistent local temp file so AVPlayer can play real local media
                let tempDir = FileManager.default.temporaryDirectory
                let destURL = tempDir.appendingPathComponent("picked_video_\(UUID().uuidString).mp4")
                try? data.write(to: destURL)
                self.capturedVideoTempURL = destURL
                self.videoDataURL = "data:video/mp4;base64,\(data.base64EncodedString())"
                self.previewImage = nil
                self.originalImage = nil
                self.target = .shortVideo
                let vp = StudioVideoProject(sourceURL: destURL)
                self.videoProject = vp
                self.syncVideoProjectSliders(to: vp)
            }
        }
    }

    private func publishContent() async {
        isUploading = true
        defer { isUploading = false }
        let reqId = "studio_\(UUID().uuidString)"
        let cleanCap = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCaption = cleanCap

        do {
            switch target {
            case .shortVideo:
                guard !videoDataURL.isEmpty || capturedVideoTempURL != nil || videoProject != nil else {
                    appState.showToast("Vui lòng quay hoặc chọn một video MP4 (< 8MB).")
                    return
                }
                var finalVideoDataURL = videoDataURL

                if let vp = videoProject ?? (capturedVideoTempURL.map { StudioVideoProject(sourceURL: $0) }) {
                    syncVideoProjectSliders(to: vp)
                    if vp.hasEdits {
                        do {
                            appState.showToast("Đang áp dụng hiệu ứng và xuất video...")
                            let exportedURL = try await vp.exportVideo()
                            let data = try Data(contentsOf: exportedURL)
                            finalVideoDataURL = "data:video/mp4;base64," + data.base64EncodedString()
                        } catch {
                            appState.showToast("Lỗi xuất video: \(error.localizedDescription)")
                            return
                        }
                    }
                }

                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/shorts",
                    method: "POST",
                body: KinnectWriteBody.shortVideo(caption: finalCaption, dataURL: finalVideoDataURL),
                    requestId: reqId
                )
                appState.showToast("Đã đăng video ngắn thành công!")
                dismiss()

            case .feedPost:
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/posts",
                    method: "POST",
                body: KinnectWriteBody.post(text: finalCaption, category: "community", mediaDataURL: imageDataURL),
                    requestId: reqId
                )
                appState.showToast("Đã đăng bài viết mới!")
                dismiss()

            case .story:
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/stories",
                    method: "POST",
                body: KinnectWriteBody.story(text: finalCaption, colorHex: "#7C3AED", mediaDataURL: imageDataURL),
                    requestId: reqId
                )
                appState.showToast("Đã đăng tin 24h!")
                dismiss()
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct StudioMusicPickerSheet: View {
    @Binding var selectedTrack: String
    var onSelectTrack: ((String, URL?) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showAudioFilePicker = false
    @State private var playingTrackTitle: String? = nil
    @State private var previewPlayer: AVPlayer? = nil

    private let curatedTracks: [(id: String, title: String, subtitle: String, duration: String)] = [
        ("lofi_saigon", "Lofi Chill Sài Gòn", "Giai điệu thư giãn nhẹ nhàng • 85 BPM", "0:45"),
        ("acoustic_banmai", "Acoustic Ban Mai", "Guitar mộc trong sáng • 98 BPM", "0:50"),
        ("synthwave_dem", "Synthwave Đêm", "Năng động hiện đại • 118 BPM", "1:00"),
        ("piano_muathu", "Piano Mùa Thu", "Cảm xúc sâu lắng • 76 BPM", "0:40"),
        ("edm_energy", "EDM Festival Energy", "Sôi động bùng nổ • 128 BPM", "0:55")
    ]

    var body: some View {
        List {
            Section("Tệp âm thanh trên máy") {
                Button {
                    showAudioFilePicker = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(KinnectTheme.accentBright.opacity(0.2))
                                .frame(width: 38, height: 38)
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(KinnectTheme.accentBright)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chọn tệp âm thanh từ thiết bị...")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                            Text("Hỗ trợ MP3, M4A, WAV, AAC từ Tệp & iCloud")
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .frame(minHeight: 44)
                }
            }

            Section("Nhạc nền Kinnect đề xuất") {
                // Remove music option
                Button {
                    stopPreview()
                    selectedTrack = ""
                    onSelectTrack?("", nil)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.slash.fill")
                            .foregroundColor(selectedTrack.isEmpty ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Không dùng nhạc nền")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                            Text("Chỉ sử dụng âm thanh gốc từ video")
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        Spacer()
                        if selectedTrack.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(KinnectTheme.accentBright)
                        }
                    }
                    .frame(minHeight: 44)
                }

                ForEach(curatedTracks, id: \.id) { track in
                    HStack(spacing: 12) {
                        Button {
                            togglePreview(for: track.title)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(playingTrackTitle == track.title ? KinnectTheme.accentBright : KinnectTheme.surfaceElevated)
                                    .frame(width: 36, height: 36)
                                Image(systemName: playingTrackTitle == track.title ? "pause.fill" : "play.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Nghe thử \(track.title)")

                        Button {
                            stopPreview()
                            selectedTrack = track.title
                            let audioURL = UIReviewFixture.sampleAudioURL(named: track.title)
                            onSelectTrack?(track.title, audioURL)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                    Text(track.subtitle)
                                        .font(.caption2)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                }
                                Spacer()
                                Text(track.duration)
                                    .font(.caption2)
                                    .foregroundColor(KinnectTheme.textSecondary)
                                    .padding(.trailing, 4)

                                if selectedTrack == track.title {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(KinnectTheme.accentBright)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KinnectTheme.background)
        .navigationTitle("Thêm nhạc nền")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Đóng") {
                    stopPreview()
                    dismiss()
                }
            }
        }
        .fileImporter(isPresented: $showAudioFilePicker, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let fileURL):
                guard fileURL.startAccessingSecurityScopedResource() else { return }
                defer { fileURL.stopAccessingSecurityScopedResource() }
                let ext = fileURL.pathExtension
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("Kinnect-Music-\(UUID().uuidString).\(ext)")
                if let data = try? Data(contentsOf: fileURL) {
                    try? data.write(to: dest)
                    let name = fileURL.deletingPathExtension().lastPathComponent
                    selectedTrack = name
                    onSelectTrack?(name, dest)
                    dismiss()
                }
            case .failure(let err):
                print("Lỗi chọn tệp âm thanh: \(err.localizedDescription)")
            }
        }
        .onDisappear {
            stopPreview()
        }
    }

    private func togglePreview(for title: String) {
        if playingTrackTitle == title {
            stopPreview()
        } else {
            playingTrackTitle = title
            let audioURL = UIReviewFixture.sampleAudioURL(named: title)
            previewPlayer = AVPlayer(url: audioURL)
            previewPlayer?.play()
        }
    }

    private func stopPreview() {
        playingTrackTitle = nil
        previewPlayer?.pause()
        previewPlayer = nil
    }
}

struct StudioProSheet: View {
    @Binding var appliedEffect: String
    let onApply: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let proFilters = StudioProPack.allCases.map(\.rawValue)

    var body: some View {
        Form {
            Section("Công nghệ Kinnect Studio Pro") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(KinnectTheme.accentBright)
                        Text("Xử lý chất lượng hình ảnh & video cao cấp")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    Text("Áp dụng bộ lọc màu cinematic và thuật toán tăng cường chi tiết bằng CoreImage CIFilter.")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .padding(.vertical, 4)
            }

            Section("Bộ lọc màu & Hiệu ứng Pro") {
                ForEach(proFilters, id: \.self) { filter in
                    Button {
                        onApply(filter)
                        dismiss()
                    } label: {
                        HStack {
                            Text(filter)
                                .foregroundColor(filter == appliedEffect ? KinnectTheme.accentBright : .white)
                            Spacer()
                            if filter == appliedEffect {
                                Image(systemName: "checkmark")
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
        }
        .navigationTitle("Kinnect Studio Pro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Đóng") { dismiss() }
                    .foregroundColor(KinnectTheme.accentBright)
            }
        }
    }
}

// MARK: - Integrated AVFoundation Capture Controller & Preview
enum StudioLens: String, CaseIterable, Identifiable {
    case ultraWide
    case wide
    case tele

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ultraWide: return "0.5"
        case .wide: return "1x"
        case .tele: return "2x"
        }
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide: return .builtInWideAngleCamera
        case .tele: return .builtInTelephotoCamera
        }
    }
}

final class CameraCaptureController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let movieOutput = AVCaptureMovieFileOutput()
    @Published var isRecordingVideo: Bool = false
    @Published var availableLenses: [StudioLens] = []
    @Published var activeLens: StudioLens = .wide
    @Published var exposureBias: Float = 0

    var onCapturedImage: ((UIImage) -> Void)?
    var onCapturedVideoData: ((Data, URL) -> Void)?
    private var isConfigured = false
    private var currentPosition: AVCaptureDevice.Position = .back

    func configureIfAuthorized() {
        #if !targetEnvironment(simulator)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized else { return }
        if isConfigured {
            start()
            return
        }
        isConfigured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice), session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        applyStabilization()
        session.commitConfiguration()
        refreshLenses(position: .back)
        NotificationCenter.default.addObserver(self, selector: #selector(stopForInterruption), name: UIApplication.willResignActiveNotification, object: nil)
        start()
        #endif
    }

    func start() {
        #if !targetEnvironment(simulator)
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
        #endif
    }

    func stop() {
        #if !targetEnvironment(simulator)
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        if session.isRunning {
            session.stopRunning()
        }
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        #endif
    }

    deinit {
        stop()
    }

    @objc private func stopForInterruption() {
        #if !targetEnvironment(simulator)
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        #endif
    }

    func refreshLenses(position: AVCaptureDevice.Position) {
        currentPosition = position
        let found = StudioLens.allCases.filter {
            AVCaptureDevice.default($0.deviceType, for: .video, position: position) != nil
        }
        availableLenses = found.isEmpty ? [.wide] : found
        if !availableLenses.contains(activeLens) {
            activeLens = availableLenses.contains(.wide) ? .wide : availableLenses[0]
        }
    }

    func selectLens(_ lens: StudioLens, position: AVCaptureDevice.Position) {
        #if !targetEnvironment(simulator)
        guard let device = AVCaptureDevice.default(lens.deviceType, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        for existing in session.inputs {
            if let devInput = existing as? AVCaptureDeviceInput, devInput.device.hasMediaType(.video) {
                session.removeInput(devInput)
            }
        }
        if session.canAddInput(input) {
            session.addInput(input)
            activeLens = lens
        }
        applyStabilization()
        session.commitConfiguration()
        #endif
    }

    func focus(at devicePoint: CGPoint) {
        #if !targetEnvironment(simulator)
        guard let device = currentVideoDevice() else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            return
        }
        #endif
    }

    func setExposureBias(_ bias: Float) {
        #if !targetEnvironment(simulator)
        guard let device = currentVideoDevice() else { return }
        let clamped = min(device.maxExposureTargetBias, max(device.minExposureTargetBias, bias))
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clamped, completionHandler: nil)
            device.unlockForConfiguration()
            exposureBias = clamped
        } catch {
            return
        }
        #endif
    }

    private func currentVideoDevice() -> AVCaptureDevice? {
        session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first { $0.device.hasMediaType(.video) }?.device
    }

    func applyStabilization() {
        guard let connection = movieOutput.connection(with: .video), connection.isVideoStabilizationSupported else { return }
        connection.preferredVideoStabilizationMode = .cinematic
    }

    func capturePhoto(flash: Bool) {
        #if !targetEnvironment(simulator)
        if session.isRunning && !photoOutput.connections.isEmpty {
            let settings: AVCapturePhotoSettings
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
            if photoOutput.supportedFlashModes.contains(flash ? .on : .off) {
                settings.flashMode = flash ? .on : .off
            }
            photoOutput.capturePhoto(with: settings, delegate: self)
            return
        }
        #endif
        let fallback = UIReviewFixture.samplePreviewImage()
        DispatchQueue.main.async { [weak self] in
            self?.onCapturedImage?(fallback)
        }
    }

    func toggleVideoRecording() {
        #if !targetEnvironment(simulator)
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            DispatchQueue.main.async { self.isRecordingVideo = false }
            return
        }
        if session.isRunning && !movieOutput.connections.isEmpty {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("kinnect_capture_\(UUID().uuidString).mp4")
            movieOutput.startRecording(to: tempURL, recordingDelegate: self)
            DispatchQueue.main.async { self.isRecordingVideo = true }
            return
        }
        #endif
        if isRecordingVideo {
            isRecordingVideo = false
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("kinnect_sim_\(UUID().uuidString).mp4")
            let dummyMP4 = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x32, 0x00, 0x00, 0x00, 0x00, 0x6D, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6F, 0x6D])
            try? dummyMP4.write(to: tempURL)
            onCapturedVideoData?(dummyMP4, tempURL)
        } else {
            isRecordingVideo = true
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let img = UIImage(data: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onCapturedImage?(img)
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isRecordingVideo = false
            guard error == nil, let data = try? Data(contentsOf: outputFileURL) else { return }
            self?.onCapturedVideoData?(data, outputFileURL)
        }
    }
}

struct LiveCameraPreviewView: UIViewControllerRepresentable {
    @ObservedObject var controller: CameraCaptureController
    @Binding var isFlashOn: Bool
    @Binding var isUsingFrontCamera: Bool

    func makeUIViewController(context: Context) -> CameraPreviewViewController {
        let vc = CameraPreviewViewController()
        vc.controller = controller
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraPreviewViewController, context: Context) {
        uiViewController.setCamera(front: isUsingFrontCamera)
        uiViewController.setFlash(on: isFlashOn)
    }
}

final class CameraPreviewViewController: UIViewController {
    var controller: CameraCaptureController?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let backdropLayer = CAGradientLayer()
    private let gridLayer = CAShapeLayer()
    private var simulatedImageView: UIImageView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.04, blue: 0.09, alpha: 1.0)
        setupViewfinderBackdrop()
        setupSessionIfAuthorized()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupSessionIfAuthorized()
        controller?.configureIfAuthorized()
        controller?.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdropLayer.frame = view.bounds
        simulatedImageView?.frame = view.bounds
        updateGridPath()
        previewLayer?.frame = view.bounds
    }

    private func setupViewfinderBackdrop() {
        backdropLayer.colors = [
            UIColor(red: 0.11, green: 0.07, blue: 0.22, alpha: 1.0).cgColor,
            UIColor(red: 0.04, green: 0.03, blue: 0.08, alpha: 1.0).cgColor,
            UIColor(red: 0.09, green: 0.05, blue: 0.16, alpha: 1.0).cgColor
        ]
        backdropLayer.locations = [0.0, 0.55, 1.0]
        view.layer.addSublayer(backdropLayer)

        #if targetEnvironment(simulator)
        let sim = UIImageView(image: UIReviewFixture.samplePreviewImage())
        sim.contentMode = .scaleAspectFill
        sim.clipsToBounds = true
        sim.frame = view.bounds
        view.addSubview(sim)
        simulatedImageView = sim
        #endif

        // Grid & Crosshair overlay matching Google Camera in Android StudioActivity
        gridLayer.strokeColor = UIColor(red: 0xFD / 255.0, green: 0xD6 / 255.0, blue: 0x63 / 255.0, alpha: 0.65).cgColor
        gridLayer.lineWidth = 1.0
        gridLayer.fillColor = UIColor.clear.cgColor
        view.layer.addSublayer(gridLayer)
    }

    private func updateGridPath() {
        let w = view.bounds.width
        let h = view.bounds.height
        guard w > 0, h > 0 else { return }
        let path = UIBezierPath()

        // 3x3 Grid
        path.move(to: CGPoint(x: w / 3, y: 0))
        path.addLine(to: CGPoint(x: w / 3, y: h))
        path.move(to: CGPoint(x: 2 * w / 3, y: 0))
        path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
        path.move(to: CGPoint(x: 0, y: h / 3))
        path.addLine(to: CGPoint(x: w, y: h / 3))
        path.move(to: CGPoint(x: 0, y: 2 * h / 3))
        path.addLine(to: CGPoint(x: w, y: 2 * h / 3))

        // Amber balance center crosshair (+) matching Android StudioActivity lines 1795-1803
        let cx = w / 2
        let cy = h / 2
        let cross: CGFloat = 12
        path.move(to: CGPoint(x: cx - cross, y: cy))
        path.addLine(to: CGPoint(x: cx + cross, y: cy))
        path.move(to: CGPoint(x: cx, y: cy - cross))
        path.addLine(to: CGPoint(x: cx, y: cy + cross))

        // Center balance ring
        path.addArc(withCenter: CGPoint(x: cx, y: cy), radius: 18, startAngle: 0, endAngle: .pi * 2, clockwise: true)

        gridLayer.path = path.cgPath
    }

    private func setupSessionIfAuthorized() {
        #if !targetEnvironment(simulator)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            if previewLayer == nil {
                attachHardwarePreview()
            }
        } else if status == .notDetermined && !UIReviewFixture.isEnabled {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async {
                    self?.attachHardwarePreview()
                }
            }
        }
        #endif
    }

    private func attachHardwarePreview() {
        #if !targetEnvironment(simulator)
        guard let ctrl = controller else { return }
        ctrl.configureIfAuthorized()
        let layer = AVCaptureVideoPreviewLayer(session: ctrl.session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, above: backdropLayer)
        previewLayer = layer
        simulatedImageView?.removeFromSuperview()
        simulatedImageView = nil
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleFocusTap(_:)))
        view.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleExposurePan(_:)))
        view.addGestureRecognizer(pan)
        #endif
    }

    @objc private func handleFocusTap(_ gesture: UITapGestureRecognizer) {
        guard let previewLayer else { return }
        let point = previewLayer.captureDevicePointConverted(fromLayerPoint: gesture.location(in: view))
        controller?.focus(at: point)
    }

    @objc private func handleExposurePan(_ gesture: UIPanGestureRecognizer) {
        let delta = Float(-gesture.translation(in: view).y / 120)
        controller?.setExposureBias((controller?.exposureBias ?? 0) + delta)
        gesture.setTranslation(.zero, in: view)
    }

    func setCamera(front: Bool) {
        #if !targetEnvironment(simulator)
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let session = controller?.session else { return }
        session.beginConfiguration()
        for input in session.inputs {
            if let devInput = input as? AVCaptureDeviceInput, devInput.device.hasMediaType(.video) {
                session.removeInput(devInput)
            }
        }
        let pos: AVCaptureDevice.Position = front ? .front : .back
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        controller?.applyStabilization()
        session.commitConfiguration()
        controller?.refreshLenses(position: pos)
        controller?.activeLens = .wide
        #endif
    }

    func setFlash(on: Bool) {
        #if !targetEnvironment(simulator)
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
        #endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        #if !targetEnvironment(simulator)
        if let session = controller?.session, session.isRunning {
            session.stopRunning()
        }
        #endif
    }
}

final class PhotoSaveCoordinator: NSObject {
    static let shared = PhotoSaveCoordinator()
    var onComplete: ((Bool, Error?) -> Void)?

    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        DispatchQueue.main.async { [weak self] in
            if let error {
                self?.onComplete?(false, error)
            } else {
                self?.onComplete?(true, nil)
            }
        }
    }

    @objc func video(_ videoPath: String, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        DispatchQueue.main.async { [weak self] in
            if let error {
                self?.onComplete?(false, error)
            } else {
                self?.onComplete?(true, nil)
            }
        }
    }
}

// MARK: - Dedicated Native Video Player with AVPlayer & Integrated Controls
struct StudioVideoPlayerView: View {
    let videoURL: URL
    var videoProject: StudioVideoProject? = nil
    var revisionId: String = ""
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isMuted: Bool = false
    @State private var timeObserverToken: Any?
    @State private var endObserverToken: (any NSObjectProtocol)? = nil
    @State private var metadataTask: Task<Void, Never>? = nil
    @State private var videoResolution: String = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            // Native AVPlayer Rendering Layer
            if let p = player {
                VideoPlayer(player: p)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(KinnectTheme.border, lineWidth: 1)
                    )
            } else {
                Color.black
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(ProgressView().tint(.white))
            }

            // Integrated Interactive Controls
            VStack(spacing: 8) {
                // Top Metadata Bar (Derived from Asset Tracks)
                HStack {
                    if !videoResolution.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "film.fill")
                                .font(.system(size: 10))
                            Text(videoResolution)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .foregroundColor(.white)
                    }

                    Spacer()

                    Button {
                        isMuted.toggle()
                        player?.isMuted = isMuted
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.65)))
                    }
                    .accessibilityLabel(isMuted ? "Bật âm thanh" : "Tắt âm thanh")
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Spacer()

                // Center Play/Pause Toggle
                Button {
                    togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50, weight: .light))
                        .foregroundColor(.white.opacity(isPlaying ? 0.85 : 0.95))
                        .shadow(color: .black.opacity(0.6), radius: 8)
                }
                .accessibilityLabel(isPlaying ? "Tạm dừng video" : "Phát video")

                Spacer()

                // Bottom Timeline Scrubber & Counter
                VStack(spacing: 6) {
                    // Scrubber Bar
                    GeometryReader { geo in
                        let progress = duration > 0 ? (currentTime / duration) : 0
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 5)

                            Capsule()
                                .fill(KinnectTheme.primaryGradient)
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(progress))), height: 5)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    let fraction = max(0, min(1, val.location.x / geo.size.width))
                                    let targetTime = fraction * duration
                                    seek(to: targetTime)
                                }
                        )
                    }
                    .frame(height: 5)

                    HStack {
                        Text(formatDuration(currentTime))
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundColor(.white)

                        Spacer()

                        Text(formatDuration(duration))
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 320)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
        .onChange(of: videoURL) { _ in
            teardownPlayer()
            setupPlayer()
        }
        .onChange(of: revisionId) { _ in
            guard let curItem = player?.currentItem else { return }
            if let vp = videoProject, vp.hasEdits {
                curItem.videoComposition = vp.makeVideoComposition(for: curItem.asset)
            } else {
                curItem.videoComposition = nil
            }
        }
    }

    private func setupPlayer() {
        let asset = AVURLAsset(url: videoURL)
        let item = AVPlayerItem(asset: asset)
        if let vp = videoProject, vp.hasEdits {
            item.videoComposition = vp.makeVideoComposition(for: asset)
        }
        let p = AVPlayer(playerItem: item)
        p.isMuted = isMuted
        self.player = p

        // Load asset tracks metadata asynchronously
        metadataTask = Task {
            let asset = AVURLAsset(url: videoURL)
            if let d = try? await asset.load(.duration) {
                let sec = CMTimeGetSeconds(d)
                if sec.isFinite && sec > 0 && !Task.isCancelled {
                    await MainActor.run { self.duration = sec }
                }
            }
            if let tracks = try? await asset.loadTracks(withMediaType: .video), let firstTrack = tracks.first {
                var labels: [String] = []
                if let size = try? await firstTrack.load(.naturalSize) {
                    let w = Int(size.width)
                    let h = Int(size.height)
                    if w > 0 && h > 0 {
                        labels.append("\(min(w, h))p")
                    }
                }
                if let fps = try? await firstTrack.load(.nominalFrameRate), fps > 0 {
                    labels.append(String(format: "%.0ffps", fps))
                }
                if !labels.isEmpty && !Task.isCancelled {
                    let fullLabel = labels.joined(separator: " • ")
                    await MainActor.run { self.videoResolution = fullLabel }
                }
            }
        }

        // Add periodic time observer (10Hz)
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
            guard p != nil else { return }
            let sec = CMTimeGetSeconds(time)
            if sec.isFinite {
                self.currentTime = sec
            }
        }

        // Observe end of playback using retained token to prevent memory leak
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem,
            queue: .main
        ) { [weak p] _ in
            p?.seek(to: .zero)
            p?.play()
            self.isPlaying = true
        }

        p.play()
        isPlaying = true
    }

    private func teardownPlayer() {
        metadataTask?.cancel()
        metadataTask = nil

        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
        if let token = timeObserverToken, let p = player {
            p.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
    }

    private func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        guard let p = player, seconds.isFinite else { return }
        let targetCM = CMTime(seconds: seconds, preferredTimescale: 600)
        p.seek(to: targetCM, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    private func formatDuration(_ sec: Double) -> String {
        guard sec.isFinite && sec >= 0 else { return "00:00" }
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
