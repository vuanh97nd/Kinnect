import AVKit
import CoreLocation
import SwiftUI

struct DiscoverView: View {
    let onOpenCamera: () -> Void
    @ObservedObject private var appState = AppState.shared

    enum DiscoverSegment: String, CaseIterable {
        case forYou = "Dành cho bạn"
        case nearby = "Quanh đây"
        case following = "Đang theo dõi"
    }

    enum FilterSheetType: Identifiable {
        case age, weight, height, gender, full
        var id: Int { hashValue }
    }

    @State private var segment: DiscoverSegment = .forYou
    @State private var people: [KinnectUser] = []
    @State private var posts: [PostItem] = []
    @State private var isLoading = false
    @State private var locationStatusText: String?
    @State private var selectedUserForDetail: KinnectUser?
    @State private var activeFilterType: FilterSheetType?

    // Quick filter states
    @State private var minAge: Int = 0
    @State private var maxAge: Int = 0
    @State private var minWeight: Int = 0
    @State private var maxWeight: Int = 0
    @State private var minHeight: Int = 0
    @State private var maxHeight: Int = 0
    @State private var selectedGender: String = ""
    @State private var hasLocationPermission: Bool = true

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 8) {
            // 1. Top Segment Switcher: Dành cho bạn · Quanh đây · Đang theo dõi (Android parity)
            Picker("Khám phá", selection: $segment) {
                ForEach(DiscoverSegment.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .onChange(of: segment) { _ in
                Task { await loadCurrentSegment() }
            }

            // 2. Quick Filter Chips Row (Android parity: Tuổi, Cân nặng, Chiều cao, Giới tính, Sliders)
            HStack(spacing: 6) {
                FilterChipButton(title: "Tuổi", isSelected: minAge > 0 || maxAge > 0) {
                    activeFilterType = .age
                }
                FilterChipButton(title: "Cân nặng", isSelected: minWeight > 0 || maxWeight > 0) {
                    activeFilterType = .weight
                }
                FilterChipButton(title: "Chiều cao", isSelected: minHeight > 0 || maxHeight > 0) {
                    activeFilterType = .height
                }
                FilterChipButton(title: "Giới tính", isSelected: !selectedGender.isEmpty) {
                    activeFilterType = .gender
                }
                Button {
                    activeFilterType = .full
                } label: {
                    KinnectIcon(
                        glyph: .more,
                        size: 20,
                        tint: isFilterActive ? KinnectTheme.accentBright : KinnectTheme.textSecondary
                    )
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isFilterActive ? KinnectTheme.accent.opacity(0.18) : KinnectTheme.surfaceElevated)
                    )
                }
                .accessibilityLabel("Bộ lọc tổng hợp")
            }
            .padding(.horizontal, 14)

            // Location banner if Nearby segment
            if let locationStatusText, segment == .nearby {
                HStack(spacing: 6) {
                    KinnectIcon(glyph: .nearby, size: 16, selected: true, tint: KinnectTheme.accentBright)
                    Text(locationStatusText)
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .kinnectMultiline()
                    Spacer()
                }
                .padding(.horizontal, 16)
            }

            // 3. Main Content: 3-Column Adaptive Grid (Android AdaptivePeopleGrid)
            ScrollView {
                VStack(spacing: 12) {
                    if isLoading && visiblePeople.isEmpty {
                        ProgressView().tint(KinnectTheme.accentBright).padding(.vertical, 40)
                    } else if visiblePeople.isEmpty {
                        emptyDiscoveryView
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: 8) {
                            ForEach(visiblePeople) { person in
                                DiscoverSquareUserTile(
                                    person: person,
                                    isOnline: appState.onlineUserIds.contains(person.id),
                                    onTap: { selectedUserForDetail = person }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .refreshable {
                await loadCurrentSegment()
            }
        }
        .background(KinnectTheme.background)
        .navigationTitle("Khám phá")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCurrentSegment()
        }
        .sheet(item: $activeFilterType) { filterType in
            DiscoverFilterSheet(
                type: filterType,
                minAge: $minAge,
                maxAge: $maxAge,
                minWeight: $minWeight,
                maxWeight: $maxWeight,
                minHeight: $minHeight,
                maxHeight: $maxHeight,
                selectedGender: $selectedGender,
                onApply: {
                    Task { await loadCurrentSegment() }
                },
                onReset: {
                    minAge = 0; maxAge = 0
                    minWeight = 0; maxWeight = 0
                    minHeight = 0; maxHeight = 0
                    selectedGender = ""
                    Task { await loadCurrentSegment() }
                }
            )
        }
        .sheet(item: $selectedUserForDetail) { person in
            DiscoverUserDetailSheet(
                person: person,
                isOnline: appState.onlineUserIds.contains(person.id),
                onFollowToggle: { Task { await toggleFollow(person) } },
                onCallVideo: {
                    Task { await NativeWebRTCManager.shared.startOutgoingCall(targetUser: person, mode: "video") }
                }
            )
        }
    }

    private var isFilterActive: Bool {
        minAge > 0 || maxAge > 0 || minWeight > 0 || maxWeight > 0 || minHeight > 0 || maxHeight > 0 || !selectedGender.isEmpty
    }

    private var visiblePeople: [KinnectUser] {
        people.filter { p in
            guard !appState.blockedUserIds.contains(p.id) && p.id != appState.currentUser?.id else { return false }
            if minAge > 0 && p.age < minAge { return false }
            if maxAge > 0 && p.age > maxAge { return false }
            if !selectedGender.isEmpty && p.gender.lowercased() != selectedGender.lowercased() { return false }
            return true
        }
    }

    private var visiblePosts: [PostItem] {
        posts.filter { !appState.blockedUserIds.contains($0.author.id) }
    }

    // Android discoveryEmptyState parity
    private var emptyDiscoveryView: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(KinnectTheme.accent.opacity(0.2))
                .frame(width: 64, height: 64)
                .overlay(
                    KinnectIcon(glyph: .friends, size: 28, selected: true, tint: KinnectTheme.accentBright)
                )
                .padding(.top, 36)

            Text(segment == .following ? "Chưa theo dõi ai" : "Chưa tìm thấy ai")
                .font(.headline.weight(.bold))
                .foregroundColor(KinnectTheme.textPrimary)

            Text(segment == .following
                 ? "Khám phá và theo dõi những người bạn quan tâm."
                 : (segment == .nearby
                    ? "Thử mở rộng bán kính hoặc điều chỉnh bộ lọc."
                    : "Thử điều chỉnh bộ lọc để tìm thêm thành viên."))
                .font(.subheadline)
                .foregroundColor(KinnectTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                segment = .forYou
                Task { await loadCurrentSegment() }
            } label: {
                Text("Xem tất cả")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(Capsule().fill(KinnectTheme.primaryGradient))
            }
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(KinnectTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.border, lineWidth: 1))
        )
        .padding(.vertical, 16)
    }

    private func loadCurrentSegment() async {
        isLoading = true
        defer { isLoading = false }

        var filterParams = ""
        if minAge > 0 { filterParams += "&minAge=\(minAge)" }
        if maxAge > 0 { filterParams += "&maxAge=\(maxAge)" }
        if minWeight > 0 { filterParams += "&minWeight=\(minWeight)" }
        if maxWeight > 0 { filterParams += "&maxWeight=\(maxWeight)" }
        if minHeight > 0 { filterParams += "&minHeight=\(minHeight)" }
        if maxHeight > 0 { filterParams += "&maxHeight=\(maxHeight)" }
        if !selectedGender.isEmpty {
            if let enc = selectedGender.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                filterParams += "&gender=\(enc)"
            }
        }

        switch segment {
        case .forYou:
            let path = "/api/discover?sort=interests\(filterParams)"
            if let disc = try? await KinnectAPIClient.shared.requestJSON(path) {
                self.people = (disc["people"] as? [[String: Any]] ?? disc["users"] as? [[String: Any]] ?? []).map(KinnectUser.from)
                self.posts = (disc["posts"] as? [[String: Any]] ?? []).map(PostItem.from)
            }

        case .nearby:
            locationStatusText = "Đang xác định vị trí GPS..."
            if let coord = await MediaPermissionHandler.shared.requestCurrentLocation() {
                locationStatusText = String(format: "Vị trí: %.4f, %.4f (bán kính 50km)", coord.latitude, coord.longitude)
                _ = try? await KinnectAPIClient.shared.requestJSON(
                    "/api/me/location",
                    method: "PATCH",
                    body: [
                        "lat": coord.latitude,
                        "lng": coord.longitude
                    ],
                    requestId: "loc_\(Int(Date().timeIntervalSince1970))"
                )
                let path = "/api/discover?nearby=1&lat=\(coord.latitude)&lng=\(coord.longitude)&radiusKm=50\(filterParams)"
                if let res = try? await KinnectAPIClient.shared.requestJSON(path) {
                    self.people = (res["people"] as? [[String: Any]] ?? res["users"] as? [[String: Any]] ?? []).map(KinnectUser.from)
                    self.posts = (res["posts"] as? [[String: Any]] ?? []).map(PostItem.from)
                }
            } else {
                locationStatusText = "Chưa cấp quyền vị trí. Đang hiển thị khu vực mặc định."
                let path = "/api/discover?nearby=1\(filterParams)"
                if let res = try? await KinnectAPIClient.shared.requestJSON(path) {
                    self.people = (res["people"] as? [[String: Any]] ?? res["users"] as? [[String: Any]] ?? []).map(KinnectUser.from)
                    self.posts = (res["posts"] as? [[String: Any]] ?? []).map(PostItem.from)
                }
            }

        case .following:
            let path = "/api/discover?following=1\(filterParams)"
            if let res = try? await KinnectAPIClient.shared.requestJSON(path) {
                self.people = (res["people"] as? [[String: Any]] ?? res["users"] as? [[String: Any]] ?? []).map(KinnectUser.from)
                self.posts = (res["posts"] as? [[String: Any]] ?? []).map(PostItem.from)
            }
        }
    }

    private func toggleFollow(_ person: KinnectUser) async {
        let reqId = "follow_\(person.id)_\(Int(Date().timeIntervalSince1970))"
        do {
            if person.isFollowing {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/users/\(person.id)/follow",
                    method: "DELETE",
                    body: [:],
                    requestId: reqId
                )
            } else {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/users/\(person.id)/follow",
                    method: "POST",
                    body: [:],
                    requestId: reqId
                )
            }
            await loadCurrentSegment()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

// 4. Quick Filter Chip Button Component
private struct FilterChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? KinnectTheme.accentBright : KinnectTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? KinnectTheme.accent.opacity(0.18) : KinnectTheme.surfaceElevated)
                )
        }
        .accessibilityLabel("\(title)\(isSelected ? " · Đang chọn" : "")")
    }
}

// 5. Square People Tile (Android nearTile 1:1 Parity)
private struct DiscoverSquareUserTile: View {
    let person: KinnectUser
    let isOnline: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    // Full Square Image / Avatar Background
                    if !person.avatarUrl.isEmpty {
                        KinnectRemoteImageView(
                            rawURL: person.avatarUrl,
                            contentMode: .fill,
                            cornerRadius: 14,
                            maxHeight: geo.size.width
                        )
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(KinnectTheme.surfaceElevated)
                            .overlay(
                                KinnectAvatarView(
                                    name: person.name,
                                    avatarURL: "",
                                    colorHex: person.avatarColor,
                                    size: min(geo.size.width * 0.5, 48),
                                    isOnline: isOnline
                                )
                            )
                    }

                    // Top-Right Badge: "Mới" or Online
                    if isOnline {
                        VStack {
                            HStack {
                                Spacer()
                                Text("Mới")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(KinnectTheme.accentBright))
                                    .padding(5)
                            }
                            Spacer()
                        }
                    }

                    // Bottom Gradient Shadow (0x00000000 -> 0xcc000000)
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Overlay Meta: Distance & Name
                    VStack(alignment: .leading, spacing: 1) {
                        if let dist = person.distanceKm {
                            Text(String(format: "%.1f km", dist))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.9))
                        } else if !person.locationName.isEmpty {
                            Text(person.locationName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.9))
                                .lineLimit(1)
                        }
                        Text(person.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
                .frame(width: geo.size.width, height: geo.size.width)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Thành viên \(person.name)")
    }
}

// 6. User Detail Modal Sheet on Tile Tap
private struct DiscoverUserDetailSheet: View {
    let person: KinnectUser
    let isOnline: Bool
    let onFollowToggle: () -> Void
    let onCallVideo: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                KinnectAvatarView(
                    name: person.name,
                    avatarURL: person.avatarUrl,
                    colorHex: person.avatarColor,
                    size: 80,
                    isOnline: isOnline
                )
                .padding(.top, 24)

                VStack(spacing: 6) {
                    Text(person.name)
                        .font(.title3.weight(.bold))
                        .foregroundColor(KinnectTheme.textPrimary)

                    if let dist = person.distanceKm {
                        Text(String(format: "Cách bạn %.1f km", dist))
                            .font(.caption)
                            .foregroundColor(KinnectTheme.accentBright)
                    }

                    if !person.bio.isEmpty {
                        Text(person.bio)
                            .font(.body)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }

                HStack(spacing: 16) {
                    Button(action: onFollowToggle) {
                        Text(person.isFollowing ? "Đang theo dõi" : "Theo dõi")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .frame(height: 44)
                            .background(
                                Capsule().fill(person.isFollowing ? AnyShapeStyle(KinnectTheme.surfaceElevated) : AnyShapeStyle(KinnectTheme.primaryGradient))
                            )
                    }

                    Button(action: onCallVideo) {
                        HStack(spacing: 6) {
                            KinnectIcon(glyph: .videoCall, size: 18, tint: .white)
                            Text("Gọi video")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                    }
                }
                .padding(.top, 12)

                Spacer()
            }
            .background(KinnectTheme.background)
            .navigationTitle("Thông tin thành viên")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// 7. Interactive Discover Filter Sheet
private struct DiscoverFilterSheet: View {
    let type: DiscoverView.FilterSheetType
    @Binding var minAge: Int
    @Binding var maxAge: Int
    @Binding var minWeight: Int
    @Binding var maxWeight: Int
    @Binding var minHeight: Int
    @Binding var maxHeight: Int
    @Binding var selectedGender: String
    let onApply: () -> Void
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let genders = ["", "Nam", "Nữ", "Khác"]

    var body: some View {
        NavigationStack {
            Form {
                if type == .age || type == .full {
                    Section("Độ tuổi (18 - 99)") {
                        Stepper("Tuổi tối thiểu: \(minAge > 0 ? "\(minAge)" : "Bất kỳ")", value: $minAge, in: 0...99, step: 1)
                        Stepper("Tuổi tối đa: \(maxAge > 0 ? "\(maxAge)" : "Bất kỳ")", value: $maxAge, in: 0...99, step: 1)
                    }
                }

                if type == .weight || type == .full {
                    Section("Cân nặng (kg)") {
                        Stepper("Tối thiểu: \(minWeight > 0 ? "\(minWeight) kg" : "Bất kỳ")", value: $minWeight, in: 0...200, step: 5)
                        Stepper("Tối đa: \(maxWeight > 0 ? "\(maxWeight) kg" : "Bất kỳ")", value: $maxWeight, in: 0...200, step: 5)
                    }
                }

                if type == .height || type == .full {
                    Section("Chiều cao (cm)") {
                        Stepper("Tối thiểu: \(minHeight > 0 ? "\(minHeight) cm" : "Bất kỳ")", value: $minHeight, in: 0...220, step: 5)
                        Stepper("Tối đa: \(maxHeight > 0 ? "\(maxHeight) cm" : "Bất kỳ")", value: $maxHeight, in: 0...220, step: 5)
                    }
                }

                if type == .gender || type == .full {
                    Section("Giới tính") {
                        Picker("Giới tính", selection: $selectedGender) {
                            Text("Tất cả").tag("")
                            Text("Nam").tag("Nam")
                            Text("Nữ").tag("Nữ")
                            Text("Khác").tag("Khác")
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đặt lại") {
                        onReset()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Áp dụng") {
                        onApply()
                        dismiss()
                    }
                    .font(.body.weight(.bold))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var sheetTitle: String {
        switch type {
        case .age: return "Lọc theo tuổi"
        case .weight: return "Lọc theo cân nặng"
        case .height: return "Lọc theo chiều cao"
        case .gender: return "Lọc theo giới tính"
        case .full: return "Bộ lọc thành viên"
        }
    }
}
