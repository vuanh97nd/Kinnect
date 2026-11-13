import SwiftUI

struct AdminOperationsSnapshot {
    let users: Int
    let suspended: Int
    let pendingResets: Int
    let openReports: Int
}

struct AdminResetRequest: Identifiable {
    let id: String
    let username: String
    let userId: String?
    let contact: String
    let note: String
    let status: String
    let created: Date?
}

struct AdminActivityEntry: Identifiable {
    let id: String
    let action: String
    let target: String
    let actor: String
    let created: Date?
}

enum AdminResetOperation: String {
    case reset, dismiss
}

struct AdminResetOutcome {
    let username: String?
    let temporaryPassword: String?
}

enum AdminOperationsContract {
    private static func authorize(_ role: String) throws {
        guard role == "admin" else {
            throw KinnectAPIError.serverError(status: 403, message: "Chỉ quản trị viên được thực hiện.")
        }
    }

    private static func date(_ raw: Any?) -> Date? {
        guard let number = raw as? NSNumber, number.doubleValue.isFinite, number.doubleValue > 0 else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue / 1000)
    }

    static func overview(role: String, transport: AdminTransportProtocol = LiveAdminTransport()) async throws -> AdminOperationsSnapshot {
        try authorize(role)
        let data = try await transport.requestJSON("/api/admin/overview", method: "GET", body: nil)
        let keys = ["users", "suspended", "pendingResets", "openReports"]
        let counts = keys.compactMap { data[$0] as? Int }
        guard counts.count == keys.count, counts.allSatisfy({ $0 >= 0 }) else {
            throw KinnectAPIError.serverMessage("Không đọc được tổng quan quản trị.")
        }
        return AdminOperationsSnapshot(users: counts[0], suspended: counts[1], pendingResets: counts[2], openReports: counts[3])
    }

    static func requests(role: String, transport: AdminTransportProtocol = LiveAdminTransport()) async throws -> [AdminResetRequest] {
        try authorize(role)
        let data = try await transport.requestJSON("/api/admin/password-resets", method: "GET", body: nil)
        guard let rows = data["requests"] as? [[String: Any]] else {
            throw KinnectAPIError.serverMessage("Không đọc được yêu cầu khôi phục.")
        }
        return try rows.map { row in
            guard let id = row["id"] as? String, UUID(uuidString: id) != nil,
                  let username = row["username"] as? String, !username.isEmpty,
                  let status = row["status"] as? String, ["open", "done", "dismissed"].contains(status) else {
                throw KinnectAPIError.serverMessage("Yêu cầu khôi phục có dữ liệu không hợp lệ.")
            }
            return AdminResetRequest(id: id, username: username, userId: row["user_id"] as? String,
                contact: row["contact"] as? String ?? "", note: row["note"] as? String ?? "",
                status: status, created: date(row["created"]))
        }
    }

    static func activity(role: String, transport: AdminTransportProtocol = LiveAdminTransport()) async throws -> [AdminActivityEntry] {
        try authorize(role)
        let data = try await transport.requestJSON("/api/admin/activity", method: "GET", body: nil)
        guard let rows = data["entries"] as? [[String: Any]] else {
            throw KinnectAPIError.serverMessage("Không đọc được lịch sử quản trị.")
        }
        return try rows.map { row in
            guard let id = row["id"] as? String, !id.isEmpty, let action = row["action"] as? String else {
                throw KinnectAPIError.serverMessage("Lịch sử quản trị có dữ liệu không hợp lệ.")
            }
            let kind = action.split(separator: ":", maxSplits: 1).first.map(String.init) ?? action
            let labels = ["reset-password": "Khôi phục mật khẩu", "dismiss-password-request": "Bỏ qua yêu cầu khôi phục",
                "suspend-user": "Đình chỉ tài khoản", "restore-user": "Khôi phục tài khoản", "close-report": "Đóng báo cáo",
                "hide-post": "Ẩn bài viết", "show-post": "Hiện bài viết", "hide-short": "Ẩn video", "show-short": "Hiện video"]
            return AdminActivityEntry(id: id, action: labels[kind] ?? kind,
                target: row["username"] as? String ?? row["target"] as? String ?? "",
                actor: row["actorUsername"] as? String ?? "", created: date(row["created"]))
        }
    }

    static func handle(_ request: AdminResetRequest, operation: AdminResetOperation, role: String,
                       transport: AdminTransportProtocol = LiveAdminTransport()) async throws -> AdminResetOutcome {
        try authorize(role)
        guard request.status == "open", UUID(uuidString: request.id) != nil,
              operation != .reset || request.userId?.isEmpty == false else {
            throw KinnectAPIError.serverMessage("Yêu cầu không còn ở trạng thái có thể xử lý. Hãy tải lại danh sách.")
        }
        let data = try await transport.requestJSON("/api/admin/password-resets/\(request.id.lowercased())/\(operation.rawValue)",
            method: "POST", body: [:])
        guard AdminActionsContract.flag(data["ok"]) else {
            throw KinnectAPIError.serverMessage("Máy chủ chưa xác nhận thao tác. Hãy tải lại danh sách trước khi thử lại.")
        }
        if operation == .reset {
            guard let username = data["username"] as? String, username == request.username,
                  let password = data["temporaryPassword"] as? String, !password.isEmpty else {
                throw KinnectAPIError.serverMessage("Không nhận được mật khẩu tạm hợp lệ. Hãy kiểm tra lại tài khoản trước khi thao tác tiếp.")
            }
            return AdminResetOutcome(username: username, temporaryPassword: password)
        }
        return AdminResetOutcome(username: nil, temporaryPassword: nil)
    }

    static func canPresentTemporarySecret(
        initiatedAccountId: String,
        currentAccountId: String,
        role: String,
        isAppActive: Bool
    ) -> Bool {
        !initiatedAccountId.isEmpty && initiatedAccountId == currentAccountId && role == "admin" && isAppActive
    }
}

private struct PendingAdminReset: Identifiable {
    let id = UUID()
    let request: AdminResetRequest
    let operation: AdminResetOperation
}

struct AdminOperationsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var overview: AdminOperationsSnapshot?
    @State private var requests: [AdminResetRequest] = []
    @State private var activity: [AdminActivityEntry] = []
    @State private var loading = false
    @State private var working = false
    @State private var error = ""
    @State private var message = ""
    @State private var pending: PendingAdminReset?
    @State private var showConfirmation = false
    @State private var temporaryPassword = ""
    @State private var temporaryUsername = ""
    @State private var showTemporaryPassword = false
    @State private var revealPassword = false

    private var role: String { appState.currentUser?.accountRole ?? "" }
    private var accountId: String { appState.currentUser?.id ?? "" }

    var body: some View {
        NavigationStack {
            Group {
                if role == "admin" {
                    List {
                        if loading { ProgressView("Đang tải...") }
                        if !error.isEmpty {
                            Section {
                                Text(error).foregroundColor(KinnectTheme.danger)
                                Button("Thử lại") { Task { await reload() } }.disabled(loading || working)
                            }
                        }
                        if !message.isEmpty { Text(message).foregroundColor(KinnectTheme.textSecondary) }
                        if let overview {
                            Section("Tổng quan") {
                                LabeledContent("Thành viên", value: "\(overview.users)")
                                LabeledContent("Đang đình chỉ", value: "\(overview.suspended)")
                                LabeledContent("Chờ khôi phục mật khẩu", value: "\(overview.pendingResets)")
                                LabeledContent("Báo cáo đang mở", value: "\(overview.openReports)")
                            }
                        }
                        Section("Khôi phục mật khẩu") {
                            if requests.isEmpty && !loading && error.isEmpty { Text("Chưa có yêu cầu.") }
                            ForEach(requests) { request in requestRow(request) }
                        }
                        Section("Lịch sử quản trị") {
                            if activity.isEmpty && !loading && error.isEmpty { Text("Chưa có hoạt động.") }
                            ForEach(activity) { entry in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.action).font(.headline)
                                    if !entry.target.isEmpty { Text(entry.target) }
                                    if !entry.actor.isEmpty { Text("Người thực hiện: \(entry.actor)").font(.caption) }
                                    if let date = entry.created { Text(date, style: .date).font(.caption).foregroundColor(KinnectTheme.textSecondary) }
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                    .disabled(working)
                    .refreshable { await reload() }
                } else {
                    Text("Chỉ quản trị viên được vào mục này.")
                }
            }
            .navigationTitle("Hoạt động quản trị")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { clearTemporary(); dismiss() }.disabled(working) } }
            .task { await reload() }
            .confirmationDialog("Xác nhận xử lý yêu cầu?", isPresented: $showConfirmation, titleVisibility: .visible) {
                if let pending {
                    Button(pending.operation == .reset ? "Đặt mật khẩu tạm" : "Bỏ qua yêu cầu", role: .destructive) {
                        Task { await handle(pending) }
                    }
                }
                Button("Hủy", role: .cancel) { pending = nil }
            } message: {
                if let pending {
                    Text(pending.operation == .reset
                        ? "Tài khoản: \(pending.request.username). Chỉ tiếp tục sau khi xác minh chủ tài khoản. Thao tác sẽ kết thúc các phiên đăng nhập hiện có."
                        : "Bỏ qua yêu cầu của \(pending.request.username)?")
                }
            }
            .sheet(isPresented: $showTemporaryPassword, onDismiss: clearTemporary) {
                NavigationStack {
                    Form {
                        Text("Tài khoản: \(temporaryUsername)")
                        Text("Chuyển mật khẩu tạm cho đúng chủ tài khoản qua kênh hỗ trợ đã xác minh. Mật khẩu không được lưu trên thiết bị.")
                            .font(.footnote)
                        Toggle("Hiện mật khẩu tạm", isOn: $revealPassword)
                        if revealPassword { Text(temporaryPassword).font(.body.monospaced()) }
                    }
                    .navigationTitle("Mật khẩu tạm")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Đóng") { clearTemporary() } } }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in clearTemporary() }
            .onChange(of: role) { next in
                if next != "admin" { clearTemporary(); overview = nil; requests = []; activity = []; pending = nil }
            }
            .onChange(of: accountId) { _ in
                clearTemporary(); overview = nil; requests = []; activity = []; pending = nil
            }
            .onDisappear { clearTemporary() }
        }
    }

    private func requestRow(_ request: AdminResetRequest) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(request.username).font(.headline)
            Text(request.status == "open" ? "Chờ xử lý" : request.status == "done" ? "Đã xử lý" : "Đã bỏ qua")
                .font(.caption).foregroundColor(KinnectTheme.textSecondary)
            if !request.contact.isEmpty { Text(request.contact) }
            if !request.note.isEmpty { Text(request.note).font(.footnote) }
            if let date = request.created { Text(date, style: .date).font(.caption) }
            if request.status == "open" {
                if request.userId?.isEmpty == false {
                    Button("Khôi phục mật khẩu", role: .destructive) { ask(request, .reset) }
                } else {
                    Text("Tên đăng nhập chưa khớp tài khoản.").font(.caption)
                }
                Button("Bỏ qua yêu cầu") { ask(request, .dismiss) }
            }
        }.padding(.vertical, 4)
    }

    private func ask(_ request: AdminResetRequest, _ operation: AdminResetOperation) {
        guard !working, !loading, role == "admin" else { return }
        pending = PendingAdminReset(request: request, operation: operation)
        showConfirmation = true
    }

    @MainActor private func reload() async {
        let activeAccountId = accountId
        guard !activeAccountId.isEmpty, role == "admin", !loading else { return }
        loading = true; error = ""
        defer { loading = false }
        do {
            let nextOverview = try await AdminOperationsContract.overview(role: role)
            let nextRequests = try await AdminOperationsContract.requests(role: role)
            let nextActivity = try await AdminOperationsContract.activity(role: role)
            guard accountId == activeAccountId, role == "admin" else { return }
            overview = nextOverview; requests = nextRequests; activity = nextActivity
        } catch {
            guard accountId == activeAccountId, role == "admin" else { return }
            // Clear stale data; do not present a failed request as an empty successful response.
            overview = nil; requests = []; activity = []
            self.error = error.localizedDescription
        }
    }

    @MainActor private func handle(_ action: PendingAdminReset) async {
        let activeAccountId = accountId
        guard !activeAccountId.isEmpty, role == "admin", !working, !loading else { return }
        working = true; error = ""; message = ""; pending = nil
        defer { working = false }
        do {
            let result = try await AdminOperationsContract.handle(action.request, operation: action.operation, role: role)
            guard accountId == activeAccountId, role == "admin" else {
                clearTemporary()
                return
            }
            if let password = result.temporaryPassword, let username = result.username,
               AdminOperationsContract.canPresentTemporarySecret(
                   initiatedAccountId: activeAccountId,
                   currentAccountId: accountId,
                   role: role,
                   isAppActive: UIApplication.shared.applicationState == .active
               ) {
                temporaryPassword = password; temporaryUsername = username; revealPassword = false
                showTemporaryPassword = true
            } else {
                clearTemporary()
            }
            message = action.operation == .reset ? "Đã đặt mật khẩu tạm." : "Đã bỏ qua yêu cầu."
            await reload()
        } catch {
            guard accountId == activeAccountId, role == "admin" else {
                clearTemporary()
                return
            }
            self.error = error.localizedDescription
        }
    }

    private func clearTemporary() {
        temporaryPassword = ""; temporaryUsername = ""; revealPassword = false; showTemporaryPassword = false
    }
}
