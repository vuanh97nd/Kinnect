import AVFoundation
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
            MusicTrack(id: "/music/tiktok-01.mp3", title: "LIỆU RẰNG · Remix DEMO", artist: "Huy PT Remix", path: "/music/tiktok-01.mp3"),
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

    @State private var tracks: [MusicTrack] = MusicTrack.defaultServerTracks

    var body: some View {
        List {
            Section {
                Button("Chọn tệp âm thanh từ thiết bị") { showAudioFilePicker = true }
                Button("Không dùng nhạc nền") {
                    stopPreview()
                    selectedTrack = ""
                    onSelectTrack?("", nil)
                    dismiss()
                }
            }
            Section("Thư viện âm thanh Kinnect") {
                if loading { ProgressView("Đang tải danh sách nhạc…") }
                if !errorText.isEmpty {
                    Text(errorText).foregroundColor(.secondary)
                    Button("Thử lại") { Task { await loadCatalog() } }
                } else if !loading && tracks.isEmpty {
                    Text("Chưa có âm thanh trong thư viện.")
                }
                ForEach(tracks.filter { MusicPickerQuery.matches(title: $0.title, artist: $0.artist, query: query) }) { track in
                    HStack(spacing: 12) {
                        Button {
                            Task { await preview(track) }
                        } label: {
                            Image(systemName: playingID == track.id ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 32))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Nghe thử \(track.title)")
                        Button {
                            Task { await select(track) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title).font(.subheadline.bold())
                                    Text(track.artist).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedTrack == track.title { Image(systemName: "checkmark.circle.fill") }
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .disabled(busy)
                }
            }
        }
        .searchable(text: $query, prompt: "Tìm nhạc, nghệ sĩ")
        .navigationTitle("Thêm nhạc nền")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
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
        if UIReviewFixture.isEnabled {
            tracks = [
                MusicTrack(id: "fixture-track-1", title: "Giai điệu kết nối", artist: "Kinnect Audio · 3:05", path: "/music/fixture-1.mp3"),
                MusicTrack(id: "fixture-track-2", title: "Nắng sớm thành phố", artist: "Minh Anh feat. Nam · 3:30", path: "/music/fixture-2.mp3"),
                MusicTrack(id: "fixture-track-3", title: "Khoảnh khắc thanh xuân", artist: "Kinnect Vibes · 3:15", path: "/music/fixture-3.mp3"),
                MusicTrack(id: "fixture-track-4", title: "Nhịp đập cuộc sống", artist: "Bảo Ngọc · 4:00", path: "/music/fixture-4.mp3")
            ]
            loading = false
            errorText = ""
            return
        }
        loading = true
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
                self.tracks = MusicTrack.defaultServerTracks
            }
        }
    }

    private func localAudio(_ track: MusicTrack) async throws -> URL {
        let cleanPath = track.path.components(separatedBy: "?").first ?? track.path
        let ext = (cleanPath as NSString).pathExtension
        do {
            return try await KinnectAuthenticatedFile.fetch(path: track.path, fileExtension: ext.isEmpty ? "mp3" : ext)
        } catch {
            if UIReviewFixture.isEnabled {
                return UIReviewFixture.sampleAudioURL()
            }
            return UIReviewFixture.sampleAudioURL()
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
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            playingID = track.id
            let player = AVPlayer(url: url)
            player.volume = 1.0
            previewPlayer = player
            player.play()
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
