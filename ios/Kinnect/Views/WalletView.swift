import StoreKit
import SwiftUI
import UIKit

/// Dedicated Full-Screen Wallet Screen matching Android 1.2.12 WalletActivity.java and modern social media apps (TikTok, Zalo, Instagram)
/// 100% Full-Screen navigation (NO popup sheets).
/// Features Hero Coin Balance Card with hide/show toggle, 3 shortcut actions (Nạp xu, Rút tiền, Cửa hàng),
/// Live earnings card, Kho quà Live (10 gift types), Transaction filters & history, and Full-screen Top-up & Details.
struct WalletView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var storeKit = StoreKitManager.shared

    private var ownedBadgeInk: Color {
        colorScheme == .dark
            ? Color(red: 0x75 / 255.0, green: 0xC8 / 255.0, blue: 0x9C / 255.0)
            : Color(red: 0x18 / 255.0, green: 0x66 / 255.0, blue: 0x3E / 255.0)
    }

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
    @State private var vndPerCoin: Int = 100
    @State private var withdrawableVnd: Int = 0
    @State private var giftedGiftValueCoins: Int = 0
    @State private var isBalanceHidden: Bool = false
    @State private var currencyLabel: String = "Xu Kinnect"
    @State private var entries: [WalletEntryItem] = []
    @State private var digitalProducts: [StoreDigitalProduct] = []
    @State private var ownedDigitalIds: Set<String> = []
    @State private var activeAppearance: String = ""
    @State private var showStudioFromWallet: Bool = false
    @State private var applyingProductId: String? = nil
    @State private var coinPacks: [StoreDigitalProduct] = []
    @State private var topUpEnabled: Bool = false
    @State private var appleBillingReady: Bool = false
    @State private var storeAccountUuid: String? = nil
    @State private var isRestoringPurchases = false
    @State private var selectedFilter: HistoryFilter = .all
    @State private var isLoading = false
    @State private var showWalletInfoAlert = false

    @State private var giftInventory: [GiftInventoryItem] = []
    @State private var loadError: String?
    @State private var selectedTopUpPackId: String? = nil

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
        .fullScreenCover(isPresented: $showStudioFromWallet) {
            CameraStudioView(initialMode: .photo, onClose: { showStudioFromWallet = false })
        }
        .task {
            await loadWalletData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinnectStoreUpdated)) { _ in
            Task { await loadWalletData() }
        }
    }

    // MARK: - 1. MAIN WALLET CONTENT
    private var mainWalletContent: some View {
        VStack(spacing: 0) {
            walletMainHeaderBar

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let loadError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(loadError)
                                .font(.subheadline)
                                .foregroundColor(KinnectTheme.danger)
                            Button {
                                Task { await loadWalletData() }
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .kinnectCard()
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
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .clipped()
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
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
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
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Làm mới"))

            Menu {
                Button {
                    Task { await handleRestorePurchases() }
                } label: {
                    Label(L10n.tr("Khôi phục giao dịch"), systemImage: "arrow.clockwise")
                }
                .disabled(isRestoringPurchases || storeKit.isPurchasing)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(KinnectTheme.surfaceElevated))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.tr("Tùy chọn ví"))
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(KinnectTheme.surface.ignoresSafeArea(edges: .top))
        .overlay(Divider().background(KinnectTheme.borderSoft), alignment: .bottom)
    }

    // MARK: - Hero Balance Card
    private var heroBalanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    KinnectIcon(glyph: .wallet, size: 16, selected: true, tint: .white)
                    Text("VÍ KINNECT")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(.white)
                }
                Spacer()
                Button {
                    isBalanceHidden.toggle()
                } label: {
                    Image(systemName: isBalanceHidden ? "eye.slash" : "eye")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ẩn / hiện số dư")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tổng số dư xu")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white)
                Text(isBalanceHidden ? "••••" : "\(availableBalance.formattedWithSeparator()) xu")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
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
                            .foregroundColor(.white)
                    }
                    Text(isBalanceHidden ? "••••" : "\(purchasedCoins.formattedWithSeparator()) xu")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 1, height: 34)
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        KinnectIcon(glyph: .gift, size: 14, selected: true, tint: .white)
                        Text("Xu tặng")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white)
                    }
                    Text(isBalanceHidden ? "••••" : "\(giftedCoins.formattedWithSeparator()) xu")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#5B21B6"), Color(hex: "#A21CAF")],
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
                VStack(spacing: 6) {
                    Circle()
                        .fill(KinnectTheme.warning.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(KinnectTheme.warning)
                        )
                    Text("Nạp xu")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(KinnectTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.borderSoft, lineWidth: 1))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                appState.showToast("Đang kết nối chi trả tự động. Chưa mở rút tiền mặt.")
            } label: {
                VStack(spacing: 6) {
                    Circle()
                        .fill(KinnectTheme.online.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(KinnectTheme.online)
                        )
                    Text("Rút tiền")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(KinnectTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.borderSoft, lineWidth: 1))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if let onOpenStore = onOpenStore {
                    onOpenStore()
                }
            } label: {
                VStack(spacing: 6) {
                    Circle()
                        .fill(KinnectTheme.accentBright.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay(
                            KinnectIcon(glyph: .store, size: 20, selected: true, tint: KinnectTheme.accentBright)
                        )
                    Text("Cửa hàng")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(KinnectTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.borderSoft, lineWidth: 1))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Live Earnings Card
    private var liveEarningsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Thu nhập từ Live")
                .font(.subheadline.bold())
                .foregroundColor(KinnectTheme.textPrimary)

            HStack(alignment: .firstTextBaseline) {
                Text(isBalanceHidden ? "••••" : "\(earnedBalance.formattedWithSeparator())đ")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
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
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text("Bạn nhận 75% · Nền tảng 25%")
                .font(.caption)
                .foregroundColor(KinnectTheme.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text("Có thể rút: \(isBalanceHidden ? "••••" : "\(withdrawableVnd.formattedWithSeparator())đ")")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(KinnectTheme.textSecondary)
                    Text("Quà xu tặng nhận: \(isBalanceHidden ? "••••" : "\(giftedGiftValueCoins.formattedWithSeparator()) xu")")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                Text("Quà từ xu tặng không quy đổi thành tiền mặt rút ra.")
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
        }
        .kinnectCard()
    }

    // MARK: - Kho quà Live
    private var giftInventorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
            } else {
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
                .clipped()
            }
        }
    }

    // MARK: - Transaction Filter Strip
    private var transactionFilterStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                if !entry.category.isEmpty { return entry.category == "topup" }
                return entry.title.contains("Nạp") || entry.title.contains("mua")
            case .spend:
                if !entry.category.isEmpty { return entry.category == "spend" }
                return entry.direction == "debit"
            case .grant:
                if !entry.category.isEmpty { return entry.category == "grant" }
                return entry.title.contains("tặng") || entry.title.contains("chào mừng")
            case .income:
                if !entry.category.isEmpty { return entry.category == "income" }
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
                                Text(Self.formatEntryTimestamp(entry.createdAt))
                                    .font(.caption2)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }

                            Spacer(minLength: 8)

                            Text(isBalanceHidden
                                 ? "••••"
                                 : ((entry.currency == "vnd" || entry.creatorVnd > 0)
                                     ? "+\(entry.creatorVnd.formattedWithSeparator())đ"
                                     : (entry.direction == "credit" ? "+\(entry.amount.formattedWithSeparator()) xu" : "-\(entry.amount.formattedWithSeparator()) xu")))
                                .font(.subheadline.bold())
                                .foregroundColor(entry.direction == "credit" || entry.creatorVnd > 0 ? KinnectTheme.online : KinnectTheme.textPrimary)
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

                Text("1 xu = \(vndPerCoin.formattedWithSeparator())đ")
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
                        Text(isBalanceHidden ? "••••" : "\(availableBalance.formattedWithSeparator()) xu")
                            .font(.headline.bold())
                            .foregroundColor(KinnectTheme.warning)
                    }
                    .kinnectCard()

                    if topUpEnabled && !coinPacks.isEmpty {
                        Text("Chọn gói nạp xu")
                            .font(.headline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(coinPacks) { pack in
                                topUpOptionCard(pack: pack)
                            }
                        }
                    }

                    if !topUpEnabled {
                        Text("Các gói nạp xu trực tiếp hiện chưa mở cho tài khoản này. Bạn vẫn có thể sử dụng xu hiện có hoặc mở khóa trực tiếp các tính năng/phong cách qua App Store bên dưới.")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectCard()
                    }

                    // StoreKit digital products (direct feature & style unlocks, not coin packs)
                    topUpStoreKitSection

                    restorePurchasesButton

                    Text("Xu nạp được sử dụng trong phòng Livestream và mua các vật phẩm độc quyền trên Cửa hàng Kinnect.")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                .padding(16)
                .padding(.bottom, 60)
            }
            .clipped()
        }
    }

    @ViewBuilder
    private var topUpStoreKitSection: some View {
        if !digitalProducts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mở khóa trực tiếp qua App Store")
                    .font(.headline.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Text("Các gói mở khóa tính năng Studio Pro và phong cách hồ sơ mua một lần qua Apple ID (không phải gói nạp xu).")
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)

                ForEach(digitalProducts, id: \.id) { prod in
                    digitalProductRow(prod)
                }
            }
        }
    }

    private func digitalProductRow(_ prod: StoreDigitalProduct) -> some View {
        let skProduct = storeKit.storeKitProducts[prod.id]
        let isOwned = prod.owned || ownedDigitalIds.contains(prod.id)
        let isEquipped = prod.equipped || (prod.kind == "style" && !prod.id.isEmpty && prod.id == activeAppearance)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(prod.title)
                        .font(.subheadline.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                    if isEquipped {
                        Text(L10n.tr("Đang dùng"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(red: 0x18 / 255.0, green: 0x66 / 255.0, blue: 0x3E / 255.0)))
                    } else if isOwned {
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
            }
            Spacer()
            if isOwned {
                if prod.kind == "studio" {
                    Button {
                        showStudioFromWallet = true
                    } label: {
                        Text(L10n.tr("Mở Studio"))
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Capsule().fill(KinnectTheme.primaryGradient))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Task { await applyOwnedDigitalStyle(prod, currentlyEquipped: isEquipped) }
                    } label: {
                        Text(L10n.tr(isEquipped ? "Gỡ trang trí" : "Áp dụng"))
                            .font(.caption.bold())
                            .foregroundColor(isEquipped ? KinnectTheme.textPrimary : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(
                                Capsule().fill(isEquipped ? KinnectTheme.surfaceElevated : Color(red: 0x18 / 255.0, green: 0x66 / 255.0, blue: 0x3E / 255.0))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(applyingProductId == prod.id)
                }
            } else {
                let canBuyApple = appleBillingReady && skProduct != nil
                Button {
                    guard canBuyApple && !storeKit.isPurchasing else {
                        appState.showToast("Tính năng thanh toán App Store đang được kích hoạt.")
                        return
                    }
                    Task {
                        do {
                            guard let verifyRes = try await storeKit.purchaseDigitalProduct(productId: prod.id, accountUuid: storeAccountUuid) else {
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
                            appState.showToast("Giao dịch thành công! Đã mở khóa \(prod.title) trên tài khoản.")
                            await loadWalletData()
                        } catch {
                            appState.showToast(error.localizedDescription)
                        }
                    }
                } label: {
                    Text(canBuyApple ? skProduct!.displayPrice : L10n.tr("Chưa mở App Store"))
                        .font(.caption.bold())
                        .foregroundColor(canBuyApple ? .white : KinnectTheme.inputPlaceholder)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(
                            Capsule().fill(canBuyApple ? AnyShapeStyle(KinnectTheme.primaryGradient) : AnyShapeStyle(KinnectTheme.surfaceElevated))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .kinnectCard()
    }

    @MainActor
    private func applyOwnedDigitalStyle(_ prod: StoreDigitalProduct, currentlyEquipped: Bool) async {
        guard applyingProductId == nil else { return }
        applyingProductId = prod.id
        defer { applyingProductId = nil }
        let targetId = currentlyEquipped ? "" : prod.id
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/store/style",
                method: "POST",
                body: ["productId": targetId]
            )
            activeAppearance = (res["appearance"] as? String) ?? targetId
            appState.showToast(targetId.isEmpty ? "Đã gỡ trang trí." : "Đã áp dụng \(prod.title)!")
            await loadWalletData()
        } catch {
            appState.showToast("Chưa áp dụng được phong cách: \(error.localizedDescription)")
        }
    }

    private var restorePurchasesButton: some View {
        Button {
            Task { await handleRestorePurchases() }
        } label: {
            HStack(spacing: 8) {
                if isRestoringPurchases {
                    ProgressView()
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                Text(L10n.tr("Khôi phục giao dịch"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(KinnectTheme.accentBright)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(KinnectTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(KinnectTheme.borderSoft, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isRestoringPurchases || storeKit.isPurchasing)
    }

    private func handleRestorePurchases() async {
        guard !isRestoringPurchases else { return }
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }
        do {
            let outcome = try await storeKit.restorePurchases()
            await loadWalletData()
            appState.showToast(
                outcome.failed.isEmpty
                    ? "Đã kiểm tra và khôi phục các giao dịch hợp lệ."
                    : "Một số giao dịch chưa xác minh được. Vui lòng thử lại."
            )
        } catch {
            appState.showToast("Chưa khôi phục được giao dịch: \(error.localizedDescription)")
        }
    }

    private func topUpOptionCard(pack: StoreDigitalProduct) -> some View {
        let isSelected = selectedTopUpPackId == pack.id
        return Button {
            selectedTopUpPackId = pack.id
            appState.showToast("Đã chọn gói \(pack.coinsGranted.formattedWithSeparator()) xu · Cổng nạp trực tiếp đang kết nối.")
        } label: {
            VStack(spacing: 6) {
                Text("\(pack.coinsGranted.formattedWithSeparator()) xu")
                    .font(.headline.bold())
                    .foregroundColor(isSelected ? .white : KinnectTheme.accentBright)
                Text(pack.priceLabel)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? .white : KinnectTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? AnyShapeStyle(KinnectTheme.primaryGradient) : AnyShapeStyle(KinnectTheme.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? KinnectTheme.accentBright : KinnectTheme.borderSoft, lineWidth: isSelected ? 2 : 1)
                    )
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

                        Text(isBalanceHidden
                             ? "••••"
                             : ((entry.currency == "vnd" || entry.creatorVnd > 0)
                                 ? "+\(entry.creatorVnd.formattedWithSeparator())đ"
                                 : (entry.direction == "credit" ? "+\(entry.amount.formattedWithSeparator()) xu" : "-\(entry.amount.formattedWithSeparator()) xu")))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(entry.direction == "credit" || entry.creatorVnd > 0 ? KinnectTheme.online : KinnectTheme.textPrimary)

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
                        detailRow(title: "Thời gian", value: Self.formatEntryTimestamp(entry.createdAt))
                        detailRow(title: "Loại tiền", value: entryCurrencyLabel(for: entry))
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
            .clipped()
        }
    }

    private func entryCurrencyLabel(for entry: WalletEntryItem) -> String {
        switch entry.currency.lowercased() {
        case "vnd":
            return "VNĐ (Thu nhập)"
        case "purchased":
            return "Xu mua"
        case "trial", "gifted":
            return "Xu tặng"
        default:
            return entry.creatorVnd > 0 ? "VNĐ (Thu nhập)" : currencyLabel
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
        GiftInventoryItem.emoji(for: id)
    }

    private static let entryIsoParserWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let entryIsoParserPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let entryDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "dd/MM · HH:mm"
        return f
    }()

    private static func formatEntryTimestamp(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Gần đây" }
        if let date = entryIsoParserWithFractional.date(from: trimmed) ?? entryIsoParserPlain.date(from: trimmed) {
            return entryDisplayFormatter.string(from: date)
        }
        return trimmed
    }

    private static func parseMergedGiftInventory(_ rawList: [[String: Any]]) -> [GiftInventoryItem] {
        var totals: [String: Int] = [:]
        var orderedIds: [String] = []
        for item in rawList {
            guard let id = item["giftId"] as? String, let count = item["quantity"] as? Int, count > 0 else { continue }
            if totals[id] == nil {
                orderedIds.append(id)
            }
            totals[id, default: 0] += count
        }
        return orderedIds.compactMap { id in
            guard let qty = totals[id], qty > 0 else { return nil }
            return GiftInventoryItem(giftId: id, quantity: qty)
        }
    }

    // MARK: - API Calls
    private func applyWalletResponse(_ walletData: [String: Any]) {
        purchasedCoins = (walletData["purchasedCoins"] as? Int) ?? (walletData["purchasedCoins"] as? NSNumber)?.intValue ?? 0
        giftedCoins = (walletData["giftedCoins"] as? Int) ?? (walletData["trialCoins"] as? Int) ?? (walletData["trialCoins"] as? NSNumber)?.intValue ?? 0
        availableBalance = (walletData["totalUsableCoins"] as? Int) ?? (purchasedCoins + giftedCoins)
        earnedBalance = (walletData["earningsVnd"] as? Int) ?? (walletData["earningsVnd"] as? NSNumber)?.intValue ?? 0
        spentBalance = (walletData["spentCoins"] as? Int) ?? (walletData["spentCoins"] as? NSNumber)?.intValue ?? 0
        vndPerCoin = max(1, (walletData["vndPerCoin"] as? Int) ?? (walletData["vndPerCoin"] as? NSNumber)?.intValue ?? 100)
        withdrawableVnd = (walletData["withdrawableVnd"] as? Int) ?? (walletData["withdrawableVnd"] as? NSNumber)?.intValue ?? earnedBalance
        giftedGiftValueCoins = (walletData["giftedGiftValueCoins"] as? Int) ?? (walletData["giftedGiftValueCoins"] as? NSNumber)?.intValue ?? 0
        currencyLabel = "Xu Kinnect"
        topUpEnabled = (walletData["topUpEnabled"] as? Bool) == true
        coinPacks = topUpEnabled
            ? (walletData["coinPacks"] as? [[String: Any]] ?? []).map(StoreDigitalProduct.from)
            : []
        entries = (walletData["entries"] as? [[String: Any]] ?? []).map(WalletEntryItem.from)
    }

    private func loadWalletData() async {
        var hydrated = !entries.isEmpty || availableBalance > 0
        if let cachedRes = KinnectAPIClient.shared.cachedJSON(for: "/api/wallet") {
            let walletData = cachedRes["wallet"] as? [String: Any] ?? cachedRes
            applyWalletResponse(walletData)
            hydrated = true
        }
        if giftInventory.isEmpty, let cachedStore = KinnectAPIClient.shared.cachedJSON(for: "/api/store") {
            applyStorePayloadToWallet(cachedStore)
        }
        isLoading = !hydrated
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/wallet")
            let walletData = res["wallet"] as? [String: Any] ?? res
            applyWalletResponse(walletData)
            loadError = nil
            let storeData = try await KinnectAPIClient.shared.requestJSON("/api/store")
            applyStorePayloadToWallet(storeData)
            await storeKit.loadProducts(productIds: digitalProducts.map(\.id).filter { !$0.isEmpty })
        } catch {
            if !hydrated {
                loadError = "Chưa tải được dữ liệu ví: \(error.localizedDescription)"
            }
        }
    }

    private func applyStorePayloadToWallet(_ storeData: [String: Any]) {
        storeAccountUuid = storeData["accountUuid"] as? String
        appleBillingReady = (storeData["appleBillingReady"] as? Bool) == true
        giftInventory = Self.parseMergedGiftInventory(storeData["giftInventory"] as? [[String: Any]] ?? [])
        let isStudioProPermanent = (storeData["studioProPermanent"] as? Bool) == true
        var directOwned = Set(storeData["owned"] as? [String] ?? [])
        if isStudioProPermanent {
            directOwned.insert("kinnect_studio_pro")
        } else {
            directOwned.remove("kinnect_studio_pro")
        }
        ownedDigitalIds = directOwned
        let appearance = (storeData["appearance"] as? String) ?? (storeData["activeStyle"] as? String) ?? ""
        activeAppearance = appearance
        digitalProducts = (storeData["products"] as? [[String: Any]] ?? []).map { dict in
            var item = StoreDigitalProduct.from(dict)
            item.owned = (item.id == "kinnect_studio_pro") ? isStudioProPermanent : directOwned.contains(item.id)
            item.equipped = !item.id.isEmpty && item.kind == "style" && item.id == appearance
            return item
        }
    }
}
