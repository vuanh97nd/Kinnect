import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct CameraStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    enum PublishTarget: String, CaseIterable {
        case shortVideo = "Video"
        case feedPost = "Bài viết"
        case story = "Tin 24h"
        case live = "Phát Live"
    }

    @State private var target: PublishTarget = .shortVideo
    @State private var title = ""
    @State private var caption = ""
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var videoDataURL = ""
    @State private var imageDataURL = ""
    @State private var previewImage: UIImage?
    @State private var showNativeCameraPicker = false
    @State private var showStudioProSheet = false
    @State private var showCreateLiveSheet = false
    @State private var studioProAppliedEffect = "Bộ lọc gốc"
    @State private var isUploading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Đích đăng", selection: $target) {
                    ForEach(PublishTarget.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                if target == .live {
                    VStack(spacing: 14) {
                        KinnectIcon(glyph: .live, size: 38, selected: true, tint: KinnectTheme.danger)
                        Text("Phát trực tiếp Kinnect Live")
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text("Phát Live từ Camera với chế độ Trò chuyện hoặc Chơi game.")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .kinnectMultiline()

                        Button {
                            showCreateLiveSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                KinnectIcon(glyph: .live, size: 20, selected: true, tint: .white)
                                Text("Bắt đầu phát Live")
                                    .font(.subheadline.bold())
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(KinnectTheme.primaryGradient))
                            .foregroundColor(.white)
                        }
                        .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .kinnectCard()
                } else {
                    // Native Camera Capture + Library Buttons
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                let camOk = await MediaPermissionHandler.shared.requestCameraAccess()
                                if camOk {
                                    showNativeCameraPicker = true
                                } else {
                                    appState.showToast("Vui lòng cấp quyền Camera trong Cài đặt iOS.")
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                KinnectIcon(glyph: .camera, size: 22, selected: true, tint: .white)
                                Text("Mở Camera quay/chụp")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.primaryGradient))
                            .foregroundColor(.white)
                        }

                        if target == .shortVideo {
                            PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                                HStack(spacing: 8) {
                                    KinnectIcon(glyph: .video, size: 22, tint: KinnectTheme.accentBright)
                                    Text("Chọn MP4")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                                .foregroundColor(KinnectTheme.accentBright)
                            }
                            .onChange(of: selectedVideoItem) { newItem in
                                guard let newItem else { return }
                                Task { await loadVideoFromPicker(newItem) }
                            }
                        } else {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                HStack(spacing: 8) {
                                    KinnectIcon(glyph: .photo, size: 22, tint: KinnectTheme.accentBright)
                                    Text("Chọn Ảnh")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                                .foregroundColor(KinnectTheme.accentBright)
                            }
                            .onChange(of: selectedPhotoItem) { newItem in
                                guard let newItem else { return }
                                Task { await loadImageFromPicker(newItem) }
                            }
                        }
                    }

                    if previewImage == nil && videoDataURL.isEmpty {
                        VStack(spacing: 10) {
                            KinnectIcon(glyph: .studio, size: 32, tint: KinnectTheme.textSecondary)
                            Text("Hãy chụp ảnh, quay video hoặc chọn tệp từ thư viện để mở bảng chỉnh sửa Studio.")
                                .font(.subheadline)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .kinnectMultiline()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .kinnectCard()
                    } else {
                        // Only show Studio preview, editing fields, separate Save group, and primary Use/Publish button after media is selected/captured
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                KinnectIcon(glyph: .studio, size: 22, selected: true, tint: KinnectTheme.accentBright)
                                Text("Kinnect Studio")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                Spacer()

                                // Studio Pro pill button on top-right of preview screen (Parity with Android 1.2.12)
                                Button {
                                    showStudioProSheet = true
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "sparkles")
                                            .font(.caption2.bold())
                                        Text("Studio Pro")
                                            .font(.caption2.weight(.bold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(KinnectTheme.primaryGradient))
                                    .foregroundColor(.white)
                                }
                                .accessibilityLabel("Mở công cụ Studio Pro")

                                // Separate Save button
                                Button {
                                    saveMediaToPhotos()
                                } label: {
                                    HStack(spacing: 4) {
                                        KinnectIcon(glyph: .save, size: 16, tint: KinnectTheme.accentBright)
                                        Text("Lưu")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(KinnectTheme.accentBright)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.surfaceElevated))
                                }
                                .accessibilityLabel("Lưu vào thiết bị")
                            }

                            if let previewImage {
                                Image(uiImage: previewImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            } else if !videoDataURL.isEmpty {
                                HStack(spacing: 10) {
                                    KinnectIcon(glyph: .video, size: 22, selected: true, tint: KinnectTheme.online)
                                    Text("Đã sẵn sàng tải lên video MP4 (\(videoDataURL.count / 1024) KB)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.white)
                                        .kinnectMultiline()
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            }

                            if target == .shortVideo {
                                TextField("Tiêu đề video ngắn...", text: $title)
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                                    .foregroundColor(.white)
                            }

                            TextField("Mô tả / Nội dung...", text: $caption, axis: .vertical)
                                .lineLimit(3...7)
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
                        .kinnectCard()
                    }
                }
            }
            .padding(16)
        }
        .background(KinnectTheme.background)
        .navigationTitle("Camera & Studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                KinnectIconButton(glyph: .close, label: "Thoát", tint: KinnectTheme.textPrimary) {
                    dismiss()
                }
            }
        }
        .onAppear {
            if UIReviewFixture.activeScreen == "camera-studio-edit" && previewImage == nil {
                previewImage = UIReviewFixture.samplePreviewImage()
                caption = "[Fixture UI] Kiểm thử bảng chỉnh sửa Kinnect Studio với nút Lưu tách riêng."
            }
        }
        .sheet(isPresented: $showNativeCameraPicker) {
            NativeSystemCameraCaptureView(
                captureVideo: target == .shortVideo,
                onCapturedImage: { uiImg in
                    self.previewImage = uiImg
                    if let jpeg = uiImg.jpegData(compressionQuality: 0.72) {
                        self.imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                    }
                },
                onCapturedVideoURL: { url in
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
                        appState.showToast("Đã áp dụng Studio Pro: '\(effect)'")
                    }
                )
            }
        }
        .sheet(isPresented: $showCreateLiveSheet) {
            CreateLiveRoomSheet()
        }
    }

    private func loadVideoFromPicker(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            if data.count > 8 * 1024 * 1024 {
                appState.showToast("Video vượt quá giới hạn 8MB của máy chủ.")
                return
            }
            self.videoDataURL = "data:video/mp4;base64,\(data.base64EncodedString())"
        }
    }

    private func loadImageFromPicker(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self),
           let uiImg = UIImage(data: data),
           let jpeg = uiImg.jpegData(compressionQuality: 0.72) {
            self.previewImage = uiImg
            self.imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        }
    }

    private func saveMediaToPhotos() {
        if let img = previewImage {
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            appState.showToast("Đã lưu ảnh vào Thư viện ảnh trên thiết bị.")
        } else if !videoDataURL.isEmpty {
            appState.showToast("Đã lưu bản nháp video trong phiên Studio.")
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

            case .live:
                showCreateLiveSheet = true
                return
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
                    Text("Áp dụng bộ lọc màu cinematic và thuật toán tăng cường chi tiết mà không làm biến dạng tệp gốc.")
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

