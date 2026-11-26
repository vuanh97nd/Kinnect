import AVFoundation
import Foundation
import SwiftUI
import UIKit

/// Isolated UI review fixture mode activated ONLY in `#if DEBUG` builds
/// via `--ui-review-screen <name>` or `kinnect://ui-review?...`.
/// Compiled out completely in Release builds.
#if DEBUG
enum UIReviewFixture {
    /// Runtime overrides driven solely by `#if DEBUG` deep-link (`kinnect://ui-review?...`)
    /// so a single simulator session (such as run.cloud) can switch screens/themes/Dynamic Type live.
    static var overrideScreen: String? = nil
    static var overrideLightMode: Bool? = nil
    static var overrideMaxDynamicType: Bool? = nil

    static var activeScreen: String? {
        if let override = overrideScreen, !override.isEmpty {
            return override
        }
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--ui-review-screen"), idx + 1 < args.count {
            return args[idx + 1]
        }
        return nil
    }

    static var forceLightMode: Bool {
        if let override = overrideLightMode {
            return override
        }
        return CommandLine.arguments.contains("--ui-review-light")
    }

    static var forceMaxDynamicType: Bool {
        if let override = overrideMaxDynamicType {
            return override
        }
        return CommandLine.arguments.contains("--ui-review-dynamictype-max")
    }

    static var isEnabled: Bool {
        activeScreen != nil
    }

    /// Synchronizes AppState, WebRTC, Live, and Localization singletons before rendering a fixture screen
    /// so sequential deep-link switches in a single simulator session never leak transient state.
    @MainActor
    static func prepareRuntimeState(for screenName: String) {
        let appState = AppState.shared
        NativeWebRTCManager.shared.activeCall = nil
        appState.leaveCurrentLiveRoom()
        appState.liveRooms = []
        appState.activeReportContext = nil
        appState.pendingPrivacyConsent = nil
        appState.toastMessage = nil
        appState.isRestoringSession = false

        let targetLang: AppLanguage = screenName.hasSuffix("-en") ? .en : .vi
        if LocalizationManager.shared.currentLanguage != targetLang {
            LocalizationManager.shared.setLanguage(targetLang)
        }

        let isUnauthenticated =
            screenName == "splash"
            || screenName == "auth"
            || screenName.hasPrefix("auth-")
            || screenName == "forgot-password"

        if isUnauthenticated {
            appState.currentUser = nil
            appState.onlineUserIds = []
            appState.unreadNotificationsCount = 0
            appState.unreadMessagesCount = 0
            appState.pendingFriendRequestsCount = 0
        } else {
            appState.currentUser = KinnectUser.from(currentUserDict)
            appState.onlineUserIds = ["u2"]
            appState.unreadNotificationsCount = 1
            appState.unreadMessagesCount = 2
            appState.pendingFriendRequestsCount = 1
        }
    }

    /// Camera and microphone prompts belong only to capture, live, and call screens.
    /// Password, chat, and settings fixtures must not raise a system permission dialog.
    static var allowsCapturePrompt: Bool {
        guard isEnabled else { return true }
        let screen = activeScreen ?? ""
        if screen.hasPrefix("camera") || screen.hasPrefix("studio") { return true }
        if screen.hasPrefix("live") || screen.contains("call") { return true }
        return false
    }

    static let currentUserDict: [String: Any] = [
        "id": "u1",
        "name": "Nguyễn Minh Anh",
        "handle": "minhanh",
        "username": "minhanh",
        "email": "minhanh@kinnect.local",
        "bio": "Nhiếp ảnh đường phố · TP.HCM",
        "locationName": "Quận 1, TP. Hồ Chí Minh",
        "city": "TP. Hồ Chí Minh",
        "avatarColor": "#7C3AED",
        "age": 25,
        "height": 175,
        "weight": 68,
        "gender": "Nam",
        "orientation": "Gay / Đồng tính nam",
        "communityRole": "Vers",
        "pronouns": "Anh",
        "relationshipRole": "Đang tìm hiểu",
        "lookingFor": "Kết bạn, Trò chuyện",
        "occupation": "Thiết kế sản phẩm",
        "school": "Đại học Bách Khoa",
        "interests": ["Nhiếp ảnh", "Du lịch", "Công nghệ", "Âm nhạc"],
        "friendsCount": 128,
        "followersCount": 1420,
        "followingCount": 95,
        "postsCount": 24,
        "joinedAt": 1704067200000,
        "coins": 12500,
        "purchasedCoins": 8500,
        "giftedCoins": 4000,
        "trialCoins": 4000,
        "identityPublic": true,
        "isPrivate": false
    ]

    static let peerUserDict: [String: Any] = [
        "id": "u2",
        "name": "Lê Hoàng Nam",
        "handle": "hoangnam",
        "username": "hoangnam",
        "bio": "Thiết kế sản phẩm & nhiếp ảnh • Đà Nẵng",
        "locationName": "Đà Nẵng",
        "city": "Đà Nẵng",
        "avatarColor": "#2563EB",
        "age": 26,
        "height": 178,
        "weight": 72,
        "gender": "Nam",
        "orientation": "Gay / Đồng tính nam",
        "communityRole": "Top",
        "pronouns": "Anh",
        "relationshipRole": "Đang tìm hiểu",
        "lookingFor": "Kết bạn, Hẹn hò",
        "occupation": "Thiết kế sản phẩm",
        "school": "Đại học Bách Khoa",
        "interests": ["Nhiếp ảnh", "Du lịch", "Công nghệ"],
        "distanceKm": 2.4,
        "isFollowing": true,
        "isFriend": true,
        "postsCount": 18,
        "joinedAt": 1698796800000,
        "identityPublic": true
    ]

    static let secondPeerDict: [String: Any] = [
        "id": "u3",
        "name": "Trần Thanh Trúc",
        "handle": "thanhtruc",
        "username": "thanhtruc",
        "bio": "Âm nhạc, du lịch & công nghệ • Hà Nội",
        "locationName": "Hà Nội",
        "city": "Hà Nội",
        "avatarColor": "#EC4899",
        "age": 24,
        "height": 165,
        "weight": 52,
        "gender": "Nữ",
        "orientation": "Song tính / Bisexual",
        "communityRole": "Femme",
        "pronouns": "Chị",
        "relationshipRole": "Độc thân",
        "lookingFor": "Kết bạn, Trò chuyện",
        "occupation": "Lập trình viên",
        "school": "Đại học Quốc Gia Hà Nội",
        "interests": ["Âm nhạc", "Du lịch", "Cà phê"],
        "distanceKm": 5.8,
        "isFollowing": false,
        "isFriend": false,
        "postsCount": 9,
        "joinedAt": 1701388800000,
        "identityPublic": true
    ]

    static let thirdPeerDict: [String: Any] = [
        "id": "u4",
        "name": "Linh Nhi",
        "handle": "linhnhi",
        "username": "linhnhi",
        "bio": "Thiết kế sáng tạo & nhiếp ảnh • Đà Nẵng",
        "locationName": "Đà Nẵng",
        "avatarColor": "#8B5CF6",
        "distanceKm": 4.2,
        "isFollowing": false,
        "isFriend": false
    ]

    static let fixtureGroupDict: [String: Any] = [
        "id": "fixture_group_1",
        "name": "Nhóm Thiết Kế Kinnect",
        "description": "Trao đổi ý tưởng sáng tạo và nhiếp ảnh",
        "avatarColor": "#6D4AFF",
        "membersCount": 4,
        "lastMessageText": "@Tất cả Hẹn mọi người 19h tối nay tại quán quen nhé!",
        "unreadCount": 1,
        "members": [peerUserDict, secondPeerDict, thirdPeerDict]
    ]

    static func mockResponse(for path: String) -> [String: Any] {
        let cleanPath = path.components(separatedBy: "?").first ?? path

        switch cleanPath {
        case "/api/me", "/api/auth/me":
            if let act = activeScreen, act == "splash" || act.hasPrefix("auth") || act == "forgot-password" {
                return [:]
            }
            return ["user": currentUserDict]

        case "/api/posts":
            return [
                "posts": [
                    [
                        "id": "fixture_post_1",
                        "author": peerUserDict,
                        "text": "Hoàng hôn trên cầu Rồng chiều cuối tuần. Khoảnh khắc thật đẹp cùng bạn bè!",
                        "category": "community",
                        "imageUrl": sampleImageDataURL,
                        "likesCount": 42,
                        "commentsCount": 2,
                        "liked": true,
                        "userReaction": "love",
                        "reactions": ["love": 26, "like": 12, "haha": 4],
                        "createdAt": "2026-11-07T01:30:00.000Z"
                    ],
                    [
                        "id": "fixture_post_2",
                        "author": secondPeerDict,
                        "text": "Buổi chiều cà phê cuối tuần cùng hội bạn thân tại trung tâm Sài Gòn.",
                        "category": "events",
                        "imageUrl": "",
                        "likesCount": 19,
                        "commentsCount": 3,
                        "liked": false,
                        "userReaction": "",
                        "createdAt": "2026-11-07T01:00:00.000Z"
                    ]
                ]
            ]

        case "/api/stories":
            return [
                "stories": [
                    [
                        "id": "fixture_story_1",
                        "author": peerUserDict,
                        "text": "Khoảnh khắc 24h",
                        "backgroundColor": "#7C3AED",
                        "viewed": false,
                        "viewsCount": 15,
                        "createdAt": "2026-11-07T01:20:00.000Z"
                    ],
                    [
                        "id": "fixture_story_2",
                        "author": secondPeerDict,
                        "text": "Cuối tuần vui vẻ",
                        "backgroundColor": "#EC4899",
                        "viewed": true,
                        "viewsCount": 9,
                        "createdAt": "2026-11-07T00:50:00.000Z"
                    ]
                ]
            ]

        case "/api/discover":
            if activeScreen == "discover-empty" {
                return [
                    "people": [],
                    "users": [],
                    "posts": []
                ]
            }
            let users: [[String: Any]] = [
                [
                    "id": "u2",
                    "name": "Lê Hoàng Nam",
                    "handle": "hoangnam",
                    "username": "hoangnam",
                    "bio": "Thiết kế sản phẩm & nhiếp ảnh",
                    "locationName": "Đà Nẵng",
                    "avatarColor": "#2563EB",
                    "age": 26,
                    "height": 178,
                    "weight": 72,
                    "gender": "Nam",
                    "orientation": "Gay / Đồng tính nam",
                    "communityRole": "Top",
                    "distanceKm": 1.8,
                    "isFollowing": true,
                    "isFriend": true
                ],
                [
                    "id": "u3",
                    "name": "Trần Thanh Trúc",
                    "handle": "thanhtruc",
                    "username": "thanhtruc",
                    "bio": "Âm nhạc, cà phê & du lịch",
                    "locationName": "Hà Nội",
                    "avatarColor": "#EC4899",
                    "age": 24,
                    "height": 165,
                    "weight": 52,
                    "gender": "Nữ",
                    "orientation": "Song tính / Bisexual",
                    "communityRole": "Femme",
                    "distanceKm": 3.2,
                    "isFollowing": false,
                    "isFriend": false
                ],
                [
                    "id": "u4",
                    "name": "Linh Nhi",
                    "handle": "linhnhi",
                    "username": "linhnhi",
                    "bio": "Thiết kế sáng tạo & nhiếp ảnh",
                    "locationName": "Đà Nẵng",
                    "avatarColor": "#8B5CF6",
                    "age": 23,
                    "height": 164,
                    "weight": 50,
                    "gender": "Nữ",
                    "orientation": "Queer",
                    "communityRole": "Femme",
                    "distanceKm": 4.2,
                    "isFollowing": true,
                    "isFriend": false
                ],
                [
                    "id": "u5",
                    "name": "Đặng Phương Anh",
                    "handle": "phuonganh_hp",
                    "bio": "Sáng tạo nội dung • Hội họa",
                    "locationName": "Hải Phòng",
                    "avatarColor": "#F59E0B",
                    "age": 23,
                    "height": 165,
                    "weight": 50,
                    "gender": "Nam chuyển giới",
                    "orientation": "Song tính / Bisexual",
                    "communityRole": "Top",
                    "distanceKm": 5.1,
                    "isFollowing": false,
                    "isFriend": false
                ],
                [
                    "id": "u6",
                    "name": "Phạm Quốc Bảo",
                    "handle": "quocbao_ct",
                    "bio": "Kiến trúc sư • Cà phê",
                    "locationName": "Cần Thơ",
                    "avatarColor": "#10B981",
                    "age": 28,
                    "height": 172,
                    "weight": 65,
                    "gender": "nam",
                    "distanceKm": 6.8,
                    "isFollowing": false,
                    "isFriend": true
                ],
                [
                    "id": "u7",
                    "name": "Vũ Hoàng Khánh My",
                    "handle": "khanhmy_nt",
                    "bio": "Thời trang & Phong cách sống",
                    "locationName": "Nha Trang",
                    "avatarColor": "#06B6D4",
                    "age": 25,
                    "height": 168,
                    "weight": 52,
                    "gender": "nu",
                    "distanceKm": 7.4,
                    "isFollowing": true,
                    "isFriend": false
                ],
                [
                    "id": "u8",
                    "name": "Nguyễn Hải Đăng",
                    "handle": "haidang_hue",
                    "bio": "Ẩm thực truyền thống • Guitar",
                    "locationName": "Huế",
                    "avatarColor": "#3B82F6",
                    "age": 27,
                    "height": 180,
                    "weight": 75,
                    "gender": "nam",
                    "distanceKm": 8.0,
                    "isFollowing": false,
                    "isFriend": false
                ],
                [
                    "id": "u9",
                    "name": "Hoàng Bích Thảo",
                    "handle": "bichthao_dl",
                    "bio": "Vườn hoa • Sách • Trà",
                    "locationName": "Đà Lạt",
                    "avatarColor": "#E11D48",
                    "age": 21,
                    "height": 160,
                    "weight": 46,
                    "gender": "nu",
                    "distanceKm": 9.3,
                    "isFollowing": false,
                    "isFriend": false
                ],
                [
                    "id": "u10",
                    "name": "Đỗ Thành Long",
                    "handle": "thanhlong_vt",
                    "bio": "Lướt sóng & Khám phá biển",
                    "locationName": "Vũng Tàu",
                    "avatarColor": "#6366F1",
                    "age": 29,
                    "height": 174,
                    "weight": 70,
                    "gender": "nam",
                    "distanceKm": 11.2,
                    "isFollowing": true,
                    "isFriend": true
                ]
            ]
            let queryParam = URLComponents(string: "https://kinnect.local" + path)?
                .queryItems?
                .first(where: { $0.name == "q" })?
                .value?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let effectiveQuery: String
            if !queryParam.isEmpty {
                effectiveQuery = queryParam
            } else if activeScreen == "discover-results" {
                effectiveQuery = "cà phê"
            } else {
                effectiveQuery = ""
            }
            let filteredUsers: [[String: Any]]
            if effectiveQuery.isEmpty {
                filteredUsers = users
            } else {
                let viLocale = Locale(identifier: "vi_VN")
                let needle = effectiveQuery.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: viLocale)
                filteredUsers = users.filter { u in
                    let haystack = [
                        u["name"] as? String ?? "",
                        u["handle"] as? String ?? "",
                        u["bio"] as? String ?? "",
                        u["locationName"] as? String ?? ""
                    ].joined(separator: " ")
                        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: viLocale)
                    return haystack.contains(needle)
                }
            }
            return [
                "people": filteredUsers,
                "users": filteredUsers
            ]

        case "/api/shorts":
            let videoURL = samplePlayableVideoURL()?.absoluteString ?? ""
            return [
                "shorts": [
                    [
                        "id": "fixture_short_1",
                        "author": peerUserDict,
                        "title": "Dạo phố sáng cuối tuần",
                        "caption": "Video ngắn ghi lại khoảnh khắc buổi sáng cuối tuần.",
                        "videoUrl": videoURL,
                        "durationSec": 15,
                        "likesCount": 128,
                        "commentsCount": 14,
                        "liked": true,
                        "createdAt": "2026-11-07T01:10:00.000Z"
                    ]
                ]
            ]

        case "/api/music":
            return [
                "tracks": [
                    ["file": "tiktok-01.mp3", "title": "LIỆU RẰNG · Remix", "artist": "Huy PT Remix", "url": "/music/tiktok-01.mp3"],
                    ["file": "tiktok-02.mp3", "title": "Xin lỗi vì đã…", "artist": "Huy PT Remix", "url": "/music/tiktok-02.mp3"],
                    ["file": "tiktok-03.mp3", "title": "EM ĐAU LẮM ANH À · Remix", "artist": "Huy PT Remix", "url": "/music/tiktok-03.mp3"],
                    ["file": "tiktok-04.mp3", "title": "Nghe có vẻ mọi người không chuộng mixtape", "artist": "Huy PT Remix", "url": "/music/tiktok-04.mp3"],
                    ["file": "tiktok-05.mp3", "title": "TỰ EM SAI · Remix", "artist": "Huy PT Remix", "url": "/music/tiktok-05.mp3"],
                    ["file": "tiktok-06.mp3", "title": "Sự đời trớ trêu thay ngay khi…", "artist": "Huy PT Remix", "url": "/music/tiktok-06.mp3"],
                    ["file": "tiktok-07.mp3", "title": "CÔ DÂU CỦA NGƯỜI TA · Remix", "artist": "Huy PT Remix", "url": "/music/tiktok-07.mp3"],
                    ["file": "tiktok-08.mp3", "title": "Cứa lên da vết thương không lành…", "artist": "Huy PT Remix", "url": "/music/tiktok-08.mp3"],
                    ["file": "tiktok-09.mp3", "title": "Em muốn kết thúc như thế này sao?", "artist": "Huy PT Remix", "url": "/music/tiktok-09.mp3"],
                    ["file": "tiktok-10.mp3", "title": "Âm nhạc dùng để sáng tạo và thưởng thức", "artist": "Huy PT Remix", "url": "/music/tiktok-10.mp3"]
                ]
            ]

        case "/api/conversations":
            let iso = ISO8601DateFormatter()
            let t1 = iso.string(from: Date().addingTimeInterval(-5 * 60))
            let t2 = iso.string(from: Date().addingTimeInterval(-95 * 60))
            return [
                "conversations": [
                    [
                        "user": peerUserDict,
                        "preview": "Hẹn gặp lúc 19h tối nay nhé!",
                        "unreadCount": 2,
                        "updatedAt": t1,
                        "lastTime": t1
                    ],
                    [
                        "user": secondPeerDict,
                        "preview": "Mình vừa gửi ảnh buổi gặp mặt hôm nay rồi nhé.",
                        "unreadCount": 0,
                        "updatedAt": t2,
                        "lastTime": t2
                    ]
                ]
            ]

        case "/api/groups":
            return [
                "groups": [
                    [
                        "id": "fixture_group_1",
                        "name": "Nhóm Thiết Kế Kinnect",
                        "description": "Trao đổi ý tưởng sáng tạo và nhiếp ảnh",
                        "avatarColor": "#6D4AFF",
                        "membersCount": 6,
                        "lastMessageText": "Hẹn mọi người 19h tối nay tại quán quen nhé!",
                        "unreadCount": 1
                    ]
                ]
            ]

        case "/api/friends":
            return ["friends": [peerUserDict, thirdPeerDict]]

        case "/api/friend-requests":
            return [
                "incoming": [["fromUser": secondPeerDict]],
                "outgoing": [["toUser": thirdPeerDict]]
            ]

        case "/api/me/privacy-consent":
            return [
                "version": "2026-10-29",
                "notice": "Kinnect cam kết bảo vệ dữ liệu cá nhân, mã hóa dữ liệu truyền tải và lưu trữ an toàn theo quy định pháp luật về an toàn thông tin. Người dùng toàn quyền quản lý, kiểm soát và yêu cầu xóa thông tin cá nhân bất kỳ lúc nào.",
                "accepted": false
            ]

        case "/api/me/account-deletion":
            return [
                "requiresPassword": true,
                "username": "minhanh",
                "permanent": true
            ]

        case "/api/groups/fixture_group_1/messages":
            return [
                "messages": [
                    [
                        "id": "fixture_gmsg_1",
                        "groupId": "fixture_group_1",
                        "sender": peerUserDict,
                        "text": "@Tất cả Chào cả nhóm! Cuối tuần này mọi người rảnh buổi nào để đi cà phê?",
                        "createdAt": "2026-11-07T01:30:00.000Z",
                        "seenCount": 4
                    ],
                    [
                        "id": "fixture_gmsg_2",
                        "groupId": "fixture_group_1",
                        "sender": currentUserDict,
                        "text": "@minhanh Cảm ơn bạn! Chiều thứ Bảy mình ghé qua luôn nhé.",
                        "createdAt": "2026-11-07T01:31:00.000Z",
                        "seenCount": 3
                    ],
                    [
                        "id": "fixture_gmsg_3",
                        "groupId": "fixture_group_1",
                        "sender": peerUserDict,
                        "text": "Lịch trình và tài liệu buổi gặp mặt đính kèm:",
                        "attachment": [
                            "name": "Lich-Trinh-Gap-Mat.pdf",
                            "url": "/api/chat-attachments/fixture_pdf_1",
                            "kind": "file",
                            "type": "application/pdf"
                        ],
                        "createdAt": "2026-11-07T01:32:00.000Z",
                        "seenCount": 4
                    ],
                    [
                        "id": "fixture_gmsg_4",
                        "groupId": "fixture_group_1",
                        "sender": secondPeerDict,
                        "text": "Ảnh chụp hoàng hôn chiều nay gửi cả nhóm:",
                        "imageUrl": sampleImageDataURL,
                        "createdAt": "2026-11-07T01:33:00.000Z",
                        "seenCount": 3
                    ]
                ]
            ]

        case _ where cleanPath.hasSuffix("/reactions"):
            var r1 = peerUserDict
            r1["reaction"] = "love"
            var r2 = secondPeerDict
            r2["reaction"] = "love"
            var r3 = thirdPeerDict
            r3["reaction"] = "like"
            var r4 = currentUserDict
            r4["reaction"] = "haha"
            return [
                "users": [r1, r2, r3, r4]
            ]

        case _ where cleanPath.hasSuffix("/comments"):
            return [
                "comments": [
                    [
                        "id": "fixture_c_1",
                        "author": peerUserDict,
                        "text": "Bức ảnh đẹp quá bạn ơi! Chụp bằng ống kính nào thế? 📸",
                        "createdAt": "2026-11-07T01:35:00.000Z",
                        "liked": true,
                        "likesCount": 5
                    ],
                    [
                        "id": "fixture_c_2",
                        "parentId": "fixture_c_1",
                        "author": currentUserDict,
                        "text": "@minhanh Cảm ơn bạn nhé! Chụp bằng camera góc rộng của Kinnect Studio.",
                        "createdAt": "2026-11-07T01:36:00.000Z",
                        "liked": true,
                        "likesCount": 2
                    ]
                ]
            ]

        case "/api/friend-suggestions":
            return ["suggestions": [secondPeerDict, thirdPeerDict]]

        case "/api/notifications":
            return [
                "notifications": [
                    [
                        "id": "fixture_notif_1",
                        "type": "like",
                        "actor": peerUserDict,
                        "preview": "Hoàng Nam đã bày tỏ cảm xúc với bài viết của bạn.",
                        "read": false,
                        "createdAt": "2026-11-07T01:40:00.000Z"
                    ],
                    [
                        "id": "fixture_notif_2",
                        "type": "friend_request",
                        "actor": secondPeerDict,
                        "preview": "Thanh Trúc đã gửi lời mời kết bạn.",
                        "read": true,
                        "createdAt": "2026-11-07T00:30:00.000Z"
                    ]
                ]
            ]

        case "/api/wallet":
            return [
                "availableBalance": 12500,
                "totalUsableCoins": 12500,
                "purchasedCoins": 8500,
                "giftedCoins": 4000,
                "trialCoins": 4000,
                "earningsVnd": 15000,
                "spentCoins": 2500,
                "vndPerCoin": 100,
                "withdrawableVnd": 0,
                "topUpEnabled": false,
                "currencyLabel": "Xu Kinnect",
                "entries": [
                    [
                        "id": "fixture_tx_1",
                        "title": "Nhận xu thưởng thành viên",
                        "note": "Quà tặng chào mừng thành viên mới",
                        "amount": 5000,
                        "direction": "credit",
                        "createdAt": "2026-11-07T01:00:00.000Z"
                    ],
                    [
                        "id": "fixture_tx_2",
                        "title": "Đổi khung Avatar Cực Quang",
                        "note": "Gói trang trí hồ sơ",
                        "amount": 500,
                        "direction": "debit",
                        "createdAt": "2026-11-06T22:00:00.000Z"
                    ]
                ]
            ]

        case "/api/store":
            let studioPackages: [[String: Any]] = ["video", "photo"].flatMap { line -> [[String: Any]] in
                let isVideo = (line == "video")
                let titleBase = isVideo ? "Studio Video Pro" : "Studio Ảnh Pro"
                let subtitle = isVideo
                    ? "Chỉnh video và mẫu dựng nâng cao trong Studio. Không tự gia hạn hay tự trừ xu."
                    : "Chỉnh ảnh nâng cao trong Studio. Không tự gia hạn hay tự trừ xu."
                let colors = isVideo ? ["#7C3AED", "#C026D3"] : ["#DB2777", "#F97316"]
                let durations: [(Int, Int, String, String)] = [
                    (7, 190, "common", "7 ngày"),
                    (30, 490, "rare", "1 tháng"),
                    (180, 2190, "epic", "6 tháng"),
                    (365, 3990, "legendary", "1 năm")
                ]
                return durations.map { days, priceCoins, tier, period in
                    [
                        "id": "studio_\(line)_\(days)",
                        "title": "\(titleBase) \(period)",
                        "name": titleBase,
                        "subtitle": subtitle,
                        "description": subtitle,
                        "category": "studio",
                        "kind": "studio",
                        "line": line,
                        "days": days,
                        "period": period,
                        "priceCoins": priceCoins,
                        "badgeText": tier.uppercased(),
                        "tier": tier,
                        "colors": colors,
                        "accentColor": colors[0],
                        "available": true,
                        "owned": false,
                        "equipped": false
                    ]
                }
            }
            let basePackages: [[String: Any]] = [
                [
                    "id": "style_neon",
                    "title": "Neon",
                    "name": "Neon",
                    "subtitle": "Khung avatar và màu bong bóng hội thoại.",
                    "category": "style",
                    "kind": "style",
                    "priceCoins": 300,
                    "period": "Vĩnh viễn",
                    "badgeText": "RARE",
                    "tier": "rare",
                    "colors": ["#7C3AED", "#06B6D4"],
                    "accentColor": "#7C3AED",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "style_aurora",
                    "title": "Cực quang",
                    "name": "Cực quang",
                    "subtitle": "Khung avatar và màu bong bóng hội thoại.",
                    "category": "style",
                    "kind": "style",
                    "priceCoins": 500,
                    "period": "Vĩnh viễn",
                    "badgeText": "EPIC",
                    "tier": "epic",
                    "colors": ["#8B5CF6", "#EC4899"],
                    "accentColor": "#8B5CF6",
                    "available": true,
                    "owned": true,
                    "equipped": true
                ],
                [
                    "id": "style_galaxy",
                    "title": "Galaxy",
                    "name": "Galaxy",
                    "subtitle": "Khung avatar và màu bong bóng hội thoại.",
                    "category": "style",
                    "kind": "style",
                    "priceCoins": 800,
                    "period": "Vĩnh viễn",
                    "badgeText": "LEGENDARY",
                    "tier": "legendary",
                    "colors": ["#312E81", "#A855F7"],
                    "accentColor": "#312E81",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "style_ice",
                    "title": "Băng hà",
                    "name": "Băng hà",
                    "subtitle": "Khung avatar và màu bong bóng hội thoại.",
                    "category": "style",
                    "kind": "style",
                    "priceCoins": 600,
                    "period": "Vĩnh viễn",
                    "badgeText": "EPIC",
                    "tier": "epic",
                    "colors": ["#38BDF8", "#E0F2FE"],
                    "accentColor": "#38BDF8",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "style_ruby",
                    "title": "Hồng ngọc",
                    "name": "Hồng ngọc",
                    "subtitle": "Khung avatar và màu bong bóng hội thoại.",
                    "category": "style",
                    "kind": "style",
                    "priceCoins": 650,
                    "period": "Vĩnh viễn",
                    "badgeText": "EPIC",
                    "tier": "epic",
                    "colors": ["#BE123C", "#FB7185"],
                    "accentColor": "#BE123C",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "style_forest",
                    "title": "Rừng thẳm",
                    "name": "Rừng thẳm",
                    "subtitle": "Khung avatar và màu bong bóng hội thoại.",
                    "category": "style",
                    "kind": "style",
                    "priceCoins": 350,
                    "period": "Vĩnh viễn",
                    "badgeText": "RARE",
                    "tier": "rare",
                    "colors": ["#047857", "#A3E635"],
                    "accentColor": "#047857",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "style_paper",
                    "title": "Giấy mỹ thuật",
                    "name": "Giấy mỹ thuật",
                    "subtitle": "Khung avatar và màu bong bóng hội thoại.",
                    "category": "style",
                    "kind": "style",
                    "priceCoins": 300,
                    "period": "Vĩnh viễn",
                    "badgeText": "RARE",
                    "tier": "rare",
                    "colors": ["#D6D3D1", "#57534E"],
                    "accentColor": "#D6D3D1",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "style_ember",
                    "title": "Lửa trại",
                    "name": "Lửa trại",
                    "subtitle": "Khung avatar và màu bong bóng hội thoại.",
                    "category": "style",
                    "kind": "style",
                    "priceCoins": 900,
                    "period": "Vĩnh viễn",
                    "badgeText": "LEGENDARY",
                    "tier": "legendary",
                    "colors": ["#F59E0B", "#DC2626"],
                    "accentColor": "#F59E0B",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "live_chill",
                    "title": "Chill",
                    "name": "Chill",
                    "subtitle": "Bộ trang trí phòng Live. Không bao gồm quyền phát Live Game.",
                    "category": "live",
                    "kind": "live",
                    "priceCoins": 500,
                    "period": "Vĩnh viễn",
                    "badgeText": "RARE",
                    "tier": "rare",
                    "colors": ["#0D9488", "#38BDF8"],
                    "accentColor": "#0D9488",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "live_gaming",
                    "title": "Gaming",
                    "name": "Gaming",
                    "subtitle": "Bộ trang trí phòng Live. Không bao gồm quyền phát Live Game.",
                    "category": "live",
                    "kind": "live",
                    "priceCoins": 800,
                    "period": "Vĩnh viễn",
                    "badgeText": "EPIC",
                    "tier": "epic",
                    "colors": ["#4F46E5", "#F43F5E"],
                    "accentColor": "#4F46E5",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "live_spotlight",
                    "title": "Spotlight",
                    "name": "Spotlight",
                    "subtitle": "Bộ trang trí phòng Live. Không bao gồm quyền phát Live Game.",
                    "category": "live",
                    "kind": "live",
                    "priceCoins": 1200,
                    "period": "Vĩnh viễn",
                    "badgeText": "LEGENDARY",
                    "tier": "legendary",
                    "colors": ["#A16207", "#FBBF24"],
                    "accentColor": "#A16207",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "live_game_30",
                    "title": "Live Game",
                    "name": "Live Game",
                    "subtitle": "Phát màn hình game, bình luận nổi và trả lời bình luận.",
                    "category": "live",
                    "kind": "live",
                    "priceCoins": 490,
                    "days": 30,
                    "period": "30 ngày",
                    "badgeText": "EPIC",
                    "tier": "epic",
                    "colors": ["#6D28D9", "#DB2777"],
                    "accentColor": "#6D28D9",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "gift_love",
                    "title": "Yêu thương",
                    "name": "Yêu thương",
                    "subtitle": "Bộ quà có sẵn trong kho, tiêu hao khi gửi Live.",
                    "category": "gifts",
                    "kind": "gifts",
                    "priceCoins": 300,
                    "period": "Bộ quà",
                    "badgeText": "RARE",
                    "tier": "rare",
                    "colors": ["#DB2777", "#FB7185"],
                    "accentColor": "#DB2777",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "gift_speed",
                    "title": "Tốc độ",
                    "name": "Tốc độ",
                    "subtitle": "Bộ quà có sẵn trong kho, tiêu hao khi gửi Live.",
                    "category": "gifts",
                    "kind": "gifts",
                    "priceCoins": 1000,
                    "period": "Bộ quà",
                    "badgeText": "EPIC",
                    "tier": "epic",
                    "colors": ["#2563EB", "#06B6D4"],
                    "accentColor": "#2563EB",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "gift_royal",
                    "title": "Hoàng gia",
                    "name": "Hoàng gia",
                    "subtitle": "Bộ quà có sẵn trong kho, tiêu hao khi gửi Live.",
                    "category": "gifts",
                    "kind": "gifts",
                    "priceCoins": 2000,
                    "period": "Bộ quà",
                    "badgeText": "LEGENDARY",
                    "tier": "legendary",
                    "colors": ["#7E22CE", "#EAB308"],
                    "accentColor": "#7E22CE",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "member_plus",
                    "title": "Plus",
                    "name": "Plus",
                    "subtitle": "Huy hiệu thành viên trên hồ sơ và phòng Live.",
                    "category": "member",
                    "kind": "member",
                    "priceCoins": 490,
                    "days": 30,
                    "period": "30 ngày",
                    "badgeText": "RARE",
                    "tier": "rare",
                    "colors": ["#4338CA", "#A78BFA"],
                    "accentColor": "#4338CA",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ],
                [
                    "id": "member_creator",
                    "title": "Creator",
                    "name": "Creator",
                    "subtitle": "Huy hiệu thành viên trên hồ sơ và phòng Live.",
                    "category": "member",
                    "kind": "member",
                    "priceCoins": 990,
                    "days": 30,
                    "period": "30 ngày",
                    "badgeText": "LEGENDARY",
                    "tier": "legendary",
                    "colors": ["#C026D3", "#FB923C"],
                    "accentColor": "#C026D3",
                    "available": true,
                    "owned": false,
                    "equipped": false
                ]
            ]
            return [
                "ownedPackages": ["style_aurora"],
                "appearance": "style_aurora",
                "liveTheme": "",
                "membership": "",
                "trialPackagePurchases": true,
                "purchasedCoins": 8500,
                "giftedCoins": 4000,
                "trialCoins": 4000,
                "packages": basePackages + studioPackages,
                "products": [
                    [
                        "id": "kinnect_style_aurora",
                        "kind": "style",
                        "name": "Aurora",
                        "title": "Aurora",
                        "description": "Khung ảnh tím hồng và màu hội thoại Aurora.",
                        "colors": ["#8b5cf6", "#ec4899"],
                        "referenceVnd": 29000,
                        "priceLabel": "29.000đ"
                    ],
                    [
                        "id": "kinnect_style_ocean",
                        "kind": "style",
                        "name": "Ocean",
                        "title": "Ocean",
                        "description": "Khung ảnh xanh biển và màu hội thoại Ocean.",
                        "colors": ["#0284c7", "#14b8a6"],
                        "referenceVnd": 29000,
                        "priceLabel": "29.000đ"
                    ],
                    [
                        "id": "kinnect_style_sunset",
                        "kind": "style",
                        "name": "Sunset",
                        "title": "Sunset",
                        "description": "Khung ảnh hoàng hôn và màu hội thoại Sunset.",
                        "colors": ["#f97316", "#db2777"],
                        "referenceVnd": 29000,
                        "priceLabel": "29.000đ"
                    ],
                    [
                        "id": "kinnect_studio_pro",
                        "kind": "studio",
                        "name": "Studio Pro",
                        "title": "Studio Pro",
                        "description": "Ba mẫu dựng video Aurora, Travel, Cinema và trình sửa ảnh nâng cao: lớp ảnh/chữ, mặt nạ, Curves/HSL, lưu nháp và xuất ảnh. Mua một lần, dùng trên tài khoản này.",
                        "colors": ["#7c3aed", "#c026d3"],
                        "referenceVnd": 149000,
                        "priceLabel": "149.000đ"
                    ]
                ]
            ]

        case "/api/live/rooms":
            if activeScreen == "live-empty" {
                return ["rooms": []]
            }
            return [
                "rooms": [
                    [
                        "id": "fixture_live_1",
                        "title": "Giao lưu âm nhạc tối cuối tuần",
                        "topic": "Trò chuyện & kết nối bạn mới",
                        "liveMode": "chat",
                        "gameTitle": "",
                        "hostUserId": "u2",
                        "hostName": "Lê Hoàng Nam",
                        "hostAvatarColor": "#2563EB",
                        "viewerCount": 64
                    ],
                    [
                        "id": "fixture_live_2",
                        "title": "Cà phê acoustic & tâm sự cuối ngày",
                        "topic": "Trò chuyện thư giãn",
                        "liveMode": "chat",
                        "gameTitle": "",
                        "hostUserId": "u3",
                        "hostName": "Trần Thanh Trúc",
                        "hostAvatarColor": "#EC4899",
                        "viewerCount": 142
                    ]
                ]
            ]

        case "/api/live/gifts":
            return [
                "version": 1,
                "balance": 12500,
                "purchasedCoins": 8500,
                "giftedCoins": 4000,
                "trialCoins": 4000,
                "quantities": [1, 5, 10, 99],
                "inventory": [
                    ["giftId": "rose", "quantity": 3],
                    ["giftId": "heart", "quantity": 2]
                ],
                "items": LiveGiftCatalogItem.defaultCatalog.map { gift in
                    [
                        "id": gift.id,
                        "name": gift.label,
                        "label": gift.label,
                        "emoji": gift.emoji,
                        "costCoins": gift.coins,
                        "coins": gift.coins,
                        "tier": gift.tier
                    ] as [String: Any]
                }
            ]

        case "/api/me/private/requests":
            return [
                "requests": [
                    [
                        "status": "pending",
                        "created": 1762500000000,
                        "user": secondPeerDict
                    ],
                    [
                        "status": "granted",
                        "created": 1762490000000,
                        "user": peerUserDict
                    ]
                ]
            ]

        case "/api/sessions", "/api/me/sessions":
            return [
                "sessions": [
                    [
                        "id": "fixture_sess_1",
                        "label": "iPhone 17e • iOS 26.5",
                        "userAgent": "iPhone 17e • iOS 26.5 (Thiết bị hiện tại)",
                        "deviceName": "iPhone 17e (Thiết bị này)",
                        "ip": "127.0.0.1",
                        "current": true,
                        "expires": Int64(Date().addingTimeInterval(86400 * 14).timeIntervalSince1970 * 1000),
                        "lastActive": "Vừa xong"
                    ],
                    [
                        "id": "fixture_sess_2",
                        "label": "iPad (A16) • iPadOS 26.5",
                        "userAgent": "iPad (A16) • iPadOS 26.5",
                        "deviceName": "iPad (A16)",
                        "ip": "192.168.1.15",
                        "current": false,
                        "expires": Int64(Date().addingTimeInterval(86400 * 7).timeIntervalSince1970 * 1000),
                        "lastActive": "2 giờ trước"
                    ]
                ]
            ]

        case "/api/support":
            return [
                "user": peerUserDict,
                "contact": "anhvn53@wru.vn",
                "operator": "Mr Ánh"
            ]

        case "/api/admin/reports":
            return [
                "reports": [[
                    "id": "fixture_report_1",
                    "target_type": "post",
                    "target_id": "fixture_post_1",
                    "status": "open",
                    "reason": "Nội dung không phù hợp",
                    "subject": [
                        "username": "hoangnam",
                        "body": "Bài viết mẫu",
                        "userId": "u2",
                        "hidden": false
                    ]
                ]]
            ]

        case "/api/admin/users":
            return [
                "users": [
                    ["id": "u2", "username": "hoangnam", "role": "member", "suspended": 0],
                    ["id": "u1", "username": "minhanh", "role": "admin", "suspended": 0]
                ]
            ]

        case "/api/admin/moderate":
            return ["ok": true]

        default:
            if cleanPath.hasSuffix("/private") {
                return [
                    "status": "owner",
                    "count": 2,
                    "pending": 1,
                    "photos": [
                        [
                            "id": "fixture_priv_1",
                            "url": sampleImageDataURL,
                            "created": 1762500000000
                        ],
                        [
                            "id": "fixture_priv_2",
                            "url": sampleImageDataURL,
                            "created": 1762490000000
                        ]
                    ]
                ]
            }
            if cleanPath.hasSuffix("/messages") {
                return [
                    "messages": [
                        [
                            "id": "fixture_msg_1",
                            "fromUserId": "u2",
                            "toUserId": "u1",
                            "text": "Chào Minh Anh! Tối nay 19h mình gặp nhau ở quán cà phê cũ nhé?",
                            "imageUrl": "",
                            "createdAt": "2026-11-07T01:35:00.000Z",
                            "deliveredAt": "2026-11-07T01:35:01.000Z",
                            "seenAt": "2026-11-07T01:35:10.000Z",
                            "isSeen": true
                        ],
                        [
                            "id": "fixture_msg_2",
                            "fromUserId": "u1",
                            "toUserId": "u2",
                            "text": "Ok luôn, mình sẽ tới đúng giờ. Hẹn gặp bạn tối nay!",
                            "imageUrl": "",
                            "createdAt": "2026-11-07T01:36:00.000Z",
                            "deliveredAt": "2026-11-07T01:36:01.000Z",
                            "seenAt": "2026-11-07T01:36:05.000Z",
                            "isSeen": true
                        ],
                        [
                            "id": "fixture_msg_3",
                            "fromUserId": "u2",
                            "toUserId": "u1",
                            "text": "Tài liệu hành trình chuyến đi cuối tuần:",
                            "attachment": [
                                "name": "Ke-Hoach-Cuoi-Tuan.pdf",
                                "url": "/api/chat-attachments/fixture_doc_1",
                                "kind": "file",
                                "type": "application/pdf"
                            ],
                            "createdAt": "2026-11-07T01:37:00.000Z",
                            "deliveredAt": "2026-11-07T01:37:01.000Z",
                            "seenAt": "2026-11-07T01:37:05.000Z",
                            "isSeen": true
                        ],
                        [
                            "id": "fixture_msg_4",
                            "fromUserId": "u1",
                            "toUserId": "u2",
                            "text": "Ảnh chụp chiều nay mình mới chỉnh xong:",
                            "imageUrl": sampleImageDataURL,
                            "createdAt": "2026-11-07T01:38:00.000Z",
                            "deliveredAt": "2026-11-07T01:38:01.000Z",
                            "seenAt": "",
                            "isSeen": false
                        ]
                    ]
                ]
            }
            return [:]
        }
    }

    static var sampleImageDataURL: String = {
        let img = samplePreviewImage()
        if let jpeg = img.jpegData(compressionQuality: 0.82) {
            return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        }
        return ""
    }()

    static func samplePreviewImage() -> UIImage {
        let size = CGSize(width: 640, height: 420)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let skyColors = [
                UIColor(red: 0.14, green: 0.06, blue: 0.34, alpha: 1.0).cgColor,
                UIColor(red: 0.48, green: 0.18, blue: 0.68, alpha: 1.0).cgColor,
                UIColor(red: 0.96, green: 0.45, blue: 0.38, alpha: 1.0).cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: skyColors, locations: [0.0, 0.55, 1.0]) {
                cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }

            // Warm sunset sun disc
            cg.setFillColor(UIColor(red: 1.0, green: 0.84, blue: 0.42, alpha: 0.92).cgColor)
            cg.fillEllipse(in: CGRect(x: 420, y: 78, width: 96, height: 96))

            // Distant mountain silhouette
            let backMountains = UIBezierPath()
            backMountains.move(to: CGPoint(x: 0, y: 290))
            backMountains.addLine(to: CGPoint(x: 140, y: 190))
            backMountains.addLine(to: CGPoint(x: 270, y: 255))
            backMountains.addLine(to: CGPoint(x: 410, y: 165))
            backMountains.addLine(to: CGPoint(x: 540, y: 245))
            backMountains.addLine(to: CGPoint(x: 640, y: 205))
            backMountains.addLine(to: CGPoint(x: 640, y: 420))
            backMountains.addLine(to: CGPoint(x: 0, y: 420))
            backMountains.close()
            UIColor(red: 0.18, green: 0.08, blue: 0.32, alpha: 0.85).setFill()
            backMountains.fill()

            // Foreground mountain ridge
            let frontMountains = UIBezierPath()
            frontMountains.move(to: CGPoint(x: 0, y: 335))
            frontMountains.addLine(to: CGPoint(x: 190, y: 235))
            frontMountains.addLine(to: CGPoint(x: 340, y: 310))
            frontMountains.addLine(to: CGPoint(x: 500, y: 225))
            frontMountains.addLine(to: CGPoint(x: 640, y: 295))
            frontMountains.addLine(to: CGPoint(x: 640, y: 420))
            frontMountains.addLine(to: CGPoint(x: 0, y: 420))
            frontMountains.close()
            UIColor(red: 0.09, green: 0.04, blue: 0.18, alpha: 0.96).setFill()
            frontMountains.fill()
        }
    }

    static func mockPosts() -> [PostItem] {
        return [
            PostItem(
                id: "fixture_post_1",
                author: KinnectUser.from(peerUserDict),
                text: "Hoàng hôn trên cầu Rồng chiều cuối tuần.",
                imageUrl: sampleImageDataURL,
                category: "community",
                createdAt: "2026-11-07T01:30:00.000Z",
                likesCount: 42,
                commentsCount: 2,
                liked: true,
                userReaction: "love"
            ),
            PostItem(
                id: "fixture_post_2",
                author: KinnectUser.from(currentUserDict),
                text: "Cà phê chiều cuối tuần cùng hội bạn thân tại Quận 1.",
                imageUrl: sampleImageDataURL,
                category: "events",
                createdAt: "2026-11-07T01:00:00.000Z",
                likesCount: 19,
                commentsCount: 3,
                liked: false,
                userReaction: ""
            )
        ]
    }

    static func mockPrivatePhotos() -> [PrivatePhotoItem] {
        return [
            PrivatePhotoItem(id: "fixture_priv_1", url: sampleImageDataURL, createdAt: "1762500000000"),
            PrivatePhotoItem(id: "fixture_priv_2", url: sampleImageDataURL, createdAt: "1762490000000")
        ]
    }

    static func mockPrivateRequests() -> [PrivateAccessRequestItem] {
        return [
            PrivateAccessRequestItem(status: "pending", user: KinnectUser.from(secondPeerDict)),
            PrivateAccessRequestItem(status: "granted", user: KinnectUser.from(peerUserDict))
        ]
    }

    /// Generates a genuine playable H.264 MP4 video file on disk for local video playback verification.
    static func samplePlayableVideoURL() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let movieURL = tempDir.appendingPathComponent("ui_review_sample_shorts_v2.mp4")
        if FileManager.default.fileExists(atPath: movieURL.path) {
            return movieURL
        }

        let width = 720
        let height = 1280
        let fps: Int32 = 30
        let totalFrames = 60

        guard let writer = try? AVAssetWriter(outputURL: movieURL, fileType: .mp4) else {
            return nil
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let sourceAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourceAttrs
        )

        guard writer.canAdd(writerInput) else { return nil }
        writer.add(writerInput)

        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        for idx in 0..<totalFrames {
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32ARGB,
                nil,
                &pixelBuffer
            )
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else { continue }

            CVPixelBufferLockBaseAddress(buffer, [])
            if let pxdata = CVPixelBufferGetBaseAddress(buffer) {
                let context = CGContext(
                    data: pxdata,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                )
                if let ctx = context {
                    let progress = CGFloat(idx) / CGFloat(totalFrames)
                    let topColor = UIColor(
                        red: 0.08 + 0.06 * progress,
                        green: 0.05 + 0.03 * progress,
                        blue: 0.19 + 0.07 * progress,
                        alpha: 1.0
                    ).cgColor
                    let midColor = UIColor(
                        red: 0.22 + 0.10 * progress,
                        green: 0.11 + 0.05 * progress,
                        blue: 0.40,
                        alpha: 1.0
                    ).cgColor
                    let bottomColor = UIColor(
                        red: 0.06,
                        green: 0.04,
                        blue: 0.14,
                        alpha: 1.0
                    ).cgColor
                    if let grad = CGGradient(
                        colorsSpace: colorSpace,
                        colors: [topColor, midColor, bottomColor] as CFArray,
                        locations: [0.0, 0.52, 1.0]
                    ) {
                        ctx.drawLinearGradient(
                            grad,
                            start: CGPoint(x: 0, y: 0),
                            end: CGPoint(x: CGFloat(width), y: CGFloat(height)),
                            options: []
                        )
                    } else {
                        ctx.setFillColor(red: 0.12, green: 0.07, blue: 0.28, alpha: 1.0)
                        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            let frameTime = CMTime(value: Int64(idx), timescale: fps)
            while !writerInput.isReadyForMoreMediaData {
                usleep(500)
            }
            adaptor.append(buffer, withPresentationTime: frameTime)
        }

        writerInput.markAsFinished()
        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting {
            sema.signal()
        }
        sema.wait()

        return movieURL
    }

    /// Generates a valid playable PCM WAV audio file for background music muxing verification.
    static func sampleAudioURL(named name: String = "kinnect_sample_music") -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let safeName = name.replacingOccurrences(of: " ", with: "_")
        let fileURL = tempDir.appendingPathComponent("\(safeName).wav")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        let sampleRate: Int32 = 44100
        let numChannels: Int16 = 2
        let bitsPerSample: Int16 = 16
        let durationSeconds = 8
        let numFrames = Int(sampleRate) * durationSeconds
        let dataSize = Int32(numFrames * Int(numChannels) * Int(bitsPerSample / 8))
        let totalSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        var totalSizeLE = totalSize.littleEndian
        header.append(Data(bytes: &totalSizeLE, count: 4))
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        var fmtChunkSize: Int32 = 16
        header.append(Data(bytes: &fmtChunkSize, count: 4))
        var audioFormat: Int16 = 1 // PCM
        header.append(Data(bytes: &audioFormat, count: 2))
        var channels = numChannels.littleEndian
        header.append(Data(bytes: &channels, count: 2))
        var rate = sampleRate.littleEndian
        header.append(Data(bytes: &rate, count: 4))
        var byteRate: Int32 = (sampleRate * Int32(numChannels) * Int32(bitsPerSample / 8)).littleEndian
        header.append(Data(bytes: &byteRate, count: 4))
        var blockAlign: Int16 = (numChannels * (bitsPerSample / 8)).littleEndian
        header.append(Data(bytes: &blockAlign, count: 2))
        var bps = bitsPerSample.littleEndian
        header.append(Data(bytes: &bps, count: 2))
        header.append(contentsOf: "data".utf8)
        var dataSizeLE = dataSize.littleEndian
        header.append(Data(bytes: &dataSizeLE, count: 4))

        let freq: Double = name.contains("Lofi") ? 330.0 : name.contains("Acoustic") ? 440.0 : name.contains("EDM") ? 520.0 : 392.0
        var samples = Data(capacity: Int(dataSize))
        for i in 0..<numFrames {
            let t = Double(i) / Double(sampleRate)
            let val = sin(2.0 * .pi * freq * t) * 0.25 * sin(2.0 * .pi * (freq * 1.5) * t)
            var sample = Int16(val * 32767.0).littleEndian
            samples.append(Data(bytes: &sample, count: 2))
            samples.append(Data(bytes: &sample, count: 2))
        }

        var fullData = header
        fullData.append(samples)
        try? fullData.write(to: fileURL)
        return fileURL
    }

    static func mockStories() -> [StoryItem] {
        return [
            StoryItem.from([
                "id": "fixture_story_1",
                "author": peerUserDict,
                "text": "Hoàng hôn trên cầu Rồng cuối tuần 🌅",
                "imageUrl": sampleImageDataURL,
                "backgroundColor": "#7C3AED",
                "viewed": false,
                "viewsCount": 15,
                "createdAt": "2026-11-07T01:20:00.000Z"
            ]),
            StoryItem.from([
                "id": "fixture_story_2",
                "author": secondPeerDict,
                "text": "Cuối tuần cà phê Sài Gòn cùng bạn bè ☕",
                "backgroundColor": "#EC4899",
                "viewed": true,
                "viewsCount": 9,
                "createdAt": "2026-11-07T00:50:00.000Z"
            ])
        ]
    }

    /// Creates the appropriate SwiftUI view for the given screen name.
    /// Used by SceneDelegate when --ui-review-screen or `#if DEBUG` deep-link is active.
    @MainActor
    static func makeView(for screenName: String) -> AnyView {
        switch screenName {
        // MARK: - Splash & Auth Screens
        case "splash":
            return AnyView(KinnectSplashScreen())
        case "auth-welcome", "auth":
            return AnyView(AuthView(initialStage: .welcome))
        case "auth-login", "auth-login-populated", "auth-login-error", "auth-login-keyboard", "auth-login-password-keyboard", "auth-login-en":
            return AnyView(AuthView(initialStage: .login))
        case "auth-register":
            return AnyView(AuthView(initialStage: .register))
        case "auth-reset", "auth-forgot", "forgot-password":
            return AnyView(AuthView(initialStage: .forgotPassword))

        // MARK: - Main Tabs (Real KinnectTopBar + KinnectBottomBar shell)
        case "feed":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: nil) {
                    FeedView(onOpenCamera: {}, onOpenFriends: {})
                }
            )
        case "feed-narrow":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: nil) {
                    FeedView(onOpenCamera: {}, onOpenFriends: {})
                }
                .frame(width: 320)
                .clipped()
                .environment(\.horizontalSizeClass, .compact)
            )
        case "feed-story":
            return AnyView(
                StoryDetailSheet(stories: UIReviewFixture.mockStories(), initialIndex: 0)
            )
        case "feed-post-detail":
            return AnyView(
                NotificationPostDetailView(post: UIReviewFixture.mockPosts()[0])
            )
        case "feed-comments":
            return AnyView(
                PostCommentsSheet(post: UIReviewFixture.mockPosts()[0], onChanged: {})
            )
        case "feed-reactions":
            return AnyView(
                PostReactorsSheet(postId: "fixture_post_1")
            )
        case "discover", "discover-empty", "discover-search":
            return AnyView(
                UIReviewMainShell(selectedTab: .discover, activeTopSection: nil) {
                    DiscoverView(onOpenCamera: {})
                }
            )
        case "discover-results":
            return AnyView(
                UIReviewMainShell(selectedTab: .discover, activeTopSection: nil) {
                    DiscoverView(initialSearchQuery: "cà phê", onOpenCamera: {})
                }
            )
        case "create", "camera-studio":
            return AnyView(
                CameraStudioView(initialMode: .photo)
            )
        case "camera-studio-edit", "camera-studio-video-edit":
            return AnyView(
                CameraStudioView()
            )
        case "camera-studio-video":
            return AnyView(
                CameraStudioView(initialMode: .video)
            )
        case "studio-pro-sheet":
            return AnyView(
                NavigationStack {
                    StudioProSheet(appliedEffect: .constant(StudioProPack.cinema.rawValue), onApply: { _ in })
                }
            )
        case "studio-music-picker":
            return AnyView(
                NavigationStack {
                    StudioMusicPickerSheet(
                        selectedTrack: .constant("LIỆU RẰNG · Remix"),
                        onSelectTrack: { _, _ in }
                    )
                }
            )
        case "video", "shorts":
            return AnyView(
                UIReviewMainShell(selectedTab: .video, activeTopSection: nil) {
                    ShortsVideoView()
                }
            )
        case "live", "live-empty":
            return AnyView(
                UIReviewMainShell(selectedTab: .live, activeTopSection: nil) {
                    LiveStreamView(onOpenWallet: {})
                }
            )
        case "live-room":
            let fixtureRoom = LiveRoomItem.from([
                "id": "fixture_live_1",
                "title": "Giao lưu âm nhạc tối cuối tuần",
                "topic": "Trò chuyện & kết nối bạn mới",
                "liveMode": "chat",
                "gameTitle": "",
                "hostUserId": "u2",
                "hostName": "Lê Hoàng Nam",
                "hostAvatarColor": "#2563EB",
                "viewerCount": 64
            ])
            AppState.shared.liveRooms = [fixtureRoom]
            AppState.shared.currentLiveRoom = fixtureRoom
            AppState.shared.isCurrentLiveHost = false
            AppState.shared.liveChatMessages = [
                LiveChatMessage.from([
                    "id": "fixture_lchat_1",
                    "senderId": "u4",
                    "name": "Linh Nhi",
                    "avatarColor": "#8B5CF6",
                    "text": "Chào mừng mọi người đến với buổi tối cuối tuần cùng Hoàng Nam!"
                ]),
                LiveChatMessage.from([
                    "id": "fixture_lchat_2",
                    "senderId": "u3",
                    "name": "Trần Thanh Trúc",
                    "avatarColor": "#EC4899",
                    "text": "Chúc buổi phát trực tiếp thật nhiều niềm vui nha ❤️"
                ]),
                LiveChatMessage.from([
                    "id": "fixture_lchat_3",
                    "senderId": "u2",
                    "name": "Lê Hoàng Nam",
                    "avatarColor": "#2563EB",
                    "text": "Cảm ơn cả nhà đã ghé xem, nghe cùng mình một bài nhé!"
                ])
            ]
            return AnyView(
                LiveRoomFullScreenView()
            )
        case "live-setup":
            return AnyView(CreateLiveRoomSheet(initialMode: "chat"))
        case "live-setup-game":
            return AnyView(CreateLiveRoomSheet(initialMode: "game"))
        case "live-gifts":
            let fixtureRoom = LiveRoomItem.from([
                "id": "fixture_live_1",
                "title": "Giao lưu âm nhạc tối cuối tuần",
                "topic": "Trò chuyện & kết nối bạn mới",
                "liveMode": "chat",
                "gameTitle": "",
                "hostUserId": "u2",
                "hostName": "Lê Hoàng Nam",
                "hostAvatarColor": "#2563EB",
                "viewerCount": 64
            ])
            AppState.shared.liveRooms = [fixtureRoom]
            AppState.shared.currentLiveRoom = fixtureRoom
            return AnyView(
                LiveGiftDrawerSheet(
                    roomId: fixtureRoom.id,
                    gifts: LiveGiftCatalogItem.defaultCatalog,
                    priceVersion: 1
                )
            )

        // MARK: - Messages & Chats
        case "messages":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: .messages) {
                    NavigationStack {
                        MessagesView(initialScope: .direct, onOpenFriends: {}, onBack: {})
                    }
                }
            )
        case "chat-detail", "chat-menu", "message-menu":
            return AnyView(
                NavigationStack {
                    DirectChatDetailView(peer: KinnectUser.from(UIReviewFixture.peerUserDict))
                }
            )
        case "group-chat-detail":
            return AnyView(
                NavigationStack {
                    GroupChatDetailView(group: ChatGroupItem.from(UIReviewFixture.fixtureGroupDict), onLeftGroup: {})
                }
            )
        case "call-overlay", "call-incoming", "call-outgoing", "call-connected":
            NativeWebRTCManager.shared.activeCall = ActiveCallSession(
                callId: "fixture_call_1",
                peerUser: KinnectUser.from(UIReviewFixture.peerUserDict),
                mode: "video",
                isIncoming: screenName != "call-outgoing",
                state: screenName == "call-connected" ? .connected
                    : screenName == "call-outgoing" ? .dialingOutgoing : .ringingIncoming,
                connectedAt: screenName == "call-connected" ? Date().addingTimeInterval(-85) : nil
            )
            return AnyView(
                CallOverlayView()
            )
        case "shorts-comments":
            return AnyView(
                ShortCommentsSheet(short: ShortItem.from([
                    "id": "fixture_short_1",
                    "title": "Khoảnh khắc hoàng hôn Hà Nội",
                    "videoUrl": samplePlayableVideoURL()?.absoluteString ?? "",
                    "author": UIReviewFixture.peerUserDict,
                    "likesCount": 142,
                    "commentsCount": 18,
                    "liked": true
                ]), onUpdated: {})
            )
        case "forward-message":
            return AnyView(
                NavigationStack {
                    ForwardMessageSheet(text: "Tin nhắn chia sẻ từ Bảng tin Kinnect", imageUrl: "")
                }
            )

        // MARK: - Profile & Settings
        case "profile":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: .profile) {
                    ProfileView(onBack: {}, onOpenWallet: {}, onOpenFriends: {}, onOpenStore: {})
                }
            )
        case "profile-posts":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: .profile) {
                    ProfileView(onBack: {}, onOpenWallet: {}, onOpenFriends: {}, onOpenStore: {}, initialTab: .posts)
                }
            )
        case "profile-albums":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: .profile) {
                    ProfileView(onBack: {}, onOpenWallet: {}, onOpenFriends: {}, onOpenStore: {}, initialTab: .albums)
                }
            )
        case "profile-videos":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: .profile) {
                    ProfileView(onBack: {}, onOpenWallet: {}, onOpenFriends: {}, onOpenStore: {}, initialTab: .videos)
                }
            )
        case "profile-edit":
            return AnyView(
                EditProfileSheet(onSaved: {})
            )
        case "profile-public-album":
            return AnyView(
                NavigationStack {
                    PublicAlbumManageSheet(posts: UIReviewFixture.mockPosts(), onRefresh: {})
                }
            )
        case "profile-private-album":
            return AnyView(
                NavigationStack {
                    PrivateAlbumManageSheet(
                        photos: .constant(UIReviewFixture.mockPrivatePhotos()),
                        requests: .constant(UIReviewFixture.mockPrivateRequests()),
                        onRefresh: {}
                    )
                }
            )
        case "profile-sessions":
            return AnyView(
                ActiveSessionsSheet()
            )
        case "account-menu", "me-menu":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: .profile) {
                    AccountMenuView(onOpenProfile: {}, onOpenStore: {}, onOpenWallet: {}, onOpenFriends: {}, onBack: {})
                }
            )

        // MARK: - Friends
        case "friends":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: .friends) {
                    FriendsView(initialTab: .friends, onBack: {})
                }
            )
        case "friends-requests":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: .friends) {
                    FriendsView(initialTab: .requests, onBack: {})
                }
            )
        case "friends-suggestions":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: .friends) {
                    FriendsView(initialTab: .friends, onBack: {})
                }
            )

        // MARK: - Notifications
        case "notifications":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: .notifications) {
                    NotificationsView(onBack: {}, onOpenFriends: {}, onOpenMessages: {})
                }
            )

        // MARK: - Wallet & Store
        case "wallet", "wallet-topup":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: .wallet) {
                    WalletView(onBack: {}, onOpenStore: {})
                }
            )
        case "store", "wallet-packages", "store-packages":
            return AnyView(
                UIReviewMainShell(selectedTab: .feed, activeTopSection: .store) {
                    StoreView(onBack: {}, onOpenWallet: {})
                }
            )

        // MARK: - Modals / Sheets
        case "privacy-consent":
            return AnyView(
                PrivacyConsentSheet(
                    request: PrivacyConsentRequest(
                        version: "2026.11",
                        notice: "Chính sách quyền riêng tư và điều khoản dịch vụ Kinnect. Cam kết bảo mật theo tiêu chuẩn Apple và pháp luật Việt Nam."
                    ),
                    recordOnServer: false,
                    onAccepted: {}
                )
            )
        case "delete-account":
            return AnyView(DeleteAccountConfirmationSheet())
        case "ugc-report":
            return AnyView(
                UGCReportSheet(
                    context: UGCReportContext(
                        targetType: "user",
                        targetId: "u2",
                        targetUserId: "u2",
                        targetTitle: "Lê Hoàng Nam"
                    )
                )
            )
        case "change-password":
            return AnyView(ChangePasswordSheet())
        case "blocked-users":
            return AnyView(BlockedUsersSheet())
        case "privacy-settings":
            return AnyView(PrivacySettingsSheet())
        case "support":
            return AnyView(SupportContactSheet())
        case "support-chat":
            return AnyView(DirectChatDetailView(peer: KinnectUser.from(peerUserDict)))
        case "admin":
            return AnyView(AdminConsoleView())

        default:
            return AnyView(RootMainView())
        }
    }
}

/// Real app chrome (`KinnectTopBar` + Content + `KinnectBottomBar`) for UI Review parity captures
/// so iOS main screens match Android's 1:1 shell layout without splash delay or NavigationStack drift.
private struct UIReviewMainShell<Content: View>: View {
    let selectedTab: KinnectNavTab
    let activeTopSection: KinnectTopSection?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            KinnectTopBar(
                appState: AppState.shared,
                activeTopSection: .constant(activeTopSection),
                onLogoTap: {}
            )

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            KinnectBottomBar(
                selectedTab: .constant(selectedTab),
                isTopSectionActive: activeTopSection != nil,
                onCreateTap: {}
            )
        }
        .background(KinnectTheme.background.ignoresSafeArea())
    }
}
#else
enum UIReviewFixture {
    static let activeScreen: String? = nil
    static let forceLightMode: Bool = false
    static let forceMaxDynamicType: Bool = false
    static let isEnabled: Bool = false
    static let allowsCapturePrompt: Bool = true
}
#endif
