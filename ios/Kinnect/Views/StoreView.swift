import StoreKit
import SwiftUI
import UIKit

/// Dedicated Full-Screen Store Screen matching Android 1.2.12 StoreActivity.java
/// Features 6 category tabs: Phong cách, Gói Live, Gói Studio, Quà tặng, Hội viên, Của tôi.
/// Pinned top header with Back button, Title, Coin balance chip, and Store Menu.
struct StoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var storeKit = StoreKitManager.shared

    private var ownedBadgeInk: Color {
        colorScheme == .dark
            ? Color(red: 0x75 / 255.0, green: 0xC8 / 255.0, blue: 0x9C / 255.0)
            : Color(red: 0x18 / 255.0, green: 0x66 / 255.0, blue: 0x3E / 255.0)
    }

    private var warningIconInk: Color {
        colorScheme == .dark
            ? KinnectTheme.warning
            : Color(red: 0x92 / 255.0, green: 0x40 / 255.0, blue: 0x0E / 255.0)
    }

    var onBack: (() -> Void)? = nil
    var onOpenWallet: (() -> Void)? = nil

    enum StoreCategoryFilter: String, CaseIterable {
        case style = "Phong cách"
        case studio = "Studio"
        case live = "Live"
        case gifts = "Quà"
        case member = "Thành viên"
        case owned = "Của tôi"
    }

    @State private var storeFilter: StoreCategoryFilter = .style
    @State private var previewPackage: StorePackageItem? = nil
    @State private var packages: [StorePackageItem] = []
    @State private var digitalProducts: [StoreDigitalProduct] = []
    @State private var ownedDigitalIds: Set<String> = []
    @State private var activeAppearance: String = ""
    @State private var accountUuid: UUID? = nil
    @State private var showStudioProCamera = false
    @State private var previewDigitalProduct: StoreDigitalProduct? = nil
    @State private var isLoading = false
    @State private var transactionInProgress = false
    @State private var coinSource = "gifted"
    @State private var trialPackagePurchases = true
    @State private var appleBillingReady = false
    @State private var storeBalance = 0
    @State private var purchasedCoinsBalance = 0
    @State private var giftedCoinsBalance = 0
    @State private var studioVideoUntilMs: Int64 = 0
    @State private var studioPhotoUntilMs: Int64 = 0
    @State private var activeMembershipId: String = ""
    @State private var loadError: String?
    @State private var studioPackage: StorePackageItem?
    @State private var giftInventory: [GiftInventoryItem] = []
    @State private var showStoreMenuDialog = false
    @State private var showStoreInfoAlert = false
    @State private var confirmBuyPackage: StorePackageItem? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Dedicated Header Bar with Coin Balance Chip
            storeHeaderBar

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 6 Category Tabs
                    categoryFilterStrip

                    // Hero Shop Banner (only on Style tab, matching Android StoreActivity)
                    if storeFilter == .style {
                        storeHeroBanner
                    }

                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(L10n.tr("Đang tải cửa hàng…"))
                                .font(.subheadline)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .kinnectCard()
                    }

                    // Interactive Live Preview (when "Xem thử" tapped)
                    if let preview = previewPackage {
                        interactivePreviewBanner(preview)
                    } else if let digitalPreview = previewDigitalProduct {
                        interactiveDigitalPreviewBanner(digitalPreview)
                    }

                    // StoreKit 2 Direct In-App Purchase Section (above packages only when Apple billing is active)
                    if appleBillingReady && !filteredDigitalProducts.isEmpty {
                        storeKitProductsSection
                            .disabled(transactionInProgress || storeKit.isPurchasing)
                    }

                    // Package Cards List
                    if let loadError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(loadError)
                                .foregroundColor(KinnectTheme.danger)
                                .font(.subheadline)
                            Button {
                                Task { await loadStoreData() }
                            } label: {
                                Text(L10n.tr("Thử lại"))
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .background(Capsule().fill(KinnectTheme.primaryGradient))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if storeFilter != .owned {
                        if trialPackagePurchases {
                            KinnectSegmentedBar(
                                selection: $coinSource,
                                options: [
                                    ("gifted", L10n.tr("Xu tặng")),
                                    ("purchased", L10n.tr("Xu mua"))
                                ],
                                accessibilityLabel: L10n.tr("Nguồn xu")
                            )
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "bitcoinsign.circle.fill")
                                    .foregroundColor(warningIconInk)
                                Text(L10n.tr("Thanh toán bằng Xu mua"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(KinnectTheme.textSecondary)
                                Spacer()
                                Text("\(purchasedCoinsBalance.formattedWithSeparator()) \(L10n.tr("xu mua"))")
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(KinnectTheme.surfaceElevated)
                            )
                        }
                    }

                    if storeFilter == .live {
                        liveChatFreeCard
                    }

                    if storeFilter == .owned {
                        ownedGiftInventorySection
                    }

                    packagesSection
                        .disabled(transactionInProgress)

                    if !appleBillingReady && !filteredDigitalProducts.isEmpty {
                        storeKitProductsSection
                            .disabled(transactionInProgress || storeKit.isPurchasing)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .clipped()
            .refreshable {
                await loadStoreData()
            }
        }
        .background(KinnectTheme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .kinnectActionSheet(
            isPresented: $showStoreMenuDialog,
            title: L10n.tr("Cửa hàng Kinnect"),
            items: [
                KinnectActionSheetItem(title: L10n.tr("Khôi phục giao dịch"), glyph: .refresh) {
                    Task {
                        do {
                            let outcome = try await storeKit.restorePurchases()
                            appState.showToast(outcome.failed.isEmpty
                                ? L10n.tr("Đã kiểm tra và khôi phục các giao dịch hợp lệ.")
                                : L10n.tr("Một số giao dịch chưa xác minh được. Hãy thử lại."))
                            await loadStoreData()
                        } catch {
                            appState.showToast("\(L10n.tr("Chưa khôi phục được:")) \(error.localizedDescription)")
                        }
                    }
                },
                KinnectActionSheetItem(title: L10n.tr("Phong cách mặc định"), glyph: .profile) {
                    Task {
                        do {
                            _ = try await KinnectAPIClient.shared.requestJSON("/api/store/style", method: "POST", body: ["productId": ""])
                            appState.showToast(L10n.tr("Đã chuyển về phong cách mặc định"))
                            await loadStoreData()
                        } catch {
                            appState.showToast("\(L10n.tr("Chưa đổi được phong cách:")) \(error.localizedDescription)")
                        }
                    }
                },
                KinnectActionSheetItem(title: L10n.tr("Thông tin cửa hàng"), glyph: .info) {
                    showStoreInfoAlert = true
                }
            ]
        )
        .alert(L10n.tr("Cửa hàng Kinnect"), isPresented: $showStoreInfoAlert) {
            Button(L10n.tr("Đóng"), role: .cancel) { }
        } message: {
            Text(L10n.tr("Quyền lợi gắn với tài khoản Kinnect. Xem thử không thay đổi hồ sơ của bạn. Giá hiển thị quy đổi theo xu hoặc App Store."))
        }
        .alert(
            L10n.tr("Xác nhận đổi gói?"),
            isPresented: Binding(
                get: { confirmBuyPackage != nil },
                set: { if !$0 { confirmBuyPackage = nil } }
            ),
            presenting: confirmBuyPackage
        ) { pkg in
            Button(L10n.tr("Hủy"), role: .cancel) { confirmBuyPackage = nil }
            Button("\(L10n.tr("Đổi ngay")) (\(pkg.priceCoins.formattedWithSeparator()) \(L10n.tr("xu")))") {
                confirmBuyPackage = nil
                Task { await buyPackage(pkg) }
            }
        } message: { pkg in
            let effectiveSource = trialPackagePurchases ? coinSource : "purchased"
            let sourceLabel = effectiveSource == "purchased" ? L10n.tr("Xu mua") : L10n.tr("Xu tặng")
            Text("\(L10n.tr("Gói:")) \(pkg.title)\n\(L10n.tr("Chi phí:")) \(pkg.priceCoins.formattedWithSeparator()) \(L10n.tr("xu")) (\(sourceLabel)).")
        }
        .fullScreenCover(item: $studioPackage) { pkg in
            CameraStudioView(initialMode: pkg.id.hasPrefix("studio_video_") ? .video : .photo,
                             onClose: { studioPackage = nil })
        }
        .fullScreenCover(isPresented: $showStudioProCamera) {
            CameraStudioView(initialMode: .photo, onClose: { showStudioProCamera = false })
        }
        .task {
            await loadStoreData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinnectStoreUpdated)) { _ in
            Task { await loadStoreData() }
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
            .accessibilityLabel(L10n.tr("Quay lại"))

            HStack(spacing: 8) {
                KinnectIcon(glyph: .store, size: 20, selected: true, tint: KinnectTheme.accentBright)
                Text(L10n.tr("Cửa hàng"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)
            }

            Spacer()

            // Coin Balance Chip -> Opens Wallet
            Button {
                onOpenWallet?()
            } label: {
                HStack(spacing: 5) {
                    KinnectIcon(glyph: .wallet, size: 15, selected: true, tint: KinnectTheme.accentBright)
                    Text("\(storeBalance.formattedWithSeparator()) \(L10n.tr("xu"))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(KinnectTheme.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 44, minHeight: 44)
                .background(Capsule().fill(KinnectTheme.surfaceElevated))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Xem ví Kinnect"))

            // Store Menu Button
            Button {
                showStoreMenuDialog = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(KinnectTheme.surfaceElevated))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Tùy chọn cửa hàng"))
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
                    KinnectIcon(glyph: .store, size: 14, selected: true, tint: Color(hex: "#E9D5FF"))
                    Text("KINNECT SHOP")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(Color(hex: "#E9D5FF"))
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text(L10n.tr("Xem thử miễn phí"))
                        .font(.caption2.bold())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.18)))
            }

            Text(L10n.tr("Thêm sắc màu.\nThêm chất riêng."))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .lineSpacing(3)
        }
        .padding(16)
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
            HStack(spacing: 6) {
                ForEach(StoreCategoryFilter.allCases, id: \.self) { cat in
                    let isSelected = storeFilter == cat
                    Button {
                        storeFilter = cat
                    } label: {
                        HStack(spacing: 4) {
                            categoryIcon(for: cat, isSelected: isSelected)
                            Text(L10n.tr(cat.rawValue))
                                .font(.caption.bold())
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundColor(isSelected ? .white : KinnectTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(
                            Capsule().fill(isSelected ? KinnectTheme.accent : KinnectTheme.surfaceElevated)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .clipped()
    }

    // MARK: - Interactive Preview Banner
    private func interactivePreviewBanner(_ preview: StorePackageItem) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(L10n.tr("Xem thử")) · \(preview.title)")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Spacer()
                Button {
                    previewPackage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            ZStack {
                Circle()
                    .fill(Color(hex: "#23183D"))
                    .frame(width: 68, height: 68)
                Text("K")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                if let frame = packageFrameImage(preview) {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                } else if let gift = packageGiftImage(preview) {
                    Image(uiImage: gift)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 76)
                } else {
                    Circle()
                        .strokeBorder(Color(hex: preview.accentColor), lineWidth: 4)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(Color(hex: preview.accentColor).opacity(0.2)))
                        .overlay(
                            Image(systemName: preview.iconName)
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
            }
            .shadow(color: Color(hex: preview.accentColor).opacity(0.6), radius: 10)

            Text(L10n.tr("Xin chào! Đây là bản xem thử."))
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

            Text(L10n.tr("Xem thử không thay đổi hồ sơ thực tế của bạn."))
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
    private var filteredDigitalProducts: [StoreDigitalProduct] {
        let storeItems = digitalProducts.filter {
            $0.kind != "coins" && $0.coinsGranted <= 0 && !$0.id.lowercased().contains(".coins.")
        }
        switch storeFilter {
        case .style:
            return storeItems.filter { $0.kind == "style" }
        case .studio:
            return storeItems.filter { $0.kind == "studio" }
        case .owned:
            return storeItems.filter { $0.owned }
        case .live, .gifts, .member:
            return []
        }
    }

    private func interactiveDigitalPreviewBanner(_ prod: StoreDigitalProduct) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(L10n.tr("Xem thử")) · \(prod.title)")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Spacer()
                Button {
                    previewDigitalProduct = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: prod.accentColor), Color(hex: prod.secondaryColor)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: prod.kind == "studio" ? "wand.and.stars" : "paintpalette.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            .shadow(color: Color(hex: prod.accentColor).opacity(0.6), radius: 10)

            Text(prod.description.isEmpty ? L10n.tr("Mở khóa vĩnh viễn trên tài khoản Kinnect qua Apple ID.") : prod.description)
                .font(.caption)
                .foregroundColor(.white.opacity(0.92))
                .multilineTextAlignment(.center)

            Text(L10n.tr("Xem thử không thay đổi hồ sơ thực tế của bạn."))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.75))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(hex: "#1A102E"))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color(hex: prod.accentColor).opacity(0.55), lineWidth: 1.5)
                )
        )
    }

    private var storeKitProductsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "apple.logo")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                    Text(L10n.tr("Mở khóa qua App Store"))
                        .font(.subheadline.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                }
                Spacer()
                Button {
                    Task {
                        do {
                            let outcome = try await storeKit.restorePurchases()
                            await loadStoreData()
                            appState.showToast(outcome.failed.isEmpty
                                ? L10n.tr("Đã kiểm tra và khôi phục các giao dịch hợp lệ.")
                                : L10n.tr("Một số giao dịch chưa xác minh được. Hãy thử lại."))
                        } catch {
                            appState.showToast("\(L10n.tr("Chưa khôi phục được:")) \(error.localizedDescription)")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2.bold())
                        Text(L10n.tr("Khôi phục"))
                            .font(.caption.bold())
                    }
                    .foregroundColor(KinnectTheme.accentBright)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            ForEach(filteredDigitalProducts) { prod in
                storeDigitalProductCard(prod)
            }
        }
    }

    private func storeDigitalProductCard(_ prod: StoreDigitalProduct) -> some View {
        let skProduct = storeKit.storeKitProducts[prod.id]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: prod.accentColor), Color(hex: prod.secondaryColor)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: prod.kind == "studio" ? "wand.and.stars" : "sparkles")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(prod.title)
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        if prod.equipped {
                            Text(L10n.tr("Đang dùng"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(red: 0x18 / 255.0, green: 0x66 / 255.0, blue: 0x3E / 255.0)))
                        } else if prod.owned {
                            Text(L10n.tr("Đã sở hữu"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(ownedBadgeInk)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(KinnectTheme.online.opacity(0.16)))
                        }
                    }
                    Text(prod.description)
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if prod.kind != "coins" && prod.coinsGranted <= 0 {
                    Button {
                        withAnimation {
                            previewPackage = nil
                            previewDigitalProduct = prod
                        }
                    } label: {
                        Text(L10n.tr("Xem thử"))
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Capsule().fill(KinnectTheme.surfaceElevated))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if prod.owned {
                    if prod.kind == "studio" {
                        Button {
                            showStudioProCamera = true
                        } label: {
                            Text(L10n.tr("Mở Studio Pro"))
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(Capsule().fill(KinnectTheme.primaryGradient))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            Task { await toggleDigitalStyle(prod) }
                        } label: {
                            Text(prod.equipped ? L10n.tr("Gỡ trang trí") : L10n.tr("Dùng"))
                                .font(.caption.bold())
                                .foregroundColor(prod.equipped ? KinnectTheme.textPrimary : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(
                                    Capsule().fill(
                                        prod.equipped ? KinnectTheme.surfaceElevated : Color(red: 0x18 / 255.0, green: 0x66 / 255.0, blue: 0x3E / 255.0)
                                    )
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    let canBuyApple = appleBillingReady && skProduct != nil
                    Button {
                        guard canBuyApple && !storeKit.isPurchasing else {
                            appState.showToast(L10n.tr("Chưa mở App Store"))
                            return
                        }
                        Task { await buyDigitalProduct(prod) }
                    } label: {
                        Text(canBuyApple ? "\(L10n.tr("Mua")) · \(skProduct!.displayPrice)" : L10n.tr("Chưa mở App Store"))
                            .font(.caption.bold())
                            .foregroundColor(canBuyApple ? .white : KinnectTheme.inputPlaceholder)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(
                                Capsule().fill(canBuyApple ? AnyShapeStyle(KinnectTheme.primaryGradient) : AnyShapeStyle(KinnectTheme.surfaceElevated))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(KinnectTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(hex: prod.accentColor).opacity(0.28), lineWidth: 1)
                )
        )
    }

    private var liveChatFreeCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(KinnectTheme.primaryGradient)
                    .frame(width: 48, height: 48)
                Image(systemName: "video.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(L10n.tr("Trò chuyện · Miễn phí"))
                        .font(.subheadline.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                    Text(L10n.tr("MIỄN PHÍ"))
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(red: 0x18 / 255.0, green: 0x66 / 255.0, blue: 0x3E / 255.0)))
                }
                Text(L10n.tr("Phát trực tiếp trò chuyện với bạn bè, bộ lọc làm đẹp và nhận quà tặng hoàn toàn miễn phí."))
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(KinnectTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(KinnectTheme.online.opacity(0.3), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var ownedGiftInventorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("Kho quà Live"))
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Spacer()
                Text("\(giftInventory.map(\.quantity).reduce(0, +)) \(L10n.tr("món quà"))")
                    .font(.caption.bold())
                    .foregroundColor(KinnectTheme.accentBright)
            }

            if giftInventory.isEmpty {
                Text(L10n.tr("Chưa có quà dự trữ trong kho."))
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(giftInventory) { item in
                            VStack(spacing: 4) {
                                Text(item.emoji)
                                    .font(.system(size: 26))
                                Text(item.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(KinnectTheme.textPrimary)
                                    .lineLimit(1)
                                Text("x\(item.quantity)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(KinnectTheme.warning)
                            }
                            .frame(width: 78, height: 80)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(KinnectTheme.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(KinnectTheme.borderSoft, lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
                .clipped()
            }
        }
        .kinnectCard()
    }

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
        let list = filteredPackages
        return Group {
            if list.isEmpty {
                VStack(spacing: 8) {
                    KinnectIcon(glyph: .store, size: 36, tint: KinnectTheme.textSecondary)
                    Text(L10n.tr("Chưa có gói trong mục này"))
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .kinnectCard()
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(list) { pkg in
                        storePackageCard(pkg)
                    }
                }
                .clipped()
            }
        }
    }

    // MARK: - Package Artwork View (Android parity: 1:1 fill with proper scaling)
    private struct PackageArtworkView: View {
        let package: StorePackageItem
        let frameImage: UIImage?
        let giftImage: UIImage?
        let artworkImage: UIImage?
        let iconName: String

        @State private var containerSize: CGSize = .zero

        var body: some View {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)

                ZStack {
                    if let frame = frameImage {
                        // Avatar frame: circle background + frame image (84% of container)
                        Circle()
                            .fill(Color(hex: "#23183D"))
                            .frame(width: size * 0.72, height: size * 0.72)
                            .shadow(color: Color(hex: package.accentColor).opacity(0.4), radius: size * 0.08)
                        Text("K")
                            .font(.system(size: size * 0.22, weight: .bold))
                            .foregroundColor(.white)
                        Image(uiImage: frame)
                            .resizable()
                            .scaledToFit()
                            .frame(width: size * 0.84, height: size * 0.84)
                    } else if let gift = giftImage {
                        // Gift: centered, 70% of container
                        Image(uiImage: gift)
                            .resizable()
                            .scaledToFit()
                            .frame(width: size * 0.7, height: size * 0.7)
                            .shadow(color: Color(hex: package.accentColor).opacity(0.4), radius: size * 0.08)
                    } else if let artwork = artworkImage {
                        // Artwork: fit entire container so any text on artwork is fully readable
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                    } else {
                        // Fallback icon
                        Image(systemName: iconName)
                            .font(.system(size: size * 0.28, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    private func storePackageCard(_ pkg: StorePackageItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1:1 Square Artwork Container (Parity with Android 1x1 store without cropping)
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: pkg.accentColor), Color(hex: "#161329")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Render 1:1 artwork - fill the container properly
                PackageArtworkView(
                    package: pkg,
                    frameImage: packageFrameImage(pkg),
                    giftImage: packageGiftImage(pkg),
                    artworkImage: packageArtwork(pkg),
                    iconName: packageIconName(for: pkg.id, category: pkg.category)
                )

                // Top badges
                HStack {
                    if pkg.equipped {
                        Text(L10n.tr("Đang dùng"))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(red: 0x18 / 255.0, green: 0x66 / 255.0, blue: 0x3E / 255.0)))
                    }
                    Spacer()
                    if !pkg.badgeText.isEmpty {
                        Text(pkg.badgeText.uppercased())
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                    }
                }
                .padding(6)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Info and Actions
            VStack(alignment: .leading, spacing: 6) {
                Text(pkg.title)
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(pkg.subtitle)
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack(spacing: 3) {
                    KinnectIcon(glyph: .coin, size: 12, selected: true, tint: KinnectTheme.warning)
                    Text("\(pkg.priceCoins.formattedWithSeparator()) \(L10n.tr("xu"))")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.warning)
                    if pkg.owned, let expMs = pkg.expiresAt {
                        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
                        let remMs = expMs - nowMs
                        if remMs > 0 {
                            let days = max(1, Int(ceil(Double(remMs) / 86_400_000.0)))
                            Spacer(minLength: 4)
                            Text("\(L10n.tr("Còn")) \(days) \(L10n.tr("ngày"))")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(KinnectTheme.online)
                                .lineLimit(1)
                        }
                    }
                }

                HStack(spacing: 4) {
                    Button {
                        withAnimation {
                            previewPackage = pkg
                        }
                    } label: {
                        Text(L10n.tr("Xem thử"))
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundColor(KinnectTheme.accentBright)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(KinnectTheme.surfaceElevated))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if pkg.owned {
                        Button {
                            Task { await usePackage(pkg) }
                        } label: {
                            Text(ownedActionTitle(pkg))
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .foregroundColor(pkg.equipped ? KinnectTheme.textPrimary : .white)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.horizontal, 4)
                                .background(Capsule().fill(pkg.equipped ? KinnectTheme.surfaceElevated : Color(red: 0x18 / 255.0, green: 0x66 / 255.0, blue: 0x3E / 255.0)))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if pkg.kind == "gifts" || pkg.kind == "gift" || pkg.kind == "studio" {
                            Button {
                                requestPurchaseConfirmation(for: pkg)
                            } label: {
                                Text(pkg.kind == "studio" ? L10n.tr("Gia hạn") : L10n.tr("Mua thêm"))
                                    .font(.system(size: 11, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .padding(.horizontal, 4)
                                    .background(
                                        Capsule().fill(
                                            LinearGradient(
                                                colors: [Color(hex: pkg.accentColor), KinnectTheme.accent],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                    )
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        let isAlternateMembershipBlocked = (pkg.category == "member" || pkg.category == "membership")
                            && !activeMembershipId.isEmpty
                            && activeMembershipId != pkg.id
                        Button {
                            guard !isAlternateMembershipBlocked else {
                                appState.showToast(L10n.tr("Đang có gói"))
                                return
                            }
                            requestPurchaseConfirmation(for: pkg)
                        } label: {
                            Text(isAlternateMembershipBlocked ? L10n.tr("Đang có gói") : L10n.tr("Đổi"))
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .foregroundColor(isAlternateMembershipBlocked ? KinnectTheme.inputPlaceholder : .white)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.horizontal, 4)
                                .background(
                                    Capsule().fill(
                                        isAlternateMembershipBlocked
                                            ? AnyShapeStyle(KinnectTheme.surfaceElevated)
                                            : AnyShapeStyle(
                                                LinearGradient(
                                                    colors: [Color(hex: pkg.accentColor), KinnectTheme.accent],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    )
                                )
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(8)
            .background(KinnectTheme.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func packageFrameImage(_ pkg: StorePackageItem) -> UIImage? {
        let suffix = pkg.id.hasPrefix("style_") ? String(pkg.id.dropFirst(6)) : pkg.id
        return UIImage(named: "avatar_frame_" + suffix)
    }

    private func packageGiftImage(_ pkg: StorePackageItem) -> UIImage? {
        let giftName = pkg.id == "gift_love" ? "gift_rose"
            : pkg.id == "gift_speed" ? "gift_sports_car"
            : pkg.id == "gift_royal" ? "gift_crown" : ""
        return giftName.isEmpty ? nil : UIImage(named: giftName)
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
        case "studio": return L10n.tr("Mở Studio")
        case "gift", "gifts": return L10n.tr("Xem kho quà")
        case "member", "membership": return L10n.tr("Đang sử dụng")
        default:
            if pkg.id == "live_game_30" { return L10n.tr("Quyền Live Game") }
            return pkg.equipped ? L10n.tr("Gỡ trang bị") : L10n.tr("Áp dụng")
        }
    }

    private func applyStoreState(_ res: [String: Any]) {
        if let uuidStr = res["accountUuid"] as? String, let parsed = UUID(uuidString: uuidStr) {
            accountUuid = parsed
        }
        appleBillingReady = (res["appleBillingReady"] as? Bool) == true
        let ownedIds = Set(res["ownedPackages"] as? [String] ?? [])
        let isStudioProPermanent = (res["studioProPermanent"] as? Bool) == true
        var directOwned = Set(res["owned"] as? [String] ?? [])
        if isStudioProPermanent {
            directOwned.insert("kinnect_studio_pro")
        } else {
            directOwned.remove("kinnect_studio_pro")
        }
        ownedDigitalIds = directOwned
        let expiries = res["packageExpiries"] as? [String: Any] ?? [:]
        let appearance = (res["appearance"] as? String) ?? (res["activeStyle"] as? String) ?? ""
        activeAppearance = appearance
        let liveTheme = res["liveTheme"] as? String ?? ""
        let membership = res["membership"] as? String ?? ""
        activeMembershipId = membership
        studioVideoUntilMs = (res["studioVideoUntil"] as? NSNumber)?.int64Value ?? 0
        studioPhotoUntilMs = (res["studioPhotoUntil"] as? NSNumber)?.int64Value ?? 0
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        digitalProducts = (res["products"] as? [[String: Any]] ?? []).compactMap { dict in
            var item = StoreDigitalProduct.from(dict)
            if item.kind == "coins" || item.coinsGranted > 0 || item.id.lowercased().contains(".coins.") {
                return nil
            }
            item.owned = (item.id == "kinnect_studio_pro") ? isStudioProPermanent : directOwned.contains(item.id)
            item.equipped = !item.id.isEmpty && item.kind == "style" && item.id == appearance
            return item
        }
        packages = (res["packages"] as? [[String: Any]] ?? []).compactMap { dict in
            var item = StorePackageItem.from(dict)
            guard item.id != "live_game_30" else { return nil }
            if item.category == "studio" {
                let lineUntil: Int64 = item.id.hasPrefix("studio_video_") ? studioVideoUntilMs
                    : (item.id.hasPrefix("studio_photo_") ? studioPhotoUntilMs : max(studioVideoUntilMs, studioPhotoUntilMs))
                item.owned = ownedIds.contains(item.id) || lineUntil > nowMs
                item.expiresAt = (expiries[item.id] as? NSNumber)?.int64Value ?? (lineUntil > nowMs ? lineUntil : nil)
            } else {
                item.owned = ownedIds.contains(item.id)
                item.expiresAt = (expiries[item.id] as? NSNumber)?.int64Value
            }
            item.equipped = [appearance, liveTheme, membership].contains(item.id)
            return item
        }
        trialPackagePurchases = res["trialPackagePurchases"] as? Bool ?? false
        if !trialPackagePurchases { coinSource = "purchased" }
        purchasedCoinsBalance = (res["purchasedCoins"] as? Int) ?? (res["purchasedCoins"] as? NSNumber)?.intValue ?? 0
        giftedCoinsBalance = (res["giftedCoins"] as? Int) ?? (res["trialCoins"] as? Int) ?? (res["trialCoins"] as? NSNumber)?.intValue ?? 0
        storeBalance = purchasedCoinsBalance + giftedCoinsBalance
        let rawInv = res["giftInventory"] as? [[String: Any]] ?? []
        var totals: [String: Int] = [:]
        var orderedIds: [String] = []
        for entry in rawInv {
            guard let gid = entry["giftId"] as? String, !gid.isEmpty else { continue }
            let qty = (entry["quantity"] as? Int) ?? (entry["quantity"] as? NSNumber)?.intValue ?? 0
            guard qty > 0 else { continue }
            if totals[gid] == nil { orderedIds.append(gid) }
            totals[gid, default: 0] += qty
        }
        giftInventory = orderedIds.compactMap { gid in
            guard let qty = totals[gid], qty > 0 else { return nil }
            return GiftInventoryItem(giftId: gid, quantity: qty)
        }
    }

    private func requestPurchaseConfirmation(for pkg: StorePackageItem) {
        let effectiveSource = trialPackagePurchases ? coinSource : "purchased"
        let availableBalance = effectiveSource == "purchased" ? purchasedCoinsBalance : giftedCoinsBalance
        if pkg.priceCoins > availableBalance {
            let sourceName = effectiveSource == "purchased" ? L10n.tr("xu mua") : L10n.tr("xu tặng")
            appState.showToast("\(L10n.tr("Chưa đủ")) \(sourceName). \(L10n.tr("Cần")) \(pkg.priceCoins.formattedWithSeparator()) \(L10n.tr("xu")) (\(L10n.tr("hiện có")) \(availableBalance.formattedWithSeparator()) \(L10n.tr("xu"))).")
            return
        }
        confirmBuyPackage = pkg
    }

    private func loadStoreData() async {
        if packages.isEmpty && digitalProducts.isEmpty, let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/store") {
            applyStoreState(cached)
        }
        isLoading = packages.isEmpty && digitalProducts.isEmpty
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/store")
            applyStoreState(res)
            loadError = nil
            await storeKit.loadProducts(productIds: digitalProducts.map(\.id).filter { !$0.isEmpty })
        } catch {
            if packages.isEmpty && digitalProducts.isEmpty {
                loadError = "\(L10n.tr("Chưa tải được cửa hàng:")) \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func buyDigitalProduct(_ prod: StoreDigitalProduct) async {
        guard !transactionInProgress && !storeKit.isPurchasing else { return }
        transactionInProgress = true
        defer { transactionInProgress = false }
        do {
            guard let verifyRes = try await storeKit.purchaseDigitalProduct(productId: prod.id, accountUuid: accountUuid) else {
                return
            }
            if let serverOwned = verifyRes["owned"] as? [String],
               (verifyRes["state"] as? String) == "PURCHASED" {
                if prod.id == "kinnect_studio_pro" {
                    ownedDigitalIds.insert("kinnect_studio_pro")
                } else {
                    for id in serverOwned where id != "kinnect_studio_pro" {
                        ownedDigitalIds.insert(id)
                    }
                }
            }
            appState.showToast("\(L10n.tr("Đã mở khóa")) \(prod.title)!")
            await loadStoreData()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    @MainActor
    private func toggleDigitalStyle(_ prod: StoreDigitalProduct) async {
        guard !transactionInProgress else { return }
        transactionInProgress = true
        defer { transactionInProgress = false }
        let targetId = prod.equipped ? "" : prod.id
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/store/style",
                method: "POST",
                body: ["productId": targetId]
            )
            let applied = (res["appearance"] as? String) ?? ""
            guard applied == targetId else {
                throw KinnectAPIError.serverMessage(L10n.tr("Máy chủ chưa xác nhận trang trí."))
            }
            appState.showToast(targetId.isEmpty ? L10n.tr("Đã gỡ trang trí.") : "\(L10n.tr("Đã áp dụng")) \(prod.title)!")
            await loadStoreData()
        } catch {
            appState.showToast("\(L10n.tr("Chưa đổi được phong cách:")) \(error.localizedDescription)")
        }
    }

    @MainActor
    private func buyPackage(_ pkg: StorePackageItem) async {
        guard !transactionInProgress else { return }
        transactionInProgress = true
        defer { transactionInProgress = false }
        // Retain this ID after a transport failure so retry cannot debit twice.
        let effectiveSource = trialPackagePurchases ? coinSource : "purchased"
        let key = "kinnect-package-request:" + ServerConfig.currentOrigin + ":"
            + (appState.currentUser?.id ?? "") + ":" + pkg.id + ":" + effectiveSource
        let requestId = UserDefaults.standard.string(forKey: key) ?? KinnectWriteBody.packageRequestId()
        UserDefaults.standard.set(requestId, forKey: key)
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/store/packages/buy", method: "POST",
                body: KinnectWriteBody.packageBuy(productId: pkg.id, priceCoins: pkg.priceCoins,
                                                  requestId: requestId, coinSource: effectiveSource),
                requestId: requestId)
            let isDuplicate = (res["duplicate"] as? Bool) == true
            let isGiftPack = pkg.id.hasPrefix("gift_") || pkg.category == "gifts" || pkg.category == "gift"
            let ownedList = res["ownedPackages"] as? [String] ?? []
            if isGiftPack || isDuplicate {
                UserDefaults.standard.removeObject(forKey: key)
            }
            guard isGiftPack || isDuplicate || ownedList.contains(pkg.id) else {
                throw KinnectAPIError.serverMessage(L10n.tr("Máy chủ chưa xác nhận quyền sử dụng gói."))
            }
            UserDefaults.standard.removeObject(forKey: key)
            applyStoreState(res)
            appState.showToast(isDuplicate ? "\(L10n.tr("Giao dịch đã được ghi nhận trước đó cho")) \(pkg.title)." : "\(L10n.tr("Đã sở hữu")) \(pkg.title)!")
            await loadStoreData()
            await appState.refreshGlobalBadges()
        } catch {
            appState.showToast("\(L10n.tr("Giao dịch chưa hoàn tất:")) \(error.localizedDescription)")
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
            appState.showToast(L10n.tr("Huy hiệu thành viên được áp dụng tự động trong thời hạn gói."))
        default:
            if pkg.id == "live_game_30" {
                appState.showToast(L10n.tr("Gói đã được ghi nhận. Phát màn hình game trên iOS đang được hoàn thiện."))
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
                throw KinnectAPIError.serverMessage(L10n.tr("Máy chủ chưa xác nhận trang trí."))
            }
            appState.showToast(productId.isEmpty ? L10n.tr("Đã gỡ trang bị.") : "\(L10n.tr("Đã kích hoạt")) \(pkg.title)!")
            await loadStoreData()
        } catch {
            appState.showToast("\(L10n.tr("Chưa kích hoạt được:")) \(error.localizedDescription)")
        }
    }
}
