import SwiftUI
import UniformTypeIdentifiers

protocol AdminTransportProtocol {
    func requestJSON(_ path: String, method: String, body: [String: Any]?) async throws -> [String: Any]
}

struct LiveAdminTransport: AdminTransportProtocol {
    func requestJSON(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        try await KinnectAPIClient.shared.requestJSON(path, method: method, body: body)
    }
}

struct AdminEconomyDraft: Equatable {
    var version: Int
    var vndPerCoin: Int
    var signupBonusCoins: Int
    var signupBonusEnabled: Bool
    var trialPackagePurchases: Bool
    var trialGiftsEnabled: Bool
    var showCoinPacks: Bool
    var giftPrices: [String: Int]
    var coinPacks: [Int]

    static let requiredGiftIds: [String] = [
        "rose", "heart", "coffee", "love_gun", "fireworks", "star", "crown", "diamond",
        "car", "sports_car", "yacht", "castle", "aurora", "meteor", "butterfly", "lotus"
    ]

    static func parse(from response: [String: Any]) -> AdminEconomyDraft? {
        guard let version = (response["version"] as? NSNumber)?.intValue ?? (response["version"] as? Int),
              let config = response["config"] as? [String: Any],
              let pricesRaw = config["giftPrices"] as? [String: Any] else {
            return nil
        }
        var prices: [String: Int] = [:]
        for key in requiredGiftIds {
            guard let val = (pricesRaw[key] as? NSNumber)?.intValue ?? (pricesRaw[key] as? Int) else {
                return nil
            }
            prices[key] = val
        }
        let rawPacks = config["coinPacks"] as? [Any] ?? []
        let packs = rawPacks.compactMap { ($0 as? NSNumber)?.intValue ?? ($0 as? Int) }
        return AdminEconomyDraft(
            version: version,
            vndPerCoin: (config["vndPerCoin"] as? NSNumber)?.intValue ?? (config["vndPerCoin"] as? Int) ?? 100,
            signupBonusCoins: (config["signupBonusCoins"] as? NSNumber)?.intValue ?? (config["signupBonusCoins"] as? Int) ?? 2000,
            signupBonusEnabled: AdminActionsContract.flag(config["signupBonusEnabled"]),
            trialPackagePurchases: AdminActionsContract.flag(config["trialPackagePurchases"]),
            trialGiftsEnabled: AdminActionsContract.flag(config["trialGiftsEnabled"]),
            showCoinPacks: AdminActionsContract.flag(config["showCoinPacks"]),
            giftPrices: prices,
            coinPacks: packs
        )
    }

    func validate() -> String? {
        guard (1...100_000).contains(vndPerCoin),
              (0...1_000_000).contains(signupBonusCoins) else {
            return "Giá trị xu không hợp lệ."
        }
        guard giftPrices.count == Self.requiredGiftIds.count else {
            return "Thiếu giá quà."
        }
        for key in Self.requiredGiftIds {
            guard let price = giftPrices[key], (1...1_000_000).contains(price) else {
                return "Giá quà không hợp lệ (\(key))."
            }
        }
        guard (1...12).contains(coinPacks.count),
              Set(coinPacks).count == coinPacks.count,
              coinPacks.allSatisfy({ (1...1_000_000).contains($0) && Int64($0) * Int64(vndPerCoin) <= 100_000_000 }) else {
            return "Mệnh giá nạp không hợp lệ."
        }
        return nil
    }

    func patchPayload() -> [String: Any] {
        [
            "version": version,
            "config": [
                "vndPerCoin": vndPerCoin,
                "signupBonusEnabled": signupBonusEnabled,
                "trialPackagePurchases": trialPackagePurchases,
                "signupBonusCoins": signupBonusCoins,
                "trialGiftsEnabled": trialGiftsEnabled,
                "showCoinPacks": showCoinPacks,
                "giftPrices": giftPrices,
                "coinPacks": coinPacks
            ]
        ]
    }
}

struct AdminMusicUploadDraft: Equatable {
    var title: String = ""
    var artist: String = ""
    var license: String = ""
    var source: String = ""
    var rightsConfirmed: Bool = false
    var mimeType: String = "audio/mpeg"
    var audioData: Data = Data()

    static let allowedMimeTypes: Set<String> = [
        "audio/mpeg", "audio/mp3", "audio/mp4", "audio/x-m4a", "audio/aac"
    ]
    static let maxDecodedBytes = 15 * 1024 * 1024

    func clean(_ raw: String, limit: Int) -> String {
        let stripped = String(raw.unicodeScalars.filter { $0.value >= 0x20 })
        return String(stripped.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    func validate() -> String? {
        if clean(title, limit: 80).isEmpty || clean(artist, limit: 60).isEmpty || clean(license, limit: 80).isEmpty {
            return "Nhập tên bài, nghệ sĩ và giấy phép."
        }
        guard rightsConfirmed else {
            return "Cần xác nhận bạn có quyền dùng và chia sẻ bài này."
        }
        guard Self.allowedMimeTypes.contains(mimeType) else {
            return "Chỉ hỗ trợ MP3, M4A hoặc AAC."
        }
        guard !audioData.isEmpty, audioData.count <= Self.maxDecodedBytes else {
            return "File nhạc không hợp lệ hoặc vượt quá 15 MB."
        }
        return nil
    }

    func requestBody() -> [String: Any] {
        [
            "title": clean(title, limit: 80),
            "artist": clean(artist, limit: 60),
            "license": clean(license, limit: 80),
            "source": clean(source, limit: 300),
            "rights": rightsConfirmed,
            "data": "data:\(mimeType);base64,\(audioData.base64EncodedString())"
        ]
    }
}

struct AdminMusicItem: Identifiable, Equatable {
    let file: String
    let title: String
    let artist: String
    let license: String
    var id: String { file }

    static func isValidFilename(_ file: String) -> Bool {
        guard !file.isEmpty, !file.hasPrefix("."),
              !file.contains("/"), !file.contains("\\") else {
            return false
        }
        let lower = file.lowercased()
        return lower.hasSuffix(".mp3") || lower.hasSuffix(".m4a") || lower.hasSuffix(".aac")
    }
}

struct AdminAICredentialSummary: Equatable {
    let workerUrl: String
    let tokenSaved: Bool
    let nvidiaKeySaved: Bool
    let nvidiaModel: String
    let nvidiaVisionModel: String
    let fallbackEnabled: Bool
    let primaryProvider: String
    let fallbackReady: Bool

    static func parse(from response: [String: Any]) -> AdminAICredentialSummary? {
        let raw = (response["credentials"] as? [String: Any]) ?? response
        guard let workerUrl = raw["workerUrl"] as? String else { return nil }
        return AdminAICredentialSummary(
            workerUrl: workerUrl,
            tokenSaved: AdminActionsContract.flag(raw["tokenSaved"]),
            nvidiaKeySaved: AdminActionsContract.flag(raw["nvidiaKeySaved"]),
            nvidiaModel: raw["nvidiaModel"] as? String ?? "",
            nvidiaVisionModel: raw["nvidiaVisionModel"] as? String ?? "",
            fallbackEnabled: AdminActionsContract.flag(raw["fallbackEnabled"]),
            primaryProvider: raw["primaryProvider"] as? String ?? "cloudflare",
            fallbackReady: AdminActionsContract.flag(raw["fallbackReady"])
        )
    }
}

struct AdminAIConfigPatch: Equatable {
    var support: Bool?
    var moderation: Bool?
    var adminId: String?

    func requestBody() -> [String: Any] {
        var body: [String: Any] = [:]
        if let support { body["support"] = support }
        if let moderation { body["moderation"] = moderation }
        if let adminId, !adminId.isEmpty { body["adminId"] = adminId }
        return body
    }
}

struct AdminAICredentialsPatch {
    var password: String
    var workerUrl: String?
    var token: String?
    var nvidiaKey: String?
    var nvidiaModel: String?
    var nvidiaVisionModel: String?
    var fallbackEnabled: Bool?

    static let allowedWorkerHosts: Set<String> = [
        "kinnect-ai.vuanh97nd.workers.dev",
        "ai.kinnect.io.vn"
    ]

    func validate() -> String? {
        guard !password.isEmpty, password.count <= 128 else {
            return "Cần nhập mật khẩu quản trị hiện tại để xác thực."
        }
        if let workerUrl {
            guard let url = URL(string: workerUrl),
                  url.scheme == "https",
                  let host = url.host,
                  Self.allowedWorkerHosts.contains(host),
                  url.port == nil,
                  url.user == nil,
                  url.password == nil,
                  url.query == nil,
                  url.fragment == nil,
                  url.path.isEmpty || url.path == "/" else {
                return "URL Worker AI không nằm trong danh sách cho phép."
            }
        }
        for key in [token, nvidiaKey].compactMap({ $0 }) where !key.isEmpty {
            let hasWhitespace = key.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
            guard (32...512).contains(key.count), !hasWhitespace else {
                return "Khóa kết nối AI phải từ 32 đến 512 ký tự và không chứa khoảng trắng."
            }
        }
        return nil
    }

    /// Serializes only explicitly entered credentials; never persists keys to disk/UserDefaults.
    func requestBody() -> [String: Any] {
        var body: [String: Any] = ["password": password]
        if let workerUrl { body["workerUrl"] = workerUrl }
        if let token, !token.isEmpty { body["token"] = token }
        if let nvidiaKey, !nvidiaKey.isEmpty { body["nvidiaKey"] = nvidiaKey }
        if let nvidiaModel { body["nvidiaModel"] = nvidiaModel }
        if let nvidiaVisionModel { body["nvidiaVisionModel"] = nvidiaVisionModel }
        if let fallbackEnabled { body["fallbackEnabled"] = fallbackEnabled }
        return body
    }
}

enum AdminAITestProvider: String, CaseIterable {
    case cloudflare
    case nvidia
    case fallback
}

enum AdminActionsContract {
    static func flag(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.intValue == 1 }
        return false
    }

    static func saveEconomy(
        draft: AdminEconomyDraft,
        role: String,
        transport: AdminTransportProtocol = LiveAdminTransport()
    ) async throws -> AdminEconomyDraft {
        guard role == "admin" else {
            throw KinnectAPIError.serverError(status: 403, message: "Chỉ quản trị viên được cấu hình.")
        }
        if let errorText = draft.validate() {
            throw KinnectAPIError.serverError(status: 400, message: errorText)
        }
        let response = try await transport.requestJSON(
            "/api/admin/economy",
            method: "PATCH",
            body: draft.patchPayload()
        )
        guard let updated = AdminEconomyDraft.parse(from: response) else {
            throw KinnectAPIError.serverMessage("Phản hồi cấu hình kinh tế không hợp lệ.")
        }
        return updated
    }

    static func uploadMusic(
        draft: AdminMusicUploadDraft,
        role: String,
        transport: AdminTransportProtocol = LiveAdminTransport()
    ) async throws -> String {
        guard role == "admin" else {
            throw KinnectAPIError.serverError(status: 403, message: "Chỉ quản trị viên được quản lý thư viện nhạc.")
        }
        if let errorText = draft.validate() {
            throw KinnectAPIError.serverError(status: 400, message: errorText)
        }
        let response = try await transport.requestJSON(
            "/api/music",
            method: "POST",
            body: draft.requestBody()
        )
        return response["file"] as? String ?? ""
    }

    static func deleteMusic(
        file: String,
        role: String,
        transport: AdminTransportProtocol = LiveAdminTransport()
    ) async throws {
        guard role == "admin" else {
            throw KinnectAPIError.serverError(status: 403, message: "Chỉ quản trị viên được quản lý thư viện nhạc.")
        }
        guard AdminMusicItem.isValidFilename(file) else {
            throw KinnectAPIError.serverError(status: 400, message: "Tên file không hợp lệ.")
        }
        _ = try await transport.requestJSON(
            "/api/music",
            method: "DELETE",
            body: ["file": file]
        )
    }

    static func updateAISettings(
        patch: AdminAIConfigPatch,
        role: String,
        transport: AdminTransportProtocol = LiveAdminTransport()
    ) async throws -> [String: Any] {
        guard role == "admin" else {
            throw KinnectAPIError.serverError(status: 403, message: "Chỉ quản trị viên có quyền thực hiện.")
        }
        return try await transport.requestJSON(
            "/api/admin/ai",
            method: "PATCH",
            body: patch.requestBody()
        )
    }
}

struct AdminEconomyEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    let initialDraft: AdminEconomyDraft
    let onSaved: () -> Void

    @State private var draft: AdminEconomyDraft
    @State private var confirmSave = false
    @State private var saving = false
    @State private var conflictReloadRequired = false
    @State private var errorMessage = ""

    init(initialDraft: AdminEconomyDraft, onSaved: @escaping () -> Void) {
        self.initialDraft = initialDraft
        self.onSaved = onSaved
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Phiên bản & Tỷ lệ") {
                    Text("Phiên bản máy chủ: v\(draft.version)")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                    Toggle("Bật tặng quà trải nghiệm", isOn: $draft.trialGiftsEnabled)
                    Toggle("Cho phép mua gói trải nghiệm", isOn: $draft.trialPackagePurchases)
                    Toggle("Hiển thị gói xu", isOn: $draft.showCoinPacks)
                    Toggle("Thưởng xu khi đăng ký", isOn: $draft.signupBonusEnabled)
                    Stepper("Tỷ giá VNĐ / xu: \(draft.vndPerCoin)", value: $draft.vndPerCoin, in: 1...100_000, step: 10)
                    Stepper("Xu thưởng tân thủ: \(draft.signupBonusCoins)", value: $draft.signupBonusCoins, in: 0...1_000_000, step: 100)
                }

                Section("Giá quà Live (xu)") {
                    ForEach(AdminEconomyDraft.requiredGiftIds, id: \.self) { giftId in
                        let current = draft.giftPrices[giftId] ?? 50
                        Stepper(
                            "\(giftId): \(current) xu",
                            value: Binding(
                                get: { draft.giftPrices[giftId] ?? 50 },
                                set: { draft.giftPrices[giftId] = $0 }
                            ),
                            in: 1...1_000_000,
                            step: 10
                        )
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.danger)
                        if conflictReloadRequired {
                            Button("Tải lại từ máy chủ") {
                                Task { await reloadFromServer() }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cấu hình kinh tế")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Đang lưu..." : "Lưu") {
                        confirmSave = true
                    }
                    .disabled(saving)
                }
            }
            .confirmationDialog(
                "Lưu cấu hình kinh tế (v\(draft.version))?",
                isPresented: $confirmSave,
                titleVisibility: .visible
            ) {
                Button("Xác nhận lưu", role: .destructive) {
                    Task { await save() }
                }
                Button("Hủy", role: .cancel) {}
            }
        }
    }

    private func reloadFromServer() async {
        errorMessage = ""
        do {
            let res = try await LiveAdminTransport().requestJSON("/api/admin/economy")
            if let latest = AdminEconomyDraft.parse(from: res) {
                draft = latest
                conflictReloadRequired = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        errorMessage = ""
        saving = true
        defer { saving = false }
        let role = appState.currentUser?.accountRole ?? ""
        do {
            _ = try await AdminActionsContract.saveEconomy(draft: draft, role: role)
            appState.showToast("Đã cập nhật cấu hình kinh tế.")
            onSaved()
            dismiss()
        } catch let KinnectAPIError.serverError(status, message) {
            errorMessage = message
            if status == 409 {
                conflictReloadRequired = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AdminMusicManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    let tracks: [AdminMusicItem]
    let onChanged: () -> Void

    @State private var pendingDeleteFile: String?
    @State private var confirmDelete = false
    @State private var confirmUpload = false
    @State private var showAudioImporter = false
    @State private var pickedFileName = ""
    @State private var uploadDraft = AdminMusicUploadDraft()
    @State private var uploading = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            List {
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(KinnectTheme.danger)
                }

                Section("Tải nhạc lên thư viện chung") {
                    TextField("Tên bài nhạc", text: $uploadDraft.title)
                    TextField("Nghệ sĩ", text: $uploadDraft.artist)
                    TextField("Giấy phép (VD: CC BY / Royalty-Free)", text: $uploadDraft.license)
                    TextField("Nguồn (không bắt buộc)", text: $uploadDraft.source)
                    Toggle("Xác nhận tôi có quyền chia sẻ bài này", isOn: $uploadDraft.rightsConfirmed)
                    Button(pickedFileName.isEmpty ? "Chọn file MP3 / M4A / AAC" : "Đã chọn: \(pickedFileName)") {
                        showAudioImporter = true
                    }
                    Button(uploading ? "Đang tải lên..." : "Tải nhạc lên") {
                        confirmUpload = true
                    }
                    .disabled(uploading || uploadDraft.validate() != nil)
                }

                Section("Danh sách nhạc hiện có") {
                    if tracks.isEmpty {
                        Text("Chưa có bài nhạc trong thư viện.")
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        ForEach(tracks) { track in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(track.artist.isEmpty ? "Kinnect" : track.artist) · \(track.file)")
                                        .font(.caption)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                }
                                Spacer()
                                Button("Xóa", role: .destructive) {
                                    pendingDeleteFile = track.file
                                    confirmDelete = true
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Quản lý thư viện nhạc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio]) { result in
                loadPickedAudio(result)
            }
            .confirmationDialog(
                "Tải bài nhạc lên thư viện chung?",
                isPresented: $confirmUpload,
                titleVisibility: .visible
            ) {
                Button("Xác nhận tải lên") {
                    Task { await uploadTrack() }
                }
                Button("Hủy", role: .cancel) {}
            }
            .confirmationDialog(
                "Xóa bài nhạc khỏi thư viện chung?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Xóa bài nhạc", role: .destructive) {
                    if let file = pendingDeleteFile {
                        Task { await deleteTrack(file) }
                    }
                }
                Button("Hủy", role: .cancel) { pendingDeleteFile = nil }
            }
        }
    }

    private func loadPickedAudio(_ result: Result<URL, Error>) {
        errorMessage = ""
        guard case let .success(url) = result else {
            errorMessage = "Không thể mở file âm thanh."
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty, data.count <= AdminMusicUploadDraft.maxDecodedBytes else {
                errorMessage = "File nhạc trống hoặc vượt quá 15 MB."
                return
            }
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "m4a":
                uploadDraft.mimeType = "audio/x-m4a"
            case "aac":
                uploadDraft.mimeType = "audio/aac"
            case "mp4":
                uploadDraft.mimeType = "audio/mp4"
            default:
                uploadDraft.mimeType = "audio/mpeg"
            }
            uploadDraft.audioData = data
            pickedFileName = url.lastPathComponent
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadTrack() async {
        errorMessage = ""
        uploading = true
        defer { uploading = false }
        let role = appState.currentUser?.accountRole ?? ""
        do {
            _ = try await AdminActionsContract.uploadMusic(draft: uploadDraft, role: role)
            appState.showToast("Đã tải bài nhạc lên thư viện.")
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTrack(_ file: String) async {
        errorMessage = ""
        let role = appState.currentUser?.accountRole ?? ""
        do {
            try await AdminActionsContract.deleteMusic(file: file, role: role)
            appState.showToast("Đã xóa bài nhạc.")
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AdminAISettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let summary: AdminAICredentialSummary
    let supportEnabled: Bool
    let moderationEnabled: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Trạng thái kết nối (không hiển thị khóa)") {
                    LabeledContent("Worker URL", value: summary.workerUrl)
                    LabeledContent("Token Cloudflare", value: summary.tokenSaved ? "Đã lưu" : "Chưa có")
                    LabeledContent("Khóa NVIDIA", value: summary.nvidiaKeySaved ? "Đã lưu" : "Chưa có")
                    LabeledContent("Model NVIDIA", value: summary.nvidiaModel.isEmpty ? "Chưa đặt" : summary.nvidiaModel)
                    LabeledContent("Fallback", value: summary.fallbackEnabled ? "Đang bật" : "Đang tắt")
                }

                Section("Tính năng AI") {
                    LabeledContent("Hỗ trợ tự động", value: supportEnabled ? "Bật" : "Tắt")
                    LabeledContent("Kiểm duyệt nội dung", value: moderationEnabled ? "Bật" : "Tắt")
                }

                Section {
                    Text("Cập nhật khóa API (`PATCH /api/admin/ai/credentials`) yêu cầu nhập lại mật khẩu quản trị và không lưu khóa trên thiết bị.")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
            }
            .navigationTitle("Trạng thái & Bảo mật AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}

