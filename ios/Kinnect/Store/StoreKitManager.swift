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
        updatesTask = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    _ = try? await verifyWithBackendAndFinish(result: result, transaction: transaction)
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
            var map: [String: Product] = [:]
            for product in products {
                map[product.id] = product
            }
            self.storeKitProducts = map
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
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { outcome.unverified += 1; continue }
            if transaction.revocationDate != nil { outcome.revoked.append(transaction.productID); continue }
            do {
                _ = try await verifyWithBackendAndFinish(result: entitlement, transaction: transaction)
                outcome.reconciled.append(transaction.productID)
            } catch {
                outcome.failed.append(transaction.productID)
            }
        }
        return outcome
    }

    /// Initiates a real StoreKit 2 purchase and verifies the signed transaction on the Kinnect server.
    /// Binds deterministic appAccountToken UUID to ensure account ownership integrity.
    /// Never mocks or fabricates purchase success when StoreKit products are unavailable.
    func purchaseDigitalProduct(productId: String, accountUuid: UUID? = nil) async throws -> [String: Any] {
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

        var options: Set<Product.PurchaseOption> = []
        if let accountUuid = accountUuid {
            options.insert(.appAccountToken(accountUuid))
        }

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
            throw KinnectAPIError.serverMessage("Bạn đã hủy giao dịch trên App Store.")
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
        let token = jws.isEmpty ? String(transaction.id) : jws
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

        await transaction.finish()
        return response
    }
}

