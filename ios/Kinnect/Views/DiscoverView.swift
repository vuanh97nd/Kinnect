import AVKit
import CoreLocation
import SwiftUI

private let discoverWcagPrimaryGradient = LinearGradient(
    colors: [
        Color(red: 0x5B / 255.0, green: 0x21 / 255.0, blue: 0xB6 / 255.0),
        KinnectTheme.accent
    ],
    startPoint: .leading,
    endPoint: .trailing
)

struct DiscoverView: View {
    let initialSearchQuery: String
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
    @State private var searchQuery: String
    @State private var hasExecutedSearch: Bool

    init(initialSearchQuery: String = "", onOpenCamera: @escaping () -> Void) {
        self.initialSearchQuery = initialSearchQuery
        self.onOpenCamera = onOpenCamera
        let trimmed = initialSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        _searchQuery = State(initialValue: initialSearchQuery)
        _hasExecutedSearch = State(initialValue: !trimmed.isEmpty)
    }
    @State private var selectedRadiusKm: Int = 50
    @State private var people: [KinnectUser] = []
    @State private var posts: [PostItem] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var locationStatusText: String?
    @State private var selectedUserForDetail: KinnectUser?
    @State private var activeFilterType: FilterSheetType?

    // Quick filter states (matching Android MainActivity lines 1650-1668)
    @State private var minAge: Int = 0
    @State private var maxAge: Int = 0
    @State private var minWeight: Int = 0
    @State private var maxWeight: Int = 0
    @State private var minHeight: Int = 0
    @State private var maxHeight: Int = 0
    @State private var selectedGender: String = ""
    @State private var selectedOrientation: String = ""
    @State private var selectedRole: String = ""
    @State private var selectedIntent: String = ""
    @State private var isOnlineOnly: Bool = false
    @State private var isRecentOnly: Bool = false
    @State private var hasLocationPermission: Bool = true

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 8) {
            // 1. Top Segment Switcher: Dành cho bạn · Quanh đây · Đang theo dõi (Android parity)
            KinnectSegmentedBar(
                selection: $segment,
                accessibilityLabel: L10n.tr("Khám phá")
            )
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .onChange(of: segment) { _ in
                people = []
                loadError = nil
                Task { await loadCurrentSegment() }
            }

            // Search bar (q)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(KinnectTheme.textSecondary)
                TextField(
                    "",
                    text: $searchQuery,
                    prompt: Text(L10n.tr("Tìm tên, @username hoặc sở thích…"))
                        .foregroundColor(KinnectTheme.inputPlaceholder)
                )
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textPrimary)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await loadCurrentSegment() }
                    }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        Task { await loadCurrentSegment() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(KinnectTheme.textSecondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Xóa tìm kiếm"))
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, searchQuery.isEmpty ? 12 : 4)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
            .padding(.horizontal, 14)

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
                FilterChipButton(title: "Giới tính", isSelected: !selectedGender.isEmpty || !selectedOrientation.isEmpty || !selectedRole.isEmpty) {
                    activeFilterType = .gender
                }
                Button {
                    activeFilterType = .full
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isFilterActive ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isFilterActive ? KinnectTheme.accent.opacity(0.18) : KinnectTheme.surfaceElevated)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bộ lọc tổng hợp")
            }
            .padding(.horizontal, 14)

            // Radius selector & location banner for Nearby segment
            if segment == .nearby {
                HStack(spacing: 8) {
                    KinnectIcon(glyph: .nearby, size: 15, selected: true, tint: KinnectTheme.accentBright)
                    if let locationStatusText {
                        Text(locationStatusText)
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .lineLimit(2)
                    } else {
                        Text(L10n.tr("Bán kính tìm quanh đây"))
                            .font(.caption2.weight(.medium))
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    Spacer()
                    Menu {
                        ForEach([1, 5, 10, 25, 50], id: \.self) { km in
                            Button {
                                selectedRadiusKm = km
                                Task { await loadCurrentSegment() }
                            } label: {
                                if selectedRadiusKm == km {
                                    Label("\(km) km", systemImage: "checkmark")
                                } else {
                                    Text("\(km) km")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(selectedRadiusKm) km")
                                .font(.caption.bold())
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(KinnectTheme.accentBright)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L10n.tr("Chọn bán kính"))
                }
                .padding(.horizontal, 14)
            }

            // 3. Main Content: 3-Column Adaptive Grid (Android AdaptivePeopleGrid)
            ScrollView {
                VStack(spacing: 12) {
                    if segment == .nearby && appState.currentUser?.hasLocation != true {
                        VStack(spacing: 12) {
                            KinnectIcon(glyph: .nearby, size: 40, tint: KinnectTheme.accentBright)
                            Text("Khám phá quanh bạn")
                                .font(.headline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                            Text("Chỉ dùng vị trí gần đúng, lưu theo ô khoảng 5 km trong tối đa 24 giờ hiệu lực; không công khai tọa độ. Bạn có thể tắt và xóa ở Hồ sơ.")
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                            Button {
                                Task { await requestEnableLocation() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "location.fill")
                                    Text("Bật vị trí")
                                        .font(.subheadline.bold())
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(discoverWcagPrimaryGradient)
                                .clipShape(Capsule())
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                        .kinnectCard()
                    } else if isLoading && visiblePeople.isEmpty {
                        ProgressView().tint(KinnectTheme.accentBright).padding(.vertical, 40)
                    } else if let loadError, visiblePeople.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.largeTitle)
                                .foregroundColor(KinnectTheme.textSecondary)
                            Text(L10n.tr("Không thể tải danh sách khám phá"))
                                .font(.headline)
                                .foregroundColor(KinnectTheme.textPrimary)
                            Text(loadError)
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            Button {
                                Task { await loadCurrentSegment() }
                            } label: {
                                Text(L10n.tr("Thử lại"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 22)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .background(Capsule().fill(discoverWcagPrimaryGradient))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 36)
                        .frame(maxWidth: .infinity)
                        .kinnectCard()
                    } else if visiblePeople.isEmpty {
                        emptyDiscoveryView
                    } else {
                        let trimmedQ = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedQ.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(KinnectTheme.accentBright)
                                Text("\(visiblePeople.count) \(L10n.tr("kết quả cho")) \"\(trimmedQ)\"")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(KinnectTheme.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Button {
                                    searchQuery = ""
                                } label: {
                                    Text(L10n.tr("Xem tất cả"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(KinnectTheme.accentBright)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(KinnectTheme.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(KinnectTheme.accentBright.opacity(0.28), lineWidth: 1)
                                    )
                            )
                        }
                        LazyVGrid(columns: gridColumns, spacing: 8) {
                            ForEach(visiblePeople) { person in
                                DiscoverSquareUserTile(
                                    person: person,
                                    isOnline: person.showActivity && (person.isActive || appState.onlineUserIds.contains(person.id)),
                                    onTap: { selectedUserForDetail = person }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .clipped()
            .refreshable {
                await loadCurrentSegment()
            }
        }
        .background(KinnectTheme.background)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .task(id: searchQuery) {
            let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !hasExecutedSearch && people.isEmpty {
                    await loadCurrentSegment()
                } else if hasExecutedSearch {
                    hasExecutedSearch = false
                    await loadCurrentSegment()
                }
                return
            }
            if !hasExecutedSearch {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                hasExecutedSearch = true
            }
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
                selectedOrientation: $selectedOrientation,
                selectedRole: $selectedRole,
                selectedIntent: $selectedIntent,
                isOnlineOnly: $isOnlineOnly,
                isRecentOnly: $isRecentOnly,
                onApply: {
                    Task { await loadCurrentSegment() }
                },
                onReset: {
                    resetFilterCriteria()
                    Task { await loadCurrentSegment() }
                }
            )
        }
        .fullScreenCover(item: $selectedUserForDetail) { person in
            NavigationStack {
                ProfileView(targetUser: person)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            KinnectIconButton(glyph: .close, label: L10n.tr("Đóng"), tint: KinnectTheme.textPrimary) {
                                selectedUserForDetail = nil
                            }
                        }
                    }
            }
        }
    }

    private var isFilterActive: Bool {
        minAge > 0 || maxAge > 0 || minWeight > 0 || maxWeight > 0 || minHeight > 0 || maxHeight > 0 ||
        !selectedGender.isEmpty || !selectedOrientation.isEmpty || !selectedRole.isEmpty || !selectedIntent.isEmpty ||
        isOnlineOnly || isRecentOnly
    }

    private static func canonicalGender(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "nam", "male", "man":
            return "male"
        case "nữ", "nu", "female", "woman":
            return "female"
        case "nam chuyển giới", "transgender_male", "trans_male", "trans male":
            return "transgender_male"
        case "nữ chuyển giới", "nu chuyen gioi", "transgender_female", "trans_female", "trans female":
            return "transgender_female"
        case "phi nhị nguyên", "phi nhi nguyen", "non_binary", "nonbinary", "non-binary":
            return "non_binary"
        case "linh hoạt giới", "linh hoat gioi", "genderfluid":
            return "genderfluid"
        case "vô giới", "vo gioi", "agender":
            return "agender"
        case "đang tìm hiểu", "dang tim hieu", "questioning":
            return "questioning"
        case "khác", "khac", "other":
            return "other"
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private static func canonicalOrientation(_ raw: String) -> String {
        let low = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if low.contains("gay") || low.contains("đồng tính nam") { return "gay" }
        if low.contains("lesbian") || low.contains("đồng tính nữ") { return "lesbian" }
        if low.contains("bisexual") || low.contains("song tính") { return "bisexual" }
        if low.contains("pansexual") || low.contains("toàn tính") { return "pansexual" }
        if low.contains("asexual") || low.contains("vô tính") { return "asexual" }
        if low.contains("dị tính") || low == "heterosexual" || low == "straight" { return "heterosexual" }
        if low.contains("demisexual") || low.contains("á tính") { return "demisexual" }
        if low.contains("queer") { return "queer" }
        if low.contains("tìm hiểu") || low == "questioning" { return "questioning" }
        if low.contains("khác") || low == "other" { return "other" }
        return low
    }

    private var visiblePeople: [KinnectUser] {
        people.filter { p in
            !appState.blockedUserIds.contains(p.id) && p.id != appState.currentUser?.id
        }
    }

    private var visiblePosts: [PostItem] {
        posts.filter { !appState.blockedUserIds.contains($0.author.id) }
    }

    // Android discoveryEmptyState parity
    private var emptyDiscoveryView: some View {
        let trimmedQ = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(spacing: 14) {
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

            Text(!trimmedQ.isEmpty
                 ? String(format: L10n.tr("Không tìm thấy kết quả cho \"%@\"."), trimmedQ)
                 : (segment == .following
                    ? "Khám phá và theo dõi những người bạn quan tâm."
                    : (segment == .nearby
                       ? "Thử mở rộng bán kính hoặc điều chỉnh bộ lọc."
                       : "Thử điều chỉnh bộ lọc để tìm thêm thành viên.")))
                .font(.subheadline)
                .foregroundColor(KinnectTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                resetAllFilters()
                segment = .forYou
                Task { await loadCurrentSegment() }
            } label: {
                Text(L10n.tr("Xem tất cả"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Capsule().fill(discoverWcagPrimaryGradient))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

    private func resetFilterCriteria() {
        selectedRadiusKm = 50
        minAge = 0; maxAge = 0
        minWeight = 0; maxWeight = 0
        minHeight = 0; maxHeight = 0
        selectedGender = ""
        selectedOrientation = ""
        selectedRole = ""
        selectedIntent = ""
        isOnlineOnly = false
        isRecentOnly = false
    }

    private func resetAllFilters() {
        searchQuery = ""
        resetFilterCriteria()
    }

    private func loadCurrentSegment() async {
        var components = URLComponents()
        components.path = "/api/discover"
        var queryItems: [URLQueryItem] = []

        switch segment {
        case .forYou:
            queryItems.append(URLQueryItem(name: "sort", value: isOnlineOnly ? "active" : "interests"))
        case .nearby:
            queryItems.append(URLQueryItem(name: "nearby", value: "1"))
            queryItems.append(URLQueryItem(name: "radius", value: "\(selectedRadiusKm)"))
            queryItems.append(URLQueryItem(name: "sort", value: isOnlineOnly ? "active" : "new"))
        case .following:
            queryItems.append(URLQueryItem(name: "following", value: "1"))
            if isOnlineOnly {
                queryItems.append(URLQueryItem(name: "sort", value: "active"))
            }
        }

        let cleanQ = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanQ.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: cleanQ))
        }
        if minAge > 0 { queryItems.append(URLQueryItem(name: "minAge", value: "\(minAge)")) }
        if maxAge > 0 { queryItems.append(URLQueryItem(name: "maxAge", value: "\(maxAge)")) }
        if minWeight > 0 { queryItems.append(URLQueryItem(name: "minWeight", value: "\(minWeight)")) }
        if maxWeight > 0 { queryItems.append(URLQueryItem(name: "maxWeight", value: "\(maxWeight)")) }
        if minHeight > 0 { queryItems.append(URLQueryItem(name: "minHeight", value: "\(minHeight)")) }
        if maxHeight > 0 { queryItems.append(URLQueryItem(name: "maxHeight", value: "\(maxHeight)")) }
        if !selectedGender.isEmpty {
            queryItems.append(URLQueryItem(name: "gender", value: selectedGender))
        }
        if !selectedOrientation.isEmpty {
            queryItems.append(URLQueryItem(name: "orientation", value: selectedOrientation))
        }
        if !selectedRole.isEmpty {
            queryItems.append(URLQueryItem(name: "communityRole", value: selectedRole))
        }
        if !selectedIntent.isEmpty {
            queryItems.append(URLQueryItem(name: "intent", value: selectedIntent))
        }
        if isRecentOnly {
            queryItems.append(URLQueryItem(name: "recent", value: "1"))
        }

        components.queryItems = queryItems
        let path = components.string ?? "/api/discover?sort=interests"

        if let cached = KinnectAPIClient.shared.cachedJSON(for: path) {
            self.people = (cached["people"] as? [[String: Any]] ?? cached["users"] as? [[String: Any]] ?? []).map(KinnectUser.from)
            self.posts = (cached["posts"] as? [[String: Any]] ?? []).map(PostItem.from)
        }

        isLoading = people.isEmpty && posts.isEmpty
        loadError = nil
        defer { isLoading = false }

        do {
            let res = try await KinnectAPIClient.shared.requestJSON(path)
            self.people = (res["people"] as? [[String: Any]] ?? res["users"] as? [[String: Any]] ?? []).map(KinnectUser.from)
            self.posts = (res["posts"] as? [[String: Any]] ?? []).map(PostItem.from)
            self.loadError = nil
        } catch {
            if self.people.isEmpty {
                self.loadError = error.localizedDescription
            } else {
                appState.showToast(error.localizedDescription)
            }
        }
    }

    private func requestEnableLocation() async {
        locationStatusText = "Đang lấy vị trí gần đúng…"
        if let coord = await MediaPermissionHandler.shared.requestCurrentLocation() {
            let body: [String: Any] = [
                "enabled": true,
                "latitude": coord.latitude,
                "longitude": coord.longitude
            ]
            do {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/me/location",
                    method: "PATCH",
                    body: body,
                    requestId: "loc_\(Int(Date().timeIntervalSince1970))"
                )
                if var me = appState.currentUser {
                    me.hasLocation = true
                    appState.currentUser = me
                }
                locationStatusText = "Đang tìm kiếm quanh đây trong bán kính 50 km"
                await loadCurrentSegment()
            } catch {
                locationStatusText = error.localizedDescription
                appState.showToast(error.localizedDescription)
            }
        } else {
            locationStatusText = "Chưa cấp quyền vị trí. Bạn có thể bật vị trí trong Cài đặt máy."
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                                    size: min(geo.size.width * 0.42, 42),
                                    isOnline: isOnline
                                )
                                .padding(.bottom, 30)
                            )
                    }

                    // Top-Left Online Dot (Android parity lines 1639: 10dp ONLINE dot with 2dp CARD stroke)
                    if isOnline {
                        VStack {
                            HStack {
                                Circle()
                                    .fill(KinnectTheme.onlineDot)
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(KinnectTheme.surface, lineWidth: 2))
                                    .padding(7)
                                Spacer()
                            }
                            Spacer()
                        }
                    }

                    // Top-Right Badge: "Mới" (Android parity lines 1638: RegistrationBadge.today)
                    let isNew = person.joinedAt > 0 && (Date().timeIntervalSince1970 * 1000 - Double(person.joinedAt)) < 86_400_000
                    if isNew {
                        VStack {
                            HStack {
                                Spacer()
                                Text("Mới")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(KinnectTheme.accent))
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
                            HStack(spacing: 3) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.85))
                                Text(String(format: "%.1f km", dist))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.95))
                            }
                        } else if !person.locationName.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.85))
                                Text(person.locationName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.9))
                                    .lineLimit(1)
                            }
                        }
                        Text(person.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 7)
                }
                .frame(width: geo.size.width, height: geo.size.width)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
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
                            .foregroundColor(person.isFollowing ? KinnectTheme.textPrimary : .white)
                            .padding(.horizontal, 20)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(
                                Capsule().fill(person.isFollowing ? AnyShapeStyle(KinnectTheme.surfaceElevated) : AnyShapeStyle(discoverWcagPrimaryGradient))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: onCallVideo) {
                        HStack(spacing: 6) {
                            KinnectIcon(glyph: .videoCall, size: 18, tint: KinnectTheme.textPrimary)
                            Text("Gọi video")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(KinnectTheme.textPrimary)
                        }
                        .padding(.horizontal, 20)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)

                Spacer()
            }
            .background(KinnectTheme.background)
            .navigationTitle("Thông tin thành viên")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: L10n.tr("Đóng"), tint: KinnectTheme.textPrimary) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// 7. Interactive Discover Filter Sheet (100% Parity with Android MainActivity lines 1650-1668)
private struct DiscoverFilterSheet: View {
    let type: DiscoverView.FilterSheetType
    @Binding var minAge: Int
    @Binding var maxAge: Int
    @Binding var minWeight: Int
    @Binding var maxWeight: Int
    @Binding var minHeight: Int
    @Binding var maxHeight: Int
    @Binding var selectedGender: String
    @Binding var selectedOrientation: String
    @Binding var selectedRole: String
    @Binding var selectedIntent: String
    @Binding var isOnlineOnly: Bool
    @Binding var isRecentOnly: Bool
    let onApply: () -> Void
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let genders = [
        "", "Nam", "Nữ", "Nam chuyển giới", "Nữ chuyển giới",
        "Phi nhị nguyên", "Linh hoạt giới", "Vô giới", "Đang tìm hiểu", "Khác"
    ]

    private let orientations = [
        "", "Gay / Đồng tính nam", "Lesbian / Đồng tính nữ", "Song tính / Bisexual",
        "Toàn tính / Pansexual", "Vô tính / Asexual", "Dị tính", "Queer",
        "Á tính / Demisexual", "Đang tìm hiểu", "Khác"
    ]

    private let communityRoles = [
        "", "Top", "Bottom", "Vers", "Vers Top", "Vers Bottom",
        "Side", "Femme", "Masc / Butch", "Androgynous", "Stem", "Đang tìm hiểu", "Khác"
    ]

    private let intents = [
        "", "Trò chuyện", "Kết bạn", "Hẹn hò"
    ]

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
                        Stepper("Tối thiểu: \(minWeight > 0 ? "\(minWeight) kg" : "Bất kỳ")", value: $minWeight, in: 0...400, step: 5)
                        Stepper("Tối đa: \(maxWeight > 0 ? "\(maxWeight) kg" : "Bất kỳ")", value: $maxWeight, in: 0...400, step: 5)
                    }
                }

                if type == .height || type == .full {
                    Section("Chiều cao (cm)") {
                        Stepper("Tối thiểu: \(minHeight > 0 ? "\(minHeight) cm" : "Bất kỳ")", value: $minHeight, in: 0...250, step: 5)
                        Stepper("Tối đa: \(maxHeight > 0 ? "\(maxHeight) cm" : "Bất kỳ")", value: $maxHeight, in: 0...250, step: 5)
                    }
                }

                if type == .gender || type == .full {
                    Section("Bản dạng giới & Xu hướng (LGBT+)") {
                        Picker("Bản dạng giới", selection: $selectedGender) {
                            Text("Tất cả").tag("")
                            ForEach(genders.filter { !$0.isEmpty }, id: \.self) { g in
                                Text(g).tag(g)
                            }
                        }

                        Picker("Xu hướng tính dục", selection: $selectedOrientation) {
                            Text("Tất cả").tag("")
                            ForEach(orientations.filter { !$0.isEmpty }, id: \.self) { o in
                                Text(o).tag(o)
                            }
                        }

                        Picker("Vai trò tự mô tả", selection: $selectedRole) {
                            Text("Tất cả").tag("")
                            ForEach(communityRoles.filter { !$0.isEmpty }, id: \.self) { r in
                                Text(r).tag(r)
                            }
                        }

                        Picker("Mục đích kết nối", selection: $selectedIntent) {
                            Text("Tất cả").tag("")
                            ForEach(intents.filter { !$0.isEmpty }, id: \.self) { i in
                                Text(i).tag(i)
                            }
                        }
                    }

                    Section("Trạng thái hoạt động") {
                        Toggle("Đang online", isOn: $isOnlineOnly)
                            .tint(KinnectTheme.accentBright)
                        Toggle("Hoạt động gần đây", isOn: $isRecentOnly)
                            .tint(KinnectTheme.accentBright)
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
