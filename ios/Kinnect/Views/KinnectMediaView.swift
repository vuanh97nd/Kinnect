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
                let videoRatio: CGFloat = {
                    if let img = thumbnail.image, img.size.width > 0, img.size.height > 0 {
                        return min(max(img.size.width / img.size.height, 0.72), 1.85)
                    }
                    return 16.0 / 9.0
                }()
                ZStack {
                    Color(red: 0.06, green: 0.08, blue: 0.13)
                    if let image = thumbnail.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    Circle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 62, height: 62)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: 2)
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(videoRatio, contentMode: .fit)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                KinnectRemoteImageView(
                    rawURL: path,
                    contentMode: .fit,
                    cornerRadius: 14,
                    maxHeight: 560,
                    fillWidthNaturalHeight: true
                )
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
            .preferredColorScheme(.dark)
            .statusBarHidden(false)
        }
    }
}
