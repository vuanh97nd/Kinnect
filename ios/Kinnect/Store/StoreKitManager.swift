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

    /// Initiates a real StoreKit 2 purchase and verifies the signed transaction on the Kinnect server.
    /// Never mocks or fabricates purchase success when StoreKit products are unavailable.
    func purchaseDigitalProduct(productId: String) async throws -> [String: Any] {
        if storeKitProducts[productId] == nil {
            await loadProducts(productIds: [productId])
        }

        guard let product = storeKitProducts[productId] else {
            throw KinnectAPIError.serverMessage(
                "Sản phẩm '\(productId)' chưa được cấu hình trên App Store Connect hoặc bản cài thử chưa ký tài khoản Apple Developer trả phí. Không thể giả lập giao dịch StoreKit."
            )
        }

        isPurchasing = true
        defer { isPurchasing = false }

        let purchaseResult = try await product.purchase()
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

