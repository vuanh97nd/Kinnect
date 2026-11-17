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
    @State private var selectedMusicURL: URL?
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
    var onClose: (() -> Void)? = nil

    init(initialMode: CaptureMode = .photo, onClose: (() -> Void)? = nil) {
        _captureMode = State(initialValue: initialMode)
        self.onClose = onClose
    }

    private func closeCameraView() {
        cameraController.stop()
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
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
            Task {
                _ = await MediaPermissionHandler.shared.requestCameraAccess()
                _ = await MediaPermissionHandler.shared.requestMicrophoneAccess()
                cameraController.configureIfAuthorized()
                cameraController.start()
            }
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
                    vp.musicURL = self.selectedMusicURL
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
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .sheet(isPresented: $showMusicPickerSheet) {
            NavigationStack {
                StudioMusicPickerSheet(
                    selectedTrack: $selectedMusicTrack,
                    onSelectTrack: { title, url in
                        selectedMusicTrack = title
                        selectedMusicURL = url
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
        .fullScreenCover(isPresented: $showCreateLiveSheet) {
            CreateLiveRoomSheet(
                initialLiveMode: "chat",
                onStarted: {
                    closeCameraView()
                }
            )
        }
        .onChange(of: showCreateLiveSheet) { isOpen in
            if isOpen {
                cameraController.stop()
            } else if !cameraController.isRecordingVideo && previewImage == nil && videoDataURL.isEmpty {
                cameraController.configureIfAuthorized()
                cameraController.start()
            }
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

            if cameraController.isPermissionDenied {
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Cần quyền truy cập Camera")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)
                    Text("Vui lòng cấp quyền Camera và Micro trong Cài đặt iPhone để chụp ảnh, quay video và phát trực tiếp.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Mở Cài đặt iPhone")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.white))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.85))
                .zIndex(15)
            }

            VStack(spacing: 0) {
                // Top Camera Chrome: Close, Aspect ratio 9:16, Music, Flash
                HStack(spacing: 16) {
                    KinnectIconButton(glyph: .close, label: "Thoát Camera", tint: .white) {
                        closeCameraView()
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
                                        .padding(.horizontal, 12)
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
                    .font(KinnectTheme.scaled(20, weight: .semibold))
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
                    .padding(.horizontal, 16)
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
                    .padding(.horizontal, 16)
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
                    .padding(.horizontal, 16)
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
    @ViewBuilder
    private var mediaEditHeader: some View {
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(videoProject?.musicURL != nil || !selectedMusicTrack.isEmpty ? KinnectTheme.accentBright.opacity(0.85) : Color.white.opacity(0.15)))
                    .foregroundColor(.white)
                }
                .accessibilityLabel("Gán nhạc nền cho video")
            }

            Button {
                showStudioProSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption.bold())
                    Text("Studio Pro")
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(KinnectTheme.primaryGradient))
                .foregroundColor(.white)
            }
            .accessibilityLabel("Mở bảng bộ lọc Studio Pro")

            Button {
                saveMediaToPhotos()
            } label: {
                HStack(spacing: 4) {
                    KinnectIcon(glyph: .save, size: 14, tint: .white)
                    Text("Lưu về máy")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.surfaceElevated))
            }
            .accessibilityLabel("Lưu vào thiết bị")
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var mediaEditStage: some View {
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
                    .background(KinnectTheme.studioCanvasDark)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(KinnectTheme.border, lineWidth: 1)
                    )
            }

            if capturedVideoTempURL == nil && videoDataURL.isEmpty {
                HStack {
                    Button {} label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                                .font(.caption2)
                            Text(isComparingOriginal ? "Đang xem ảnh gốc" : "Giữ xem gốc")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 12)
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
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.75)))
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel("Vừa khung hình ảnh")
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private var mediaEditToolSelector: some View {
        Picker("Công cụ chỉnh sửa", selection: $selectedTool) {
            ForEach(StudioEditTool.allCases) { tool in
                Text(tool.rawValue).tag(tool)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var mediaEditToolPanel: some View {
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
                                    ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { rate in
                                        Button("\(String(format: "%.1fx", rate))") {
                                            vp.playbackRate = rate
                                        }
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(abs(vp.playbackRate - rate) < 0.05 ? KinnectTheme.accentBright : KinnectTheme.surfaceElevated))
                                        .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                photoProject.rotation = (photoProject.rotation + 270) % 360
                                updatePhotoPreview()
                            } label: {
                                Label("Xoay trái", systemImage: "rotate.left")
                                    .font(.caption.bold())
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(KinnectTheme.surfaceElevated))
                                    .foregroundColor(.white)
                            }

                            Button {
                                photoProject.rotation = (photoProject.rotation + 90) % 360
                                updatePhotoPreview()
                            } label: {
                                Label("Xoay phải", systemImage: "rotate.right")
                                    .font(.caption.bold())
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(KinnectTheme.surfaceElevated))
                                    .foregroundColor(.white)
                            }

                            Button {
                                photoProject.flipHorizontal.toggle()
                                updatePhotoPreview()
                            } label: {
                                Label("Lật", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                                    .font(.caption.bold())
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(KinnectTheme.surfaceElevated))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated.opacity(0.6)))

            case .color:
                VStack(spacing: 10) {
                    studioSliderRow(name: "Độ sáng", value: $photoProject.brightness, range: -50...50)
                    studioSliderRow(name: "Độ tương phản", value: $photoProject.contrast, range: -50...50)
                    studioSliderRow(name: "Độ bão hòa", value: $photoProject.saturation, range: -50...50)
                    studioSliderRow(name: "Độ ấm", value: $photoProject.warmth, range: -50...50)
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
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(KinnectTheme.accentBright.opacity(0.2))
                                    .frame(width: 44, height: 44)
                                Image(systemName: vp.musicURL != nil || !selectedMusicTrack.isEmpty ? "music.note.list" : "music.note")
                                    .font(KinnectTheme.scaled(20))
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
                                selectedMusicURL = nil
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
                            Slider(value: Binding(get: { vp.originalAudioVolume }, set: { vp.originalAudioVolume = $0 }), in: 0...1, step: 0.05)
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
                            Slider(value: Binding(get: { vp.musicVolume }, set: { vp.musicVolume = $0 }), in: 0...1, step: 0.05)
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
                                        .padding(.horizontal, 16)
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
    }

    @ViewBuilder
    private var mediaEditPublishSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
    }

    private var mediaEditMode: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                mediaEditHeader
                mediaEditStage
                mediaEditToolSelector
                mediaEditToolPanel
                mediaEditPublishSection
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
        if let selectedMusicURL {
            vp.musicURL = selectedMusicURL
            vp.musicTitle = selectedMusicTrack
        }
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
        let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if !isMovie,
           let data = try? await item.loadTransferable(type: Data.self),
           let uiImg = UIImage(data: data) {
            self.originalImage = uiImg
            self.previewImage = uiImg
            self.capturedVideoTempURL = nil
            self.videoProject = nil
            self.videoDataURL = ""
            self.target = .feedPost
            if let jpeg = uiImg.jpegData(compressionQuality: 0.75) {
                self.imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
            }
            return
        }
        var resolvedMovieURL: URL?
        if let movie = try? await item.loadTransferable(type: KinnectMovieTransferable.self) {
            resolvedMovieURL = movie.url
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            let tempDir = FileManager.default.temporaryDirectory
            let destURL = tempDir.appendingPathComponent("picked_video_\(UUID().uuidString).mp4")
            try? data.write(to: destURL)
            resolvedMovieURL = destURL
        }
        if let destURL = resolvedMovieURL {
            let fileSize = ((try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int) ?? 0)
            if fileSize > 20 * 1024 * 1024 {
                appState.showToast("Video vượt quá giới hạn 20MB.")
                return
            }
            self.capturedVideoTempURL = destURL
            if let data = try? Data(contentsOf: destURL) {
                self.videoDataURL = "data:video/mp4;base64,\(data.base64EncodedString())"
            }
            self.previewImage = nil
            self.originalImage = nil
            self.target = .shortVideo
            let vp = StudioVideoProject(sourceURL: destURL)
            self.videoProject = vp
            self.syncVideoProjectSliders(to: vp)
        }
    }

    private func prepareUploadMediaDataURL(fallbackDataURL: String, defaultColorHex: String) async throws -> String {
        if let vp = videoProject ?? (capturedVideoTempURL.map { StudioVideoProject(sourceURL: $0) }) {
            syncVideoProjectSliders(to: vp)
            let needsExport = vp.hasEdits || vp.sourceURL.pathExtension.lowercased() != "mp4" || videoDataURL.isEmpty
            let outputURL = needsExport ? try await vp.exportVideo() : vp.sourceURL
            let data = try Data(contentsOf: outputURL)
            guard data.count <= 20 * 1024 * 1024 else {
                throw KinnectAPIError.serverMessage("Video vượt quá giới hạn 20 MB.")
            }
            return "data:video/mp4;base64,\(data.base64EncodedString())"
        }
        if let mURL = selectedMusicURL {
            let stillURL = try await KinnectStillVideo.makeCardVideo(
                image: previewImage,
                text: previewImage == nil ? caption : "",
                backgroundColorHex: defaultColorHex
            )
            let project = StudioVideoProject(sourceURL: stillURL)
            project.musicURL = mURL
            project.musicTitle = selectedMusicTrack
            let exported = try await project.exportVideo()
            let data = try Data(contentsOf: exported)
            guard data.count <= 20 * 1024 * 1024 else {
                throw KinnectAPIError.serverMessage("Video nhạc nền vượt quá giới hạn 20 MB.")
            }
            return "data:video/mp4;base64,\(data.base64EncodedString())"
        }
        return fallbackDataURL
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
                    appState.showToast("Vui lòng quay hoặc chọn một video MP4 (< 20MB).")
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
                closeCameraView()

            case .feedPost:
                let preparedMedia = try await prepareUploadMediaDataURL(fallbackDataURL: imageDataURL, defaultColorHex: "#1E1B4B")
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/posts",
                    method: "POST",
                    body: KinnectWriteBody.post(text: finalCaption, category: "community", mediaDataURL: preparedMedia),
                    requestId: reqId
                )
                appState.showToast("Đã đăng bài viết mới!")
                closeCameraView()

            case .story:
                let preparedMedia = try await prepareUploadMediaDataURL(fallbackDataURL: imageDataURL, defaultColorHex: "#7C3AED")
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/stories",
                    method: "POST",
                    body: KinnectWriteBody.story(text: finalCaption, colorHex: "#7C3AED", mediaDataURL: preparedMedia),
                    requestId: reqId
                )
                appState.showToast("Đã đăng tin 24h!")
                closeCameraView()
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}
