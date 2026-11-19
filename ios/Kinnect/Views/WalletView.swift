import SwiftUI
import UIKit

/// Dedicated Full-Screen Wallet Screen matching Android 1.2.12 WalletActivity.java and modern social media apps (TikTok, Zalo, Instagram)
/// 100% Full-Screen navigation (NO popup sheets).
/// Features Hero Coin Balance Card with hide/show toggle, 3 shortcut actions (Nạp xu, Rút tiền, Cửa hàng),
/// Live earnings card, Kho quà Live (10 gift types), Transaction filters & history, and Full-screen Top-up & Details.
struct WalletView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var storeKit = StoreKitManager.shared

    var onBack: (() -> Void)? = nil
    var onOpenStore: (() -> Void)? = nil

    enum WalletSubScreen: Equatable {
        case main
        case topUp
        case transactionDetail(WalletEntryItem)

        static func == (lhs: WalletSubScreen, rhs: WalletSubScreen) -> Bool {
            switch (lhs, rhs) {
            case (.main, .main): return true
            case (.topUp, .topUp): return true
            case (.transactionDetail(let a), .transactionDetail(let b)): return a.id == b.id
            default: return false
            }
        }
    }

    enum HistoryFilter: String, CaseIterable {
        case all = "Tất cả"
        case topup = "Nạp xu"
        case spend = "Chi tiêu"
        case grant = "Được tặng"
        case income = "Thu nhập"
    }

    @State private var subScreen: WalletSubScreen = .main
    @State private var availableBalance: Int = 0
    @State private var earnedBalance: Int = 0
    @State private var spentBalance: Int = 0
    @State private var purchasedCoins: Int = 0
    @State private var giftedCoins: Int = 0
    @State private var isBalanceHidden: Bool = false
    @State private var currencyLabel: String = "Xu Kinnect"
    @State private var entries: [WalletEntryItem] = []
    @State private var digitalProducts: [StoreDigitalProduct] = []
    @State private var coinPacks: [StoreDigitalProduct] = []
    @State private var selectedFilter: HistoryFilter = .all
    @State private var isLoading = false
    @State private var showWalletInfoAlert = false

    @State private var giftInventory: [GiftInventoryItem] = []
    @State private var loadError: String?

    var body: some View {
        ZStack {
            switch subScreen {
            case .main:
                mainWalletContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal: .move(edge: .leading)
                    ))

            case .topUp:
                fullScreenTopUpContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))

            case .transactionDetail(let item):
                fullScreenDetailContent(item)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KinnectTheme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .alert("Ví Kinnect", isPresented: $showWalletInfoAlert) {
            Button("Đóng", role: .cancel) { }
        } message: {
            Text("Xu tặng và quà nhận từ xu tặng không rút được. Xu mua còn dư được rút theo tỷ lệ quy đổi. Quà từ xu mua tạo thu nhập sau phí và hoàn tiền: người nhận 75%, nền tảng 25%. Không cộng trùng xu mua đã gửi quà. Nạp và rút tiền thật chưa mở.")
        }
        .task {
            await loadWalletData()
        }
    }

    // MARK: - 1. MAIN WALLET CONTENT
    private var mainWalletContent: some View {
        VStack(spacing: 0) {
            walletMainHeaderBar

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let loadError {
                        Text(loadError).foregroundColor(KinnectTheme.danger)
                    }
                    heroBalanceCard
                    actionShortcutsRow
                    liveEarningsCard
                    giftInventorySection
                    transactionFilterStrip
                    transactionHistoryList
                    bottomPolicyText
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 80)
            }
            .refreshable {
                await loadWalletData()
            }
        }
    }

    // MARK: - Header Bar
    private var walletMainHeaderBar: some View {
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
                KinnectIcon(glyph: .wallet, size: 20, selected: true, tint: KinnectTheme.warning)
                Text("Ví Kinnect")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)
            }

            Spacer()

            Button {
                showWalletInfoAlert = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(KinnectTheme.surfaceElevated))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thông tin ví")

            Button {
                Task { await loadWalletData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(KinnectTheme.surfaceElevated))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Làm mới")
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(KinnectTheme.surface.ignoresSafeArea(edges: .top))
        .overlay(Divider().background(KinnectTheme.borderSoft), alignment: .bottom)
    }

    // MARK: - Hero Balance Card
    private var heroBalanceCard: some View {
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Tổng số dư xu")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.85))
                Text(isBalanceHidden ? "••••" : "\(availableBalance.formattedWithSeparator()) xu")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        KinnectIcon(glyph: .coin, size: 14, selected: true, tint: .white)
                        Text("Xu mua")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Text(isBalanceHidden ? "••••" : "\(purchasedCoins.formattedWithSeparator()) xu")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 1, height: 36)
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        KinnectIcon(glyph: .gift, size: 14, selected: true, tint: .white)
                        Text("Xu tặng")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Text(isBalanceHidden ? "••••" : "\(giftedCoins.formattedWithSeparator()) xu")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    subScreen = .topUp
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Nạp xu Kinnect")
                        .font(.subheadline.bold())
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(Color.white.opacity(0.22)))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#7C3AED"), Color(hex: "#C026D3")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    // MARK: - Action Shortcuts Row
    private var actionShortcutsRow: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    subScreen = .topUp
                }
            } label: {
                VStack(spacing: 8) {
                    Circle()
                        .fill(KinnectTheme.warning.opacity(0.18))
                        .frame(width: 46, height: 46)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(KinnectTheme.warning)
                        )
                    Text("Nạp xu")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(KinnectTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.borderSoft, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)

            Button {
                appState.showToast("Đang kết nối chi trả tự động. Chưa mở rút tiền mặt.")
            } label: {
                VStack(spacing: 8) {
                    Circle()
                        .fill(KinnectTheme.online.opacity(0.18))
                        .frame(width: 46, height: 46)
                        .overlay(
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(KinnectTheme.online)
                        )
                    Text("Rút tiền")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(KinnectTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.borderSoft, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)

            Button {
                if let onOpenStore = onOpenStore {
                    onOpenStore()
                }
            } label: {
                VStack(spacing: 8) {
                    Circle()
                        .fill(KinnectTheme.accentBright.opacity(0.18))
                        .frame(width: 46, height: 46)
                        .overlay(
                            KinnectIcon(glyph: .store, size: 22, selected: true, tint: KinnectTheme.accentBright)
                        )
                    Text("Cửa hàng")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(KinnectTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.borderSoft, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Live Earnings Card
    private var liveEarningsCard: some View {
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
                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
                }
            }

            Text("Bạn nhận 75% · Nền tảng 25%")
                .font(.caption)
                .foregroundColor(KinnectTheme.textSecondary)
        }
        .kinnectCard()
    }

    // MARK: - Kho quà Live
    private var giftInventorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Kho quà Live của bạn")
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Spacer()
                Text("\(giftInventory.map(\.quantity).reduce(0, +)) món quà")
                    .font(.caption)
                    .foregroundColor(KinnectTheme.accentBright)
            }

            if giftInventory.isEmpty {
                Text("Kho quà của bạn đang trống.")
                    .font(.caption).foregroundColor(KinnectTheme.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(giftInventory) { gift in
                        VStack(spacing: 6) {
                            Text(giftIconEmoji(gift.giftId))
                                .font(.system(size: 28))
                            Text(gift.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(KinnectTheme.textPrimary)
                                .lineLimit(1)
                            Text("x\(gift.quantity)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(gift.quantity > 0 ? KinnectTheme.warning : KinnectTheme.textSecondary)
                        }
                        .frame(width: 80, height: 86)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(KinnectTheme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(KinnectTheme.borderSoft, lineWidth: 1))
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Transaction Filter Strip
    private var transactionFilterStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lịch sử giao dịch")
                .font(.headline.bold())
                .foregroundColor(KinnectTheme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HistoryFilter.allCases, id: \.self) { filter in
                        let isSelected = selectedFilter == filter
                        Button {
                            selectedFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(.caption.bold())
                                .foregroundColor(isSelected ? .white : KinnectTheme.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
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
    }

    // MARK: - Transaction History List
    private var filteredEntries: [WalletEntryItem] {
        if selectedFilter == .all {
            return entries
        }
        return entries.filter { entry in
            switch selectedFilter {
            case .all:
                return true
            case .topup:
                return entry.title.contains("Nạp") || entry.title.contains("mua")
            case .spend:
                return entry.direction == "debit"
            case .grant:
                return entry.title.contains("tặng") || entry.title.contains("chào mừng") || entry.direction == "credit"
            case .income:
                return entry.title.contains("Thu nhập") || entry.title.contains("Live")
            }
        }
    }

    private var transactionHistoryList: some View {
        VStack(spacing: 8) {
            let list = filteredEntries
            if list.isEmpty && !isLoading {
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
                ForEach(list) { entry in
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            subScreen = .transactionDetail(entry)
                        }
                    } label: {
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
                                Text(entry.createdAt.isEmpty ? "Gần đây" : entry.createdAt)
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
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(KinnectTheme.surface)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 2. FULL-SCREEN TOP-UP VIEW (100% Full Screen, NO Popups)
    private var fullScreenTopUpContent: some View {
        VStack(spacing: 0) {
            // Pinned Dedicated Header
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        subScreen = .main
                    }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quay lại Ví")

                Text("Nạp xu Kinnect")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)

                Spacer()

                Text("1 xu = 100đ")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(KinnectTheme.accentBright)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(KinnectTheme.accentSoft))
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(KinnectTheme.surface.ignoresSafeArea(edges: .top))
            .overlay(Divider().background(KinnectTheme.borderSoft), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Balance Chip
                    HStack {
                        Text("Số dư hiện tại:")
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)
                        Spacer()
                        Text("\(availableBalance.formattedWithSeparator()) xu")
                            .font(.headline.bold())
                            .foregroundColor(KinnectTheme.warning)
                    }
                    .kinnectCard()

                    Text("Chọn gói nạp xu")
                        .font(.headline.bold())
                        .foregroundColor(KinnectTheme.textPrimary)

                    // 6 Packages
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(coinPacks) { pack in
                            topUpOptionCard(coins: pack.coinsGranted, price: pack.priceLabel)
                        }
                    }

                    // StoreKit digital products
                    topUpStoreKitSection

                    Text("Xu nạp được sử dụng trong phòng Livestream và mua các vật phẩm độc quyền trên Cửa hàng Kinnect.")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                .padding(16)
                .padding(.bottom, 60)
            }
        }
    }

    @ViewBuilder
    private var topUpStoreKitSection: some View {
        if !digitalProducts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Gói mua In-App Purchase")
                    .font(.headline.bold())
                    .foregroundColor(KinnectTheme.textPrimary)

                ForEach(digitalProducts, id: \.id) { prod in
                    digitalProductRow(prod)
                }
            }
        }
    }

    private func digitalProductRow(_ prod: StoreDigitalProduct) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(prod.title)
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Text(prod.description)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            Spacer()
            Button {
                Task {
                    _ = try? await storeKit.purchaseDigitalProduct(productId: prod.id)
                    await loadWalletData()
                }
            } label: {
                Text(prod.priceLabel)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(KinnectTheme.primaryGradient))
            }
        }
        .kinnectCard()
    }

    private func topUpOptionCard(coins: Int, price: String) -> some View {
        Button {
            appState.showToast("Cổng thanh toán đang kết nối. Gói \(coins) xu.")
        } label: {
            VStack(spacing: 6) {
                Text("\(coins) xu")
                    .font(.headline.bold())
                    .foregroundColor(KinnectTheme.accentBright)
                Text(price)
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(KinnectTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.borderSoft, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. FULL-SCREEN TRANSACTION DETAIL VIEW (100% Full Screen, NO Popups)
    private func fullScreenDetailContent(_ entry: WalletEntryItem) -> some View {
        VStack(spacing: 0) {
            // Pinned Dedicated Header
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        subScreen = .main
                    }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quay lại Ví")

                Text("Chi tiết giao dịch")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(KinnectTheme.surface.ignoresSafeArea(edges: .top))
            .overlay(Divider().background(KinnectTheme.borderSoft), alignment: .bottom)

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Circle()
                            .fill((entry.direction == "credit" ? KinnectTheme.online : KinnectTheme.warning).opacity(0.18))
                            .frame(width: 64, height: 64)
                            .overlay(
                                KinnectIcon(
                                    glyph: entry.direction == "credit" ? .add : .coin,
                                    size: 30,
                                    selected: true,
                                    tint: entry.direction == "credit" ? KinnectTheme.online : KinnectTheme.warning
                                )
                            )

                        Text(entry.direction == "credit" ? "+\(entry.amount.formattedWithSeparator()) xu" : "-\(entry.amount.formattedWithSeparator()) xu")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(entry.direction == "credit" ? KinnectTheme.online : KinnectTheme.textPrimary)

                        Text("Giao dịch thành công")
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.online)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 14) {
                        detailRow(title: "Nội dung", value: entry.title)
                        if !entry.note.isEmpty {
                            detailRow(title: "Ghi chú", value: entry.note)
                        }
                        detailRow(title: "Thời gian", value: entry.createdAt.isEmpty ? "Gần đây" : entry.createdAt)
                        detailRow(title: "Loại tiền", value: currencyLabel)
                        detailRow(title: "Mã giao dịch", value: String(entry.id.prefix(12)))
                    }
                    .kinnectCard()

                    Text("Xu tặng và quà từ xu tặng không rút được. Xu mua còn dư được rút theo tỷ lệ quy đổi. Quà từ xu mua tạo thu nhập: người nhận 75%, nền tảng 25%.")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .lineSpacing(3)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
                .padding(16)
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(KinnectTheme.textSecondary)
                .frame(width: 110, alignment: .leading)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(KinnectTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var bottomPolicyText: some View {
        Text("Tỷ lệ chia áp dụng sau phí thanh toán và hoàn tiền. Xu mua vật phẩm và thu nhập được rút là hai số dư riêng. Xu tặng không quy đổi thành tiền mặt.")
            .font(.caption2)
            .foregroundColor(KinnectTheme.textSecondary)
            .lineSpacing(3)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    private func giftIconEmoji(_ id: String) -> String {
        switch id {
        case "rose": return "🌹"
        case "coffee": return "☕"
        case "heart": return "❤️"
        case "love_gun": return "🔫"
        case "diamond": return "💎"
        case "crown": return "👑"
        case "sports_car": return "🏎️"
        case "yacht": return "🛥️"
        case "castle": return "🏰"
        case "fireworks": return "🎆"
        default: return "🎁"
        }
    }

    // MARK: - API Calls
    private func loadWalletData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/wallet")
            let wallet = res["wallet"] as? [String: Any] ?? res
            purchasedCoins = wallet["purchasedCoins"] as? Int ?? 0
            giftedCoins = wallet["giftedCoins"] as? Int ?? wallet["trialCoins"] as? Int ?? 0
            availableBalance = wallet["totalUsableCoins"] as? Int ?? (purchasedCoins + giftedCoins)
            earnedBalance = wallet["earningsVnd"] as? Int ?? 0
            spentBalance = wallet["spentCoins"] as? Int ?? 0
            currencyLabel = "Xu Kinnect"
            coinPacks = (wallet["coinPacks"] as? [[String: Any]] ?? []).map(StoreDigitalProduct.from)
            entries = (wallet["entries"] as? [[String: Any]] ?? []).map(WalletEntryItem.from)
            loadError = nil
            let store = try await KinnectAPIClient.shared.requestJSON("/api/store")
            giftInventory = (store["giftInventory"] as? [[String: Any]] ?? []).compactMap { item in
                guard let id = item["giftId"] as? String, let count = item["quantity"] as? Int, count > 0 else { return nil }
                return GiftInventoryItem(giftId: id, quantity: count)
            }
        } catch {
            loadError = "Chưa tải được dữ liệu ví: \(error.localizedDescription)"
        }
    }
}
