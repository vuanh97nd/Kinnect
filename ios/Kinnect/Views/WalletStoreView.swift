import SwiftUI

struct WalletStoreView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var storeKit = StoreKitManager.shared

    enum SectionTab: String, CaseIterable {
        case wallet = "Ví Kinnect"
        case packages = "Cửa hàng"
        case topup = "Nạp xu"
    }

    enum StoreCategoryFilter: String, CaseIterable {
        case style = "Phong cách"
        case live = "Phòng Live"
        case gifts = "Bộ quà"
        case member = "Hội viên"
        case studio = "Studio Pro"
        case owned = "Đã sở hữu"
    }

    @State private var tab: SectionTab = .wallet
    @State private var storeFilter: StoreCategoryFilter = .style
    @State private var previewPackage: StorePackageItem? = nil

    init(initialTab: SectionTab = .wallet, initialStoreFilter: StoreCategoryFilter = .style) {
        _tab = State(initialValue: initialTab)
        _storeFilter = State(initialValue: initialStoreFilter)
    }

    @State private var availableBalance: Int = 0
    @State private var earnedBalance: Int = 0
    @State private var spentBalance: Int = 0
    @State private var purchasedCoins: Int = 0
    @State private var giftedCoins: Int = 0
    @State private var isBalanceHidden: Bool = false
    @State private var currencyLabel: String = "Xu Kinnect"
    @State private var entries: [WalletEntryItem] = []
    @State private var packages: [StorePackageItem] = []
    @State private var digitalProducts: [StoreDigitalProduct] = []
    @State private var accountUuid: UUID? = nil
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Segmented Tab
            Picker("Ví & Cửa hàng", selection: $tab) {
                ForEach(SectionTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(KinnectTheme.background)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .wallet:
                        walletSectionView

                    case .packages:
                        storeSectionView

                    case .topup:
                        storeKitSectionView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 84)
            }
            .refreshable {
                await loadWalletAndStore()
            }
        }
        .background(KinnectTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(tab == .wallet ? "Ví Kinnect" : (tab == .topup ? "Nạp xu Kinnect" : "Cửa hàng Kinnect"))
        .task {
            await loadWalletAndStore()
        }
        .onAppear {
            if UIReviewFixture.activeScreen == "wallet-topup" {
                tab = .topup
            } else if UIReviewFixture.activeScreen == "wallet-packages" || UIReviewFixture.activeScreen == "store-packages" {
                tab = .packages
            } else if UIReviewFixture.activeScreen == "wallet" {
                tab = .wallet
            }
        }
    }

    // MARK: - 1. Ví Kinnect (Strict Parity with Web `walletScreen`)
    private var walletSectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Main Hero Balance Card matching Web `linear-gradient(125deg,#5b21b6,#c026d3)`
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        KinnectIcon(glyph: .wallet, size: 16, selected: true, tint: .white)
                        Text("VÍ KINNECT")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.95))
                    }
                    Spacer()
                    Button {
                        isBalanceHidden.toggle()
                    } label: {
                        Image(systemName: isBalanceHidden ? "eye.slash" : "eye")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ẩn / hiện số dư")
                }

                HStack(spacing: 0) {
                    // Column 1: Xu mua
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            KinnectIcon(glyph: .coin, size: 16, selected: true, tint: .white)
                            Text("Xu mua")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        Text(isBalanceHidden ? "••••" : "\(purchasedCoins.formattedWithSeparator()) xu")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Vertical Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 1, height: 42)
                        .padding(.horizontal, 12)

                    // Column 2: Xu tặng
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            KinnectIcon(glyph: .gift, size: 16, selected: true, tint: .white)
                            Text("Xu tặng")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        Text(isBalanceHidden ? "••••" : "\(giftedCoins.formattedWithSeparator()) xu")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    tab = .topup
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Nạp xu Kinnect")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.white.opacity(0.22))
                    )
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#5B21B6"), Color(hex: "#C026D3")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )

            // Panel: Thu nhập từ Live (Web Parity `wallet-earnings`)
            VStack(alignment: .leading, spacing: 10) {
                Text("Thu nhập từ Live")
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.textPrimary)

                HStack(alignment: .firstTextBaseline) {
                    Text(isBalanceHidden ? "••••" : "\(earnedBalance.formattedWithSeparator())đ")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(KinnectTheme.accentBright)

                    Spacer()

                    Button {
                        appState.showToast("Đang kết nối chi trả tự động. Chưa mở rút tiền.")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right")
                            Text("Rút tiền")
                        }
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(KinnectTheme.surfaceElevated)
                        )
                    }
                }

                Text("Bạn nhận 75% · Nền tảng 25%")
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .kinnectCard()

            // Status Note matching Web
            Text("Đang kết nối thanh toán và chi trả tự động. Chưa mở nạp, mua bằng xu hoặc rút tiền.")
                .font(.caption2)
                .foregroundColor(KinnectTheme.textSecondary)
                .padding(.horizontal, 4)

            // Transaction History Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Lịch sử giao dịch")
                    .font(.headline.bold())
                    .foregroundColor(KinnectTheme.textPrimary)

                if entries.isEmpty && !isLoading {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            KinnectIcon(glyph: .coin, size: 32, tint: KinnectTheme.textSecondary)
                            Text("Chưa có giao dịch")
                                .font(.subheadline)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                    .kinnectCard()
                } else {
                    ForEach(entries) { entry in
                        HStack(alignment: .center, spacing: 12) {
                            KinnectIcon(
                                glyph: entry.direction == "credit" ? .add : .coin,
                                size: 20,
                                selected: true,
                                tint: entry.direction == "credit" ? KinnectTheme.online : KinnectTheme.accentBright
                            )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(KinnectTheme.textPrimary)
                                    .lineLimit(2)
                                if !entry.note.isEmpty {
                                    Text(entry.note)
                                        .font(.caption2)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                        .lineLimit(2)
                                }
                                Text(formatRelativeDate(entry.createdAt))
                                    .font(.caption2)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }

                            Spacer(minLength: 8)

                            Text(entry.direction == "credit" ? "+\(entry.amount.formattedWithSeparator()) xu" : "-\(entry.amount.formattedWithSeparator()) xu")
                                .font(.subheadline.bold())
                                .foregroundColor(entry.direction == "credit" ? KinnectTheme.online : KinnectTheme.textPrimary)
                                .layoutPriority(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(KinnectTheme.surface)
                        )
                    }
                }
            }

            // Bottom Policy Text matching Web
            Text("Tỷ lệ chia áp dụng sau phí thanh toán và hoàn tiền. Xu mua vật phẩm và thu nhập được rút là hai số dư riêng. Xu tặng không quy đổi thành tiền mặt.")
                .font(.caption2)
                .foregroundColor(KinnectTheme.textSecondary)
                .lineSpacing(3)
                .padding(.horizontal, 4)
                .padding(.top, 4)
        }
    }

    // MARK: - 2. Cửa hàng Kinnect (Strict Parity with Web `storeScreen`)
    private var storeSectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Store Hero Banner matching Web `store-hero`
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

            // Category Filter Pills matching Web `store-category`
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

            // Interactive Live Preview Banner when user taps "Xem thử" (Web `storePreview()`)
            if let preview = previewPackage {
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

                    // Avatar with package border
                    Circle()
                        .strokeBorder(Color(hex: preview.accentColor), lineWidth: 4)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(Color(hex: preview.accentColor).opacity(0.2)))
                        .overlay(
                            Text("K")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .shadow(color: Color(hex: preview.accentColor).opacity(0.6), radius: 10)

                    // Preview Chat Bubble matching Web `.store-preview-chat`
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
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(radius: 4)

                    Text(preview.subtitle.isEmpty ? "Khung avatar và màu bong bóng hội thoại đặc quyền." : preview.subtitle)
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    Text("Xem thử không thay đổi hồ sơ và không cấp quyền sử dụng.")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary.opacity(0.8))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(KinnectTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Color(hex: preview.accentColor).opacity(0.4), lineWidth: 1.5)
                        )
                )
            }

            // Section Title & Items Count
            HStack {
                Text(storeFilter == .studio ? "Sáng tạo cùng Studio Pro" : (storeFilter == .owned ? "Bộ sưu tập của bạn" : "Chọn màu cho cá tính"))
                    .font(.headline.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Spacer()
                Text("\(filteredPackages.count) lựa chọn")
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
            }

            // Grid of Packages with Individual Visual Artwork Design
            if filteredPackages.isEmpty && !isLoading {
                VStack(spacing: 8) {
                    Text(storeFilter == .owned ? "Bạn chưa sở hữu gói trang trí nào." : "Chưa có gói trong danh mục này.")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .kinnectCard()
            } else {
                ForEach(filteredPackages) { pkg in
                    storeProductCard(pkg)
                }
            }

            // Footer note
            VStack(spacing: 6) {
                Text("Xem thử miễn phí · Gói đã mua được đồng bộ vĩnh viễn theo tài khoản Kinnect.")
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    private var filteredPackages: [StorePackageItem] {
        packages.filter { p in
            switch storeFilter {
            case .style:
                return p.kind == "style" || p.kind == "frame" || p.kind == "badge" || p.kind.isEmpty
            case .live:
                return p.kind == "live"
            case .gifts:
                return p.kind == "gifts"
            case .member:
                return p.kind == "member"
            case .studio:
                return p.kind == "studio" || p.id.contains("studio")
            case .owned:
                return p.owned
            }
        }
    }

    @ViewBuilder
    private func categoryIcon(for cat: StoreCategoryFilter, isSelected: Bool) -> some View {
        let tint: Color = isSelected ? .white : KinnectTheme.textSecondary
        switch cat {
        case .style:
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
        case .live:
            KinnectIcon(glyph: .live, size: 14, selected: isSelected, tint: tint)
        case .gifts:
            KinnectIcon(glyph: .gift, size: 14, selected: isSelected, tint: tint)
        case .member:
            Image(systemName: "crown.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
        case .studio:
            KinnectIcon(glyph: .studio, size: 14, selected: isSelected, tint: tint)
        case .owned:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
        }
    }

    @ViewBuilder
    private func packageKindIcon(_ kind: String, accentHex: String) -> some View {
        let accent = Color(hex: accentHex)
        switch kind {
        case "live":
            KinnectIcon(glyph: .live, size: 20, selected: true, tint: accent)
        case "gifts":
            KinnectIcon(glyph: .gift, size: 20, selected: true, tint: accent)
        case "member":
            Image(systemName: "crown.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(accent)
        case "studio":
            KinnectIcon(glyph: .studio, size: 20, selected: true, tint: accent)
        default:
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(accent)
        }
    }

    // MARK: - Individual Package Card with Visual Artwork Parity (`storeArtwork(p)`)
    private func storeProductCard(_ pkg: StorePackageItem) -> some View {
        VStack(spacing: 0) {
            // 1. Top Artwork Header (Web Parity `storeArtwork`)
            StorePackageArtworkView(pkg: pkg)
                .frame(height: 140)

            // 2. Body Copy & Actions
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(pkg.title)
                                .font(.headline.bold())
                                .foregroundColor(.white)
                            if !pkg.badgeText.isEmpty {
                                Text(pkg.badgeText)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color(hex: pkg.accentColor).opacity(0.3)))
                                    .foregroundColor(.white)
                            }
                        }

                        Text(pkg.subtitle.isEmpty ? "Khung avatar và màu bong bóng hội thoại." : pkg.subtitle)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    packageKindIcon(pkg.kind, accentHex: pkg.accentColor)
                }

                // Price Row
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if pkg.owned {
                        Text("Đã sở hữu")
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.online)
                        Text("· Đồng bộ theo tài khoản")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        KinnectIcon(glyph: .coin, size: 16, selected: true, tint: KinnectTheme.warning)
                        Text("\(pkg.priceCoins.formattedWithSeparator()) xu")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(KinnectTheme.warning)
                        Text("· Mua một lần")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }

                // Action Buttons Row (Xem thử + Mua / Trang bị)
                HStack(spacing: 10) {
                    Button {
                        previewPackage = pkg
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                                .font(.caption2)
                            Text("Xem thử")
                                .font(.caption.bold())
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(Color.white.opacity(0.14))
                        )
                    }

                    Spacer()

                    if pkg.owned {
                        Button {
                            Task { await applyPackage(pkg) }
                        } label: {
                            Text(pkg.equipped ? "Đang sử dụng" : "Áp dụng")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule().fill(pkg.equipped ? KinnectTheme.surfaceElevated : KinnectTheme.online)
                                )
                        }
                    } else {
                        Button {
                            Task { await buyPackage(pkg) }
                        } label: {
                            Text("Đổi gói")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
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
            .padding(16)
            .background(KinnectTheme.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 3. Nạp xu StoreKit
    private var storeKitSectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nạp xu Kinnect")
                    .font(.headline.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Text("Xu nạp được sử dụng để tặng quà trải nghiệm cho thần tượng trong phòng Live và mở khóa các gói trang trí hồ sơ độc quyền.")
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .kinnectMultiline()
            }

            ForEach(digitalProducts) { prod in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prod.title)
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text(prod.description)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                        HStack(spacing: 4) {
                            KinnectIcon(glyph: .coin, size: 14, selected: true, tint: KinnectTheme.warning)
                            Text("Gói xu chính thức")
                                .font(.caption2.bold())
                                .foregroundColor(KinnectTheme.warning)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await purchaseStoreKitProduct(prod) }
                    } label: {
                        Text(storeKit.storeKitProducts[prod.id]?.displayPrice ?? prod.priceLabel)
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(KinnectTheme.primaryGradient))
                            .foregroundColor(.white)
                    }
                    .disabled(storeKit.isPurchasing)
                }
                .kinnectCard()
            }

            Button {
                Task {
                    do {
                        let r = try await storeKit.restorePurchases()
                        if r.isEmpty {
                            appState.showToast("Không tìm thấy gói mua nào có thể khôi phục cho Apple ID này.")
                        } else if r.failed.isEmpty && r.unverified == 0 {
                            let revokedNote = r.revoked.isEmpty ? "" : " \(r.revoked.count) gói đã hoàn tiền không được khôi phục."
                            appState.showToast("Đã khôi phục \(r.reconciled.count) gói.\(revokedNote)")
                        } else {
                            appState.showToast("Chưa khôi phục được \(r.failed.count + r.unverified) gói. Vui lòng thử lại sau.")
                        }
                    } catch {
                        appState.showToast("Chưa khôi phục được: \(error.localizedDescription)")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                    Text("Khôi phục gói mua đã thanh toán")
                        .font(.caption.bold())
                }
                .foregroundColor(KinnectTheme.accentBright)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }

            Text("Lưu ý: Tính năng khôi phục StoreKit áp dụng cho các gói dịch vụ cố định và mẫu giao diện đã mua. Số dư xu Kinnect được lưu trữ an toàn trên máy chủ tài khoản Kinnect.")
                .font(.caption2)
                .foregroundColor(KinnectTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.top, 2)
        }
    }

    // MARK: - API Calls
    private func loadWalletAndStore() async {
        isLoading = true
        defer { isLoading = false }

        async let wTask = KinnectAPIClient.shared.requestJSON("/api/wallet")
        async let sTask = KinnectAPIClient.shared.requestJSON("/api/store")

        if let wRes = try? await wTask {
            if let wallet = wRes["wallet"] as? [String: Any] {
                self.availableBalance = wallet["availableBalance"] as? Int ?? 0
                self.earnedBalance = wallet["earnedBalance"] as? Int ?? 0
                self.spentBalance = wallet["spentBalance"] as? Int ?? 0
                self.purchasedCoins = wallet["purchasedCoins"] as? Int ?? (wallet["paidCoins"] as? Int ?? self.earnedBalance)
                self.giftedCoins = wallet["giftedCoins"] as? Int ?? (wallet["trialCoins"] as? Int ?? max(0, self.availableBalance - self.purchasedCoins))
                self.currencyLabel = wallet["currencyLabel"] as? String ?? "Xu Kinnect"
            }
            let rawEntries = wRes["entries"] as? [[String: Any]] ?? []
            self.entries = rawEntries.map(WalletEntryItem.from)
        }

        if let sRes = try? await sTask {
            if let uuidStr = sRes["accountUuid"] as? String, let uuid = UUID(uuidString: uuidStr) {
                self.accountUuid = uuid
            }
            let rawPkgs = sRes["packages"] as? [[String: Any]] ?? []
            let ownedIds = Set(sRes["ownedPackages"] as? [String] ?? [])
            let expiries = sRes["packageExpiries"] as? [String: Any] ?? [:]
            let liveTheme = sRes["liveTheme"] as? String ?? ""
            let membership = sRes["membership"] as? String ?? ""
            self.packages = rawPkgs.map { dict in
                var item = StorePackageItem.from(dict)
                item.owned = ownedIds.contains(item.id)
                if let raw = expiries[item.id] as? NSNumber {
                    item.expiresAt = raw.int64Value
                }
                item.equipped = !item.id.isEmpty && (item.id == liveTheme || item.id == membership)
                return item
            }
            let rawProds = sRes["products"] as? [[String: Any]] ?? []
            self.digitalProducts = rawProds.map(StoreDigitalProduct.from)
            await storeKit.loadProducts(productIds: self.digitalProducts.map(\.id))
        }
    }

    private func buyPackage(_ pkg: StorePackageItem) async {
        let reqId = KinnectWriteBody.packageRequestId()
        let source = giftedCoins >= pkg.priceCoins ? "gifted" : "purchased"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/store/packages/buy",
                method: "POST",
                body: KinnectWriteBody.packageBuy(
                    productId: pkg.id,
                    priceCoins: pkg.priceCoins,
                    requestId: reqId,
                    coinSource: source
                ),
                requestId: reqId
            )
            appState.showToast("Đã đổi gói '\(pkg.title)' thành công!")
            await loadWalletAndStore()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func applyPackage(_ pkg: StorePackageItem) async {
        let productId = pkg.equipped ? "" : pkg.id
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/store/packages/apply",
                method: "POST",
                body: KinnectWriteBody.packageApply(productId: productId)
            )
            await loadWalletAndStore()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func purchaseStoreKitProduct(_ prod: StoreDigitalProduct) async {
        do {
            _ = try await storeKit.purchaseDigitalProduct(productId: prod.id, accountUuid: self.accountUuid)
            appState.showToast("Xác minh giao dịch StoreKit thành công!")
            await loadWalletAndStore()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

// MARK: - Visual Artwork for Each Package (100% Web `storeArtwork` & Android `StorePackageDesign`)
private struct StorePackageArtworkView: View {
    let pkg: StorePackageItem

    private var assetImageName: String {
        let id = pkg.id
        if id.starts(with: "studio_video_") {
            return "store_pkg_studio_video_30"
        } else if id.starts(with: "studio_photo_") {
            return "store_pkg_studio_photo_30"
        }
        return "store_pkg_" + id
    }

    private var resolvedImage: UIImage? {
        if let img = UIImage(named: assetImageName) {
            return img
        }
        // Fallback to direct bundle file lookup
        let candidatePaths = [
            Bundle.main.path(forResource: assetImageName, ofType: "png"),
            Bundle.main.path(forResource: assetImageName, ofType: "webp"),
            Bundle.main.path(forResource: assetImageName, ofType: "png", inDirectory: "StoreArt"),
            Bundle.main.path(forResource: "StoreArt/\(assetImageName)", ofType: "png"),
            Bundle.main.path(forResource: "Graphics/\(assetImageName)", ofType: "png")
        ]
        for p in candidatePaths.compactMap({ $0 }) {
            if let img = UIImage(contentsOfFile: p) {
                return img
            }
        }
        return nil
    }

    var body: some View {
        ZStack {
            if let img = resolvedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 140)
                    .clipped()
            } else {
                // Background Gradient with Package Accent Colors
                LinearGradient(
                    colors: [Color(hex: pkg.accentColor).opacity(0.85), Color(hex: "#181326")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

            if pkg.kind == "studio" || pkg.id.contains("studio") {
                // Studio Pro Filmstrip Artwork
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                        Image(systemName: "play.circle.fill")
                            .font(.largeTitle)
                        Image(systemName: "film.fill")
                            .font(.title2)
                    }
                    .foregroundColor(.white)

                    Text("AURORA · TRAVEL · CINEMA")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.9))
                }
            } else {
                // Style Package Artwork: Orbit ring + Avatar + Chat bubble (Web `.store-art`)
                ZStack {
                    // Orbit Circle (.store-art-orbit)
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 130, height: 130)

                    // Avatar Circle (.store-art-avatar)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 3)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color(hex: pkg.accentColor)))
                        .overlay(
                            Text("K")
                                .font(.system(size: 28, weight: .heavy))
                                .foregroundColor(.white)
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                        .offset(x: -28, y: -8)

                    // Mini Chat Bubble (.store-art-chat)
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule()
                            .fill(Color(hex: pkg.accentColor))
                            .frame(width: 38, height: 4)
                        Capsule()
                            .fill(Color(hex: pkg.accentColor).opacity(0.6))
                            .frame(width: 24, height: 4)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.9))
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                    .rotationEffect(.degrees(-6))
                    .offset(x: 34, y: 14)

                    // Caption (.store-art-caption)
                    VStack {
                        Spacer()
                        Text("\(pkg.title.uppercased()) COLLECTION")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(2.5)
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.bottom, 8)
                    }
                }
            }
            }
        }
    }
}

private extension Int {
    func formattedWithSeparator() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
