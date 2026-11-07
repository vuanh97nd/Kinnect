import SwiftUI

struct WalletStoreView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var storeKit = StoreKitManager.shared

    enum SectionTab: String, CaseIterable {
        case wallet = "Ví của tôi"
        case packages = "Gói trang trí"
        case storeKit = "Nạp hàng số (StoreKit 2)"
    }

    @State private var tab: SectionTab = .wallet
    @State private var availableBalance: Int = 0
    @State private var earnedBalance: Int = 0
    @State private var spentBalance: Int = 0
    @State private var currencyLabel: String = "Xu thử nghiệm"
    @State private var entries: [WalletEntryItem] = []
    @State private var packages: [StorePackageItem] = []
    @State private var digitalProducts: [StoreDigitalProduct] = []
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
                    // Balance Hero Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Số dư khả dụng", systemImage: "creditcard.and.123")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Text(currencyLabel)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.2)))
                                .foregroundColor(.white)
                        }

                        Text("\(availableBalance) xu")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(.white)

                        HStack(spacing: 16) {
                            Text("Đã nhận: +\(earnedBalance)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                            Text("Đã dùng: -\(spentBalance)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(KinnectTheme.primaryGradient)
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
                                        Image(systemName: "sparkles")
                                            .foregroundColor(.white)
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
                                    Text("\(pkg.priceCoins) xu")
                                        .font(.caption.bold())
                                        .foregroundColor(KinnectTheme.warning)
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
                            Text("Mua hàng số qua Apple StoreKit 2")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Mọi giao dịch hàng số đều thông qua StoreKit 2 chính thức và xác minh chữ ký JWS trực tiếp tại máy chủ `/api/store/verify` (không bao giờ giả lập mua thành công).")
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .kinnectMultiline()
                        }

                        ForEach(digitalProducts) { prod in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(prod.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                        .kinnectMultiline()
                                    Text(prod.description)
                                        .font(.caption)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                        .kinnectMultiline()
                                    Text("Mã StoreKit: \(prod.id)")
                                        .font(.caption2)
                                        .foregroundColor(KinnectTheme.accentBright)
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
                    }
                }
                .padding(14)
            }
            .refreshable {
                await loadWalletAndStore()
            }
        }
        .background(KinnectTheme.background)
        .navigationTitle("Ví & Cửa hàng")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Đóng") { dismiss() }
            }
        }
        .task {
            await loadWalletAndStore()
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
                self.currencyLabel = wallet["currencyLabel"] as? String ?? "Xu thử nghiệm"
            }
            let rawEntries = wRes["entries"] as? [[String: Any]] ?? []
            self.entries = rawEntries.map(WalletEntryItem.from)
        }

        if let sRes = try? await sTask {
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
            _ = try await storeKit.purchaseDigitalProduct(productId: prod.id)
            appState.showToast("Xác minh giao dịch StoreKit thành công!")
            await loadWalletAndStore()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

