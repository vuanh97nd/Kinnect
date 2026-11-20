import PhotosUI
import SwiftUI
import UIKit

// MARK: - Dedicated Edit Profile Sheet (100% Android & Web Parity)
struct EditProfileSheet: View {
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    // Basic Info
    @State private var name = ""
    @State private var birthDate = ""
    @State private var birthDateValue = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var showDatePicker = false

    // About & Interests
    @State private var bio = ""
    @State private var selectedInterests: [String] = []

    // Identity
    @State private var gender = ""
    @State private var height = ""
    @State private var weight = ""
    @State private var orientation = ""
    @State private var communityRole = ""
    @State private var pronouns = ""

    // Connection & Life
    @State private var relationshipRole = ""
    @State private var selectedLookingFor: [String] = []
    @State private var city = ""
    @State private var occupation = ""
    @State private var school = ""
    @State private var isPrivate = false

    // Field-level Public/Private Visibility (Globe 🌐 vs Lock 🔒)
    @State private var visibility: [String: Bool] = [:]

    // Media & State
    @State private var isSaving = false
    @State private var isLoading = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedCoverItem: PhotosPickerItem?

    private let interestChoices = [
        "Nhiếp ảnh", "Du lịch", "Âm nhạc", "Đọc sách",
        "Thể thao", "Ẩm thực", "Phim ảnh", "Công nghệ",
        "Nghệ thuật", "Thiên nhiên", "Game", "Thú cưng"
    ]

    private let genderChoices = [
        "Nam", "Nữ", "Nam chuyển giới", "Nữ chuyển giới",
        "Phi nhị nguyên", "Linh hoạt giới", "Vô giới", "Đang tìm hiểu", "Khác"
    ]

    private let orientationChoices = [
        "Dị tính", "Gay / Đồng tính nam", "Lesbian / Đồng tính nữ",
        "Song tính / Bisexual", "Toàn tính / Pansexual", "Vô tính / Asexual",
        "Queer", "Á tính / Demisexual", "Đang tìm hiểu", "Khác"
    ]

    private let communityRoleChoices = [
        "Top", "Bottom", "Vers", "Vers Top", "Vers Bottom",
        "Side", "Femme", "Masc / Butch", "Androgynous", "Stem", "Đang tìm hiểu", "Khác"
    ]

    private let pronounChoices = ["Anh", "Chị", "Em", "Bạn", "Họ / They"]

    private let relationshipChoices = [
        "Độc thân", "Đang tìm hiểu", "Đang trong mối quan hệ", "Đã kết hôn", "Mối quan hệ mở"
    ]

    private let lookingForChoices = [
        "Kết bạn", "Trò chuyện", "Hẹn hò", "Mối quan hệ nghiêm túc", "Cùng sở thích"
    ]

    var body: some View {
        NavigationStack {
            Form {
                // 1. Photos Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                                HStack(spacing: 6) {
                                    KinnectIcon(glyph: .profile, size: 18, tint: KinnectTheme.accentBright)
                                    Text("Đổi Avatar")
                                        .font(.caption.bold())
                                }
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                                .foregroundColor(KinnectTheme.accentBright)
                            }
                            .onChange(of: selectedAvatarItem) { item in
                                guard let item else { return }
                                Task { await uploadImage(item: item, endpoint: "/api/me/avatar", field: "avatarDataUrl") }
                            }

                            PhotosPicker(selection: $selectedCoverItem, matching: .images) {
                                HStack(spacing: 6) {
                                    KinnectIcon(glyph: .photo, size: 18, tint: KinnectTheme.accentBright)
                                    Text("Đổi Ảnh bìa")
                                        .font(.caption.bold())
                                }
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                                .foregroundColor(KinnectTheme.accentBright)
                            }
                            .onChange(of: selectedCoverItem) { item in
                                guard let item else { return }
                                Task { await uploadImage(item: item, endpoint: "/api/me/cover", field: "coverDataUrl") }
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.accentBright)
                            Text("Chạm 🌐 / 🔒 để chọn thông tin công khai hoặc riêng tư.")
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                } header: {
                    Text("Hình ảnh đại diện")
                }

                // 2. Thông tin cơ bản
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tên hiển thị")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textSecondary)
                        TextField("Nhập tên hiển thị...", text: $name)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Ngày sinh")
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            visibilityToggle(key: "age", title: "Hiện tuổi")
                        }
                        Button {
                            showDatePicker.toggle()
                        } label: {
                            HStack {
                                Text(birthDate.isEmpty ? "Chọn ngày sinh (YYYY-MM-DD)" : birthDate)
                                    .foregroundColor(birthDate.isEmpty ? KinnectTheme.textSecondary : KinnectTheme.textPrimary)
                                Spacer()
                                Image(systemName: "calendar")
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                        .buttonStyle(.plain)

                        if showDatePicker {
                            DatePicker(
                                "Ngày sinh",
                                selection: $birthDateValue,
                                in: ...eighteenYearsAgo,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .onChange(of: birthDateValue) { newDate in
                                let formatter = DateFormatter()
                                formatter.dateFormat = "yyyy-MM-dd"
                                self.birthDate = formatter.string(from: newDate)
                            }
                        }
                        Text("Ngày sinh chỉ bạn xem; biểu tượng 🌐 cho phép hiện tuổi trên hồ sơ.")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                } header: {
                    Text("Thông tin cơ bản")
                }

                // 3. Giới thiệu và sở thích
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Giới thiệu bản thân (Bio)")
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            visibilityToggle(key: "bio", title: "Tiểu sử")
                        }
                        TextField("Chia sẻ vài dòng về bạn...", text: $bio, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Sở thích")
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            visibilityToggle(key: "interests", title: "Sở thích")
                        }
                        chipFlow(choices: interestChoices, selected: $selectedInterests, max: 10)
                    }
                } header: {
                    Text("Giới thiệu và sở thích")
                }

                // 4. Bản thân và cách xưng hô (Identity)
                Section {
                    pickerWithVisibility(title: "Bản dạng giới", key: "gender", selection: $gender, choices: genderChoices)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Chiều cao (cm)")
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.textSecondary)
                                Spacer()
                                visibilityToggle(key: "height", title: "Chiều cao")
                            }
                            TextField("175", text: $height)
                                .keyboardType(.numberPad)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Cân nặng (kg)")
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.textSecondary)
                                Spacer()
                                visibilityToggle(key: "weight", title: "Cân nặng")
                            }
                            TextField("68", text: $weight)
                                .keyboardType(.numberPad)
                        }
                    }

                    pickerWithVisibility(title: "Xu hướng tính dục", key: "orientation", selection: $orientation, choices: orientationChoices)
                    pickerWithVisibility(title: "Vai trò tự mô tả (tùy chọn)", key: "communityRole", selection: $communityRole, choices: communityRoleChoices)
                    pickerWithVisibility(title: "Cách xưng hô", key: "pronouns", selection: $pronouns, choices: pronounChoices)
                } header: {
                    Text("Bản thân và cách xưng hô")
                }

                // 5. Kết nối và cuộc sống
                Section {
                    pickerWithVisibility(title: "Tình trạng quan hệ", key: "relationshipRole", selection: $relationshipRole, choices: relationshipChoices)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Mong muốn kết nối")
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            visibilityToggle(key: "lookingFor", title: "Mong muốn")
                        }
                        chipFlow(choices: lookingForChoices, selected: $selectedLookingFor, max: 7)
                    }

                    textWithVisibility(title: "Nơi sống", key: "city", text: $city, placeholder: "Hà Nội, TP. Hồ Chí Minh...")
                    textWithVisibility(title: "Nghề nghiệp", key: "occupation", text: $occupation, placeholder: "Lập trình viên, Nhiếp ảnh gia...")
                    textWithVisibility(title: "Trường học", key: "school", text: $school, placeholder: "Đại học Bách Khoa...")

                    Toggle(isOn: $isPrivate) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chế độ tài khoản riêng tư")
                                .font(.subheadline.bold())
                            Text("Chỉ bạn bè mới xem được đầy đủ bài viết và album của bạn.")
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                    .tint(KinnectTheme.accentBright)
                } header: {
                    Text("Kết nối và cuộc sống")
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 36)
            }
            .navigationTitle("Chỉnh sửa hồ sơ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu thay đổi") {
                        Task { await saveProfile() }
                    }
                    .bold()
                    .disabled(isSaving)
                }
            }
            .task {
                await loadMyProfile()
            }
        }
    }

    private var eighteenYearsAgo: Date {
        Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    }

    @ViewBuilder
    private func visibilityToggle(key: String, title: String) -> some View {
        let isPublic = visibility[key] ?? true
        Button {
            visibility[key] = !isPublic
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isPublic ? "globe" : "lock.fill")
                    .font(.caption2)
                Text(isPublic ? "Công khai" : "Chỉ tôi")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(isPublic ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(KinnectTheme.surfaceElevated))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isPublic ? "Công khai" : "Ẩn") \(title)")
    }

    @ViewBuilder
    private func chipFlow(choices: [String], selected: Binding<[String]>, max: Int) -> some View {
        WrappingHStack(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(choices, id: \.self) { choice in
                let isSel = selected.wrappedValue.contains(choice)
                Button {
                    if isSel {
                        selected.wrappedValue.removeAll { $0 == choice }
                    } else {
                        if selected.wrappedValue.count < max {
                            selected.wrappedValue.append(choice)
                        } else {
                            appState.showToast("Tối đa \(max) lựa chọn.")
                        }
                    }
                } label: {
                    Text(choice)
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isSel ? KinnectTheme.accentBright : KinnectTheme.surfaceElevated)
                        )
                        .foregroundColor(isSel ? .white : KinnectTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func pickerWithVisibility(title: String, key: String, selection: Binding<String>, choices: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(KinnectTheme.textSecondary)
                Spacer()
                visibilityToggle(key: key, title: title)
            }
            Picker(title, selection: selection) {
                Text("Không muốn tiết lộ").tag("")
                ForEach(choices, id: \.self) { c in
                    Text(c).tag(c)
                }
            }
            .pickerStyle(.menu)
            .tint(KinnectTheme.accentBright)
        }
    }

    @ViewBuilder
    private func textWithVisibility(title: String, key: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(KinnectTheme.textSecondary)
                Spacer()
                visibilityToggle(key: key, title: title)
            }
            TextField(placeholder, text: text)
        }
    }

    private func loadMyProfile() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/me")
            if let me = res["user"] as? [String: Any] {
                self.name = me["name"] as? String ?? ""
                self.bio = me["bio"] as? String ?? ""
                self.birthDate = me["birthDate"] as? String ?? ""
                if !self.birthDate.isEmpty {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    if let d = formatter.date(from: self.birthDate) {
                        self.birthDateValue = d
                    }
                }
                if let ints = me["interests"] as? [String] {
                    self.selectedInterests = ints
                } else if let intStr = me["interests"] as? String {
                    self.selectedInterests = intStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                self.gender = me["gender"] as? String ?? ""
                if let h = me["height"] as? Int, h > 0 { self.height = "\(h)" }
                if let w = me["weight"] as? Int, w > 0 { self.weight = "\(w)" }
                self.orientation = me["orientation"] as? String ?? ""
                self.communityRole = me["communityRole"] as? String ?? ""
                self.pronouns = me["pronouns"] as? String ?? ""
                self.relationshipRole = me["relationshipRole"] as? String ?? ""
                if let lfs = me["lookingFor"] as? [String] {
                    self.selectedLookingFor = lfs
                } else if let lfStr = me["lookingFor"] as? String {
                    self.selectedLookingFor = lfStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                self.city = (me["city"] as? String) ?? (me["locationName"] as? String) ?? ""
                self.occupation = me["occupation"] as? String ?? ""
                self.school = me["school"] as? String ?? ""
                self.isPrivate = me["isPrivate"] as? Bool ?? false

                if let vis = me["profileVisibility"] as? [String: Bool] {
                    self.visibility = vis
                } else {
                    for k in ["bio", "age", "gender", "orientation", "communityRole", "pronouns", "relationshipRole", "lookingFor", "city", "interests", "height", "weight", "occupation", "school"] {
                        self.visibility[k] = true
                    }
                }
            }
        } catch {}
    }

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }
        let reqId = "patch_me_\(Int(Date().timeIntervalSince1970))"

        var payload: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "birthDate": birthDate.trimmingCharacters(in: .whitespacesAndNewlines),
            "bio": bio.trimmingCharacters(in: .whitespacesAndNewlines),
            "interests": selectedInterests,
            "gender": gender,
            "orientation": orientation,
            "communityRole": communityRole,
            "pronouns": pronouns,
            "relationshipRole": relationshipRole,
            "lookingFor": selectedLookingFor.joined(separator: ", "),
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines),
            "locationName": city.trimmingCharacters(in: .whitespacesAndNewlines),
            "occupation": occupation.trimmingCharacters(in: .whitespacesAndNewlines),
            "school": school.trimmingCharacters(in: .whitespacesAndNewlines),
            "identityPublic": true,
            "isPrivate": isPrivate,
            "profileVisibility": visibility
        ]

        if let h = Int(height.trimmingCharacters(in: .whitespacesAndNewlines)), h > 0 {
            payload["height"] = h
        } else {
            payload["height"] = NSNull()
        }
        if let w = Int(weight.trimmingCharacters(in: .whitespacesAndNewlines)), w > 0 {
            payload["weight"] = w
        } else {
            payload["weight"] = NSNull()
        }

        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/me",
                method: "PATCH",
                body: payload,
                requestId: reqId
            )
            if let userDict = res["user"] as? [String: Any] {
                appState.applyAuthenticatedUser(KinnectUser.from(userDict), rawDict: userDict)
            }
            appState.showToast("Đã cập nhật hồ sơ cá nhân hoàn chỉnh.")
            onSaved()
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func uploadImage(item: PhotosPickerItem, endpoint: String, field: String) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImg = UIImage(data: data),
              let jpeg = uiImg.jpegData(compressionQuality: 0.72) else {
            appState.showToast("Không thể xử lý ảnh đã chọn.")
            return
        }
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        let reqId = "upload_\(field)_\(Int(Date().timeIntervalSince1970))"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                endpoint,
                method: "POST",
                body: [field: dataURL],
                requestId: reqId
            )
            appState.showToast("Đã cập nhật hình ảnh hồ sơ.")
            onSaved()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}
