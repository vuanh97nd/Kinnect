import SwiftUI
import UIKit

/// Dedicated Full-Screen Wallet Screen matching Android 1.2.12 WalletActivity.java
/// Features Hero Coin Balance Card with hide/show toggle, 3 shortcut actions (Nạp xu, Rút tiền, Cửa hàng),
/// Live earnings card, Kho quà Live (10 gift types), Transaction filters & history, and Top-up Sheet.
struct WalletView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var storeKit = StoreKitManager.shared

    var onBack: (() -> Void)? = nil
    var onOpenStore: (() -> Void)? = nil

    enum HistoryFilter: String, CaseIterable {
        case all = "Tất cả"
        case topup = "Nạp xu"
        case spend = "Chi tiêu"
        case grant = "Được tặng"
        case income = "Thu nhập"

        var apiKey: String {
            switch self {
            case .all: return "all"
            case .topup: return "topup"
            case .spend: return "spend"
            case .grant: return "grant"
            case .income: return "income"
            }
        }
    }

    @State private var availableBalance: Int = 0
    @State private var earnedBalance: Int = 0
    @State private var spentBalance: Int = 0
    @State private var purchasedCoins: Int = 0
    @State private var giftedCoins: Int = 0
    @State private var isBalanceHidden: Bool = false
    @State private var currencyLabel: String = "Xu Kinnect"
    @State private var entries: [WalletEntryItem] = []
    @State private var digitalProducts: [StoreDigitalProduct] = []
    @State private var selectedFilter: HistoryFilter = .all
    @State private var isLoading = false
    @State private var showWalletInfoAlert = false
    @State private var showTopUpSheet = false
    @State private var selectedEntryDetail: WalletEntryItem? = nil

    @State private var giftInventory: [GiftInventoryItem] = [
        GiftInventoryItem(giftId: "rose", quantity: 12),
        GiftInventoryItem(giftId: "coffee", quantity: 5),
        GiftInventoryItem(giftId: "heart", quantity: 8),
        GiftInventoryItem(giftId: "love_gun", quantity: 2),
        GiftInventoryItem(giftId: "diamond", quantity: 3),
        GiftInventoryItem(giftId: "crown", quantity: 1),
        GiftInventoryItem(giftId: "sports_car", quantity: 0),
        GiftInventoryItem(giftId: "yacht", quantity: 0),
        GiftInventoryItem(giftId: "castle", quantity: 0),
        GiftInventoryItem(giftId: "fireworks", quantity: 4)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Dedicated Header Bar matching Android WalletActivity
            walletHeaderBar

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. Hero Balance Card
                    heroBalanceCard

                    // 2. Action Shortcuts (Nạp xu, Rút tiền, Cửa hàng) matching Android
                    actionShortcutsRow

                    // 3. Live Earnings Card
                    liveEarningsCard

                    // 4. Kho quà Live (Gift inventory)
                    giftInventorySection

                    // 5. Transaction History Filter Strip
                    transactionFilterStrip

                    // 6. Transaction History List
                    transactionHistoryList

                    // Policy text
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
        .background(KinnectTheme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .alert("Ví Kinnect", isPresented: $showWalletInfoAlert) {
            Button("Đóng", role: .cancel) { }
        } message: {
            Text("Xu tặng và quà nhận từ xu tặng không rút được. Xu mua còn dư được rút theo tỷ lệ quy đổi. Quà từ xu mua tạo thu nhập sau phí và hoàn tiền: người nhận 75%, nền tảng 25%. Không cộng trùng xu mua đã gửi quà. Nạp và rút tiền thật chưa mở.")
        }
        .sheet(item: $selectedEntryDetail) { entry in
            transactionDetailSheet(entry)
        }
        .sheet(isPresented: $showTopUpSheet) {
            topUpSheetContent
        }
        .task {
            await loadWalletData()
        }
    }

    // MARK: - Header Bar
    private var walletHeaderBar: some View {
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

            // Info Button
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

            // Refresh Button
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

            // Total Balance
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

            // Two Sub-columns: Xu mua and Xu tặng
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

            // Quick Top-up Button
            Button {
                showTopUpSheet = true
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
            // Nạp xu
            Button {
                showTopUpSheet = true
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

            // Rút tiền
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

            // Cửa hàng -> Transitions to StoreView!
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
                        selectedEntryDetail = entry
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

    // MARK: - Transaction Detail Sheet
    private func transactionDetailSheet(_ entry: WalletEntryItem) -> some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 12)

            Text("Chi tiết giao dịch")
                .font(.headline.bold())
                .foregroundColor(KinnectTheme.textPrimary)

            VStack(spacing: 12) {
                Text(entry.direction == "credit" ? "+\(entry.amount.formattedWithSeparator()) xu" : "-\(entry.amount.formattedWithSeparator()) xu")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(entry.direction == "credit" ? KinnectTheme.online : KinnectTheme.textPrimary)

                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .multilineTextAlignment(.center)

                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Text(formatRelativeDate(entry.createdAt))
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(KinnectTheme.surface)
            )
            .padding(.horizontal, 16)

            Button("Đóng") {
                selectedEntryDetail = nil
            }
            .font(.subheadline.bold())
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(KinnectTheme.accentBright))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .presentationDetents([.height(340)])
    }

    // MARK: - Top-Up Sheet Content
    private var topUpSheetContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Conversion Rate Badge
                    HStack {
                        Spacer()
                        Text("1 xu = 100đ")
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(KinnectTheme.accentSoft))
                        Spacer()
                    }

                    Text("Chọn gói nạp xu Kinnect")
                        .font(.headline.bold())
                        .foregroundColor(KinnectTheme.textPrimary)

                    // Coin Packages Grid
                    let packages: [(coins: Int, price: String)] = [
                        (100, "10.000đ"),
                        (200, "20.000đ"),
                        (500, "50.000đ"),
                        (1000, "100.000đ"),
                        (2000, "200.000đ"),
                        (5000, "500.000đ")
                    ]

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(packages, id: \.coins) { pack in
                            Button {
                                appState.showToast("Cổng thanh toán đang kết nối. Gói \(pack.coins) xu.")
                            } label: {
                                VStack(spacing: 6) {
                                    Text("\(pack.coins) xu")
                                        .font(.headline.bold())
                                        .foregroundColor(KinnectTheme.accentBright)
                                    Text(pack.price)
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
                    }

                    // StoreKit Products (if configured)
                    if !digitalProducts.isEmpty {
                        Text("Gói mua qua App Store")
                            .font(.headline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                            .padding(.top, 8)

                        ForEach(digitalProducts) { prod in
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
                                        _ = try? await storeKit.purchaseProduct(productId: prod.id)
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
                    }

                    Text("Xu nạp được sử dụng trong phòng Livestream và mua các vật phẩm độc quyền trên Cửa hàng Kinnect.")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                .padding(16)
            }
            .background(KinnectTheme.background.ignoresSafeArea())
            .navigationTitle("Nạp xu Kinnect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        showTopUpSheet = false
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.accentBright)
                }
            }
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

    private func formatRelativeDate(_ ts: Int64) -> String {
        guard ts > 0 else { return "Gần đây" }
        let date = Date(timeIntervalSince1970: TimeInterval(ts > 10_000_000_000 ? ts / 1000 : ts))
        let df = DateFormatter()
        df.dateFormat = "dd/MM · HH:mm"
        return df.string(from: date)
    }

    // MARK: - API Calls
    private func loadWalletData() async {
        isLoading = true
        defer { isLoading = false }

        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/wallet") {
            if let wallet = res["wallet"] as? [String: Any] {
                self.availableBalance = wallet["availableBalance"] as? Int ?? (wallet["coins"] as? Int ?? 0)
                self.earnedBalance = wallet["earnedBalance"] as? Int ?? 0
                self.spentBalance = wallet["spentBalance"] as? Int ?? 0
                self.purchasedCoins = wallet["purchasedCoins"] as? Int ?? (wallet["paidCoins"] as? Int ?? self.earnedBalance)
                self.giftedCoins = wallet["giftedCoins"] as? Int ?? (wallet["trialCoins"] as? Int ?? max(0, self.availableBalance - self.purchasedCoins))
                self.currencyLabel = wallet["currencyLabel"] as? String ?? "Xu Kinnect"
            }
            let rawEntries = res["entries"] as? [[String: Any]] ?? []
            self.entries = rawEntries.map(WalletEntryItem.from)
        }
    }
}
