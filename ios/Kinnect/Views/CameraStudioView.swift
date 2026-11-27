import AVFoundation
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision

enum StudioEditTool: String, CaseIterable, Identifiable {
    case crop = "Cắt & xoay"
    case color = "Điều chỉnh"
    case beauty = "Làm mịn"
    case audio = "Âm thanh"
    case filters = "Bộ lọc Pro"

    var id: String { rawValue }

    var systemIcon: String {
        switch self {
        case .crop: return "crop.rotate"
        case .color: return "slider.horizontal.3"
        case .beauty: return "sparkles"
        case .audio: return "music.note"
        case .filters: return "camera.filters"
        }
    }
}

private enum CameraCaptureEffects {
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

    static func applyCameraFilterAndBeauty(filter: String, intensity: Double, beauty: [String: Double], to input: UIImage) -> UIImage {
        let smooth = beauty["smooth"] ?? 0
        let whiten = beauty["whiten"] ?? 0
        let blemish = beauty["blemish"] ?? 0
        let hasBeauty = smooth > 0.05 || whiten > 0.05 || blemish > 0.05
        guard filter != "none" || hasBeauty else { return input }
        // Normalize upright first
        let size = input.size
        guard size.width > 0, size.height > 0 else { return input }
        let upright: UIImage
        if input.imageOrientation == .up {
            upright = input
        } else {
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = input.scale
            upright = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
                input.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard let cgIn = upright.cgImage else { return upright }
        var ci = CIImage(cgImage: cgIn)
        let extent = ci.extent
        let amt = max(0.1, min(1.0, intensity))
        if hasBeauty {
            let skinAmt = max(smooth, blemish * 0.8)
            if skinAmt > 0.05 {
                ci = StudioMediaFilters.applySkinSmoothing(to: ci, intensity: skinAmt * 85)
            }
            if whiten > 0.05 {
                ci = ci.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: whiten * 0.08])
            }
        }
        switch filter {
        case "mono": ci = ci.applyingFilter("CIPhotoEffectMono")
        case "noir": ci = ci.applyingFilter("CIPhotoEffectNoir")
        case "film", "retro", "vintage": ci = ci.applyingFilter("CIPhotoEffectInstant")
        case "cinema", "drama": ci = ci.applyingFilter("CIPhotoEffectProcess")
        case "warm", "sunset", "golden":
            ci = ci.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 6500 - CGFloat(1300 * amt), y: 0)
            ])
        case "cool", "ice", "mint", "teal", "teal_orange":
            ci = ci.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 6500 + CGFloat(1300 * amt), y: 0)
            ])
        case "peach", "rose", "candy", "dream", "cyberpunk", "beauty_glow":
            ci = ci.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 6100, y: CGFloat(16 * amt))
            ])
        case "vivid":
            ci = ci.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.0 + 0.35 * amt,
                kCIInputContrastKey: 1.0 + 0.08 * amt
            ])
        case "clear", "milk":
            ci = ci.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: 0.05 * amt,
                kCIInputContrastKey: 0.96
            ])
        default: break
        }
        let ctx = CIContext(options: nil)
        guard let cgOut = ctx.createCGImage(ci.cropped(to: extent), from: extent) else { return upright }
        return UIImage(cgImage: cgOut, scale: upright.scale, orientation: .up)
    }

    static func stickerAnchor(for id: String) -> (yRatio: CGFloat, widthScale: CGFloat) {
        switch id {
        case "crown", "golden_tiara", "bunny", "bunny_ears", "cat", "cat_whiskers", "dog", "dog_ears", "flowers", "flower_crown", "halo", "angel_halo", "party_hat", "party", "devil", "butterfly":
            return (-0.18, 1.15)
        case "glasses", "neon_glasses", "round_glasses", "heart_glasses", "pixel_glasses", "pixel", "retro_shades", "retro", "cyber_mask", "mask":
            return (0.36, 1.05)
        case "hearts", "cheek_hearts", "blush_cheeks", "blush", "sparkle", "sparkle_eyes", "freckles", "rainbow", "rainbow_paint":
            return (0.56, 0.95)
        case "lips", "bow":
            return (0.78, 0.65)
        default:
            return (0.10, 1.20)
        }
    }

    static func stickerImage(for id: String) -> UIImage? {
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

    static func bakeFaceSticker(_ stickerId: String, onto input: UIImage) -> UIImage {
        guard let s = Self.stickers.first(where: { $0.id == stickerId }) else { return input }
        // Normalize orientation to upright so Vision boundingBox aligns 1:1 with drawing coordinates
        let size = input.size
        guard size.width > 0, size.height > 0 else { return input }
        let upright: UIImage
        if input.imageOrientation == .up {
            upright = input
        } else {
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = input.scale
            upright = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
                input.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard let cg = upright.cgImage else { return input }
        let req = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        try? handler.perform([req])
        guard let faces = req.results, !faces.isEmpty else { return upright }
        let anchor = Self.stickerAnchor(for: s.id)
        let img = Self.stickerImage(for: s.id)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = upright.scale
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            upright.draw(in: CGRect(origin: .zero, size: size))
            for face in faces {
                let bb = face.boundingBox
                let faceRect = CGRect(
                    x: bb.minX * size.width,
                    y: (1.0 - bb.maxY) * size.height,
                    width: bb.width * size.width,
                    height: bb.height * size.height
                )
                let w = faceRect.width * anchor.widthScale
                let center = CGPoint(x: faceRect.midX, y: faceRect.minY + faceRect.height * anchor.yRatio)
                let roll = CGFloat(face.roll?.doubleValue ?? 0)
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: center.x, y: center.y)
                ctx.cgContext.rotate(by: -roll)
                let drawRect = CGRect(x: -w / 2, y: -w / 2, width: w, height: w)
                if let img {
                    img.draw(in: drawRect)
                } else {
                    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: w * 0.68)]
                    let str = NSAttributedString(string: s.emoji, attributes: attrs)
                    let sz = str.size()
                    str.draw(at: CGPoint(x: -sz.width / 2, y: -sz.height / 2))
                }
                ctx.cgContext.restoreGState()
            }
        }
    }
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
    @State private var simulatedZoom2x = false
    @State private var isFlashOn = false
    @State private var showCameraGrid = false
    @State private var timerSeconds: Int = 0
    @State private var timerCountdown: Int = 0
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var cameraAspectRatio: String = "9:16"
    @State private var videoDurationLimit: Int = 0
    @State private var recordingLimitTask: Task<Void, Never>? = nil
    @State private var showMusicPickerSheet = false
    @State private var selectedMusicTrack = ""
    @State private var selectedMusicURL: URL?
    @State private var showStudioProSheet = false
    @State private var showCreateLiveSheet = false
    @State private var studioProAppliedEffect = StudioProPack.original.rawValue
    @State private var isUploading = false
    @State private var isSaving = false
    @State private var hasLoadedStoreEntitlements = false
    @State private var studioProPermanent = false
    @State private var studioProFree = false
    @State private var studioAdminAccess = false
    @State private var studioPhotoUntilMs: Int64 = 0
    @State private var studioVideoUntilMs: Int64 = 0
    @State private var studioProUntilMs: Int64 = 0
    @State private var ownedStoreProductIds: Set<String> = []
    @State private var showStudioProLockedAlert = false
    @State private var showStoreFromStudio = false

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

    static let stickers: [(id: String, name: String, emoji: String)] = CameraCaptureEffects.stickers

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
        #if DEBUG
        if UIReviewFixture.activeScreen == "camera-studio-video-edit" {
            return true
        }
        #endif
        return capturedVideoTempURL != nil || videoProject != nil || !videoDataURL.isEmpty
    }

    // Pickers
    @State private var selectedLibraryItem: PhotosPickerItem?
    var onClose: (() -> Void)? = nil

    init(initialMode: CaptureMode = .photo, onClose: (() -> Void)? = nil) {
        _captureMode = State(initialValue: initialMode)
        self.onClose = onClose
    }

    private func cleanupCapturedVideoTempFile() {
        guard let url = capturedVideoTempURL else { return }
        if url.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
            let name = url.lastPathComponent
            if name.hasPrefix("picked_video_")
                || name.hasPrefix("kinnect_capture_")
                || name.hasPrefix("Kinnect-PhotoMusic-") {
                try? FileManager.default.removeItem(at: url)
            }
        }
        capturedVideoTempURL = nil
    }

    private func cancelCaptureTimers() {
        timerTask?.cancel()
        timerTask = nil
        timerCountdown = 0
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
    }

    private func closeCameraView() {
        cancelCaptureTimers()
        cameraController.stop()
        cleanupCapturedVideoTempFile()
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var isFixtureEditMode: Bool {
        #if DEBUG
        return UIReviewFixture.activeScreen == "camera-studio-edit"
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if previewImage == nil && !isVideoActive && !isFixtureEditMode {
                // 1. Direct-to-Camera Viewfinder Mode (100% Android StudioActivity Parity)
                cameraViewfinderMode
            } else {
                // 2. Media Edit Mode (Studio Pro top-right, distinct Save, Publish)
                mediaEditMode
            }
        }
        .background(Color(red: 0.05, green: 0.04, blue: 0.11).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                _ = await MediaPermissionHandler.shared.requestCameraAccess()
                _ = await MediaPermissionHandler.shared.requestMicrophoneAccess()
                cameraController.configureIfAuthorized()
                cameraController.start()
            }
            Task {
                await refreshStudioEntitlements()
            }
            cameraController.onCapturedImage = { uiImg in
                let activeFilterSnapshot = self.activeFilter
                let intensitySnapshot = self.filterIntensity
                let beautySnapshot = self.beautyValues
                let stickerSnapshot = self.activeSticker
                Task { @MainActor in
                    let finalImg = await Task.detached(priority: .userInitiated) {
                        let styled = CameraCaptureEffects.applyCameraFilterAndBeauty(
                            filter: activeFilterSnapshot,
                            intensity: intensitySnapshot,
                            beauty: beautySnapshot,
                            to: uiImg
                        )
                        return stickerSnapshot != "none"
                            ? CameraCaptureEffects.bakeFaceSticker(stickerSnapshot, onto: styled)
                            : styled
                    }.value
                    self.cleanupCapturedVideoTempFile()
                    self.videoProject = nil
                    self.videoDataURL = ""
                    self.originalImage = finalImg
                    self.photoProject.originalImage = finalImg
                    self.photoProject.resetAll()
                    self.target = .feedPost
                    self.imageDataURL = ""
                    self.previewImage = await self.renderPhotoOffMainThread(maxDimension: 900)
                }
            }
            cameraController.onCapturedVideoData = { _, tempURL in
                let activeFilterSnapshot = self.activeFilter
                let intensitySnapshot = self.filterIntensity
                let beautySnapshot = self.beautyValues
                self.cleanupCapturedVideoTempFile()
                self.capturedVideoTempURL = tempURL
                self.videoDataURL = ""
                self.previewImage = nil
                self.originalImage = nil
                self.imageDataURL = ""
                self.photoProject.resetAll()
                self.target = .shortVideo
                let vp = StudioVideoProject(sourceURL: tempURL)
                if !self.selectedMusicTrack.isEmpty {
                    vp.musicTitle = self.selectedMusicTrack
                    vp.musicURL = self.selectedMusicURL
                }
                self.applyCaptureFilterAndBeauty(
                    filter: activeFilterSnapshot,
                    intensity: intensitySnapshot,
                    beauty: beautySnapshot,
                    to: vp
                )
                self.videoProject = vp
                self.syncVideoProjectSliders(to: vp)
                self.videoCompositionRevision = UUID().uuidString
            }
            #if DEBUG
            if UIReviewFixture.activeScreen == "camera-studio-video" {
                captureMode = .video
            }
            if UIReviewFixture.activeScreen == "camera-studio-video-edit" {
                target = .shortVideo
                title = "Video ngắn Kinnect Shorts"
                caption = "Video ngắn quay bằng Camera Studio."
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
                caption = "Khoảnh khắc chiều cuối tuần cùng Kinnect Studio."
            }
            if UIReviewFixture.activeScreen == "studio-pro-sheet" {
                captureMode = .photo
                selectedCreativeTool = .filters
                activeFilter = "clear"
            }
            #endif
        }
        .onDisappear {
            cancelCaptureTimers()
            cameraController.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinnectStoreUpdated)) { _ in
            Task { await refreshStudioEntitlements() }
        }
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
                        Task { await tryApplyStudioProEffect(effect) }
                    }
                )
            }
        }
        .alert("Mở khóa Studio Pro", isPresented: $showStudioProLockedAlert) {
            Button("Mở Cửa hàng") {
                showStoreFromStudio = true
            }
            if photoProject.proPack != .original {
                Button("Bỏ mẫu màu Pro", role: .destructive) {
                    Task { await tryApplyStudioProPack(.original) }
                }
            }
            Button("Để sau", role: .cancel) { }
        } message: {
            Text("Bạn có thể xem thử tự do trong Studio. Để xuất hoặc đăng bài với mẫu màu Studio Pro, hãy mở khóa gói Studio Pro trong Cửa hàng Kinnect.")
        }
        .fullScreenCover(isPresented: $showStoreFromStudio) {
            StoreView(onBack: {
                showStoreFromStudio = false
                Task { await refreshStudioEntitlements() }
            })
        }
        .sheet(isPresented: $showCreateLiveSheet) {
            CreateLiveRoomSheet(onStarted: {
                closeCameraView()
            })
        }
    }

    // MARK: - Direct Camera Viewfinder Mode
    private var cameraViewfinderMode: some View {
        ZStack(alignment: .bottom) {
            // Live Hardware Camera Viewport Layer with live filter tint preview
            LiveCameraPreviewView(
                controller: cameraController,
                isFlashOn: $isFlashOn,
                isUsingFrontCamera: $isUsingFrontCamera,
                showGrid: $showCameraGrid
            )
            .scaleEffect(cameraController.availableLenses.count <= 1 && simulatedZoom2x ? 2.0 : 1.0)
            .clipped()
            .saturation(activeFilter == "mono" || activeFilter == "noir" ? 0 : (activeFilter == "vivid" ? 1.25 : 1.0))
            .contrast(activeFilter == "noir" || activeFilter == "drama" ? 1.18 : 1.0)
            .overlay(
                liveFilterTint(for: activeFilter)
                    .opacity(filterIntensity * 0.24)
                    .blendMode(.softLight)
                    .allowsHitTesting(false)
            )
            .ignoresSafeArea()

            // Real-time 60fps Hardware Face-Tracked AR Sticker Overlay
            if activeSticker != "none", let s = Self.stickers.first(where: { $0.id == activeSticker }) {
                let anchor = CameraCaptureEffects.stickerAnchor(for: s.id)
                ZStack {
                    ForEach(cameraController.trackedFaces) { face in
                        let w = max(64, face.bounds.width * anchor.widthScale)
                        let pos = CGPoint(
                            x: face.bounds.midX,
                            y: face.bounds.minY + face.bounds.height * anchor.yRatio
                        )
                        Group {
                            if let img = CameraCaptureEffects.stickerImage(for: s.id) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: w, height: w)
                            } else {
                                Text(s.emoji)
                                    .font(.system(size: w * 0.68))
                            }
                        }
                        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
                        .rotationEffect(.degrees(Double(face.rollAngle)))
                        .position(pos)
                    }
                    if cameraController.trackedFaces.isEmpty {
                        VStack {
                            HStack(spacing: 6) {
                                Image(systemName: "faceid")
                                    .font(.caption.bold())
                                Text("Đưa khuôn mặt vào khung hình")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(.top, 110)
                            Spacer()
                        }
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
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

            if timerCountdown > 0 {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    Text("\(timerCountdown)")
                        .font(.system(size: 88, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 12)
                }
                .allowsHitTesting(false)
                .zIndex(18)
            }

            VStack(spacing: 0) {
                cameraViewfinderTopChrome

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
                                        .padding(.vertical, 8)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .background(Capsule().fill(cameraController.activeLens == lens ? Color.white : Color.black.opacity(0.48)))
                                        .foregroundColor(cameraController.activeLens == lens ? .black : .white)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                simulatedZoom2x.toggle()
                            }
                        } label: {
                            Text(simulatedZoom2x ? "2×" : "1×")
                                .font(.caption.bold())
                                .foregroundColor(simulatedZoom2x ? .black : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(Capsule().fill(simulatedZoom2x ? Color.white : Color.black.opacity(0.48)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr(simulatedZoom2x ? "Thu phóng 2x" : "Thu phóng 1x"))
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
                            handleShutterTap()
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
                    HStack(spacing: 16) {
                        ForEach(CaptureMode.allCases, id: \.self) { mode in
                            Button {
                                captureMode = mode
                                if mode == .live {
                                    showCreateLiveSheet = true
                                }
                            } label: {
                                Text(mode.rawValue)
                                    .font(.subheadline.weight(captureMode == mode ? .bold : .medium))
                                    .foregroundColor(captureMode == mode ? KinnectTheme.accentBright : .white.opacity(0.78))
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .background(
                                        captureMode == mode ?
                                            Capsule().fill(Color.white.opacity(0.18)) :
                                            Capsule().fill(Color.clear)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var cameraViewfinderTopChrome: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.48))
                    .frame(width: 44, height: 44)
                KinnectIconButton(glyph: .close, label: L10n.tr("Thoát Camera"), tint: .white) {
                    closeCameraView()
                }
            }
            .frame(width: 44, height: 44)

            Spacer(minLength: 2)

            Button {
                showMusicPickerSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                    Text(selectedMusicTrack.isEmpty ? L10n.tr("Thêm nhạc") : selectedMusicTrack)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 44, minHeight: 44)
                .background(Capsule().fill(selectedMusicTrack.isEmpty ? Color.black.opacity(0.48) : KinnectTheme.accent.opacity(0.85)))
                .foregroundColor(.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Chọn nhạc nền cho bài đăng hoặc video"))

            Spacer(minLength: 2)

            HStack(spacing: 0) {
                Button {
                    isFlashOn.toggle()
                } label: {
                    Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isFlashOn ? KinnectTheme.warning : .white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.black.opacity(0.48)))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr(isFlashOn ? "Tắt đèn flash" : "Bật đèn flash"))

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showCameraGrid.toggle()
                    }
                } label: {
                    Image(systemName: "grid")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(showCameraGrid ? KinnectTheme.warning : .white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(showCameraGrid ? Color.white.opacity(0.22) : Color.black.opacity(0.48)))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr(showCameraGrid ? "Tắt lưới bố cục" : "Bật lưới bố cục"))

                Button {
                    switch timerSeconds {
                    case 0: timerSeconds = 3
                    case 3: timerSeconds = 10
                    default: timerSeconds = 0
                    }
                } label: {
                    Group {
                        if timerSeconds > 0 {
                            Text("\(timerSeconds)s")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(KinnectTheme.warning)
                        } else {
                            Image(systemName: "timer")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(timerSeconds > 0 ? Color.white.opacity(0.22) : Color.black.opacity(0.48)))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Hẹn giờ chụp"))

                Button {
                    if captureMode == .video {
                        switch videoDurationLimit {
                        case 0: videoDurationLimit = 15
                        case 15: videoDurationLimit = 60
                        default: videoDurationLimit = 0
                        }
                    } else {
                        switch cameraAspectRatio {
                        case "9:16": cameraAspectRatio = "4:3"
                        case "4:3": cameraAspectRatio = "1:1"
                        default: cameraAspectRatio = "9:16"
                        }
                    }
                } label: {
                    let pillLabel = captureMode == .video
                        ? (videoDurationLimit == 0 ? "∞" : "\(videoDurationLimit)s")
                        : cameraAspectRatio
                    Text(pillLabel)
                        .font(.caption2.bold())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 34, minHeight: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.48)))
                        .foregroundColor(.white)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr(captureMode == .video ? "Đổi thời lượng quay" : "Đổi tỉ lệ khung hình"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    private func handleShutterTap() {
        if captureMode == .live {
            showCreateLiveSheet = true
            return
        }
        if timerCountdown > 0 {
            cancelCaptureTimers()
            return
        }
        if captureMode == .video && cameraController.isRecordingVideo {
            recordingLimitTask?.cancel()
            recordingLimitTask = nil
            cameraController.toggleVideoRecording()
            return
        }
        if timerSeconds > 0 {
            let total = timerSeconds
            timerTask?.cancel()
            timerTask = Task { @MainActor in
                for remaining in stride(from: total, through: 1, by: -1) {
                    timerCountdown = remaining
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else {
                        timerCountdown = 0
                        return
                    }
                }
                timerCountdown = 0
                executeCaptureAction()
            }
        } else {
            executeCaptureAction()
        }
    }

    private func executeCaptureAction() {
        if captureMode == .video {
            cameraController.toggleVideoRecording()
            if videoDurationLimit > 0 {
                let limit = videoDurationLimit
                recordingLimitTask?.cancel()
                recordingLimitTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(limit) * 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    if cameraController.isRecordingVideo {
                        cameraController.toggleVideoRecording()
                    }
                }
            }
        } else {
            cameraController.capturePhoto(flash: isFlashOn)
        }
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
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
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
                            .frame(minHeight: 44)
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
                                .frame(minWidth: 48, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .clipped()

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
                    .frame(minHeight: 44)
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
                                .frame(minWidth: 48, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .clipped()

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
                                    if let img = CameraCaptureEffects.stickerImage(for: s.id) {
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
                                .frame(minWidth: 52, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .clipped()
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

    private func liveFilterTint(for id: String) -> Color {
        switch id {
        case "warm", "sunset", "golden": return Color.orange
        case "cool", "ice", "teal": return Color.cyan
        case "peach", "rose", "candy", "beauty_glow": return Color.pink
        case "mint": return Color.mint
        case "dream", "cyberpunk": return Color.purple
        case "film", "retro", "vintage": return Color(red: 0.72, green: 0.56, blue: 0.36)
        case "teal_orange", "cinema": return Color(red: 0.15, green: 0.55, blue: 0.65)
        case "clear", "milk": return Color.white
        default: return Color.clear
        }
    }

    private func beautyLabel(for key: String) -> String {
        Self.beautyTools.first(where: { $0.key == key })?.title ?? "Cường độ"
    }

    // MARK: - Media Edit Mode (Real Mobile Editor with Parity to Android PhotoEditActivity)
    @ViewBuilder
    private var mediaEditHeader: some View {
        HStack(spacing: 10) {
            KinnectIconButton(glyph: .close, label: L10n.tr("Thoát"), tint: .white) {
                originalImage = nil
                previewImage = nil
                imageDataURL = ""
                videoDataURL = ""
                cleanupCapturedVideoTempFile()
                videoProject = nil
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.tr("Studio Pro"))
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(isVideoActive ? L10n.tr("Video") : L10n.tr("Ảnh"))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Button {
                saveMediaToPhotos()
            } label: {
                HStack(spacing: 5) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.7)
                    } else {
                        KinnectIcon(glyph: .save, size: 14, tint: .white)
                    }
                    Text(isSaving ? L10n.tr("Đang lưu…") : L10n.tr("Lưu về máy"))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .accessibilityLabel(L10n.tr("Lưu vào thiết bị"))
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var mediaEditStage: some View {
        ZStack(alignment: .bottom) {
            #if DEBUG
            let fixtureVideoURL = UIReviewFixture.activeScreen == "camera-studio-video-edit" ? UIReviewFixture.samplePlayableVideoURL() : nil
            let fixturePreviewFallback = UIReviewFixture.samplePreviewImage()
            #else
            let fixtureVideoURL: URL? = nil
            let fixturePreviewFallback = UIImage()
            #endif
            if let vURL = capturedVideoTempURL ?? fixtureVideoURL {
                StudioVideoPlayerView(videoURL: vURL, videoProject: videoProject ?? StudioVideoProject(sourceURL: vURL), revisionId: videoCompositionRevision)
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                let displayImg = isComparingOriginal
                    ? (originalImage ?? fixturePreviewFallback)
                    : (previewImage ?? fixturePreviewFallback)
                Image(uiImage: displayImg)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 240)
                    .background(Color(red: 0.05, green: 0.04, blue: 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(KinnectTheme.border, lineWidth: 1)
                    )
            }

            if !isVideoActive {
                HStack {
                    Button {} label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                                .font(.caption2)
                            Text(isComparingOriginal ? L10n.tr("Đang xem ảnh gốc") : L10n.tr("Giữ xem gốc"))
                                .font(.caption2.bold())
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .foregroundColor(isComparingOriginal ? KinnectTheme.accentBright : .white)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isComparingOriginal = true }
                            .onEnded { _ in isComparingOriginal = false }
                    )
                    .accessibilityLabel(L10n.tr("Giữ để xem ảnh gốc"))

                    Spacer()

                    Button {
                        photoProject.cropRatio = .original
                        photoProject.rotation = 0
                        photoProject.flipHorizontal = false
                        updatePhotoPreview()
                    } label: {
                        Text(L10n.tr("Vừa khung"))
                            .font(.caption2.bold())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Capsule().fill(Color.black.opacity(0.75)))
                            .foregroundColor(.white)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Vừa khung hình ảnh"))
                }
                .padding(8)
            } else {
                let musicTitle = (videoProject?.musicTitle.isEmpty == false)
                    ? (videoProject?.musicTitle ?? "")
                    : selectedMusicTrack
                let hasMusic = (videoProject?.musicURL != nil || !musicTitle.isEmpty)
                HStack {
                    Button {
                        selectedTool = .audio
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "music.note")
                                .font(.caption2.bold())
                            Text(musicTitle.isEmpty ? L10n.tr("Gán nhạc") : musicTitle)
                                .font(.caption2.bold())
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(hasMusic ? KinnectTheme.accent.opacity(0.88) : Color.black.opacity(0.72)))
                        .foregroundColor(.white)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Gán nhạc nền cho video"))

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 36)
            }
        }
    }

    @ViewBuilder
    private var mediaEditToolSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StudioEditTool.allCases) { tool in
                    let isSelected = selectedTool == tool
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedTool = tool
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tool.systemIcon)
                                .font(.caption.weight(.semibold))
                            Text(L10n.tr(tool.rawValue))
                                .font(.caption.weight(isSelected ? .bold : .semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundColor(isSelected ? .white : .white.opacity(0.85))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(
                            Capsule().fill(
                                isSelected
                                    ? AnyShapeStyle(KinnectTheme.primaryGradient)
                                    : AnyShapeStyle(Color.white.opacity(0.10))
                            )
                        )
                        .overlay(
                            Capsule().stroke(
                                isSelected ? Color.clear : Color.white.opacity(0.14),
                                lineWidth: 1
                            )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
        .clipped()
    }

    @ViewBuilder
    private var mediaEditToolPanel: some View {
        VStack(spacing: 12) {
            switch selectedTool {
            case .crop:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tỉ lệ khung hình:")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.textSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(StudioCropRatio.allCases) { ratio in
                                let activeRatio = isVideoActive ? (videoProject?.cropRatio ?? photoProject.cropRatio) : photoProject.cropRatio
                                let isChosen = (activeRatio == ratio)
                                Button {
                                    photoProject.cropRatio = ratio
                                    if isVideoActive {
                                        if let vp = videoProject ?? (capturedVideoTempURL.map { StudioVideoProject(sourceURL: $0) }) {
                                            if videoProject == nil { videoProject = vp }
                                            vp.cropRatio = ratio
                                            videoCompositionRevision = UUID().uuidString
                                        }
                                    } else {
                                        updatePhotoPreview()
                                    }
                                } label: {
                                    Text(ratio == .original ? "Gốc" : ratio.rawValue)
                                        .font(.caption.weight(isChosen ? .bold : .medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .background(
                                            Capsule().fill(isChosen ? KinnectTheme.accent : KinnectTheme.surfaceElevated)
                                        )
                                        .foregroundColor(isChosen ? .white : KinnectTheme.textPrimary)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .clipped()

                    if isVideoActive {
                        if let vp = videoProject {
                            StudioVideoTrimPanel(project: vp) {
                                videoCompositionRevision = UUID().uuidString
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
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(KinnectTheme.surfaceElevated))
                                    .foregroundColor(KinnectTheme.textPrimary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                photoProject.rotation = (photoProject.rotation + 90) % 360
                                updatePhotoPreview()
                            } label: {
                                Label("Xoay phải", systemImage: "rotate.right")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(KinnectTheme.surfaceElevated))
                                    .foregroundColor(KinnectTheme.textPrimary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                photoProject.flipHorizontal.toggle()
                                updatePhotoPreview()
                            } label: {
                                Label("Lật", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(KinnectTheme.surfaceElevated))
                                    .foregroundColor(KinnectTheme.textPrimary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
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
                        Button {
                            photoProject.resetColor()
                            if isVideoActive, let vp = videoProject {
                                syncVideoProjectSliders(to: vp)
                                videoCompositionRevision = UUID().uuidString
                            } else {
                                updatePhotoPreview()
                            }
                        } label: {
                            Text(L10n.tr("Đặt lại màu"))
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.accentBright)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(Capsule().fill(KinnectTheme.surfaceElevated))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
                        StudioVideoAudioPanel(
                            project: vp,
                            selectedMusicTrack: $selectedMusicTrack,
                            selectedMusicURL: $selectedMusicURL,
                            onPickMusic: { showMusicPickerSheet = true }
                        )
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
                    HStack {
                        Text(L10n.tr("Mẫu màu Studio Pro:"))
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textSecondary)
                        Spacer()
                        if photoProject.proPack != .original && !isStudioProEntitledLocally {
                            Text(L10n.tr("Xem thử Pro"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color(red: 0x78 / 255.0, green: 0x35 / 255.0, blue: 0x0F / 255.0)))
                        }
                        Button {
                            showStudioProSheet = true
                        } label: {
                            Text(L10n.tr("Xem tất cả"))
                                .font(.caption2.bold())
                                .foregroundColor(KinnectTheme.accentBright)
                                .padding(.horizontal, 8)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(StudioProPack.allCases) { pack in
                                Button {
                                    Task { await tryApplyStudioProPack(pack) }
                                } label: {
                                    Text(pack.rawValue)
                                        .font(.caption.weight(photoProject.proPack == pack ? .bold : .medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(photoProject.proPack == pack ? KinnectTheme.accent : KinnectTheme.surfaceElevated)
                                        )
                                        .foregroundColor(photoProject.proPack == pack ? .white : KinnectTheme.textPrimary)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .clipped()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Chữ trên ảnh / video:")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textSecondary)
                        HStack(spacing: 8) {
                            TextField(
                                "",
                                text: $photoProject.overlayText,
                                prompt: Text(L10n.tr("Nhập chữ hiển thị...")).foregroundColor(KinnectTheme.inputPlaceholder)
                            )
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.surfaceElevated))
                                .foregroundColor(KinnectTheme.textPrimary)
                                .onChange(of: photoProject.overlayText) { _ in
                                    if isVideoActive, let vp = videoProject {
                                        syncVideoProjectSliders(to: vp)
                                        videoCompositionRevision = UUID().uuidString
                                    } else {
                                        updatePhotoPreview()
                                    }
                                }
                            if !photoProject.overlayText.isEmpty {
                                Button {
                                    photoProject.overlayText = ""
                                    if isVideoActive, let vp = videoProject {
                                        syncVideoProjectSliders(to: vp)
                                        videoCompositionRevision = UUID().uuidString
                                    } else {
                                        updatePhotoPreview()
                                    }
                                } label: {
                                    Text("Xóa")
                                        .font(.caption.bold())
                                        .foregroundColor(KinnectTheme.danger)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated.opacity(0.6)))
            }
        }
    }

    @ViewBuilder
    private var mediaEditPublishSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("Đích đăng tải:"))
                    .font(.caption.bold())
                    .foregroundColor(KinnectTheme.textSecondary)

                KinnectSegmentedBar(
                    selection: $target,
                    options: PublishTarget.allCases.map { ($0, L10n.tr($0.rawValue)) },
                    accessibilityLabel: L10n.tr("Đích đăng")
                )
            }

            if target == .shortVideo {
                TextField(
                    "",
                    text: $title,
                    prompt: Text("Tiêu đề video ngắn...").foregroundColor(KinnectTheme.inputPlaceholder)
                )
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(KinnectTheme.textPrimary)
            }

            TextField(
                "",
                text: $caption,
                prompt: Text("Mô tả / Nội dung bài viết...").foregroundColor(KinnectTheme.inputPlaceholder),
                axis: .vertical
            )
                .lineLimit(1...3)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                .foregroundColor(KinnectTheme.textPrimary)

            Button {
                Task { await publishContent() }
            } label: {
                HStack(spacing: 8) {
                    Spacer()
                    if isUploading {
                        ProgressView().tint(.white)
                    } else {
                        KinnectIcon(glyph: .send, size: 20, selected: true, tint: .white)
                        Text(isVideoActive ? L10n.tr("Dùng video & Đăng ngay") : L10n.tr("Dùng ảnh & Đăng ngay"))
                            .font(.headline)
                    }
                    Spacer()
                }
                .frame(minHeight: 48)
                .background(KinnectTheme.primaryGradient)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isUploading)
        }
    }

    private var mediaEditMode: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    mediaEditHeader
                    mediaEditStage
                    mediaEditToolSelector
                    mediaEditToolPanel
                }
                .padding(16)
                .padding(.bottom, 16)
            }
            .clipped()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                mediaEditPublishSection
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .background(
                        Color(red: 0.08, green: 0.06, blue: 0.16)
                            .ignoresSafeArea(edges: .bottom)
                    )
                    .overlay(Divider().background(KinnectTheme.borderSoft), alignment: .top)
            }
            if let vp = videoProject {
                StudioExportProgressHUD(project: vp)
            }
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
                    .foregroundColor(KinnectTheme.textPrimary)
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
            .frame(minHeight: 44)
        }
    }

    private func makePhotoSnapshot() -> StudioPhotoProject {
        let copy = StudioPhotoProject(originalImage: photoProject.originalImage)
        copy.brightness = photoProject.brightness
        copy.exposure = photoProject.exposure
        copy.highlights = photoProject.highlights
        copy.shadows = photoProject.shadows
        copy.contrast = photoProject.contrast
        copy.saturation = photoProject.saturation
        copy.vibrance = photoProject.vibrance
        copy.warmth = photoProject.warmth
        copy.tint = photoProject.tint
        copy.smooth = photoProject.smooth
        copy.sharpness = photoProject.sharpness
        copy.clarity = photoProject.clarity
        copy.curveAmount = photoProject.curveAmount
        copy.grain = photoProject.grain
        copy.rotation = photoProject.rotation
        copy.flipHorizontal = photoProject.flipHorizontal
        copy.cropRatio = photoProject.cropRatio
        copy.proTemplate = photoProject.proTemplate
        copy.proPack = photoProject.proPack
        copy.overlayText = photoProject.overlayText
        return copy
    }

    private func renderPhotoOffMainThread(maxDimension: CGFloat? = nil) async -> UIImage {
        let snapshot = makePhotoSnapshot()
        return await Task.detached(priority: .userInitiated) {
            snapshot.render(maxDimension: maxDimension)
        }.value
    }

    private func encodeFullResPhotoDataURL() async throws -> String {
        let snapshot = makePhotoSnapshot()
        return try await Task.detached(priority: .userInitiated) {
            let rendered = snapshot.render(maxDimension: 2048)
            guard let jpeg = rendered.jpegData(compressionQuality: 0.88) else {
                throw KinnectAPIError.serverMessage("Không thể nén ảnh để tải lên.")
            }
            return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        }.value
    }

    private func updatePhotoPreview() {
        Task { @MainActor in
            self.previewImage = await renderPhotoOffMainThread(maxDimension: 900)
        }
    }

    // MARK: - Studio Pro Entitlement Verification
    private func applyStoreEntitlementPayload(_ res: [String: Any]) {
        studioProPermanent = (res["studioProPermanent"] as? Bool) == true
        studioProFree = (res["studioProFree"] as? Bool) == true
        studioAdminAccess = (res["adminAccess"] as? Bool) == true
        studioPhotoUntilMs = (res["studioPhotoUntil"] as? NSNumber)?.int64Value ?? 0
        studioVideoUntilMs = (res["studioVideoUntil"] as? NSNumber)?.int64Value ?? 0
        studioProUntilMs = (res["studioProUntil"] as? NSNumber)?.int64Value ?? 0
        var ids = Set(res["owned"] as? [String] ?? [])
        for pkgId in (res["ownedPackages"] as? [String] ?? []) {
            ids.insert(pkgId)
        }
        ownedStoreProductIds = ids
        hasLoadedStoreEntitlements = true
    }

    private func refreshStudioEntitlements() async {
        if !hasLoadedStoreEntitlements, let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/store") {
            applyStoreEntitlementPayload(cached)
        }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/store") {
            applyStoreEntitlementPayload(res)
        }
    }

    private var isStudioProEntitledLocally: Bool {
        #if DEBUG
        if UIReviewFixture.isEnabled { return true }
        #endif
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        if studioProPermanent || studioProFree || studioAdminAccess { return true }
        return isVideoActive ? (studioVideoUntilMs > nowMs) : (studioPhotoUntilMs > nowMs)
    }

    private func hasActiveStudioProEntitlement() async -> Bool {
        #if DEBUG
        if UIReviewFixture.isEnabled { return true }
        #endif
        if !hasLoadedStoreEntitlements {
            await refreshStudioEntitlements()
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        if studioProPermanent || studioProFree || studioAdminAccess { return true }
        if isVideoActive {
            return studioVideoUntilMs > nowMs
        } else {
            return studioPhotoUntilMs > nowMs
        }
    }

    private func applyCaptureFilterAndBeauty(
        filter: String,
        intensity: Double,
        beauty: [String: Double],
        to vp: StudioVideoProject
    ) {
        let amt = max(0.1, min(1.0, intensity))
        let smooth = beauty["smooth"] ?? 0
        let whiten = beauty["whiten"] ?? 0
        let blemish = beauty["blemish"] ?? 0
        let skinAmt = max(smooth, blemish * 0.8)
        if skinAmt > 0.05 {
            photoProject.smooth = min(100, skinAmt * 85)
        }
        if whiten > 0.05 {
            photoProject.brightness = min(50, whiten * 22)
        }
        switch filter {
        case "mono", "noir":
            photoProject.proPack = .noir
            studioProAppliedEffect = StudioProPack.noir.rawValue
        case "cinema", "drama":
            photoProject.proPack = .cinema
            studioProAppliedEffect = StudioProPack.cinema.rawValue
        case "sunset", "golden", "warm":
            photoProject.warmth = max(photoProject.warmth, 28 * amt)
            if filter == "sunset" {
                photoProject.proPack = .sunset
                studioProAppliedEffect = StudioProPack.sunset.rawValue
            }
        case "cool", "ice", "mint", "teal", "teal_orange":
            photoProject.warmth = -26 * amt
        case "vivid", "cyberpunk":
            photoProject.proPack = .vivid
            studioProAppliedEffect = StudioProPack.vivid.rawValue
        case "peach", "rose", "candy", "dream":
            photoProject.warmth = 10 * amt
            photoProject.tint = 14 * amt
            photoProject.saturation = 12 * amt
        case "film", "retro", "vintage":
            photoProject.contrast = 12 * amt
            photoProject.grain = 0.03 * amt
            photoProject.warmth = 10 * amt
        case "clear", "milk", "beauty_glow":
            photoProject.brightness = max(photoProject.brightness, 12 * amt)
            photoProject.contrast = -8 * amt
            if filter == "beauty_glow" {
                photoProject.proPack = .beauty
                studioProAppliedEffect = StudioProPack.beauty.rawValue
            }
        default:
            break
        }
        syncVideoProjectSliders(to: vp)
    }

    private func resolvedProPack(for effect: String) -> StudioProPack {
        if let exact = StudioProPack.allCases.first(where: { $0.rawValue == effect }) {
            return exact
        }
        switch effect {
        case "Bộ lọc gốc", "Gốc":
            return .original
        case "Kinnect Vivid":
            return .vivid
        case "Cinematic Teal & Orange", "Cinema":
            return .cinema
        case "Noir Cổ điển":
            return .noir
        case "Ấm áp hoàng hôn", "Hoàng hôn":
            return .sunset
        case "Mịn da tự nhiên (Beauty)", "Beauty":
            return .beauty
        default:
            return .original
        }
    }

    @MainActor
    private func tryApplyStudioProPack(_ pack: StudioProPack) async {
        // Non-destructive preview is always allowed; export/publish gates on Studio Pro entitlement.
        photoProject.proPack = pack
        studioProAppliedEffect = pack.rawValue
        if isVideoActive {
            if let vp = videoProject ?? (capturedVideoTempURL.map { StudioVideoProject(sourceURL: $0) }) {
                if videoProject == nil { videoProject = vp }
                syncVideoProjectSliders(to: vp)
                videoCompositionRevision = UUID().uuidString
            }
        } else {
            updatePhotoPreview()
        }
        if pack != .original {
            let entitled = await hasActiveStudioProEntitlement()
            if !entitled {
                appState.showToast("Đang xem thử '\(pack.rawValue)'. Cần gói Studio Pro khi lưu hoặc đăng.")
            }
        }
    }

    @MainActor
    private func tryApplyStudioProEffect(_ effect: String) async {
        let pack = resolvedProPack(for: effect)
        studioProAppliedEffect = pack.rawValue
        photoProject.proPack = pack
        if isVideoActive {
            if let vp = videoProject ?? (capturedVideoTempURL.map { StudioVideoProject(sourceURL: $0) }) {
                if videoProject == nil { videoProject = vp }
                syncVideoProjectSliders(to: vp)
                videoCompositionRevision = UUID().uuidString
            }
        } else {
            updatePhotoPreview()
        }
        if pack != .original {
            let entitled = await hasActiveStudioProEntitlement()
            if !entitled {
                appState.showToast("Đang xem thử '\(pack.rawValue)'. Cần gói Studio Pro khi lưu hoặc đăng.")
                return
            }
        }
        appState.showToast("Đã áp dụng Studio Pro: '\(pack.rawValue)'")
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
        vp.cropRatio = photoProject.cropRatio
        vp.proTemplate = photoProject.proTemplate
        vp.proPack = photoProject.proPack
        vp.overlayText = photoProject.overlayText
    }

    private func saveMediaToPhotos() {
        guard !isSaving else { return }
        if photoProject.proPack != .original || (videoProject?.proPack ?? .original) != .original {
            Task { @MainActor in
                guard await hasActiveStudioProEntitlement() else {
                    showStudioProLockedAlert = true
                    return
                }
                performSaveMediaToPhotos()
            }
            return
        }
        performSaveMediaToPhotos()
    }

    private func performSaveMediaToPhotos() {
        guard !isSaving else { return }
        isSaving = true
        if isVideoActive {
            guard let vp = videoProject ?? (capturedVideoTempURL.map { StudioVideoProject(sourceURL: $0) }) else {
                isSaving = false
                appState.showToast(L10n.tr("Không tìm thấy video để lưu."))
                return
            }
            syncVideoProjectSliders(to: vp)
            Task { @MainActor in
                var targetURL = vp.sourceURL
                var didExportTemp = false
                if vp.hasEdits {
                    do {
                        appState.showToast(L10n.tr("Đang xuất video qua Studio Pro..."))
                        targetURL = try await vp.exportVideo()
                        didExportTemp = true
                    } catch is CancellationError {
                        isSaving = false
                        appState.showToast("Đã hủy xuất video.")
                        return
                    } catch {
                        isSaving = false
                        appState.showToast("Không thể xuất video: \(error.localizedDescription)")
                        return
                    }
                }
                let cleanupURL = didExportTemp ? targetURL : nil
                PhotoSaveCoordinator.saveVideo(atPath: targetURL.path) { success, error in
                    if let cleanupURL {
                        try? FileManager.default.removeItem(at: cleanupURL)
                    }
                    isSaving = false
                    if success {
                        appState.showToast(L10n.tr("Đã lưu video đã chỉnh sửa vào Album ảnh trên thiết bị."))
                    } else {
                        appState.showToast("Không thể lưu video: \(error?.localizedDescription ?? "Lỗi quyền truy cập")")
                    }
                }
            }
        } else {
            Task { @MainActor in
                let img = await renderPhotoOffMainThread(maxDimension: 2048)
                PhotoSaveCoordinator.saveImage(img) { success, error in
                    isSaving = false
                    if success {
                        appState.showToast(L10n.tr("Đã lưu ảnh vào Album ảnh trên thiết bị."))
                    } else {
                        appState.showToast("Không thể lưu ảnh: \(error?.localizedDescription ?? "Lỗi quyền truy cập")")
                    }
                }
            }
        }
    }

    private func loadMediaFromLibrary(_ item: PhotosPickerItem) async {
        defer { selectedLibraryItem = nil }
        let isMovieItem = item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }
        if isMovieItem {
            do {
                if let pickedMovie = try await item.loadTransferable(type: PickedMovieFile.self) {
                    cleanupCapturedVideoTempFile()
                    self.capturedVideoTempURL = pickedMovie.url
                    self.videoDataURL = ""
                    self.previewImage = nil
                    self.originalImage = nil
                    self.imageDataURL = ""
                    self.photoProject.resetAll()
                    self.target = .shortVideo
                    let vp = StudioVideoProject(sourceURL: pickedMovie.url)
                    if !self.selectedMusicTrack.isEmpty {
                        vp.musicTitle = self.selectedMusicTrack
                        vp.musicURL = self.selectedMusicURL
                    }
                    self.videoProject = vp
                    self.syncVideoProjectSliders(to: vp)
                    return
                }
                appState.showToast("Không đọc được tệp video từ thư viện.")
            } catch {
                appState.showToast("Không thể tải video từ thư viện: \(error.localizedDescription)")
            }
            return
        }

        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImg = UIImage(data: data) {
                cleanupCapturedVideoTempFile()
                self.originalImage = uiImg
                self.photoProject.originalImage = uiImg
                self.photoProject.resetAll()
                self.videoProject = nil
                self.videoDataURL = ""
                self.imageDataURL = ""
                self.target = .feedPost
                self.previewImage = await renderPhotoOffMainThread(maxDimension: 900)
                return
            }
            // Fallback for items that didn't advertise .movie in supportedContentTypes
            if let pickedMovie = try await item.loadTransferable(type: PickedMovieFile.self) {
                cleanupCapturedVideoTempFile()
                self.capturedVideoTempURL = pickedMovie.url
                self.videoDataURL = ""
                self.previewImage = nil
                self.originalImage = nil
                self.imageDataURL = ""
                self.photoProject.resetAll()
                self.target = .shortVideo
                let vp = StudioVideoProject(sourceURL: pickedMovie.url)
                if !self.selectedMusicTrack.isEmpty {
                    vp.musicTitle = self.selectedMusicTrack
                    vp.musicURL = self.selectedMusicURL
                }
                self.videoProject = vp
                self.syncVideoProjectSliders(to: vp)
                return
            }
            appState.showToast("Không đọc được tệp đã chọn từ thư viện.")
        } catch {
            appState.showToast("Không thể tải tệp từ thư viện: \(error.localizedDescription)")
        }
    }

    private func encodeVideoFileOffMainThread(url: URL, maxBytes: Int = 42 * 1024 * 1024) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            if size > maxBytes {
                throw NSError(
                    domain: "KinnectStudio",
                    code: -10,
                    userInfo: [NSLocalizedDescriptionKey: "Video vượt quá giới hạn \(maxBytes / (1024 * 1024))MB."]
                )
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            if data.count > maxBytes {
                throw NSError(
                    domain: "KinnectStudio",
                    code: -10,
                    userInfo: [NSLocalizedDescriptionKey: "Video vượt quá giới hạn \(maxBytes / (1024 * 1024))MB."]
                )
            }
            return "data:video/mp4;base64," + data.base64EncodedString()
        }.value
    }

    private func resolvePublishVideoDataURL(maxBytes: Int) async throws -> String {
        if let vp = videoProject ?? (capturedVideoTempURL.map { StudioVideoProject(sourceURL: $0) }) {
            syncVideoProjectSliders(to: vp)
            appState.showToast(vp.hasEdits ? "Đang áp dụng hiệu ứng và xuất video..." : "Đang chuyển đổi video sang chuẩn MP4...")
            let exportedURL = try await vp.exportVideo(maxBytes: maxBytes)
            defer { try? FileManager.default.removeItem(at: exportedURL) }
            return try await encodeVideoFileOffMainThread(url: exportedURL, maxBytes: maxBytes)
        }
        return videoDataURL
    }

    private func publishContent() async {
        if photoProject.proPack != .original || (videoProject?.proPack ?? .original) != .original {
            guard await hasActiveStudioProEntitlement() else {
                showStudioProLockedAlert = true
                return
            }
        }
        isUploading = true
        defer { isUploading = false }
        let reqId = "studio_\(UUID().uuidString)"
        let cleanCap = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCaption = cleanCap
        let maxVideoBytes = (target == .shortVideo) ? (42 * 1024 * 1024) : (20 * 1024 * 1024)

        do {
            switch target {
            case .shortVideo:
                guard !videoDataURL.isEmpty || capturedVideoTempURL != nil || videoProject != nil else {
                    appState.showToast("Vui lòng quay hoặc chọn một video MP4 (< 42MB).")
                    return
                }
                let finalVideoDataURL: String
                do {
                    finalVideoDataURL = try await resolvePublishVideoDataURL(maxBytes: maxVideoBytes)
                } catch {
                    appState.showToast("Lỗi xuất video: \(error.localizedDescription)")
                    return
                }

                let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let shortCaption = finalCaption.isEmpty ? cleanTitle : finalCaption
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/shorts",
                    method: "POST",
                    body: KinnectWriteBody.shortVideo(caption: shortCaption, dataURL: finalVideoDataURL, title: cleanTitle),
                    requestId: reqId
                )
                appState.showToast("Đã đăng video ngắn thành công!")
                closeCameraView()

            case .feedPost:
                let mediaURL: String
                if !isVideoActive && (originalImage != nil || previewImage != nil) {
                    mediaURL = try await encodeFullResPhotoDataURL()
                } else if !imageDataURL.isEmpty {
                    mediaURL = imageDataURL
                } else if !videoDataURL.isEmpty || capturedVideoTempURL != nil || videoProject != nil {
                    mediaURL = try await resolvePublishVideoDataURL(maxBytes: maxVideoBytes)
                } else {
                    mediaURL = ""
                }
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/posts",
                    method: "POST",
                    body: KinnectWriteBody.post(text: finalCaption, category: "community", mediaDataURL: mediaURL),
                    requestId: reqId
                )
                appState.showToast("Đã đăng bài viết mới!")
                closeCameraView()

            case .story:
                let mediaURL: String
                if !isVideoActive && (originalImage != nil || previewImage != nil) {
                    mediaURL = try await encodeFullResPhotoDataURL()
                } else if !imageDataURL.isEmpty {
                    mediaURL = imageDataURL
                } else if !videoDataURL.isEmpty || capturedVideoTempURL != nil || videoProject != nil {
                    mediaURL = try await resolvePublishVideoDataURL(maxBytes: maxVideoBytes)
                } else {
                    mediaURL = ""
                }
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/stories",
                    method: "POST",
                    body: KinnectWriteBody.story(text: finalCaption, colorHex: "#7C3AED", mediaDataURL: mediaURL),
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

struct PickedMovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked_video_\(UUID().uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovieFile(url: destination)
        }
    }
}

struct StudioMusicPickerSheet: View {
    @Binding var selectedTrack: String
    var onSelectTrack: ((String, URL?) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var calls = NativeWebRTCManager.shared
    @State private var showAudioFilePicker = false
    @State private var previewPlayer: AVPlayer?
    @State private var playingID: String?
    @State private var query: String = ""
    @State private var loading: Bool = false
    @State private var busy: Bool = false
    @State private var errorText: String = ""
    struct MusicTrack: Identifiable, Hashable {
        let id: String
        let title: String
        let artist: String
        let path: String

        static let defaultServerTracks: [MusicTrack] = [
            MusicTrack(id: "/music/tiktok-01.mp3", title: "LIỆU RẰNG · Remix", artist: "Huy PT Remix", path: "/music/tiktok-01.mp3"),
            MusicTrack(id: "/music/tiktok-02.mp3", title: "Xin lỗi vì đã…", artist: "Huy PT Remix", path: "/music/tiktok-02.mp3"),
            MusicTrack(id: "/music/tiktok-03.mp3", title: "EM ĐAU LẮM ANH À · Remix", artist: "Huy PT Remix", path: "/music/tiktok-03.mp3"),
            MusicTrack(id: "/music/tiktok-04.mp3", title: "Nghe có vẻ mọi người không chuộng mixtape", artist: "Huy PT Remix", path: "/music/tiktok-04.mp3"),
            MusicTrack(id: "/music/tiktok-05.mp3", title: "TỰ EM SAI · Remix", artist: "Huy PT Remix", path: "/music/tiktok-05.mp3"),
            MusicTrack(id: "/music/tiktok-06.mp3", title: "Sự đời trớ trêu thay ngay khi…", artist: "Huy PT Remix", path: "/music/tiktok-06.mp3"),
            MusicTrack(id: "/music/tiktok-07.mp3", title: "CÔ DÂU CỦA NGƯỜI TA · Remix", artist: "Huy PT Remix", path: "/music/tiktok-07.mp3"),
            MusicTrack(id: "/music/tiktok-08.mp3", title: "Cứa lên da vết thương không lành…", artist: "Huy PT Remix", path: "/music/tiktok-08.mp3"),
            MusicTrack(id: "/music/tiktok-09.mp3", title: "Em muốn kết thúc như thế này sao?", artist: "Huy PT Remix", path: "/music/tiktok-09.mp3"),
            MusicTrack(id: "/music/tiktok-10.mp3", title: "Âm nhạc dùng để sáng tạo và thưởng thức", artist: "Huy PT Remix", path: "/music/tiktok-10.mp3")
        ]
    }

    @State private var tracks: [MusicTrack] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Button {
                    showAudioFilePicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                        Text(L10n.tr("Chọn tệp âm thanh từ thiết bị"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(KinnectTheme.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(KinnectTheme.borderSoft, lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    stopPreview()
                    selectedTrack = ""
                    onSelectTrack?("", nil)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.slash.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textSecondary)
                        Text(L10n.tr("Không dùng nhạc nền"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(KinnectTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(KinnectTheme.borderSoft, lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(L10n.tr("Thư viện âm thanh Kinnect"))
                    .font(.caption.bold())
                    .foregroundColor(KinnectTheme.textSecondary)
                    .padding(.top, 6)

                if loading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.tr("Đang tải danh sách nhạc…"))
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .padding(.vertical, 8)
                }

                if !errorText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorText)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                        Button {
                            Task { await loadCatalog() }
                        } label: {
                            Text(L10n.tr("Thử lại"))
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(Capsule().fill(KinnectTheme.primaryGradient))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else if !loading && tracks.isEmpty {
                    Text(L10n.tr("Chưa có âm thanh trong thư viện."))
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                }

                ForEach(tracks.filter { query.isEmpty || ($0.title + " " + $0.artist).localizedCaseInsensitiveContains(query) }) { track in
                    let isPlaying = playingID == track.id
                    let isSelected = selectedTrack == track.title
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(KinnectTheme.primaryGradient)
                                .frame(width: 44, height: 44)
                            Image(systemName: isPlaying ? "waveform" : "music.note")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }

                        Button {
                            Task { await select(track) }
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(KinnectTheme.textPrimary)
                                        .lineLimit(1)
                                    Text(track.artist)
                                        .font(.caption)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(KinnectTheme.accentBright)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await preview(track) }
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(isPlaying ? .white : KinnectTheme.accentBright)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle().fill(isPlaying ? KinnectTheme.accent : KinnectTheme.surfaceElevated)
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(L10n.tr("Nghe thử")) \(track.title)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(KinnectTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isSelected ? KinnectTheme.accentBright : KinnectTheme.borderSoft, lineWidth: isSelected ? 1.5 : 1)
                            )
                    )
                    .disabled(busy)
                }
            }
            .padding(16)
        }
        .clipped()
        .background(KinnectTheme.background.ignoresSafeArea())
        .searchable(text: $query, prompt: Text(L10n.tr("Tìm nhạc, nghệ sĩ")))
        .navigationTitle(L10n.tr("Thêm nhạc nền"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text(L10n.tr("Đóng"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .task { await loadCatalog() }
        .refreshable { await loadCatalog() }
        .onDisappear { stopPreview() }
        .onChange(of: calls.activeCall) { call in if call != nil { stopPreview() } }
        .fileImporter(isPresented: $showAudioFilePicker, allowedContentTypes: [.audio]) { result in
            do {
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Kinnect-Music-\(UUID().uuidString).\(url.pathExtension)")
                try FileManager.default.copyItem(at: url, to: destination)
                let title = url.deletingPathExtension().lastPathComponent
                stopPreview()
                selectedTrack = title
                onSelectTrack?(title, destination)
                dismiss()
            } catch { errorText = error.localizedDescription }
        }
    }

    private func loadCatalog() async {
        if tracks.isEmpty, let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/music") {
            let parsed = (cached["tracks"] as? [[String: Any]] ?? []).compactMap { entry -> MusicTrack? in
                guard let path = entry["url"] as? String, !path.isEmpty else { return nil }
                let title = entry["title"] as? String ?? entry["file"] as? String ?? "Âm thanh"
                return MusicTrack(id: path, title: title, artist: entry["artist"] as? String ?? "Kinnect Music", path: path)
            }
            if !parsed.isEmpty { self.tracks = parsed }
        }
        loading = tracks.isEmpty
        errorText = ""
        defer { loading = false }
        do {
            let result = try await KinnectAPIClient.shared.requestJSON("/api/music")
            let parsed = (result["tracks"] as? [[String: Any]] ?? []).compactMap { entry -> MusicTrack? in
                guard let path = entry["url"] as? String, !path.isEmpty else { return nil }
                let title = entry["title"] as? String ?? entry["file"] as? String ?? "Âm thanh"
                return MusicTrack(id: path, title: title, artist: entry["artist"] as? String ?? "Kinnect Music", path: path)
            }
            if !parsed.isEmpty {
                self.tracks = parsed
            }
        } catch {
            if tracks.isEmpty {
                #if DEBUG
                if UIReviewFixture.isEnabled {
                    self.tracks = MusicTrack.defaultServerTracks
                } else {
                    errorText = "\(L10n.tr("Không tải được thư viện nhạc:")) \(error.localizedDescription)"
                }
                #else
                errorText = "\(L10n.tr("Không tải được thư viện nhạc:")) \(error.localizedDescription)"
                #endif
            }
        }
    }

    private func localAudio(_ track: MusicTrack) async throws -> URL {
        let ext = URL(string: track.path)?.pathExtension ?? "mp3"
        do {
            return try await KinnectAuthenticatedFile.fetch(path: track.path, fileExtension: ext.isEmpty ? "mp3" : ext)
        } catch {
            #if DEBUG
            if UIReviewFixture.isEnabled {
                return UIReviewFixture.sampleAudioURL()
            }
            #endif
            throw error
        }
    }

    private func preview(_ track: MusicTrack) async {
        if playingID == track.id { stopPreview(); return }
        guard calls.activeCall == nil else { return }
        stopPreview()
        busy = true
        defer { busy = false }
        do {
            let url = try await localAudio(track)
            guard calls.activeCall == nil else { return }
            playingID = track.id
            previewPlayer = AVPlayer(url: url)
            previewPlayer?.play()
        } catch { errorText = error.localizedDescription }
    }

    private func select(_ track: MusicTrack) async {
        stopPreview()
        busy = true
        defer { busy = false }
        do {
            let url = try await localAudio(track)
            selectedTrack = track.title
            onSelectTrack?(track.title, url)
            dismiss()
        } catch { errorText = error.localizedDescription }
    }

    private func stopPreview() {
        previewPlayer?.pause()
        previewPlayer = nil
        playingID = nil
    }
}

struct StudioProSheet: View {
    @Binding var appliedEffect: String
    let onApply: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private func isSelected(_ pack: StudioProPack) -> Bool {
        if pack.rawValue == appliedEffect { return true }
        switch (pack, appliedEffect) {
        case (.original, "Bộ lọc gốc"): return true
        case (.cinema, "Cinematic Teal & Orange"): return true
        case (.sunset, "Ấm áp hoàng hôn"): return true
        case (.beauty, "Mịn da tự nhiên (Beauty)"): return true
        default: return false
        }
    }

    private func swatchColors(for pack: StudioProPack) -> [Color] {
        switch pack {
        case .original: return [Color(hex: "#6B7280"), Color(hex: "#9CA3AF")]
        case .vivid: return [Color(hex: "#EC4899"), Color(hex: "#8B5CF6")]
        case .cinema: return [Color(hex: "#0F766E"), Color(hex: "#EA580C")]
        case .noir: return [Color(hex: "#111827"), Color(hex: "#6B7280")]
        case .sunset: return [Color(hex: "#F59E0B"), Color(hex: "#EF4444")]
        case .beauty: return [Color(hex: "#F472B6"), Color(hex: "#FBCFE8")]
        }
    }

    private func subtitle(for pack: StudioProPack) -> String {
        switch pack {
        case .original: return L10n.tr("Giữ nguyên màu sắc tự nhiên ban đầu")
        case .vivid: return L10n.tr("Màu sắc rực rỡ, độ tương phản sống động")
        case .cinema: return L10n.tr("Tông màu điện ảnh sâu lắng, có chiều sâu")
        case .noir: return L10n.tr("Đen trắng nghệ thuật tương phản cao")
        case .sunset: return L10n.tr("Ánh vàng ấm áp mang sắc hoàng hôn")
        case .beauty: return L10n.tr("Mịn da tự nhiên, sáng dịu và hài hòa")
        }
    }

    private func filterAssetName(for pack: StudioProPack) -> String {
        switch pack {
        case .original: return "kg20261109_filter_original"
        case .vivid: return "kg20261109_filter_vivid"
        case .cinema: return "kg20261109_filter_cinema"
        case .noir: return "kg20261109_filter_noir"
        case .sunset: return "kg20261109_filter_sunset"
        case .beauty: return "kg20261109_filter_beauty_glow"
        }
    }

    var body: some View {
        Form {
            Section(L10n.tr("Công nghệ Kinnect Studio Pro")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(KinnectTheme.accentBright)
                        Text(L10n.tr("Xử lý chất lượng hình ảnh & video cao cấp"))
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                    }
                    Text(L10n.tr("Áp dụng bộ lọc màu điện ảnh, cân bằng ánh sáng và tăng cường chi tiết sắc nét theo thời gian thực."))
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .padding(.vertical, 4)
            }

            Section(L10n.tr("Bộ lọc màu & Hiệu ứng Pro")) {
                ForEach(StudioProPack.allCases) { pack in
                    let selected = isSelected(pack)
                    Button {
                        onApply(pack.rawValue)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            if let uiImg = UIImage(named: filterAssetName(for: pack)) {
                                Image(uiImage: uiImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(selected ? KinnectTheme.accentBright : Color.white.opacity(0.2), lineWidth: selected ? 2 : 1)
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: swatchColors(for: pack),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(selected ? KinnectTheme.accentBright : Color.white.opacity(0.2), lineWidth: selected ? 2 : 1)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pack.rawValue)
                                    .font(.subheadline.weight(selected ? .bold : .medium))
                                    .foregroundColor(selected ? KinnectTheme.accentBright : KinnectTheme.textPrimary)
                                Text(subtitle(for: pack))
                                    .font(.caption2)
                                    .foregroundColor(KinnectTheme.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(L10n.tr("Kinnect Studio Pro"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Text(L10n.tr("Đóng"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Export Progress HUD
private struct StudioExportProgressHUD: View {
    @ObservedObject var project: StudioVideoProject

    var body: some View {
        if project.isExporting {
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("Đang xuất video… \(Int((project.exportProgress * 100).rounded()))%")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    ProgressView(value: Double(min(1, max(0, project.exportProgress))))
                        .tint(KinnectTheme.accentBright)
                        .frame(width: 220)
                    Button(L10n.tr("Hủy xuất")) {
                        project.cancelExport()
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(red: 0xB9 / 255.0, green: 0x1C / 255.0, blue: 0x47 / 255.0)))
                }
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(KinnectTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(KinnectTheme.borderSoft, lineWidth: 1)
                        )
                )
            }
        }
    }
}

// MARK: - Reactive Video Editor Panels (Observes StudioVideoProject Directly)
private struct StudioVideoTrimPanel: View {
    @ObservedObject var project: StudioVideoProject
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cắt thời lượng video (Trim):")
                    .font(.caption.bold())
                    .foregroundColor(KinnectTheme.textSecondary)
                Spacer()
                Text(String(format: "%.1fs - %.1fs (%.1fs)", project.trimIn, project.trimOut, max(0, project.trimOut - project.trimIn)))
                    .font(.caption.bold())
                    .foregroundColor(KinnectTheme.accentBright)
            }

            let safeDuration = max(0.1, project.duration)
            let minGap = min(0.5, safeDuration * 0.5)

            VStack(spacing: 8) {
                HStack {
                    Text(L10n.tr("Điểm đầu"))
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .frame(width: 50, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { min(project.trimIn, safeDuration) },
                            set: {
                                let clampedOut = min(safeDuration, project.trimOut)
                                project.trimIn = min(max(0, $0), max(0, clampedOut - minGap))
                            }
                        ),
                        in: 0...safeDuration,
                        step: 0.1,
                        onEditingChanged: { editing in
                            if !editing { onChanged() }
                        }
                    )
                    .disabled(project.duration <= 0.1)
                    .tint(KinnectTheme.accentBright)
                    .frame(minHeight: 44)
                }

                HStack {
                    Text(L10n.tr("Điểm cuối"))
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .frame(width: 50, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { min(project.trimOut, safeDuration) },
                            set: {
                                let clamped = min(safeDuration, max($0, min(safeDuration, project.trimIn + minGap)))
                                project.trimOut = clamped
                            }
                        ),
                        in: 0...safeDuration,
                        step: 0.1,
                        onEditingChanged: { editing in
                            if !editing { onChanged() }
                        }
                    )
                    .disabled(project.duration <= 0.1)
                    .tint(KinnectTheme.accentBright)
                    .frame(minHeight: 44)
                }

                HStack(spacing: 8) {
                    Text("Tốc độ")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                    ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { rate in
                        let selected = abs(project.playbackRate - rate) < 0.05
                        Button {
                            project.playbackRate = rate
                            onChanged()
                        } label: {
                            Text("\(String(format: "%.1fx", rate))")
                                .font(.caption2.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(Capsule().fill(selected ? KinnectTheme.accent : KinnectTheme.surfaceElevated))
                                .foregroundColor(selected ? .white : KinnectTheme.textPrimary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct StudioVideoAudioPanel: View {
    @ObservedObject var project: StudioVideoProject
    @Binding var selectedMusicTrack: String
    @Binding var selectedMusicURL: URL?
    let onPickMusic: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(KinnectTheme.accentBright.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: project.musicURL != nil || !selectedMusicTrack.isEmpty ? "music.note.list" : "music.note")
                        .font(.system(size: 20))
                        .foregroundColor(KinnectTheme.accentBright)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.musicTitle.isEmpty ? (selectedMusicTrack.isEmpty ? "Chưa chọn nhạc nền" : selectedMusicTrack) : project.musicTitle)
                        .font(.subheadline.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                        .lineLimit(1)
                    Text(project.musicURL != nil || !project.musicTitle.isEmpty || !selectedMusicTrack.isEmpty ? "Nhạc đã gán • Sẽ trộn vào video khi xuất" : "Nhấn để chọn bài hát hoặc tải từ máy")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                }

                Spacer()

                Button {
                    onPickMusic()
                } label: {
                    Text(project.musicURL != nil || !selectedMusicTrack.isEmpty ? "Đổi bài" : "Chọn nhạc")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(KinnectTheme.primaryGradient))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surface))

            if project.musicURL != nil || !project.musicTitle.isEmpty || !selectedMusicTrack.isEmpty {
                Button(role: .destructive) {
                    project.musicURL = nil
                    project.musicTitle = ""
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
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider().background(KinnectTheme.border)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "video.fill")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                    Text("Âm lượng âm thanh gốc: \(Int(project.originalAudioVolume * 100))%")
                        .font(.caption2.bold())
                        .foregroundColor(KinnectTheme.textSecondary)
                    Spacer()
                }
                Slider(value: $project.originalAudioVolume, in: 0...1, step: 0.05)
                    .tint(KinnectTheme.accentBright)
                    .frame(minHeight: 44)

                HStack {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.accentBright)
                    Text("Âm lượng nhạc nền: \(Int(project.musicVolume * 100))%")
                        .font(.caption2.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                    Spacer()
                }
                Slider(value: $project.musicVolume, in: 0...1, step: 0.05)
                    .tint(KinnectTheme.accentBright)
                    .frame(minHeight: 44)
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

struct TrackedFace: Identifiable {
    let id: Int
    let bounds: CGRect
    let rollAngle: CGFloat
}

final class CameraCaptureController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let movieOutput = AVCaptureMovieFileOutput()
    let metadataOutput = AVCaptureMetadataOutput()
    let sessionQueue = DispatchQueue(label: "kinnect.camera.session.queue")
    private let metadataQueue = DispatchQueue(label: "kinnect.camera.face.metadata")
    weak var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var trackedFaces: [TrackedFace] = []
    private var smoothedFaces: [Int: TrackedFace] = [:]
    @Published var isRecordingVideo: Bool = false
    @Published var availableLenses: [StudioLens] = []
    @Published var activeLens: StudioLens = .wide
    @Published var exposureBias: Float = 0
    @Published var isPermissionDenied: Bool = false
    @Published var isPermissionAuthorized: Bool = false

    var onCapturedImage: ((UIImage) -> Void)?
    var onCapturedVideoData: ((Data, URL) -> Void)?
    private var isConfigured = false
    private var hasAudioInput = false
    private var hasRegisteredLifecycleObservers = false
    private var shouldRunSession = false
    private let positionLock = NSLock()
    private var _currentPosition: AVCaptureDevice.Position = .back
    private var pendingExposureBias: Float = 0
    private var isFlashDesired = false

    private var currentPosition: AVCaptureDevice.Position {
        get {
            positionLock.lock()
            defer { positionLock.unlock() }
            return _currentPosition
        }
        set {
            positionLock.lock()
            _currentPosition = newValue
            positionLock.unlock()
        }
    }

    func configureIfAuthorized() {
        #if !targetEnvironment(simulator)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted {
            DispatchQueue.main.async {
                self.isPermissionDenied = true
                self.isPermissionAuthorized = false
            }
            return
        }
        guard status == .authorized else { return }
        DispatchQueue.main.async {
            self.isPermissionDenied = false
            self.isPermissionAuthorized = true
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.isConfigured {
                // Attach audio input dynamically if mic permission was granted after initial video setup.
                if !self.hasAudioInput && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                    self.session.beginConfiguration()
                    if let audioDevice = AVCaptureDevice.default(for: .audio),
                       let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
                       self.session.canAddInput(audioInput) {
                        self.session.addInput(audioInput)
                        self.hasAudioInput = true
                    }
                    self.session.commitConfiguration()
                }
                self.registerLifecycleObserversIfNeeded()
                self.shouldRunSession = true
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                return
            }
            self.isConfigured = true
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition),
               let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice), self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
                self.hasAudioInput = true
            }
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            if self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
            }
            if self.session.canAddOutput(self.metadataOutput) {
                self.session.addOutput(self.metadataOutput)
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: self.metadataQueue)
            }
            self.applyStabilization()
            self.session.commitConfiguration()
            self.enableFaceMetadataIfSupported()
            self.refreshLenses(position: self.currentPosition)
            self.registerLifecycleObserversIfNeeded()
            self.shouldRunSession = true
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
        #endif
    }

    private func registerLifecycleObserversIfNeeded() {
        #if !targetEnvironment(simulator)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.hasRegisteredLifecycleObservers else { return }
            self.hasRegisteredLifecycleObservers = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.stopForInterruption),
                name: UIApplication.willResignActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.resumeAfterInterruption),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.resumeAfterInterruption),
                name: AVCaptureSession.interruptionEndedNotification,
                object: self.session
            )
        }
        #endif
    }

    func start() {
        #if !targetEnvironment(simulator)
        registerLifecycleObserversIfNeeded()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.shouldRunSession = true
            guard self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
        #endif
    }

    func stop() {
        #if !targetEnvironment(simulator)
        let sessionRef = self.session
        let movieRef = self.movieOutput
        sessionQueue.async { [weak self] in
            self?.shouldRunSession = false
            self?.setTorchLocked(enabled: false)
            if movieRef.isRecording {
                movieRef.stopRecording()
            }
            if sessionRef.isRunning {
                sessionRef.stopRunning()
            }
        }
        #endif
        Task { @MainActor in
            if NativeWebRTCManager.shared.activeCall == nil
                && AppState.shared.currentLiveRoom == nil
                && NativeWebRTCManager.shared.liveLocalVideoTrack == nil {
                MediaPermissionHandler.configureAudioSessionForMedia()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        #if !targetEnvironment(simulator)
        let sessionRef = self.session
        let movieRef = self.movieOutput
        sessionQueue.async {
            if movieRef.isRecording {
                movieRef.stopRecording()
            }
            if sessionRef.isRunning {
                sessionRef.stopRunning()
            }
        }
        #endif
    }

    @objc private func stopForInterruption() {
        #if !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.setTorchLocked(enabled: false)
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
        #endif
    }

    @objc private func resumeAfterInterruption() {
        #if !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let self, self.shouldRunSession, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
        #endif
    }

    func setFlashDesired(_ on: Bool) {
        #if !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.isFlashDesired = on
            self.updateTorchOnSessionQueue()
        }
        #endif
    }

    func switchPosition(front: Bool) {
        #if !targetEnvironment(simulator)
        let pos: AVCaptureDevice.Position = front ? .front : .back
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        sessionQueue.async { [weak self] in
            guard let self, pos != self.currentPosition else { return }
            self.currentPosition = pos
            self.session.beginConfiguration()
            for input in self.session.inputs {
                if let devInput = input as? AVCaptureDeviceInput, devInput.device.hasMediaType(.video) {
                    self.session.removeInput(devInput)
                }
            }
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
               let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            self.applyStabilization()
            self.session.commitConfiguration()
            self.enableFaceMetadataIfSupported()
            self.updateTorchOnSessionQueue()
            self.refreshLenses(position: pos)
            DispatchQueue.main.async {
                self.activeLens = .wide
            }
        }
        #endif
    }

    private func updateTorchOnSessionQueue() {
        #if !targetEnvironment(simulator)
        let shouldTorch = isFlashDesired && currentPosition != .front && movieOutput.isRecording
        setTorchLocked(enabled: shouldTorch)
        #endif
    }

    private func setTorchLocked(enabled: Bool) {
        #if !targetEnvironment(simulator)
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let device = currentVideoDevice() ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let targetMode: AVCaptureDevice.TorchMode = enabled ? .on : .off
            if device.isTorchModeSupported(targetMode) {
                device.torchMode = targetMode
            }
        } catch {
            return
        }
        #endif
    }

    func refreshLenses(position: AVCaptureDevice.Position) {
        let found = StudioLens.allCases.filter {
            AVCaptureDevice.default($0.deviceType, for: .video, position: position) != nil
        }
        let resolved = found.isEmpty ? [.wide] : found
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.availableLenses = resolved
            if !self.availableLenses.contains(self.activeLens) {
                self.activeLens = self.availableLenses.contains(.wide) ? .wide : self.availableLenses[0]
            }
        }
    }

    func selectLens(_ lens: StudioLens, position: AVCaptureDevice.Position) {
        #if !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = AVCaptureDevice.default(lens.deviceType, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            for existing in self.session.inputs {
                if let devInput = existing as? AVCaptureDeviceInput, devInput.device.hasMediaType(.video) {
                    self.session.removeInput(devInput)
                }
            }
            var added = false
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                added = true
            }
            self.applyStabilization()
            self.session.commitConfiguration()
            self.enableFaceMetadataIfSupported()
            self.updateTorchOnSessionQueue()
            if added {
                DispatchQueue.main.async {
                    self.activeLens = lens
                }
            }
        }
        #endif
    }

    func enableFaceMetadataIfSupported() {
        #if !targetEnvironment(simulator)
        if metadataOutput.availableMetadataObjectTypes.contains(.face) {
            metadataOutput.metadataObjectTypes = [.face]
        }
        DispatchQueue.main.async {
            self.smoothedFaces.removeAll()
            self.trackedFaces = []
        }
        #endif
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let faceObjects = metadataObjects.compactMap { $0 as? AVMetadataFaceObject }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let layer = self.previewLayer else {
                if !self.trackedFaces.isEmpty { self.trackedFaces = [] }
                return
            }
            if faceObjects.isEmpty {
                if !self.trackedFaces.isEmpty {
                    self.smoothedFaces.removeAll()
                    self.trackedFaces = []
                }
                return
            }
            var next: [TrackedFace] = []
            var nextCache: [Int: TrackedFace] = [:]
            let alpha: CGFloat = 0.45
            let isFront = self.currentPosition == .front
            for raw in faceObjects {
                guard let transformed = layer.transformedMetadataObject(for: raw) as? AVMetadataFaceObject else { continue }
                let id = transformed.faceID
                let rect = transformed.bounds
                guard rect.width > 12, rect.height > 12 else { continue }
                var roll: CGFloat = 0
                if transformed.hasRollAngle {
                    var deg = transformed.rollAngle
                    if deg > 180 { deg -= 360 }
                    roll = isFront ? -deg : deg
                }
                if let prev = self.smoothedFaces[id] {
                    let bx = prev.bounds.origin.x + (rect.origin.x - prev.bounds.origin.x) * alpha
                    let by = prev.bounds.origin.y + (rect.origin.y - prev.bounds.origin.y) * alpha
                    let bw = prev.bounds.width + (rect.width - prev.bounds.width) * alpha
                    let bh = prev.bounds.height + (rect.height - prev.bounds.height) * alpha
                    let br = prev.rollAngle + (roll - prev.rollAngle) * alpha
                    let smoothed = TrackedFace(id: id, bounds: CGRect(x: bx, y: by, width: bw, height: bh), rollAngle: br)
                    next.append(smoothed)
                    nextCache[id] = smoothed
                } else {
                    let fresh = TrackedFace(id: id, bounds: rect, rollAngle: roll)
                    next.append(fresh)
                    nextCache[id] = fresh
                }
            }
            self.smoothedFaces = nextCache
            self.trackedFaces = next
        }
    }

    func focus(at devicePoint: CGPoint) {
        #if !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentVideoDevice() else { return }
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
        }
        #endif
    }

    func setExposureBias(_ bias: Float) {
        #if !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentVideoDevice() else { return }
            let clamped = min(device.maxExposureTargetBias, max(device.minExposureTargetBias, bias))
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
                self.pendingExposureBias = clamped
                DispatchQueue.main.async { [weak self] in
                    self?.exposureBias = clamped
                }
            } catch {
                return
            }
        }
        #endif
    }

    func adjustExposureBias(by delta: Float) {
        #if !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentVideoDevice() else { return }
            let next = self.pendingExposureBias + delta
            let clamped = min(device.maxExposureTargetBias, max(device.minExposureTargetBias, next))
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
                self.pendingExposureBias = clamped
                DispatchQueue.main.async { [weak self] in
                    self?.exposureBias = clamped
                }
            } catch {
                return
            }
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

    static func simulatorPreviewFallbackImage() -> UIImage {
        let size = CGSize(width: 720, height: 1280)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [
                UIColor(red: 0.11, green: 0.09, blue: 0.18, alpha: 1).cgColor,
                UIColor(red: 0.04, green: 0.03, blue: 0.08, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
        }
    }

    func capturePhoto(flash: Bool) {
        #if DEBUG && targetEnvironment(simulator)
        let fallback = UIReviewFixture.samplePreviewImage()
        DispatchQueue.main.async { [weak self] in
            self?.onCapturedImage?(fallback)
        }
        #elseif targetEnvironment(simulator)
        let fallback = Self.simulatorPreviewFallbackImage()
        DispatchQueue.main.async { [weak self] in
            self?.onCapturedImage?(fallback)
        }
        #else
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning && !self.photoOutput.connections.isEmpty {
                if let conn = self.photoOutput.connection(with: .video) {
                    if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
                    if conn.isVideoMirroringSupported {
                        conn.automaticallyAdjustsVideoMirroring = false
                        conn.isVideoMirrored = (self.currentPosition == .front)
                    }
                }
                let settings: AVCapturePhotoSettings
                if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                } else {
                    settings = AVCapturePhotoSettings()
                }
                if self.photoOutput.supportedFlashModes.contains(flash ? .on : .off) {
                    settings.flashMode = flash ? .on : .off
                }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
                return
            }
            self.configureIfAuthorized()
            Task { @MainActor in
                AppState.shared.showToast("Camera đang khởi động. Vui lòng thử chụp lại sau giây lát.")
            }
        }
        #endif
    }

    func toggleVideoRecording() {
        #if DEBUG && targetEnvironment(simulator)
        if isRecordingVideo {
            isRecordingVideo = false
            let sampleImg = UIReviewFixture.samplePreviewImage()
            Task { @MainActor [weak self] in
                do {
                    let validURL = try await KinnectStillVideo.make(image: sampleImg, durationSeconds: 1.0)
                    let videoBytes = (try? Data(contentsOf: validURL)) ?? Data()
                    self?.onCapturedVideoData?(videoBytes, validURL)
                } catch {
                    AppState.shared.showToast("Không tạo được video mô phỏng: \(error.localizedDescription)")
                }
            }
        } else {
            isRecordingVideo = true
        }
        #elseif targetEnvironment(simulator)
        if isRecordingVideo {
            isRecordingVideo = false
            let sampleImg = Self.simulatorPreviewFallbackImage()
            Task { @MainActor [weak self] in
                do {
                    let validURL = try await KinnectStillVideo.make(image: sampleImg, durationSeconds: 1.0)
                    let videoBytes = (try? Data(contentsOf: validURL)) ?? Data()
                    self?.onCapturedVideoData?(videoBytes, validURL)
                } catch {
                    AppState.shared.showToast("Không tạo được video mô phỏng: \(error.localizedDescription)")
                }
            }
        } else {
            isRecordingVideo = true
        }
        #else
        Task { @MainActor [weak self] in
            guard let self else { return }
            let canReconfigureAudio = (NativeWebRTCManager.shared.activeCall == nil
                && AppState.shared.currentLiveRoom == nil
                && NativeWebRTCManager.shared.liveLocalVideoTrack == nil)
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                if self.movieOutput.isRecording {
                    self.setTorchLocked(enabled: false)
                    self.movieOutput.stopRecording()
                    DispatchQueue.main.async { self.isRecordingVideo = false }
                    return
                }
                if self.session.isRunning && !self.movieOutput.connections.isEmpty {
                    // Khôi phục AVAudioSession sang .playAndRecord phòng trường hợp người dùng vừa xem Shorts (.playback)
                    if canReconfigureAudio {
                        let audioSession = AVAudioSession.sharedInstance()
                        try? audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
                        try? audioSession.setActive(true)
                    }
                    if let conn = self.movieOutput.connection(with: .video) {
                        if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
                        if conn.isVideoMirroringSupported {
                            conn.automaticallyAdjustsVideoMirroring = false
                            conn.isVideoMirrored = (self.currentPosition == .front)
                        }
                    }
                    if self.isFlashDesired && self.currentPosition != .front {
                        self.setTorchLocked(enabled: true)
                    }
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("kinnect_capture_\(UUID().uuidString).mov")
                    self.movieOutput.startRecording(to: tempURL, recordingDelegate: self)
                    DispatchQueue.main.async { self.isRecordingVideo = true }
                    return
                }
                self.configureIfAuthorized()
                Task { @MainActor in
                    AppState.shared.showToast("Camera chưa sẵn sàng để quay video. Vui lòng thử lại sau giây lát.")
                }
            }
        }
        #endif
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let img = UIImage(data: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onCapturedImage?(img)
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        #if !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            self?.setTorchLocked(enabled: false)
        }
        #endif
        let recordingFinishedSuccessfully: Bool
        if let error {
            recordingFinishedSuccessfully = ((error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
        } else {
            recordingFinishedSuccessfully = true
        }
        if !recordingFinishedSuccessfully {
            try? FileManager.default.removeItem(at: outputFileURL)
        }
        let errorDescription = error?.localizedDescription
        DispatchQueue.main.async { [weak self] in
            self?.isRecordingVideo = false
            guard recordingFinishedSuccessfully else {
                Task { @MainActor in
                    let detail = errorDescription.flatMap { $0.isEmpty ? nil : $0 } ?? "Vui lòng thử quay lại."
                    AppState.shared.showToast("Quay video không thành công: \(detail)")
                }
                return
            }
            self?.onCapturedVideoData?(Data(), outputFileURL)
        }
    }
}

struct LiveCameraPreviewView: UIViewControllerRepresentable {
    @ObservedObject var controller: CameraCaptureController
    @Binding var isFlashOn: Bool
    @Binding var isUsingFrontCamera: Bool
    @Binding var showGrid: Bool

    func makeUIViewController(context: Context) -> CameraPreviewViewController {
        let vc = CameraPreviewViewController()
        vc.controller = controller
        vc.setGridVisible(showGrid)
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraPreviewViewController, context: Context) {
        uiViewController.setCamera(front: isUsingFrontCamera)
        uiViewController.setFlash(on: isFlashOn)
        uiViewController.setGridVisible(showGrid)
    }
}

final class CameraPreviewViewController: UIViewController {
    var controller: CameraCaptureController?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let backdropLayer = CAGradientLayer()
    private let gridLayer = CAShapeLayer()
    private var simulatedImageView: UIImageView?
    private var lastConfiguredPosition: AVCaptureDevice.Position? = nil
    private var lastFlashState: Bool? = nil

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
        if let previewLayer {
            previewLayer.frame = view.bounds
            if let conn = previewLayer.connection, conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
        }
    }

    private func setupViewfinderBackdrop() {
        backdropLayer.colors = [
            UIColor(red: 0.11, green: 0.07, blue: 0.22, alpha: 1.0).cgColor,
            UIColor(red: 0.04, green: 0.03, blue: 0.08, alpha: 1.0).cgColor,
            UIColor(red: 0.09, green: 0.05, blue: 0.16, alpha: 1.0).cgColor
        ]
        backdropLayer.locations = [0.0, 0.55, 1.0]
        view.layer.addSublayer(backdropLayer)

        #if DEBUG && targetEnvironment(simulator)
        let sim = UIImageView(image: UIReviewFixture.samplePreviewImage())
        sim.contentMode = .scaleAspectFill
        sim.clipsToBounds = true
        sim.frame = view.bounds
        view.addSubview(sim)
        simulatedImageView = sim
        #elseif targetEnvironment(simulator)
        let sim = UIImageView(image: CameraCaptureController.simulatorPreviewFallbackImage())
        sim.contentMode = .scaleAspectFill
        sim.clipsToBounds = true
        sim.frame = view.bounds
        view.addSubview(sim)
        simulatedImageView = sim
        #endif

        // Grid & Crosshair overlay — hidden by default, toggled via top-bar grid button
        gridLayer.strokeColor = UIColor(red: 0xFD / 255.0, green: 0xD6 / 255.0, blue: 0x63 / 255.0, alpha: 0.58).cgColor
        gridLayer.lineWidth = 1.0
        gridLayer.fillColor = UIColor.clear.cgColor
        gridLayer.isHidden = true
        view.layer.addSublayer(gridLayer)
    }

    func setGridVisible(_ visible: Bool) {
        gridLayer.isHidden = !visible
        if visible {
            updateGridPath()
        }
    }

    private func updateGridPath() {
        let w = view.bounds.width
        let h = view.bounds.height
        guard w > 0, h > 0 else { return }

        // Keep 3x3 composition grid strictly inside the viewfinder safe region
        // (never overlapping Status Bar / top chrome or bottom creative & shutter controls).
        let topInset = max(view.safeAreaInsets.top + 68, 118)
        let bottomInset = max(view.safeAreaInsets.bottom + 248, 276)
        let gridHeight = max(120, h - topInset - bottomInset)
        let gridRect = CGRect(x: 0, y: topInset, width: w, height: gridHeight)

        let path = UIBezierPath()

        // 3x3 Grid
        path.move(to: CGPoint(x: gridRect.minX + gridRect.width / 3, y: gridRect.minY))
        path.addLine(to: CGPoint(x: gridRect.minX + gridRect.width / 3, y: gridRect.maxY))
        path.move(to: CGPoint(x: gridRect.minX + 2 * gridRect.width / 3, y: gridRect.minY))
        path.addLine(to: CGPoint(x: gridRect.minX + 2 * gridRect.width / 3, y: gridRect.maxY))
        path.move(to: CGPoint(x: gridRect.minX, y: gridRect.minY + gridRect.height / 3))
        path.addLine(to: CGPoint(x: gridRect.maxX, y: gridRect.minY + gridRect.height / 3))
        path.move(to: CGPoint(x: gridRect.minX, y: gridRect.minY + 2 * gridRect.height / 3))
        path.addLine(to: CGPoint(x: gridRect.maxX, y: gridRect.minY + 2 * gridRect.height / 3))

        // Amber balance center crosshair (+) inside viewfinder center
        let cx = gridRect.midX
        let cy = gridRect.midY
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
        } else {
            #if DEBUG
            let isFixture = UIReviewFixture.isEnabled
            #else
            let isFixture = false
            #endif
            if status == .notDetermined && !isFixture {
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard granted else { return }
                    DispatchQueue.main.async {
                        self?.attachHardwarePreview()
                    }
                }
            }
        }
        #endif
    }

    private func attachHardwarePreview() {
        #if !targetEnvironment(simulator)
        guard let ctrl = controller else { return }
        ctrl.configureIfAuthorized()
        if previewLayer == nil {
            let layer = AVCaptureVideoPreviewLayer(session: ctrl.session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            if let conn = layer.connection, conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
            view.layer.insertSublayer(layer, at: 0)
            previewLayer = layer
            ctrl.previewLayer = layer
            backdropLayer.isHidden = true
            simulatedImageView?.removeFromSuperview()
            simulatedImageView = nil
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleFocusTap(_:)))
            view.addGestureRecognizer(tap)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleExposurePan(_:)))
            view.addGestureRecognizer(pan)
        } else {
            previewLayer?.frame = view.bounds
            backdropLayer.isHidden = true
        }
        ctrl.start()
        #endif
    }

    @objc private func handleFocusTap(_ gesture: UITapGestureRecognizer) {
        guard let previewLayer else { return }
        let point = previewLayer.captureDevicePointConverted(fromLayerPoint: gesture.location(in: view))
        controller?.focus(at: point)
    }

    @objc private func handleExposurePan(_ gesture: UIPanGestureRecognizer) {
        let delta = Float(-gesture.translation(in: view).y / 120)
        controller?.adjustExposureBias(by: delta)
        gesture.setTranslation(.zero, in: view)
    }

    func setCamera(front: Bool) {
        #if !targetEnvironment(simulator)
        let pos: AVCaptureDevice.Position = front ? .front : .back
        guard pos != lastConfiguredPosition else { return }
        lastConfiguredPosition = pos
        controller?.switchPosition(front: front)
        #endif
    }

    func setFlash(on: Bool) {
        #if !targetEnvironment(simulator)
        guard on != lastFlashState else { return }
        lastFlashState = on
        controller?.setFlashDesired(on)
        #endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        #if !targetEnvironment(simulator)
        controller?.stop()
        #endif
    }
}

final class PhotoSaveCoordinator: NSObject {
    private static let lock = NSLock()
    private static var active: [ObjectIdentifier: PhotoSaveCoordinator] = [:]
    private let onComplete: (Bool, Error?) -> Void

    private init(onComplete: @escaping (Bool, Error?) -> Void) {
        self.onComplete = onComplete
    }

    static func saveImage(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        let coordinator = PhotoSaveCoordinator(onComplete: completion)
        let id = ObjectIdentifier(coordinator)
        lock.lock()
        active[id] = coordinator
        lock.unlock()
        UIImageWriteToSavedPhotosAlbum(
            image,
            coordinator,
            #selector(PhotoSaveCoordinator.image(_:didFinishSavingWithError:contextInfo:)),
            nil
        )
    }

    static func saveVideo(atPath path: String, completion: @escaping (Bool, Error?) -> Void) {
        let coordinator = PhotoSaveCoordinator(onComplete: completion)
        let id = ObjectIdentifier(coordinator)
        lock.lock()
        active[id] = coordinator
        lock.unlock()
        UISaveVideoAtPathToSavedPhotosAlbum(
            path,
            coordinator,
            #selector(PhotoSaveCoordinator.video(_:didFinishSavingWithError:contextInfo:)),
            nil
        )
    }

    private func finish(error: Error?) {
        let id = ObjectIdentifier(self)
        Self.lock.lock()
        Self.active.removeValue(forKey: id)
        Self.lock.unlock()
        DispatchQueue.main.async {
            self.onComplete(error == nil, error)
        }
    }

    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer?) {
        finish(error: error)
    }

    @objc func video(_ videoPath: String, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer?) {
        finish(error: error)
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
                Task { @MainActor in
                    self.currentTime = sec
                }
            }
        }

        // Observe end of playback using retained token to prevent memory leak
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem,
            queue: .main
        ) { [weak p] _ in
            Task { @MainActor in
                p?.seek(to: .zero)
                p?.play()
                self.isPlaying = true
            }
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
