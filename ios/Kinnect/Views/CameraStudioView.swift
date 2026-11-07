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
    @State private var captureMode: CaptureMode = .photo
    @State private var target: PublishTarget = .feedPost
    @State private var showNativeCameraPicker = false
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

    var body: some View {
        Group {
            if previewImage == nil && videoDataURL.isEmpty {
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
            if UIReviewFixture.activeScreen == "camera-studio-edit" && previewImage == nil {
                let sample = UIReviewFixture.samplePreviewImage()
                originalImage = sample
                previewImage = sample
                caption = "[Fixture UI] Kiểm thử bảng chỉnh sửa Kinnect Studio với nút Lưu tách riêng."
            }
        }
        .sheet(isPresented: $showNativeCameraPicker) {
            NativeSystemCameraCaptureView(
                captureVideo: captureMode == .video,
                onCapturedImage: { uiImg in
                    self.originalImage = uiImg
                    self.previewImage = uiImg
                    self.target = .feedPost
                    if let jpeg = uiImg.jpegData(compressionQuality: 0.75) {
                        self.imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                    }
                },
                onCapturedVideoURL: { url in
                    self.capturedVideoTempURL = url
                    self.target = .shortVideo
                    if let data = try? Data(contentsOf: url) {
                        if data.count > 8 * 1024 * 1024 {
                            appState.showToast("Video vượt quá giới hạn 8MB của máy chủ.")
                        } else {
                            self.videoDataURL = "data:video/mp4;base64,\(data.base64EncodedString())"
                        }
                    }
                }
            )
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
            // Simulated live camera viewport / background canvas
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Camera Chrome: Close, Aspect ratio 9:16, Music, Flash
                HStack(spacing: 16) {
                    KinnectIconButton(glyph: .close, label: "Thoát Camera", tint: .white) {
                        dismiss()
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.caption2)
                        Text("Thêm nhạc")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .foregroundColor(.white)

                    Spacer()

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

                // Center viewfinder guidelines
                VStack(spacing: 12) {
                    KinnectIcon(glyph: .camera, size: 48, tint: .white.opacity(0.6))
                    Text("Chạm nút chụp hoặc mở Camera hệ thống")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

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

                        // Primary Camera Shutter Button
                        Button {
                            if captureMode == .live {
                                showCreateLiveSheet = true
                            } else {
                                Task {
                                    let camOk = await MediaPermissionHandler.shared.requestCameraAccess()
                                    if camOk {
                                        showNativeCameraPicker = true
                                    } else {
                                        appState.showToast("Vui lòng cấp quyền Camera trong Cài đặt iOS.")
                                    }
                                }
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 76, height: 76)
                                Circle()
                                    .fill(captureMode == .live ? KinnectTheme.danger : (captureMode == .video ? Color.red : Color.white))
                                    .frame(width: 62, height: 62)
                            }
                        }
                        .accessibilityLabel("Nút chụp hoặc quay video")

                        // Fast switch to native capture
                        Button {
                            showNativeCameraPicker = true
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
                        .accessibilityLabel("Chuyển camera")
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

                // Large Media Preview
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(KinnectTheme.border, lineWidth: 1)
                        )
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
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            appState.showToast("Đã lưu ảnh vào Album ảnh trên thiết bị.")
        } else if let tempURL = capturedVideoTempURL {
            UISaveVideoAtPathToSavedPhotosAlbum(tempURL.path, nil, nil, nil)
            appState.showToast("Đã lưu video vào Album ảnh trên thiết bị.")
        } else if !videoDataURL.isEmpty {
            if let range = videoDataURL.range(of: "base64,") {
                let b64 = String(videoDataURL[range.upperBound...])
                if let data = Data(base64Encoded: b64) {
                    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("kinnect_saved_\(UUID().uuidString).mp4")
                    try? data.write(to: tempFile)
                    UISaveVideoAtPathToSavedPhotosAlbum(tempFile.path, nil, nil, nil)
                    appState.showToast("Đã lưu video vào Album ảnh trên thiết bị.")
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
                        "caption": caption.trimmingCharacters(in: .whitespacesAndNewlines),
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
                        "text": caption.trimmingCharacters(in: .whitespacesAndNewlines),
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
                        "text": caption.trimmingCharacters(in: .whitespacesAndNewlines),
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

struct NativeSystemCameraCaptureView: UIViewControllerRepresentable {
    let captureVideo: Bool
    let onCapturedImage: (UIImage) -> Void
    let onCapturedVideoURL: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: NativeSystemCameraCaptureView
        init(_ parent: NativeSystemCameraCaptureView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                parent.onCapturedVideoURL(url)
            } else if let img = info[.originalImage] as? UIImage {
                parent.onCapturedImage(img)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            if captureVideo, let types = UIImagePickerController.availableMediaTypes(for: .camera), types.contains("public.movie") {
                picker.mediaTypes = ["public.movie"]
                picker.videoMaximumDuration = 30
                picker.videoQuality = .typeMedium
            }
        } else {
            picker.sourceType = .photoLibrary
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
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
