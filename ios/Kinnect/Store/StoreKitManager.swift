import Foundation
import StoreKit

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    @Published private(set) var storeKitProducts: [String: Product] = [:]
    @Published private(set) var isPurchasing: Bool = false
    @Published var statusMessage: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                if case .verified(let transaction) = result {
                    do {
                        _ = try await self.verifyWithBackendAndFinish(result: result, transaction: transaction)
                        NotificationCenter.default.post(name: .kinnectStoreUpdated, object: transaction.productID)
                    } catch {
                        print("[KinnectStoreKit] Deferred transaction update verification: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts(productIds: [String]) async {
        let unique = Array(Set(productIds.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return }
        do {
            let products = try await Product.products(for: unique)
            for product in products {
                self.storeKitProducts[product.id] = product
            }
        } catch {
            print("[KinnectStoreKit] Failed to fetch App Store products: \(error.localizedDescription)")
        }
    }

    /// Restores non-consumable and auto-renewable subscriptions through App Store sync.
    /// Note: Consumable coin balances are managed directly on the Kinnect account server.
    struct RestoreOutcome {
        var reconciled: [String] = []      // server accepted and recorded entitlement
        var revoked: [String] = []         // refunded/revoked by Apple: not re-granted
        var failed: [String] = []          // server rejected or unreachable
        var unverified = 0                 // StoreKit signature invalid
        var isEmpty: Bool { reconciled.isEmpty && revoked.isEmpty && failed.isEmpty && unverified == 0 }
    }

    /// Restores non-consumable / auto-renewable entitlements:
    /// 1) AppStore.sync() (may prompt Apple ID; throws on user cancel),
    /// 2) iterate Transaction.currentEntitlements, skip revoked (refund) transactions,
    /// 3) send each verified transaction to the Kinnect server and count the real server result.
    /// Consumable coins are never restorable through StoreKit; their balance lives on the account server.
    func restorePurchases() async throws -> RestoreOutcome {
        try await AppStore.sync()
        var outcome = RestoreOutcome()
        var handledIds = Set<UInt64>()
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { outcome.unverified += 1; continue }
            handledIds.insert(transaction.id)
            if transaction.revocationDate != nil {
                do {
                    _ = try await verifyWithBackendAndFinish(result: entitlement, transaction: transaction)
                    outcome.revoked.append(transaction.productID)
                } catch {
                    outcome.failed.append(transaction.productID)
                }
                continue
            }
            do {
                let response = try await verifyWithBackendAndFinish(result: entitlement, transaction: transaction)
                if (response["state"] as? String) == "CANCELLED" {
                    outcome.revoked.append(transaction.productID)
                } else {
                    outcome.reconciled.append(transaction.productID)
                }
            } catch {
                outcome.failed.append(transaction.productID)
            }
        }
        // Also submit revoked non-consumable transactions excluded from currentEntitlements so backend reconciles refunds.
        for await result in Transaction.all {
            guard case .verified(let transaction) = result else { continue }
            guard !handledIds.contains(transaction.id),
                  transaction.revocationDate != nil else { continue }
            handledIds.insert(transaction.id)
            do {
                _ = try await verifyWithBackendAndFinish(result: result, transaction: transaction)
                outcome.revoked.append(transaction.productID)
            } catch {
                outcome.failed.append(transaction.productID)
            }
        }
        NotificationCenter.default.post(name: .kinnectStoreUpdated, object: nil)
        return outcome
    }

    /// Initiates a real StoreKit 2 purchase and verifies the signed transaction on the Kinnect server.
    /// Binds deterministic appAccountToken UUID to ensure account ownership integrity.
    /// Never mocks or fabricates purchase success when StoreKit products are unavailable.
    /// Returns `nil` quietly when the user cancels the App Store purchase sheet.
    func purchaseDigitalProduct(productId: String, accountUuid: String?) async throws -> [String: Any]? {
        let parsed = accountUuid.flatMap(UUID.init(uuidString:))
        return try await purchaseDigitalProduct(productId: productId, accountUuid: parsed)
    }

    func purchaseDigitalProduct(productId: String, accountUuid: UUID? = nil) async throws -> [String: Any]? {
        if storeKitProducts[productId] == nil {
            await loadProducts(productIds: [productId])
        }

        guard let product = storeKitProducts[productId] else {
            throw KinnectAPIError.serverMessage(
                "Gói dịch vụ hiện chưa sẵn sàng trên App Store. Vui lòng thử lại sau."
            )
        }

        isPurchasing = true
        defer { isPurchasing = false }

        let state = try await KinnectAPIClient.shared.requestJSON("/api/store")
        let resolvedAccount = (state["accountUuid"] as? String).flatMap(UUID.init(uuidString:)) ?? accountUuid
        guard state["appleBillingReady"] as? Bool == true,
              let serverAccount = resolvedAccount else {
            throw KinnectAPIError.serverMessage("App Store chưa mở thanh toán cho tài khoản này.")
        }
        // Always bind purchases to the server's authenticated account, including callers without a UUID.
        let options: Set<Product.PurchaseOption> = [.appAccountToken(serverAccount)]

        let purchaseResult = try await product.purchase(options: options)
        switch purchaseResult {
        case .success(let verificationResult):
            switch verificationResult {
            case .verified(let transaction):
                return try await verifyWithBackendAndFinish(result: verificationResult, transaction: transaction)
            case .unverified(_, let verificationError):
                throw KinnectAPIError.serverMessage("Chữ ký giao dịch StoreKit không hợp lệ: \(verificationError.localizedDescription)")
            }
        case .userCancelled:
            return nil
        case .pending:
            throw KinnectAPIError.serverMessage("Giao dịch đang chờ phê duyệt từ App Store.")
        @unknown default:
            throw KinnectAPIError.serverMessage("Trạng thái giao dịch App Store không xác định.")
        }
    }

    private func verifyWithBackendAndFinish(
        result: VerificationResult<Transaction>,
        transaction: Transaction
    ) async throws -> [String: Any] {
        let jws = result.jwsRepresentation
        guard !jws.isEmpty else {
            throw KinnectAPIError.serverMessage("Thiếu chữ ký giao dịch Apple.")
        }
        let token = jws
        let requestId = "storekit_\(transaction.id)"

        let response = try await KinnectAPIClient.shared.requestJSON(
            "/api/store/verify",
            method: "POST",
            body: [
                "productId": transaction.productID,
                "purchaseToken": token,
                "transactionId": String(transaction.id),
                "platform": "ios",
                "requestId": requestId
            ],
            requestId: requestId
        )

        guard let state = response["state"] as? String, ["PURCHASED", "CANCELLED"].contains(state) else {
            throw KinnectAPIError.serverMessage("Máy chủ chưa xác nhận giao dịch Apple.")
        }
        await transaction.finish()
        return response
    }
}

