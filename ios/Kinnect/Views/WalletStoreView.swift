import SwiftUI

struct WalletStoreView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var storeKit = StoreKitManager.shared

    enum SectionTab: String, CaseIterable {
        case wallet = "Ví của tôi"
        case packages = "Gói trang trí"
        case storeKit = "Nạp xu"
    }

    @State private var tab: SectionTab = .wallet
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
        VStack(spacing: 12) {
            Picker("Ví & Cửa hàng", selection: $tab) {
                ForEach(SectionTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Balance Hero Card (Strict Parity with Android 1.2.12 CoinBalanceCard)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text("Số dư")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color(red: 0.95, green: 0.93, blue: 1.0))
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
                            // Column 1: Xu mua (purchasedCoins)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    KinnectIcon(glyph: .coin, size: 18, selected: true, tint: .white)
                                    Text("Xu mua")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(Color(red: 0.95, green: 0.93, blue: 1.0))
                                }
                                .frame(minHeight: 28)

                                Text(isBalanceHidden ? "••••" : "\(purchasedCoins) xu")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .accessibilityLabel("Xu mua · \(purchasedCoins)")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // Vertical divider
                            Rectangle()
                                .fill(Color.white.opacity(0.35))
                                .frame(width: 1, height: 42)
                                .padding(.horizontal, 12)

                            // Column 2: Xu tặng (giftedCoins)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    KinnectIcon(glyph: .gift, size: 16, selected: true, tint: .white)
                                    Text("Xu tặng")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(Color(red: 0.95, green: 0.93, blue: 1.0))
                                }
                                .frame(minHeight: 28)

                                Text(isBalanceHidden ? "••••" : "\(giftedCoins) xu")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .accessibilityLabel("Xu tặng · \(giftedCoins)")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0x5D/255.0, green: 0x36/255.0, blue: 0xD6/255.0),
                                        Color(red: 0x96/255.0, green: 0x55/255.0, blue: 0xEC/255.0),
                                        Color(red: 0xD3/255.0, green: 0x5A/255.0, blue: 0xB6/255.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                    switch tab {
                    case .wallet:
                        Text("Lịch sử biến động số dư")
                            .font(.headline)
                            .foregroundColor(.white)

                        if entries.isEmpty && !isLoading {
                            Text("Chưa có giao dịch nào trong ví.")
                                .font(.subheadline)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .padding(.vertical, 24)
                        }

                        ForEach(entries) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                        .kinnectMultiline()
                                    if !entry.note.isEmpty {
                                        Text(entry.note)
                                            .font(.caption)
                                            .foregroundColor(KinnectTheme.textSecondary)
                                            .kinnectMultiline()
                                    }
                                    Text(formatRelativeDate(entry.createdAt))
                                        .font(.caption2)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                }
                                Spacer()
                                Text(entry.direction == "credit" ? "+\(entry.amount)" : "-\(entry.amount)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(entry.direction == "credit" ? KinnectTheme.online : KinnectTheme.warning)
                            }
                            .kinnectCard()
                        }

                    case .packages:
                        Text("Gói khung Avatar, Huy hiệu & Chủ đề")
                            .font(.headline)
                            .foregroundColor(.white)

                        ForEach(packages) { pkg in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: pkg.accentColor))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        KinnectIcon(glyph: .store, size: 22, selected: true, tint: .white)
                                    )

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(pkg.title)
                                            .font(.subheadline.bold())
                                            .foregroundColor(.white)
                                            .kinnectMultiline()
                                        if !pkg.badgeText.isEmpty {
                                            Text(pkg.badgeText)
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color(hex: pkg.accentColor).opacity(0.3)))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    Text(pkg.subtitle)
                                        .font(.caption)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                        .kinnectMultiline()
                                    HStack(spacing: 4) {
                                        KinnectIcon(glyph: .coin, size: 16, selected: true, tint: KinnectTheme.warning)
                                        Text("\(pkg.priceCoins) xu")
                                            .font(.caption.bold())
                                            .foregroundColor(KinnectTheme.warning)
                                            .minimumScaleFactor(0.75)
                                    }
                                }

                                Spacer()

                                if pkg.owned {
                                    Button(pkg.equipped ? "Đang dùng" : "Trang bị") {
                                        Task { await applyPackage(pkg) }
                                    }
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(pkg.equipped ? KinnectTheme.surfaceElevated : KinnectTheme.online)
                                    )
                                    .foregroundColor(.white)
                                } else {
                                    Button("Đổi gói") {
                                        Task { await buyPackage(pkg) }
                                    }
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(KinnectTheme.primaryGradient))
                                    .foregroundColor(.white)
                                }
                            }
                            .kinnectCard()
                        }

                    case .storeKit:
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
                                        .kinnectMultiline()
                                    Text(prod.description)
                                        .font(.caption)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                        .kinnectMultiline()
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
                                        appState.showToast("Chưa khôi phục được \(r.failed.count + r.unverified) gói. Vui lòng thử lại sau hoặc liên hệ hỗ trợ.")
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

                        Text("Lưu ý: Tính năng khôi phục StoreKit áp dụng cho các gói dịch vụ cố định và mẫu giao diện đã mua. Số dư xu Kinnect (vật phẩm tiêu hao) được lưu trữ an toàn trên máy chủ tài khoản Kinnect và tự động hiển thị lại khi bạn đăng nhập.")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .padding(.top, 2)
                    }
                }
                .padding(14)
            }
            .refreshable {
                await loadWalletAndStore()
            }
        }
        .background(KinnectTheme.background)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadWalletAndStore()
        }
        .onAppear {
            if UIReviewFixture.activeScreen == "wallet-topup" {
                tab = .storeKit
            } else if UIReviewFixture.activeScreen == "wallet-packages" {
                tab = .packages
            }
        }
    }

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
            self.packages = rawPkgs.map(StorePackageItem.from)
            let rawProds = sRes["products"] as? [[String: Any]] ?? []
            self.digitalProducts = rawProds.map(StoreDigitalProduct.from)
            await storeKit.loadProducts(productIds: self.digitalProducts.map(\.id))
        }
    }

    private func buyPackage(_ pkg: StorePackageItem) async {
        // Explicit idempotency requestId so duplicate transactions never occur
        let reqId = "buy_pkg_\(pkg.id)_\(UUID().uuidString)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/store/packages/buy",
                method: "POST",
                body: [
                    "packageId": pkg.id,
                    "requestId": reqId
                ],
                requestId: reqId
            )
            appState.showToast("Đã đổi gói '\(pkg.title)' thành công!")
            await loadWalletAndStore()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func applyPackage(_ pkg: StorePackageItem) async {
        let reqId = "apply_pkg_\(pkg.id)_\(Int(Date().timeIntervalSince1970))"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/store/packages/apply",
                method: "POST",
                body: [
                    "packageId": pkg.id,
                    "slot": pkg.category,
                    "equip": !pkg.equipped
                ],
                requestId: reqId
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

