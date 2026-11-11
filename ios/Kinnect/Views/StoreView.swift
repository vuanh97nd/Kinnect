import SwiftUI
import UIKit

/// Dedicated Full-Screen Store Screen matching Android 1.2.12 StoreActivity.java
/// Features 6 category tabs: Phong cách, Gói Live, Gói Studio, Quà tặng, Hội viên, Của tôi.
/// Pinned top header with Back button, Title, Coin balance chip, and Store Menu.
struct StoreView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var storeKit = StoreKitManager.shared

    var onBack: (() -> Void)? = nil
    var onOpenWallet: (() -> Void)? = nil

    enum StoreCategoryFilter: String, CaseIterable {
        case style = "Phong cách"
        case live = "Gói Live"
        case studio = "Gói Studio"
        case gifts = "Quà tặng"
        case member = "Hội viên"
        case owned = "Của tôi"
    }

    @State private var storeFilter: StoreCategoryFilter = .style
    @State private var previewPackage: StorePackageItem? = nil
    @State private var packages: [StorePackageItem] = []
    @State private var digitalProducts: [StoreDigitalProduct] = []
    @State private var accountUuid: UUID? = nil
    @State private var isLoading = false
    @State private var transactionInProgress = false
    @State private var coinSource = "gifted"
    @State private var trialPackagePurchases = true
    @State private var storeBalance = 0
    @State private var loadError: String?
    @State private var studioPackage: StorePackageItem?
    @State private var showStoreMenuDialog = false
    @State private var showStoreInfoAlert = false
    @State private var confirmBuyPackage: StorePackageItem? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Dedicated Header Bar matching Android StoreActivity
            storeHeaderBar

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Hero Shop Banner
                    storeHeroBanner

                    // 6 Category Tabs
                    categoryFilterStrip

                    // Interactive Live Preview (when "Xem thử" tapped)
                    if let preview = previewPackage {
                        interactivePreviewBanner(preview)
                    }

                    // Package Cards List
                    if let loadError {
                        Text(loadError).foregroundColor(KinnectTheme.danger)
                    }
                    Picker("Nguồn xu", selection: $coinSource) {
                        if trialPackagePurchases { Text("Xu tặng").tag("gifted") }
                        Text("Xu mua").tag("purchased")
                    }
                    .pickerStyle(.segmented)
                    packagesSection
                        .disabled(transactionInProgress)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
            .refreshable {
                await loadStoreData()
            }
        }
        .background(KinnectTheme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .confirmationDialog("Cửa hàng Kinnect", isPresented: $showStoreMenuDialog, titleVisibility: .visible) {
            Button("Khôi phục giao dịch") {
                Task {
                    do {
                        let outcome = try await storeKit.restorePurchases()
                        appState.showToast(outcome.failed.isEmpty
                            ? "Đã kiểm tra và khôi phục các giao dịch hợp lệ."
                            : "Một số giao dịch chưa xác minh được. Hãy thử lại.")
                        await loadStoreData()
                    } catch {
                        appState.showToast("Chưa khôi phục được: \(error.localizedDescription)")
                    }
                }
            }
            Button("Phong cách mặc định") {
                Task {
                    do {
                        _ = try await KinnectAPIClient.shared.requestJSON("/api/store/style", method: "POST", body: ["productId": ""])
                        appState.showToast("Đã chuyển về phong cách mặc định")
                        await loadStoreData()
                    } catch {
                        appState.showToast("Chưa đổi được phong cách: \(error.localizedDescription)")
                    }
                }
            }
            Button("Thông tin cửa hàng") {
                showStoreInfoAlert = true
            }
            Button("Đóng", role: .cancel) { }
        }
        .alert("Cửa hàng Kinnect", isPresented: $showStoreInfoAlert) {
            Button("Đóng", role: .cancel) { }
        } message: {
            Text("Quyền lợi gắn với tài khoản Kinnect. Xem thử không thay đổi hồ sơ của bạn. Giá hiển thị quy đổi theo xu hoặc App Store.")
        }
        .alert("Xác nhận đổi gói?", isPresented: Binding(
            get: { confirmBuyPackage != nil },
            set: { if !$0 { confirmBuyPackage = nil } }
        )) {
            Button("Hủy", role: .cancel) { confirmBuyPackage = nil }
            Button("Đổi ngay (\(confirmBuyPackage?.priceCoins ?? 0) xu)") {
                if let p = confirmBuyPackage {
                    Task { await buyPackage(p) }
                }
                confirmBuyPackage = nil
            }
        } message: {
            if let p = confirmBuyPackage {
                Text("Gói: \(p.title)\nChi phí: \(p.priceCoins) xu Kinnect.")
            }
        }
        .fullScreenCover(item: $studioPackage) { pkg in
            CameraStudioView(initialMode: pkg.id.hasPrefix("studio_video_") ? .video : .photo,
                             onClose: { studioPackage = nil })
        }
        .task {
            await loadStoreData()
        }
    }

    // MARK: - Header Bar
    private var storeHeaderBar: some View {
        HStack(spacing: 12) {
            Button {
                if let onBack = onBack {
                    onBack()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quay lại")

            HStack(spacing: 8) {
                KinnectIcon(glyph: .store, size: 20, selected: true, tint: KinnectTheme.accentBright)
                Text("Cửa hàng")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)
            }

            Spacer()

            // Coin Balance Chip -> Opens Wallet
            Button {
                onOpenWallet?()
            } label: {
                HStack(spacing: 5) {
                    Text("🪙")
                        .font(.system(size: 13))
                    Text("\(storeBalance) xu")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(KinnectTheme.warning)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(KinnectTheme.surfaceElevated))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Xem ví Kinnect")

            // Store Menu Button
            Button {
                showStoreMenuDialog = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(KinnectTheme.surfaceElevated))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tùy chọn cửa hàng")
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(KinnectTheme.surface.ignoresSafeArea(edges: .top))
        .overlay(Divider().background(KinnectTheme.borderSoft), alignment: .bottom)
    }

    // MARK: - Hero Banner
    private var storeHeroBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    KinnectIcon(glyph: .store, size: 14, selected: true, tint: KinnectTheme.accentBright)
                    Text("KINNECT SHOP")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(KinnectTheme.accentBright)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text("Xem thử miễn phí")
                        .font(.caption2.bold())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.18)))
            }

            Text("Thêm sắc màu.\nThêm chất riêng.")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .lineSpacing(4)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#3B1E6D"), Color(hex: "#1E1338")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    // MARK: - Category Filter Strip
    private var categoryFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StoreCategoryFilter.allCases, id: \.self) { cat in
                    let isSelected = storeFilter == cat
                    Button {
                        storeFilter = cat
                    } label: {
                        HStack(spacing: 6) {
                            categoryIcon(for: cat, isSelected: isSelected)
                            Text(cat.rawValue)
                                .font(.caption.bold())
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundColor(isSelected ? .white : KinnectTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(isSelected ? KinnectTheme.accentBright : KinnectTheme.surfaceElevated)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Interactive Preview Banner
    private func interactivePreviewBanner(_ preview: StorePackageItem) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Xem thử · \(preview.title)")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Spacer()
                Button {
                    previewPackage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Circle()
                .strokeBorder(Color(hex: preview.accentColor), lineWidth: 4)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color(hex: preview.accentColor).opacity(0.2)))
                .overlay(
                    Image(systemName: preview.iconName)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                )
                .shadow(color: Color(hex: preview.accentColor).opacity(0.6), radius: 10)

            Text("Xin chào! Đây là bản xem thử.")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: preview.accentColor), Color(hex: preview.accentColor).opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )

            Text("Xem thử không thay đổi hồ sơ thực tế của bạn.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(hex: "#1A102E"))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color(hex: preview.accentColor).opacity(0.5), lineWidth: 1.5)
                )
        )
    }

    // MARK: - Packages List
    private var filteredPackages: [StorePackageItem] {
        switch storeFilter {
        case .style:
            return packages.filter { $0.category == "frame" || $0.category == "style" }
        case .studio:
            return packages.filter { $0.category == "studio" }
        case .live:
            return packages.filter { $0.category == "live" }
        case .gifts:
            return packages.filter { $0.category == "gift" || $0.category == "gifts" }
        case .member:
            return packages.filter { $0.category == "membership" || $0.category == "member" }
        case .owned:
            return packages.filter { $0.owned }
        }
    }

    private var packagesSection: some View {
        VStack(spacing: 14) {
            let list = filteredPackages
            if list.isEmpty {
                VStack(spacing: 8) {
                    KinnectIcon(glyph: .store, size: 36, tint: KinnectTheme.textSecondary)
                    Text("Chưa có gói trong mục này")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .kinnectCard()
            } else {
                ForEach(list) { pkg in
                    storePackageCard(pkg)
                }
            }
        }
    }

    private func storePackageCard(_ pkg: StorePackageItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Use the same bundled package artwork as Android.
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color(hex: pkg.accentColor), Color(hex: pkg.accentColor).opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 120)

                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 90, height: 90)
                    .offset(x: -20, y: -20)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if !pkg.badgeText.isEmpty {
                            Text(pkg.badgeText.uppercased())
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.black.opacity(0.35)))
                        }
                        Text(pkg.title)
                            .font(.headline.bold())
                            .foregroundColor(.white)
                    }
                    Spacer()

                    // Visual Graphic / Icon (Parity Android StorePackageDesign)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 2.5)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color.white.opacity(0.22)))
                        .overlay(
                            Image(systemName: packageIconName(for: pkg.id, category: pkg.category))
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .padding(14)
            }
            .overlay {
                if let artwork = packageArtwork(pkg) {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .accessibilityLabel(pkg.title)
                }
            }

            // Description and Action
            VStack(alignment: .leading, spacing: 12) {
                Text(pkg.subtitle)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .lineLimit(2)

                HStack(alignment: .center) {
                    HStack(spacing: 4) {
                        KinnectIcon(glyph: .coin, size: 14, selected: true, tint: KinnectTheme.warning)
                        Text("\(pkg.priceCoins) xu")
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.warning)
                    }

                    Spacer()

                    // Action: Xem thử button
                    Button {
                        withAnimation {
                            previewPackage = pkg
                        }
                    } label: {
                        Text("Xem thử")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(KinnectTheme.surfaceElevated))
                    }

                    // Action: Buy / Equip button
                    if pkg.owned {
                        Button {
                            Task { await usePackage(pkg) }
                        } label: {
                            Text(ownedActionTitle(pkg))
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(pkg.equipped ? KinnectTheme.surfaceElevated : KinnectTheme.online)
                                )
                        }
                    } else {
                        Button {
                            confirmBuyPackage = pkg
                        } label: {
                            Text("Đổi gói")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(
                                        LinearGradient(
                                            colors: [Color(hex: pkg.accentColor), KinnectTheme.accentBright],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                )
                        }
                    }
                }
            }
            .padding(14)
            .background(KinnectTheme.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func packageIconName(for id: String, category: String) -> String {
        StorePackageItem.iconName(for: id, category: category)
    }

    private func categoryIcon(for cat: StoreCategoryFilter, isSelected: Bool) -> some View {
        let tint = isSelected ? Color.white : KinnectTheme.textSecondary
        switch cat {
        case .style:
            return AnyView(Image(systemName: "paintpalette.fill").font(.system(size: 13)).foregroundColor(tint))
        case .studio:
            return AnyView(Image(systemName: "film.fill").font(.system(size: 13)).foregroundColor(tint))
        case .live:
            return AnyView(Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 13)).foregroundColor(tint))
        case .gifts:
            return AnyView(Image(systemName: "gift.fill").font(.system(size: 13)).foregroundColor(tint))
        case .member:
            return AnyView(Image(systemName: "crown.fill").font(.system(size: 13)).foregroundColor(tint))
        case .owned:
            return AnyView(Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundColor(tint))
        }
    }

    // MARK: - Actions
    private func packageArtwork(_ pkg: StorePackageItem) -> UIImage? {
        let key = pkg.id.hasPrefix("studio_video_") ? "studio_video_30"
            : pkg.id.hasPrefix("studio_photo_") ? "studio_photo_30" : pkg.id
        return UIImage(named: "store_pkg_" + key)
    }

    private func ownedActionTitle(_ pkg: StorePackageItem) -> String {
        switch pkg.category {
        case "studio": return "Mở Studio"
        case "gift", "gifts": return "Xem kho quà"
        case "member", "membership": return "Đang sử dụng"
        default:
            if pkg.id == "live_game_30" { return "Quyền Live Game" }
            return pkg.equipped ? "Gỡ trang bị" : "Áp dụng"
        }
    }

    private func applyStoreState(_ res: [String: Any]) {
        let ownedIds = Set(res["ownedPackages"] as? [String] ?? [])
        let expiries = res["packageExpiries"] as? [String: Any] ?? [:]
        let appearance = res["appearance"] as? String ?? ""
        let liveTheme = res["liveTheme"] as? String ?? ""
        let membership = res["membership"] as? String ?? ""
        packages = (res["packages"] as? [[String: Any]] ?? []).map { dict in
            var item = StorePackageItem.from(dict)
            item.owned = ownedIds.contains(item.id)
            item.expiresAt = (expiries[item.id] as? NSNumber)?.int64Value
            item.equipped = [appearance, liveTheme, membership].contains(item.id)
            return item
        }
        trialPackagePurchases = res["trialPackagePurchases"] as? Bool ?? false
        if !trialPackagePurchases { coinSource = "purchased" }
        storeBalance = (res["purchasedCoins"] as? Int ?? 0)
            + (res["giftedCoins"] as? Int ?? res["trialCoins"] as? Int ?? 0)
    }

    private func loadStoreData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/store")
            applyStoreState(res)
            loadError = nil
        } catch {
            loadError = "Chưa tải được cửa hàng: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func buyPackage(_ pkg: StorePackageItem) async {
        guard !transactionInProgress else { return }
        transactionInProgress = true
        defer { transactionInProgress = false }
        // Retain this ID after a transport failure so retry cannot debit twice.
        let key = "kinnect-package-request:" + ServerConfig.currentOrigin + ":"
            + (appState.currentUser?.id ?? "") + ":" + pkg.id + ":" + coinSource
        let requestId = UserDefaults.standard.string(forKey: key) ?? KinnectWriteBody.packageRequestId()
        UserDefaults.standard.set(requestId, forKey: key)
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/store/packages/buy", method: "POST",
                body: KinnectWriteBody.packageBuy(productId: pkg.id, priceCoins: pkg.priceCoins,
                                                  requestId: requestId, coinSource: coinSource),
                requestId: requestId)
            guard (res["ownedPackages"] as? [String] ?? []).contains(pkg.id) else {
                throw KinnectAPIError.serverMessage("Máy chủ chưa xác nhận quyền sử dụng gói.")
            }
            UserDefaults.standard.removeObject(forKey: key)
            applyStoreState(res)
            appState.showToast("Đã sở hữu \(pkg.title)!")
            await loadStoreData()
            await appState.refreshGlobalBadges()
        } catch {
            appState.showToast("Giao dịch chưa hoàn tất: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func usePackage(_ pkg: StorePackageItem) async {
        switch pkg.category {
        case "studio":
            studioPackage = pkg
        case "gift", "gifts":
            onOpenWallet?()
        case "member", "membership":
            appState.showToast("Huy hiệu thành viên được áp dụng tự động trong thời hạn gói.")
        default:
            if pkg.id == "live_game_30" {
                appState.showToast("Gói đã được ghi nhận. Phát màn hình game trên iOS đang được hoàn thiện.")
            } else {
                await equipPackage(pkg)
            }
        }
    }

    @MainActor
    private func equipPackage(_ pkg: StorePackageItem) async {
        guard !transactionInProgress else { return }
        transactionInProgress = true
        defer { transactionInProgress = false }
        do {
            let style = pkg.category == "style" || pkg.id.hasPrefix("style_")
            let endpoint = style ? "/api/store/style" : "/api/store/packages/apply"
            let productId = pkg.equipped ? "" : pkg.id
            let res = try await KinnectAPIClient.shared.requestJSON(
                endpoint, method: "POST", body: KinnectWriteBody.packageApply(productId: productId))
            let applied = res[style ? "appearance" : "liveTheme"] as? String
            guard applied == productId else {
                throw KinnectAPIError.serverMessage("Máy chủ chưa xác nhận trang trí.")
            }
            appState.showToast(productId.isEmpty ? "Đã gỡ trang bị." : "Đã kích hoạt \(pkg.title)!")
            await loadStoreData()
        } catch {
            appState.showToast("Chưa kích hoạt được: \(error.localizedDescription)")
        }
    }
}
