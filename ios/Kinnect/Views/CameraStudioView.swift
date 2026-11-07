import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import UIKit

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

    // Media Data
    @State private var originalImage: UIImage?
    @State private var previewImage: UIImage?
    @State private var videoDataURL = ""
    @State private var capturedVideoTempURL: URL?
    @State private var imageDataURL = ""
    @State private var title = ""
    @State private var caption = ""

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
            cameraController.onCapturedImage = { uiImg in
                self.originalImage = uiImg
                self.previewImage = uiImg
                self.target = .feedPost
                if let jpeg = uiImg.jpegData(compressionQuality: 0.75) {
                    self.imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                }
            }
            cameraController.onCapturedVideoData = { data, tempURL in
                self.capturedVideoTempURL = tempURL
                self.target = .shortVideo
                if data.count > 8 * 1024 * 1024 {
                    appState.showToast("Video vượt quá giới hạn 8MB của máy chủ.")
                } else {
                    self.videoDataURL = "data:video/mp4;base64,\(data.base64EncodedString())"
                }
            }
            if UIReviewFixture.activeScreen == "camera-studio-video" {
                captureMode = .video
            }
            if UIReviewFixture.activeScreen == "camera-studio-video-edit" && previewImage == nil {
                let sample = UIReviewFixture.samplePreviewImage()
                originalImage = sample
                previewImage = sample
                target = .shortVideo
                videoDataURL = "data:video/mp4;base64,AAAA"
                title = "[Fixture UI] Video ngắn kiểm thử"
                caption = "Video ngắn quay bằng Kinnect Camera Studio với điều khiển xuất bản."
            }
            if UIReviewFixture.activeScreen == "camera-studio-edit" && previewImage == nil {
                let sample = UIReviewFixture.samplePreviewImage()
                originalImage = sample
                previewImage = sample
                caption = "[Fixture UI] Kiểm thử bảng chỉnh sửa Kinnect Studio với nút Lưu tách riêng."
            }
        }
        .sheet(isPresented: $showMusicPickerSheet) {
            NavigationStack {
                StudioMusicPickerSheet(selectedTrack: $selectedMusicTrack)
            }
        }
        .sheet(isPresented: $showStudioProSheet) {
            NavigationStack {
                StudioProSheet(
                    appliedEffect: $studioProAppliedEffect,
                    onApply: { effect in
                        studioProAppliedEffect = effect
                        if let base = originalImage {
                            let filtered = applyProFilter(named: effect, to: base)
                            self.previewImage = filtered
                            if let jpeg = filtered.jpegData(compressionQuality: 0.75) {
                                self.imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                            }
                        }
                        appState.showToast("Đã áp dụng Studio Pro: '\(effect)'")
                    }
                )
            }
        }
        .sheet(isPresented: $showCreateLiveSheet) {
            CreateLiveRoomSheet()
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

            VStack(spacing: 0) {
                // Top Camera Chrome: Close, Aspect ratio 9:16, Music, Flash
                HStack(spacing: 16) {
                    KinnectIconButton(glyph: .close, label: "Thoát Camera", tint: .white) {
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

    // MARK: - Media Edit Mode
    private var mediaEditMode: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with Studio Pro in Top-Right + Distinct Save Button
                HStack(spacing: 10) {
                    KinnectIcon(glyph: .studio, size: 22, selected: true, tint: KinnectTheme.accentBright)
                    Text("Kinnect Studio")
                        .font(.headline.bold())
                        .foregroundColor(.white)

                    Spacer()

                    // Studio Pro pill button on top-right (Parity Android 1.2.12 StudioActivity)
                    Button {
                        showStudioProSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.caption.bold())
                            Text("Studio Pro")
                                .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(KinnectTheme.primaryGradient))
                        .foregroundColor(.white)
                    }
                    .accessibilityLabel("Mở bảng bộ lọc Studio Pro")

                    // Distinct Save Button (actually writes to device Photos Library)
                    Button {
                        saveMediaToPhotos()
                    } label: {
                        HStack(spacing: 4) {
                            KinnectIcon(glyph: .save, size: 16, tint: KinnectTheme.accentBright)
                            Text("Lưu")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(KinnectTheme.accentBright)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.surfaceElevated))
                    }
                    .accessibilityLabel("Lưu vào thiết bị")
                }
                .padding(.horizontal, 4)

                // Large Media Preview (Photo or Video Player Interface)
                if let displayImg = previewImage ?? (UIReviewFixture.activeScreen == "camera-studio-edit" ? UIReviewFixture.samplePreviewImage() : nil) {
                    ZStack(alignment: .bottom) {
                        Image(uiImage: displayImg)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(KinnectTheme.border, lineWidth: 1)
                            )

                        if target == .shortVideo || !videoDataURL.isEmpty {
                            // Centered Video Playback Indicator
                            VStack {
                                Spacer()
                                Image(systemName: "pause.circle.fill")
                                    .font(.system(size: 48, weight: .light))
                                    .foregroundColor(.white.opacity(0.9))
                                    .shadow(color: .black.opacity(0.6), radius: 8)
                                Spacer()
                            }

                            // Bottom Video Controls & Scrubber Timeline
                            VStack(spacing: 6) {
                                HStack(spacing: 8) {
                                    // Progress Bar
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.white.opacity(0.3))
                                                .frame(height: 4)
                                            Capsule()
                                                .fill(KinnectTheme.primaryGradient)
                                                .frame(width: geo.size.width * 0.53, height: 4)
                                        }
                                    }
                                    .frame(height: 4)

                                    Text("00:08 / 00:15")
                                        .font(.caption2.monospacedDigit().weight(.semibold))
                                        .foregroundColor(.white)
                                }

                                HStack {
                                    HStack(spacing: 4) {
                                        Image(systemName: "film.fill")
                                            .font(.system(size: 10))
                                        Text("HD 1080p • 30fps")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.black.opacity(0.6)))
                                    .foregroundColor(.white.opacity(0.9))

                                    Spacer()

                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.9))
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
                } else if !videoDataURL.isEmpty {
                    HStack(spacing: 12) {
                        KinnectIcon(glyph: .video, size: 28, selected: true, tint: KinnectTheme.online)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Đã tải video MP4 thành công (\(videoDataURL.count / 1024) KB)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Text("Sẵn sàng đăng lên luồng Video Shorts.")
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated))
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
        }
        .navigationTitle("Chỉnh sửa Studio")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                KinnectIconButton(glyph: .close, label: "Hủy bỏ", tint: KinnectTheme.textPrimary) {
                    // Reset back to viewfinder or dismiss
                    originalImage = nil
                    previewImage = nil
                    videoDataURL = ""
                }
            }
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
            output = ciInput.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: 0.05,
                kCIInputContrastKey: 1.05
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
    private func saveMediaToPhotos() {
        if let img = previewImage {
            PhotoSaveCoordinator.shared.onComplete = { success, error in
                if success {
                    appState.showToast("Đã lưu ảnh vào Album ảnh trên thiết bị.")
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
        } else if let tempURL = capturedVideoTempURL {
            PhotoSaveCoordinator.shared.onComplete = { success, error in
                if success {
                    appState.showToast("Đã lưu video vào Album ảnh trên thiết bị.")
                } else {
                    appState.showToast("Không thể lưu video: \(error?.localizedDescription ?? "Lỗi quyền truy cập")")
                }
            }
            UISaveVideoAtPathToSavedPhotosAlbum(
                tempURL.path,
                PhotoSaveCoordinator.shared,
                #selector(PhotoSaveCoordinator.video(_:didFinishSavingWithError:contextInfo:)),
                nil
            )
        } else if !videoDataURL.isEmpty {
            if let range = videoDataURL.range(of: "base64,") {
                let b64 = String(videoDataURL[range.upperBound...])
                if let data = Data(base64Encoded: b64) {
                    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("kinnect_saved_\(UUID().uuidString).mp4")
                    try? data.write(to: tempFile)
                    PhotoSaveCoordinator.shared.onComplete = { success, error in
                        if success {
                            appState.showToast("Đã lưu video vào Album ảnh trên thiết bị.")
                        } else {
                            appState.showToast("Không thể lưu video: \(error?.localizedDescription ?? "Lỗi quyền truy cập")")
                        }
                    }
                    UISaveVideoAtPathToSavedPhotosAlbum(
                        tempFile.path,
                        PhotoSaveCoordinator.shared,
                        #selector(PhotoSaveCoordinator.video(_:didFinishSavingWithError:contextInfo:)),
                        nil
                    )
                }
            }
        }
    }

    private func loadMediaFromLibrary(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            if let uiImg = UIImage(data: data) {
                self.originalImage = uiImg
                self.previewImage = uiImg
                self.target = .feedPost
                if let jpeg = uiImg.jpegData(compressionQuality: 0.75) {
                    self.imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                }
            } else {
                if data.count > 8 * 1024 * 1024 {
                    appState.showToast("Video vượt quá giới hạn 8MB.")
                    return
                }
                self.videoDataURL = "data:video/mp4;base64,\(data.base64EncodedString())"
                self.target = .shortVideo
            }
        }
    }

    private func publishContent() async {
        isUploading = true
        defer { isUploading = false }
        let reqId = "studio_\(UUID().uuidString)"
        let cleanCap = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCaption = selectedMusicTrack.isEmpty ? cleanCap : (cleanCap.isEmpty ? "🎵 \(selectedMusicTrack)" : "\(cleanCap) • 🎵 \(selectedMusicTrack)")

        do {
            switch target {
            case .shortVideo:
                guard !videoDataURL.isEmpty else {
                    appState.showToast("Vui lòng quay hoặc chọn một video MP4 (< 8MB).")
                    return
                }
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/shorts",
                    method: "POST",
                    body: [
                        "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                        "caption": finalCaption,
                        "videoDataUrl": videoDataURL,
                        "durationSec": 15
                    ],
                    requestId: reqId
                )
                appState.showToast("Đã đăng video ngắn thành công!")
                dismiss()

            case .feedPost:
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/posts",
                    method: "POST",
                    body: [
                        "text": finalCaption,
                        "category": "community",
                        "imageUrl": imageDataURL
                    ],
                    requestId: reqId
                )
                appState.showToast("Đã đăng bài viết mới!")
                dismiss()

            case .story:
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/stories",
                    method: "POST",
                    body: [
                        "text": finalCaption,
                        "imageUrl": imageDataURL,
                        "backgroundColor": "#7C3AED"
                    ],
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
    @Environment(\.dismiss) private var dismiss

    private let tracks: [(String, String)] = [
        ("", "Không dùng nhạc nền"),
        ("Lofi Chill Sài Gòn", "Giai điệu thư giãn • 85 BPM"),
        ("Acoustic Ban Mai", "Guitar mộc nhẹ nhàng • 98 BPM"),
        ("Synthwave Đêm", "Năng động hiện đại • 118 BPM"),
        ("Piano Mùa Thu", "Cảm xúc sâu lắng • 76 BPM")
    ]

    var body: some View {
        List {
            Section("Chọn nhạc nền cho bài đăng / Video Shorts") {
                ForEach(tracks, id: \.0) { track, subtitle in
                    Button {
                        selectedTrack = track
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: track.isEmpty ? "speaker.slash.fill" : "music.note.list")
                                .foregroundColor(selectedTrack == track ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.isEmpty ? subtitle : track)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                if !track.isEmpty {
                                    Text(subtitle)
                                        .font(.caption2)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                }
                            }
                            Spacer()
                            if selectedTrack == track {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KinnectTheme.background)
        .navigationTitle("Thêm nhạc")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Đóng") { dismiss() }
            }
        }
    }
}

struct StudioProSheet: View {
    @Binding var appliedEffect: String
    let onApply: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let proFilters = [
        "Bộ lọc gốc",
        "Kinnect Vivid",
        "Cinematic Teal & Orange",
        "Mịn da tự nhiên (Beauty)",
        "Noir Cổ điển",
        "Ấm áp hoàng hôn"
    ]

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
final class CameraCaptureController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let movieOutput = AVCaptureMovieFileOutput()
    @Published var isRecordingVideo: Bool = false

    var onCapturedImage: ((UIImage) -> Void)?
    var onCapturedVideoData: ((Data, URL) -> Void)?
    private var isConfigured = false

    func configureIfAuthorized() {
        #if !targetEnvironment(simulator)
        guard !isConfigured else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized else { return }
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
        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
        #endif
    }

    func capturePhoto(flash: Bool) {
        #if !targetEnvironment(simulator)
        if session.isRunning && !photoOutput.connections.isEmpty {
            let settings = AVCapturePhotoSettings()
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.04, blue: 0.09, alpha: 1.0)
        setupViewfinderBackdrop()
        setupSessionIfAuthorized()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdropLayer.frame = view.bounds
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

        gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.12).cgColor
        gridLayer.lineWidth = 0.8
        gridLayer.fillColor = UIColor.clear.cgColor
        view.layer.addSublayer(gridLayer)
    }

    private func updateGridPath() {
        let w = view.bounds.width
        let h = view.bounds.height
        guard w > 0, h > 0 else { return }
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w / 3, y: 0))
        path.addLine(to: CGPoint(x: w / 3, y: h))
        path.move(to: CGPoint(x: 2 * w / 3, y: 0))
        path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
        path.move(to: CGPoint(x: 0, y: h / 3))
        path.addLine(to: CGPoint(x: w, y: h / 3))
        path.move(to: CGPoint(x: 0, y: 2 * h / 3))
        path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
        gridLayer.path = path.cgPath
    }

    private func setupSessionIfAuthorized() {
        #if !targetEnvironment(simulator)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            attachHardwarePreview()
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
        view.layer.addSublayer(layer)
        previewLayer = layer
        #endif
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
        session.commitConfiguration()
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
