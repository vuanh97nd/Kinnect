import SwiftUI

struct KinnectMediaTile: View {
    let path: String
    var kind: String = "image"
    @State private var expanded = false
    @StateObject private var thumbnail = VideoThumbnailLoader()
    private var isVideo: Bool { kind.lowercased().contains("video") || path.lowercased().contains(".mp4") }

    var body: some View {
        Button { expanded = true } label: {
            if isVideo {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated)
                    if let image = thumbnail.image {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 56)).foregroundColor(.white)
                }
                .frame(height: 240)
            } else {
                KinnectRemoteImageView(rawURL: path, contentMode: .fit, cornerRadius: 14, maxHeight: 340)
            }
        }
        .buttonStyle(.plain)
        .task(id: path) { if isVideo { thumbnail.load(urlString: path) } }
        .accessibilityLabel(isVideo ? "Xem video toàn màn hình" : "Xem ảnh toàn màn hình")
        .fullScreenCover(isPresented: $expanded) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if isVideo {
                    ShortClipPlayer(path: path, active: true)
                } else {
                    GeometryReader { geo in
                        KinnectRemoteImageView(rawURL: path, contentMode: .fit, cornerRadius: 0, maxHeight: geo.size.height)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                Button { expanded = false } label: {
                    Image(systemName: "xmark").font(.headline)
                        .foregroundColor(.white).frame(width: 44, height: 44)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                .padding(12).accessibilityLabel("Đóng")
            }
        }
    }
}
