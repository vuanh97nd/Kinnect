import AVFoundation
import AVKit
import CoreImage
import Foundation
import SwiftUI
import UIKit

/// Isolated UI review fixture mode activated ONLY when launched with `--ui-review-screen <name>`.
/// Clearly labeled as fixture data, never touches production servers, tokens, passwords, or real users.
enum UIReviewFixture {
    static var activeScreen: String? {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--ui-review-screen"), idx + 1 < args.count {
            return args[idx + 1]
        }
        return nil
    }

    static var forceLightMode: Bool {
        CommandLine.arguments.contains("--ui-review-light")
    }

    static var forceMaxDynamicType: Bool {
        CommandLine.arguments.contains("--ui-review-dynamictype-max")
    }

    static var isEnabled: Bool {
        activeScreen != nil
    }

    static var adminApiCalls = 0

    static func noteTransport(method: String, path: String) {
        let clean = path.components(separatedBy: "?").first ?? path
        if clean.hasPrefix("/api/admin") || clean == "/api/music" {
            adminApiCalls += 1
        }
        _ = method
    }

    static func forcedError(method: String, path: String) -> String? {
        let clean = path.components(separatedBy: "?").first ?? path
        switch activeScreen {
        case "privacy-save-error", "privacy-toggle-error", "dm-mode-error":
            if method == "PATCH" && clean == "/api/me" {
                return "Không lưu được lên máy chủ."
            }
        case "location-off-error":
            if method == "PATCH" && clean == "/api/me/location" {
                return "Không tắt được tìm quanh đây."
            }
        case "sessions-error":
            if clean == "/api/me/sessions" || clean == "/api/sessions" {
                return "Không tải được phiên đăng nhập."
            }
        case "admin-error":
            if clean.hasPrefix("/api/admin") || clean == "/api/music" {
                return "Không tải được dữ liệu quản trị."
            }
        default:
            break
        }
        return nil
    }

    static func delayNanoseconds(method: String, path: String) -> UInt64 {
        let clean = path.components(separatedBy: "?").first ?? path
        _ = method
        if activeScreen == "admin-loading" && (clean.hasPrefix("/api/admin") || clean == "/api/music") {
            return 8_000_000_000
        }
        if activeScreen == "sessions-loading" && (clean == "/api/me/sessions" || clean == "/api/sessions") {
            return 8_000_000_000
        }
        return 0
    }

    static func prefersEmpty(_ path: String) -> Bool {
        let clean = path.components(separatedBy: "?").first ?? path
        if activeScreen == "sessions-empty" && (clean == "/api/me/sessions" || clean == "/api/sessions") {
            return true
        }
        if activeScreen == "admin-empty" && (clean.hasPrefix("/api/admin") || clean == "/api/music") {
            return true
        }
        return false
    }

    static func writeDocument(_ name: String, _ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? data.write(to: dir.appendingPathComponent(name))
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
        "id": "fixture_user_me",
        "name": "Nguyễn Minh Anh",
        "handle": "minhanh",
        "email": "minhanh@kinnect.local",
        "bio": "Thiết kế giao diện & nhiếp ảnh đường phố • Sài Gòn",
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
        "identityPublic": true,
        "isPrivate": false
    ]

    static let peerUserDict: [String: Any] = [
        "id": "fixture_user_peer",
        "name": "Lê Hoàng Nam",
        "handle": "hoangnam",
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
        "id": "fixture_user_2",
        "name": "Trần Thanh Trúc",
        "handle": "thanhtruc",
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
        "id": "fixture_user_3",
        "name": "Phạm Minh Hoàng",
        "handle": "hoangpham",
        "bio": "Lập trình viên iOS & đam mê thiết kế UI • Đà Nẵng",
        "locationName": "Đà Nẵng",
        "avatarColor": "#3B82F6",
        "distanceKm": 12.4,
        "isFollowing": false,
        "isFriend": false
    ]

    static let fixtureGroupDict: [String: Any] = [
        "id": "fixture_group_1",
        "name": "Nhóm Thiết Kế Kinnect [Fixture]",
        "description": "Trao đổi giao diện iOS & Android",
        "avatarColor": "#6D4AFF",
        "membersCount": 4,
        "lastMessageText": "@Tất cả Tính năng nhắc tên Zalo đã sẵn sàng!",
        "unreadCount": 1,
        "members": [peerUserDict, secondPeerDict, thirdPeerDict]
    ]

    static func mockResponse(for path: String) -> [String: Any] {
        let cleanPath = path.components(separatedBy: "?").first ?? path
        if prefersEmpty(cleanPath) {
            switch cleanPath {
            case "/api/admin/reports":
                return ["reports": []]
            case "/api/admin/users":
                return ["users": []]
            case "/api/admin/economy":
                return ["version": 1, "config": ["giftPrices": [String: Int]()]]
            case "/api/admin/ai":
                return ["config": [String: Any]()]
            case "/api/music":
                return ["tracks": []]
            case "/api/sessions", "/api/me/sessions":
                return ["sessions": []]
            default:
                break
            }
        }

        switch cleanPath {
        case "/api/me":
            if let act = activeScreen, act.hasPrefix("auth") || act == "forgot-password" {
                return [:]
            }
            return ["user": currentUserDict]

        case "/api/posts":
            return [
                "posts": [
                    [
                        "id": "fixture_post_1",
                        "author": peerUserDict,
                        "text": "Hoàng hôn trên cầu Rồng chiều cuối tuần. Giao diện Kinnect iOS Native SwiftUI mới mượt mà và sắc nét!",
                        "category": "community",
                        "imageUrl": sampleImageDataURL,
                        "likesCount": 42,
                        "commentsCount": 8,
                        "liked": true,
                        "userReaction": "love",
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
                        "text": "Khoảnh khắc 24h [Fixture]",
                        "backgroundColor": "#7C3AED",
                        "viewed": false,
                        "viewsCount": 15,
                        "createdAt": "2026-11-07T01:20:00.000Z"
                    ],
                    [
                        "id": "fixture_story_2",
                        "author": secondPeerDict,
                        "text": "Cuối tuần vui vẻ [Fixture]",
                        "backgroundColor": "#EC4899",
                        "viewed": true,
                        "viewsCount": 9,
                        "createdAt": "2026-11-07T00:50:00.000Z"
                    ]
                ]
            ]

        case "/api/discover":
            let users: [[String: Any]] = [
                [
                    "id": "fixture_user_1",
                    "name": "Trần Hoàng Nam",
                    "handle": "hoangnam_dn",
                    "bio": "Thiết kế & Nhiếp ảnh",
                    "locationName": "Đà Nẵng",
                    "avatarColor": "#2563EB",
                    "age": 24,
                    "height": 175,
                    "weight": 68,
                    "gender": "Nam",
                    "orientation": "Gay / Đồng tính nam",
                    "communityRole": "Vers",
                    "distanceKm": 1.8,
                    "isFollowing": true,
                    "isFriend": true
                ],
                [
                    "id": "fixture_user_2",
                    "name": "Nguyễn Thị Thanh Trúc",
                    "handle": "thanhtruc_hn",
                    "bio": "Âm nhạc, du lịch & công nghệ",
                    "locationName": "Hà Nội",
                    "avatarColor": "#EC4899",
                    "age": 22,
                    "height": 162,
                    "weight": 48,
                    "gender": "Nữ",
                    "orientation": "Lesbian / Đồng tính nữ",
                    "communityRole": "Femme",
                    "distanceKm": 3.2,
                    "isFollowing": false,
                    "isFriend": false
                ],
                [
                    "id": "fixture_user_3",
                    "name": "Lê Văn Minh",
                    "handle": "minhle_sg",
                    "bio": "Kỹ sư phần mềm • Thể thao",
                    "locationName": "TP. Hồ Chí Minh",
                    "avatarColor": "#10B981",
                    "age": 26,
                    "height": 178,
                    "weight": 72,
                    "gender": "Phi nhị nguyên",
                    "orientation": "Queer",
                    "communityRole": "Androgynous",
                    "distanceKm": 4.5,
                    "isFollowing": true,
                    "isFriend": false
                ],
                [
                    "id": "fixture_user_4",
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
                    "id": "fixture_user_5",
                    "name": "Phạm Quốc Bảo",
                    "handle": "quocbao_ct",
                    "bio": "Kiến trúc sư • Cà phê",
                    "locationName": "Cần Thơ",
                    "avatarColor": "#8B5CF6",
                    "age": 28,
                    "height": 172,
                    "weight": 65,
                    "gender": "nam",
                    "distanceKm": 6.8,
                    "isFollowing": false,
                    "isFriend": true
                ],
                [
                    "id": "fixture_user_6",
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
                    "id": "fixture_user_7",
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
                    "id": "fixture_user_8",
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
                    "id": "fixture_user_9",
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
            return [
                "people": users,
                "users": users
            ]

        case "/api/shorts":
            let videoURL1 = samplePlayableVideoURL()?.absoluteString ?? ""
            let videoURL2 = sampleSecondPlayableVideoURL()?.absoluteString ?? ""
            return [
                "shorts": [
                    [
                        "id": "fixture_short_1",
                        "author": peerUserDict,
                        "title": "Dạo phố sáng cuối tuần [Fixture UI]",
                        "caption": "Video ngắn thử nghiệm bố cục Shorts trên iOS Simulator.",
                        "videoUrl": videoURL1,
                        "durationSec": 15,
                        "likesCount": 128,
                        "commentsCount": 14,
                        "liked": true,
                        "createdAt": "2026-11-07T01:10:00.000Z"
                    ],
                    [
                        "id": "fixture_short_2",
                        "author": peerUserDict,
                        "title": "Hoàng hôn bên sông Hàn [Fixture UI]",
                        "caption": "Clip cục bộ thứ 2 kiểm thử vuốt Shorts trên iOS Simulator.",
                        "videoUrl": videoURL2,
                        "durationSec": 12,
                        "likesCount": 256,
                        "commentsCount": 24,
                        "liked": false,
                        "createdAt": "2026-11-07T02:20:00.000Z"
                    ]
                ]
            ]

        case "/api/music":
            return [
                "tracks": [
                    ["file": "tiktok-01.mp3", "title": "LIỆU RẰNG · Remix DEMO", "artist": "Huy PT Remix", "url": "/music/tiktok-01.mp3"],
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
            return [
                "conversations": [
                    [
                        "user": peerUserDict,
                        "preview": "[Fixture UI] Hẹn gặp lúc 19h tối nay nhé!",
                        "unreadCount": 2
                    ],
                    [
                        "user": secondPeerDict,
                        "preview": "[Fixture UI] Đã gửi bộ icon mới cho iOS.",
                        "unreadCount": 0
                    ]
                ]
            ]

        case "/api/groups":
            return [
                "groups": [
                    [
                        "id": "fixture_group_1",
                        "name": "Nhóm Thiết Kế Kinnect [Fixture]",
                        "description": "Trao đổi giao diện iOS & Android",
                        "avatarColor": "#6D4AFF",
                        "membersCount": 6,
                        "lastMessageText": "Bộ 40 icon vector đã lên chuẩn 24pt!",
                        "unreadCount": 1
                    ]
                ]
            ]

        case "/api/friends":
            return ["friends": [peerUserDict]]

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
                        "text": "@Tất cả Chào cả nhóm! Đã kích hoạt tính năng nhắc thành viên phong cách Zalo và gọi thoại iOS HIG.",
                        "createdAt": "2026-11-07T01:30:00.000Z",
                        "seenCount": 4
                    ],
                    [
                        "id": "fixture_gmsg_2",
                        "groupId": "fixture_group_1",
                        "sender": currentUserDict,
                        "text": "@minhanh_demo Cảm ơn bạn! Đã đồng bộ chuẩn 100% Android 1.2.12.",
                        "createdAt": "2026-11-07T01:31:00.000Z",
                        "seenCount": 3
                    ],
                    [
                        "id": "fixture_gmsg_3",
                        "groupId": "fixture_group_1",
                        "sender": peerUserDict,
                        "text": "Bản thiết kế và tài liệu thông số kỹ thuật đính kèm:",
                        "attachment": [
                            "name": "Kinnect-Thong-So-Ky-Thuat.pdf",
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
                        "text": "Ảnh chụp mẫu giao diện từ máy thật:",
                        "imageUrl": sampleImageDataURL,
                        "createdAt": "2026-11-07T01:33:00.000Z",
                        "seenCount": 3
                    ]
                ]
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
                        "text": "@minhanh_demo Cảm ơn bạn nhé! Chụp bằng camera góc rộng 1x của Kinnect Studio.",
                        "createdAt": "2026-11-07T01:36:00.000Z",
                        "liked": true,
                        "likesCount": 2
                    ]
                ]
            ]

        case "/api/friend-suggestions":
            return ["suggestions": [secondPeerDict]]

        case "/api/notifications":
            return [
                "notifications": [
                    [
                        "id": "fixture_notif_1",
                        "type": "like",
                        "actor": peerUserDict,
                        "preview": "[Fixture UI] Hoàng Nam đã bày tỏ cảm xúc với bài viết của bạn.",
                        "read": false,
                        "createdAt": "2026-11-07T01:40:00.000Z"
                    ],
                    [
                        "id": "fixture_notif_2",
                        "type": "friend_request",
                        "actor": secondPeerDict,
                        "preview": "[Fixture UI] Thanh Trúc đã gửi lời mời kết bạn.",
                        "read": true,
                        "createdAt": "2026-11-07T00:30:00.000Z"
                    ]
                ]
            ]

        case "/api/wallet":
            return [
                "wallet": [
                    "availableBalance": 12500,
                    "purchasedCoins": 8500,
                    "giftedCoins": 4000,
                    "trialCoins": 4000,
                    "earnedBalance": 15000,
                    "spentBalance": 2500,
                    "currencyLabel": "Xu Kinnect"
                ],
                "entries": [
                    [
                        "id": "fixture_tx_1",
                        "title": "Nhận xu thử nghiệm [Fixture UI]",
                        "note": "Kiểm tra hiển thị icon xu có chữ K không cắt số",
                        "amount": 5000,
                        "direction": "credit",
                        "createdAt": "2026-11-07T01:00:00.000Z"
                    ],
                    [
                        "id": "fixture_tx_2",
                        "title": "Đổi khung Avatar Ánh Sao [Fixture UI]",
                        "note": "Gói trang trí hồ sơ",
                        "amount": 500,
                        "direction": "debit",
                        "createdAt": "2026-11-06T22:00:00.000Z"
                    ]
                ]
            ]

        case "/api/store":
            return [
                "ownedPackages": ["style_aurora"],
                "liveTheme": "",
                "membership": "",
                "packages": [
                    [
                        "id": "style_aurora",
                        "title": "Cực quang",
                        "subtitle": "Sắc màu kết nối · Dải cực quang mềm, biểu trưng cho sự cởi mở",
                        "category": "style",
                        "priceCoins": 500,
                        "badgeText": "HOT",
                        "accentColor": "#8B5CF6",
                        "owned": true,
                        "equipped": true
                    ],
                    [
                        "id": "style_galaxy",
                        "title": "Galaxy",
                        "subtitle": "Vũ trụ của bạn · Chiều sâu bầu trời đêm, dành cho cá tính riêng",
                        "category": "style",
                        "priceCoins": 800,
                        "badgeText": "VIP",
                        "accentColor": "#312E81",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "style_neon",
                        "title": "Neon",
                        "subtitle": "Dấu ấn thành thị · Năng lượng trẻ, đường sáng tím và cyan",
                        "category": "style",
                        "priceCoins": 300,
                        "badgeText": "MỚI",
                        "accentColor": "#7C3AED",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "style_ice",
                        "title": "Băng hà",
                        "subtitle": "Tinh thể băng xanh, cảm giác lạnh và sạch",
                        "category": "style",
                        "priceCoins": 600,
                        "badgeText": "EPIC",
                        "accentColor": "#38BDF8",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "style_ruby",
                        "title": "Hồng ngọc",
                        "subtitle": "Sắc ruby sâu, điểm nhấn quyến rũ",
                        "category": "style",
                        "priceCoins": 650,
                        "badgeText": "EPIC",
                        "accentColor": "#BE123C",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "style_forest",
                        "title": "Rừng thẳm",
                        "subtitle": "Xanh lá trầm, gần gũi thiên nhiên",
                        "category": "style",
                        "priceCoins": 350,
                        "badgeText": "RARE",
                        "accentColor": "#047857",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "style_paper",
                        "title": "Giấy mỹ thuật",
                        "subtitle": "Kem và mực, tối giản như trang giấy",
                        "category": "style",
                        "priceCoins": 300,
                        "badgeText": "RARE",
                        "accentColor": "#D6D3D1",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "style_ember",
                        "title": "Lửa trại",
                        "subtitle": "Hổ phách và đỏ than, ấm áp",
                        "category": "style",
                        "priceCoins": 900,
                        "badgeText": "LEGENDARY",
                        "accentColor": "#F59E0B",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "live_chill",
                        "title": "Live Chill",
                        "subtitle": "Không gian thư giãn · Sắc biển dịu khi trò chuyện",
                        "category": "live",
                        "priceCoins": 500,
                        "badgeText": "HOT",
                        "accentColor": "#0D9488",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "live_gaming",
                        "title": "Live Gaming",
                        "subtitle": "Sân khấu trận đấu · Đường nét góc cạnh chuyên nghiệp",
                        "category": "live",
                        "priceCoins": 800,
                        "badgeText": "EPIC",
                        "accentColor": "#4F46E5",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "live_spotlight",
                        "title": "Live Spotlight",
                        "subtitle": "Bạn là tâm điểm · Ánh đèn sân khấu và sắc vàng ấm",
                        "category": "live",
                        "priceCoins": 1200,
                        "badgeText": "VIP",
                        "accentColor": "#A16207",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "live_game_30",
                        "title": "Live Game 30 ngày",
                        "subtitle": "Phát màn hình game, bình luận nổi và trả lời",
                        "category": "live",
                        "priceCoins": 490,
                        "badgeText": "PRO",
                        "accentColor": "#6D28D9",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "gift_love",
                        "title": "Bộ Quà Yêu Thương",
                        "subtitle": "Bộ 6 hoa hồng 3D độc quyền gửi tặng phòng Live",
                        "category": "gifts",
                        "priceCoins": 300,
                        "badgeText": "HOT",
                        "accentColor": "#DB2777",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "gift_speed",
                        "title": "Bộ Quà Tốc Độ",
                        "subtitle": "Bộ siêu xe & sao băng 3D hiệu ứng sân khấu",
                        "category": "gifts",
                        "priceCoins": 1000,
                        "badgeText": "EPIC",
                        "accentColor": "#2563EB",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "gift_royal",
                        "title": "Bộ Quà Hoàng Gia",
                        "subtitle": "Bộ lâu đài & vương miện 3D đỉnh cao phòng Live",
                        "category": "gifts",
                        "priceCoins": 2000,
                        "badgeText": "VIP",
                        "accentColor": "#7E22CE",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "member_plus",
                        "title": "Hội Viên Plus",
                        "subtitle": "Huy hiệu thành viên Plus trên hồ sơ và phòng Live",
                        "category": "member",
                        "priceCoins": 490,
                        "badgeText": "PLUS",
                        "accentColor": "#4338CA",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "member_creator",
                        "title": "Hội Viên Creator",
                        "subtitle": "Đặc quyền sáng tạo nội dung & huy hiệu Creator nổi bật",
                        "category": "member",
                        "priceCoins": 990,
                        "badgeText": "CREATOR",
                        "accentColor": "#C026D3",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "studio_video_30",
                        "title": "Studio Video Pro 30 ngày",
                        "subtitle": "Mở khóa toàn bộ hiệu ứng dựng phim Pro & xuất HD không watermark",
                        "category": "studio",
                        "priceCoins": 490,
                        "badgeText": "PRO",
                        "accentColor": "#7C3AED",
                        "owned": false,
                        "equipped": false
                    ],
                    [
                        "id": "studio_photo_30",
                        "title": "Studio Ảnh Pro 30 ngày",
                        "subtitle": "Bộ lọc màu điện ảnh & công cụ chỉnh ảnh cao cấp",
                        "category": "studio",
                        "priceCoins": 490,
                        "badgeText": "PRO",
                        "accentColor": "#DB2777",
                        "owned": false,
                        "equipped": false
                    ]
                ],
                "products": [
                    [
                        "id": "vn.kinnect.coins.100",
                        "title": "Gói 100 Xu Kinnect",
                        "description": "Nạp 100 xu vào số dư tài khoản Kinnect",
                        "priceLabel": "10.000 ₫",
                        "coins": 100
                    ],
                    [
                        "id": "vn.kinnect.coins.500",
                        "title": "Gói 500 Xu Kinnect",
                        "description": "Nạp 500 xu vào số dư tài khoản Kinnect",
                        "priceLabel": "50.000 ₫",
                        "coins": 500
                    ],
                    [
                        "id": "vn.kinnect.coins.1000",
                        "title": "Gói 1.000 Xu Kinnect",
                        "description": "Nạp 1.000 xu vào số dư tài khoản Kinnect",
                        "priceLabel": "100.000 ₫",
                        "coins": 1000
                    ],
                    [
                        "id": "vn.kinnect.coins.2000",
                        "title": "Gói 2.000 Xu Kinnect",
                        "description": "Nạp 2.000 xu vào số dư tài khoản Kinnect",
                        "priceLabel": "200.000 ₫",
                        "coins": 2000
                    ],
                    [
                        "id": "vn.kinnect.coins.5000",
                        "title": "Gói 5.000 Xu Kinnect",
                        "description": "Nạp 5.000 xu vào số dư tài khoản Kinnect",
                        "priceLabel": "500.000 ₫",
                        "coins": 5000
                    ],
                    [
                        "id": "vn.kinnect.coins.10000",
                        "title": "Gói 10.000 Xu Kinnect",
                        "description": "Nạp 10.000 xu vào số dư tài khoản Kinnect",
                        "priceLabel": "1.000.000 ₫",
                        "coins": 10000
                    ]
                ]
            ]

        case "/api/live/rooms":
            return [
                "rooms": [
                    [
                        "id": "fixture_live_1",
                        "title": "Giao lưu âm nhạc tối cuối tuần",
                        "topic": "Trò chuyện & kết nối bạn mới",
                        "liveMode": "chat",
                        "gameTitle": "",
                        "hostUserId": "fixture_user_peer",
                        "hostName": "Lê Hoàng Nam",
                        "hostAvatarColor": "#2563EB",
                        "viewerCount": 64
                    ],
                    [
                        "id": "fixture_live_2",
                        "title": "Leo rank Liên Quân cùng team",
                        "topic": "Chơi game trực tiếp",
                        "liveMode": "game",
                        "gameTitle": "Liên Quân Mobile",
                        "hostUserId": "fixture_user_2",
                        "hostName": "Trần Thanh Trúc",
                        "hostAvatarColor": "#EC4899",
                        "viewerCount": 142
                    ]
                ]
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
                        "label": "iPhone 16 Pro",
                        "expires": 1794528000000,
                        "userAgent": "iPhone 16 Pro • iOS 18.2 (Thiết bị hiện tại)",
                        "deviceName": "iPhone 16 Pro (Thiết bị này)",
                        "ip": "127.0.0.1",
                        "current": true,
                        "lastActive": "Vừa xong"
                    ],
                    [
                        "id": "fixture_sess_2",
                        "label": "iPad Pro 11-inch",
                        "expires": 1791936000000,
                        "userAgent": "iPad Pro 11-inch • iPadOS 18.2",
                        "deviceName": "iPad Pro 11-inch",
                        "ip": "192.168.1.15",
                        "current": false,
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
                        "userId": "fixture_user_peer",
                        "hidden": false
                    ]
                ]]
            ]

        case "/api/admin/users":
            return [
                "users": [
                    ["id": "fixture_user_peer", "username": "hoangnam", "role": "member", "suspended": 0],
                    ["id": "fixture_user_me", "username": "minhanh", "role": "admin", "suspended": 0]
                ]
            ]

        case "/api/admin/moderate":
            return ["ok": true]

        case "/api/admin/economy":
            return [
                "version": 1,
                "config": [
                    "giftPrices": [
                        "rose": 50,
                        "star": 100,
                        "crown": 200
                    ]
                ]
            ]

        case "/api/admin/ai":
            return [
                "config": [
                    "ready": false,
                    "queue": 0,
                    "failed": 0
                ]
            ]

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
                            "fromUserId": "fixture_user_peer",
                            "toUserId": "fixture_user_me",
                            "text": "[Fixture UI] Chào Minh Anh! Giao diện chat mới đưa nội dung lên trên, hàng dưới gồm giờ + seen + cảm xúc + menu 3 chấm nhìn rất gọn.",
                            "imageUrl": "",
                            "createdAt": "2026-11-07T01:35:00.000Z",
                            "deliveredAt": "2026-11-07T01:35:01.000Z",
                            "seenAt": "2026-11-07T01:35:10.000Z",
                            "isSeen": true
                        ],
                        [
                            "id": "fixture_msg_2",
                            "fromUserId": "fixture_user_me",
                            "toUserId": "fixture_user_peer",
                            "text": "[Fixture UI] Đúng rồi, nút gọi thoại/video và menu 3 chấm đều có nền trong suốt, vùng chạm 44pt chuẩn iOS!",
                            "imageUrl": "",
                            "createdAt": "2026-11-07T01:36:00.000Z",
                            "deliveredAt": "2026-11-07T01:36:01.000Z",
                            "seenAt": "2026-11-07T01:36:05.000Z",
                            "isSeen": true
                        ],
                        [
                            "id": "fixture_msg_3",
                            "fromUserId": "fixture_user_peer",
                            "toUserId": "fixture_user_me",
                            "text": "Tài liệu so sánh tính năng Android & iOS v1.2.12:",
                            "attachment": [
                                "name": "Bao-Cao-So-Sanh-Android-iOS.pdf",
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
                            "fromUserId": "fixture_user_me",
                            "toUserId": "fixture_user_peer",
                            "text": "Ảnh chụp màn hình Studio Pro:",
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
                author: KinnectUser.from(currentUserDict),
                text: "Hoàng hôn trên cầu Rồng. Album ảnh công khai Kinnect iOS.",
                imageUrl: sampleImageDataURL,
                category: "community",
                createdAt: "2026-11-07T01:30:00.000Z",
                likesCount: 42,
                commentsCount: 8,
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
        return makeSampleVideoURL(fileName: "ui_review_sample_shorts.mp4", variant: 0)
    }

    static func sampleSecondPlayableVideoURL() -> URL? {
        return makeSampleVideoURL(fileName: "ui_review_sample_shorts_2.mp4", variant: 1)
    }

    private static func makeSampleVideoURL(fileName: String, variant: Int) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let movieURL = tempDir.appendingPathComponent(fileName)
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
                    if variant == 1 {
                        ctx.setFillColor(red: 0.05, green: 0.36 + 0.28 * progress, blue: 0.42, alpha: 1.0)
                        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

                        let circleY = CGFloat(height) * (0.65 - 0.35 * progress)
                        ctx.setFillColor(red: 0.98, green: 0.80, blue: 0.20, alpha: 0.92)
                        ctx.fill(CGRect(x: CGFloat(width)/2 - 70, y: circleY - 70, width: 140, height: 140))
                    } else {
                        ctx.setFillColor(red: 0.12 + 0.35 * progress, green: 0.08 + 0.15 * progress, blue: 0.42, alpha: 1.0)
                        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

                        let circleY = CGFloat(height) * (0.3 + 0.4 * progress)
                        ctx.setFillColor(red: 0.85, green: 0.35, blue: 0.95, alpha: 0.85)
                        ctx.fillEllipse(in: CGRect(x: CGFloat(width)/2 - 60, y: circleY - 60, width: 120, height: 120))
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

    /// Creates the appropriate SwiftUI view for the given screen name.
    /// Used by SceneDelegate when --ui-review-screen argument is provided.
    @MainActor
    static func makeView(for screenName: String) -> AnyView {
        switch screenName {
        // MARK: - Auth Screens
        case "auth-welcome", "auth":
            return AnyView(AuthView(initialStage: .welcome))
        case "auth-login", "auth-login-populated", "auth-login-error", "auth-login-keyboard", "auth-login-password-keyboard", "auth-login-en":
            return AnyView(AuthView(initialStage: .login))
        case "auth-register":
            return AnyView(AuthView(initialStage: .register))
        case "auth-reset", "auth-forgot", "forgot-password":
            return AnyView(AuthView(initialStage: .forgotPassword))

        // MARK: - Main Tabs (5 tabs)
        case "feed":
            return AnyView(
                NavigationStack {
                    FeedView(onOpenCamera: {}, onOpenFriends: {})
                        .toolbar {
                            RootMainView.headerLeadingLogoStatic()
                            RootMainView.headerTrailingButtonsStatic()
                        }
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                }
            )
        case "discover":
            return AnyView(
                NavigationStack {
                    DiscoverView(onOpenCamera: {})
                        .toolbar {
                            RootMainView.headerLeadingLogoStatic()
                            RootMainView.headerTrailingButtonsStatic()
                        }
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                }
            )
        case "create", "camera-studio":
            return AnyView(
                NavigationStack {
                    CameraStudioView()
                        .toolbar {
                            RootMainView.headerLeadingLogoStatic()
                            RootMainView.headerTrailingButtonsStatic()
                        }
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                }
            )
        case "camera-studio-edit", "camera-studio-video-edit":
            return AnyView(
                CameraStudioView()
            )
        case "camera-studio-video":
            return AnyView(
                NavigationStack {
                    CameraStudioView(initialMode: .video)
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Video")
                        .navigationBarTitleDisplayMode(.large)
                }
            )
        case "studio-pro-sheet":
            return AnyView(
                NavigationStack {
                    StudioProSheet(appliedEffect: .constant("Cinematic Teal & Orange"), onApply: { _ in })
                }
            )
        case "video", "shorts", "live":
            // Exercise the real main container so header/safe-area regressions
            // are visible in simulator captures.
            return AnyView(RootMainView())
        case "live-room":
            return AnyView(
                LiveStreamView(onOpenWallet: {})
            )

        // MARK: - Messages & Chats
        case "messages":
            return AnyView(
                NavigationStack {
                    MessagesView(initialScope: .direct, onOpenFriends: {})
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Tin nhắn")
                        .navigationBarTitleDisplayMode(.large)
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
                    : screenName == "call-outgoing" ? .dialingOutgoing : .ringingIncoming
            )
            return AnyView(
                CallOverlayView()
            )
        case "feed-comments":
            return AnyView(
                PostCommentsSheet(post: UIReviewFixture.mockPosts()[0], onChanged: {})
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
                NavigationStack {
                    ProfileView(onOpenWallet: {}, onOpenFriends: {})
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Hồ sơ")
                        .navigationBarTitleDisplayMode(.large)
                }
            )
        case "profile-posts":
            return AnyView(
                NavigationStack {
                    ProfileView(onOpenWallet: {}, onOpenFriends: {}, initialTab: .posts)
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Bài viết")
                        .navigationBarTitleDisplayMode(.large)
                }
            )
        case "profile-albums":
            return AnyView(
                NavigationStack {
                    ProfileView(onOpenWallet: {}, onOpenFriends: {}, initialTab: .albums)
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Album ảnh")
                        .navigationBarTitleDisplayMode(.large)
                }
            )
        case "profile-videos":
            return AnyView(
                NavigationStack {
                    ProfileView(onOpenWallet: {}, onOpenFriends: {}, initialTab: .videos)
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Video")
                        .navigationBarTitleDisplayMode(.large)
                }
            )
        case "profile-edit":
            return AnyView(
                NavigationStack {
                    EditProfileSheet(onSaved: {})
                }
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
                NavigationStack {
                    ActiveSessionsSheet()
                }
            )
        case "account-menu", "me-menu":
            return AnyView(
                NavigationStack {
                    AccountMenuView(onOpenProfile: {}, onOpenWallet: {}, onOpenFriends: {})
                }
            )

        // MARK: - Friends
        case "friends":
            return AnyView(
                NavigationStack {
                    FriendsView(initialTab: .friends)
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Bạn bè")
                        .navigationBarTitleDisplayMode(.large)
                }
            )
        case "friends-requests":
            return AnyView(
                NavigationStack {
                    FriendsView(initialTab: .requests)
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Lời mời kết bạn")
                        .navigationBarTitleDisplayMode(.large)
                }
            )
        case "friends-suggestions":
            return AnyView(
                NavigationStack {
                    FriendsView(initialTab: .friends)
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Gợi ý kết bạn")
                        .navigationBarTitleDisplayMode(.large)
                }
            )

        // MARK: - Notifications
        case "notifications":
            return AnyView(
                NavigationStack {
                    NotificationsView()
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Thông báo")
                        .navigationBarTitleDisplayMode(.large)
                }
            )

        // MARK: - Wallet & Store
        case "wallet":
            return AnyView(
                NavigationStack {
                    WalletView()
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Ví Kinnect")
                        .navigationBarTitleDisplayMode(.large)
                }
            )
        case "store", "wallet-packages", "store-packages":
            return AnyView(
                NavigationStack {
                    StoreView()
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Cửa hàng Kinnect")
                        .navigationBarTitleDisplayMode(.large)
                }
            )
        case "wallet-topup":
            return AnyView(
                NavigationStack {
                    WalletView()
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Nạp xu Kinnect")
                        .navigationBarTitleDisplayMode(.large)
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
                        targetId: "fixture_user_peer",
                        targetUserId: "fixture_user_peer",
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
        case "gift-drawer":
            return AnyView(ReviewGiftDrawer())
        case "music-picker":
            return AnyView(ReviewMusicPicker())
        case "password-spy":
            return AnyView(PasswordSpyProbe())
        case "persist-write":
            return AnyView(PersistenceProbe(writing: true))
        case "persist-read":
            return AnyView(PersistenceProbe(writing: false))
        case "shorts-telemetry":
            return AnyView(ShortsTelemetryProbe())
        case "shorts-avplayer":
            return AnyView(ShortsAVPlayerProbe())
        case "shorts-real-swipe":
            return AnyView(ShortsVideoView())
        case "gift-catalog-v1":
            return AnyView(GiftCatalogVersionProbe())
        #if DEBUG
        case "swift-contracts-harness":
            return AnyView(SwiftContractsHarnessProbe())
        #endif
        case "admin-denied":
            return AnyView(AdminConsoleView())
        case "admin-loading", "admin-empty", "admin-error":
            return AnyView(AdminConsoleView())
        case "privacy-save-error":
            return AnyView(PrivacySettingsSheet())
        case "privacy-toggle-error", "dm-mode-error", "location-off-error":
            return AnyView(PrivacySettingsView())
        case "sessions-loading", "sessions-error", "sessions-empty":
            return AnyView(NavigationStack { ActiveSessionsSheet() })

        default:
            return AnyView(RootMainView())
        }
    }
}

private struct PasswordSpyProbe: View {
    @State private var lines: [String] = ["Đang kiểm tra..."]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Kiểm tra mật khẩu")
                    .font(KinnectTheme.sectionTitle)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(KinnectTheme.caption)
                        .foregroundColor(KinnectTheme.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(KinnectTheme.background)
        .task { runMatrix() }
    }

    private func runMatrix() {
        PasswordTransportSpy.reset()
        let cases: [(String, String, String, String)] = [
            ("", "abcdef", "abcdef", "current rỗng"),
            ("current-secret", "abcde", "abcde", "next 5"),
            ("current-secret", "abcdef", "abcdef", "next 6"),
            ("current-secret", "abcdefg", "abcdefg", "next 7"),
            ("current-secret", "abcdef", "", "retype rỗng"),
            ("current-secret", "abcdef", "abcdefX", "retype lệch")
        ]
        var shown: [String] = []
        var report: [[String: Any]] = []
        for item in cases {
            let decision = PasswordChangeValidation.evaluate(current: item.0, next: item.1, confirm: item.2)
            if decision.sendsToServer {
                PasswordTransportSpy.record(current: item.0, next: item.1)
            }
            shown.append("\(item.3): post=\(decision.sendsToServer ? "có" : "không")")
            report.append([
                "label": item.3,
                "nextCount": item.1.count,
                "sendsToServer": decision.sendsToServer,
                "message": decision.message ?? ""
            ])
        }
        shown.append("Đã ghi \(PasswordTransportSpy.attempts.count) lần, không gửi mạng.")
        lines = shown
        let payload: [String: Any] = [
            "attempts": PasswordTransportSpy.attempts.count,
            "cases": report
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: dir.appendingPathComponent("password-spy.json"))
        }
    }
}

private struct PersistenceProbe: View {
    let writing: Bool
    @State private var text = "Đang đọc..."

    var body: some View {
        Text(text)
            .font(KinnectTheme.body)
            .foregroundColor(KinnectTheme.textPrimary)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(KinnectTheme.background)
            .task {
                if writing {
                    UserDefaults.standard.set("en", forKey: AppLanguageStore.defaultsKey)
                    KinnectNotificationPrefs.set("messages", false)
                    text = "Đã ghi ngôn ngữ en và tắt thông báo tin nhắn trên máy."
                } else {
                    let lang = UserDefaults.standard.string(forKey: AppLanguageStore.defaultsKey) ?? "missing"
                    let messages = KinnectNotificationPrefs.isOn("messages")
                    text = "Đọc lại sau khi tắt app: ngôn ngữ \(lang). Thông báo tin nhắn \(messages ? "bật" : "tắt")."
                }
                let lang = UserDefaults.standard.string(forKey: AppLanguageStore.defaultsKey) ?? "missing"
                let messages = KinnectNotificationPrefs.isOn("messages")
                let payload: [String: Any] = [
                    "writing": writing,
                    "language": lang,
                    "messages": messages,
                    "languageKey": AppLanguageStore.defaultsKey,
                    "messagesKey": "kinnect_notifications.messages"
                ]
                if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
                   let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let name = writing ? "persist-write.json" : "persist-read.json"
                    try? data.write(to: dir.appendingPathComponent(name))
                }
            }
    }
}

private struct ShortsTelemetryProbe: View {
    @State private var lines: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Shorts telemetry")
                    .font(KinnectTheme.sectionTitle)
                ForEach(lines, id: \.self) { line in
                    Text(line).font(KinnectTheme.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(KinnectTheme.background)
        .task { runSequence() }
    }

    private func runSequence() {
        var state = ShortsPlaybackState(index: 0, userPaused: false, muted: false)
        var shown: [String] = []
        func note(_ line: String) { shown.append(line); lines = shown }
        note("start index=\(state.index) playing=\(state.playing) muted=\(state.muted)")
        state.togglePause()
        note("pause index=\(state.index) playing=\(state.playing)")
        state.toggleMute()
        note("mute giữ pause index=\(state.index) playing=\(state.playing) muted=\(state.muted)")
        state.togglePause()
        note("resume index=\(state.index) playing=\(state.playing) muted=\(state.muted)")
        state.swipe(to: 1)
        note("swipe index=\(state.index) playing=\(state.playing) muted=\(state.muted)")
        let payload: [String: Any] = ["lines": shown]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: dir.appendingPathComponent("shorts-telemetry.json"))
        }
    }
}

private struct ShortsAVPlayerProbe: View {
    @State private var lines: [String] = ["Đang mở video mẫu trên máy."]
    @State private var player: AVPlayer?
    @State private var frameImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
            } else {
                ProgressView("Đang tạo video mẫu.")
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
            if let frameImage {
                Image(uiImage: frameImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .accessibilityLabel("Khung điểm ảnh đã lấy từ video")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(KinnectTheme.caption)
                            .foregroundColor(KinnectTheme.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KinnectTheme.background)
        .task { await run() }
    }

    private func run() async {
        guard let url = UIReviewFixture.samplePlayableVideoURL() else {
            publish(lines: ["video=missing"], clock: false, buffer: false, frame: false, width: 0, height: 0, bufferTime: 0, probeSwitch: false, held: false, advanced: false, playTime: 0, pauseRate: 0, muteRate: 0, red: 0, green: 0, blue: 0, pixelProof: false, secondBuffer: BufferSample())
            return
        }
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        item.add(output)
        let next = AVPlayer(playerItem: item)
        next.isMuted = false
        player = next
        let ready = await waitReady(item)
        await next.seek(to: .zero)
        next.play()
        try? await Task.sleep(nanoseconds: 450_000_000)
        let playTime = seconds(next.currentTime())
        let playRate = Double(next.rate)
        next.pause()
        let pauseTime = seconds(next.currentTime())
        let pauseRate = Double(next.rate)
        try? await Task.sleep(nanoseconds: 150_000_000)
        next.isMuted = true
        try? await Task.sleep(nanoseconds: 150_000_000)
        let muteTime = seconds(next.currentTime())
        let muteRate = Double(next.rate)
        let held = muteRate == 0 && abs(muteTime - pauseTime) < 0.08
        next.play()
        try? await Task.sleep(nanoseconds: 400_000_000)
        let resumeTime = seconds(next.currentTime())
        let resumeRate = Double(next.rate)
        let clock = ready && playTime > 0.05
        let advanced = resumeTime > muteTime + 0.05
        let pixel = await sampleBuffer(output, item: item, fileName: "shorts-avplayer-frame.png", updatePreview: true)
        next.pause()
        let heldAfterPause = seconds(next.currentTime())
        let second = AVPlayerItem(url: url)
        let secondOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        second.add(secondOutput)
        let secondPlayer = AVPlayer(playerItem: second)
        secondPlayer.isMuted = true
        player = secondPlayer
        let secondReady = await waitReady(second)
        secondPlayer.play()
        try? await Task.sleep(nanoseconds: 450_000_000)
        let secondTime = seconds(secondPlayer.currentTime())
        let secondBuffer = await sampleBuffer(secondOutput, item: second, fileName: "shorts-avplayer-frame-second.png", updatePreview: false)
        let firstHeld = abs(seconds(next.currentTime()) - heldAfterPause) < 0.08 && next.rate == 0
        let probeSwitch = secondReady && secondTime > 0.05 && secondBuffer.received && firstHeld
        let pixelProof = pixel.received && pixel.width > 0 && pixel.height > 0 && pixel.time.isFinite && pixel.frameSaved
        publish(
            lines: [
                "file=\(url.lastPathComponent)",
                "status=\(ready ? "ready" : "not-ready")",
                String(format: "play time=%.3f rate=%.2f", playTime, playRate),
                String(format: "pause time=%.3f rate=%.2f", pauseTime, pauseRate),
                String(format: "mute-while-paused time=%.3f rate=%.2f muted=%@ held=%@", muteTime, muteRate, next.isMuted ? "yes" : "no", held ? "yes" : "no"),
                String(format: "resume time=%.3f rate=%.2f advanced=%@", resumeTime, resumeRate, advanced ? "yes" : "no"),
                "clockAdvanced=\(clock ? "yes" : "no")",
                String(format: "bufferReceived=%@ %dx%d time=%.3f", pixel.received ? "yes" : "no", pixel.width, pixel.height, pixel.time),
                "frameSaved=\(pixel.frameSaved ? "yes" : "no")",
                String(format: "cornerSample r=%d g=%d b=%d notProof=yes", pixel.red, pixel.green, pixel.blue),
                String(format: "probePlayerSwitch=%@ shortsSwipeClosed=no", probeSwitch ? "yes" : "no")
            ],
            clock: clock,
            buffer: pixel.received,
            frame: pixel.frameSaved,
            width: pixel.width,
            height: pixel.height,
            bufferTime: pixel.time,
            probeSwitch: probeSwitch,
            held: held,
            advanced: advanced,
            playTime: playTime,
            pauseRate: pauseRate,
            muteRate: muteRate,
            red: pixel.red,
            green: pixel.green,
            blue: pixel.blue,
            pixelProof: pixelProof,
            secondBuffer: secondBuffer
        )
    }

    private typealias BufferSample = UIReviewFixture.AVBufferSample

    private func sampleBuffer(_ output: AVPlayerItemVideoOutput, item: AVPlayerItem, fileName: String, updatePreview: Bool) async -> BufferSample {
        let (sample, rendered) = await UIReviewFixture.sampleVideoFrame(output: output, item: item, fileName: fileName)
        if updatePreview, let rendered {
            frameImage = rendered
        }
        return sample
    }

    private func waitReady(_ item: AVPlayerItem) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < 4 {
            if item.status == .readyToPlay { return true }
            if item.status == .failed { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return item.status == .readyToPlay
    }

    private func seconds(_ time: CMTime) -> Double {
        let value = time.seconds
        return value.isFinite ? value : 0
    }

    private func publish(
        lines shown: [String],
        clock: Bool,
        buffer: Bool,
        frame: Bool,
        width: Int,
        height: Int,
        bufferTime: Double,
        probeSwitch: Bool,
        held: Bool,
        advanced: Bool,
        playTime: Double,
        pauseRate: Double,
        muteRate: Double,
        red: Int,
        green: Int,
        blue: Int,
        pixelProof: Bool,
        secondBuffer: BufferSample
    ) {
        lines = shown
        let payload: [String: Any] = [
            "lines": shown,
            "clockAdvanced": clock,
            "bufferReceived": buffer,
            "bufferWidth": width,
            "bufferHeight": height,
            "bufferTimeSeconds": bufferTime,
            "frameFile": frame ? "shorts-avplayer-frame.png" : "",
            "pixelProof": pixelProof,
            "cornerSample": ["r": red, "g": green, "b": blue, "usedAsProof": false],
            "secondPlayerBuffer": [
                "received": secondBuffer.received,
                "width": secondBuffer.width,
                "height": secondBuffer.height,
                "timeSeconds": secondBuffer.time,
                "frameFile": secondBuffer.frameFile
            ],
            "probePlayerSwitch": probeSwitch,
            "shortsSwipeClosed": false,
            "swipeMethod": "second-avplayer-probe-only",
            "muteHeldPause": held,
            "resumedWhileMuted": advanced,
            "playTime": playTime,
            "pauseRate": pauseRate,
            "muteRate": muteRate
        ]
        UIReviewFixture.writeDocument("shorts-avplayer.json", payload)
    }
}

private struct GiftCatalogVersionProbe: View {
    @State private var lines: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Catalog quà phiên bản 1")
                    .font(KinnectTheme.sectionTitle)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(KinnectTheme.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(KinnectTheme.background)
        .task { run() }
    }

    private func run() {
        let parsed = LiveGiftCatalogAdapter.parse(Self.versionOnePayload)
        let rose = parsed.items.first { $0.id == "rose" }?.coins ?? -1
        let crown = parsed.items.first { $0.id == "crown" }?.coins ?? -1
        let star = parsed.items.first { $0.id == "star" }?.coins ?? -1
        let matched = parsed.version == 1 && parsed.items.count == 16 && rose == 50 && star == 100 && crown == 200
        lines = [
            "version=\(parsed.version)",
            "count=\(parsed.items.count)",
            "rose=\(rose)",
            "star=\(star)",
            "crown=\(crown)",
            "matchesIsolatedCatalog=\(matched ? "yes" : "no")",
            "adapterScope=parse-and-drawer",
            "drawerFixtureCrown=\(crown)",
            "drawerPriceParity=closed-isolated-v1"
        ]
        UIReviewFixture.writeDocument("gift-catalog-v1.json", [
            "version": parsed.version,
            "count": parsed.items.count,
            "rose": rose,
            "star": star,
            "crown": crown,
            "matchesIsolatedCatalog": matched,
            "adapterScope": "parse-and-drawer",
            "drawerFixtureCrown": crown,
            "drawerPriceParity": "closed-isolated-v1"
        ])
    }

    fileprivate static let versionOnePayload: [String: Any] = [
        "enabled": true,
        "experience": true,
        "version": 1,
        "items": [
            ["id": "rose", "name": "Hoa hồng", "tier": "small", "costCoins": 50],
            ["id": "heart", "name": "Trái tim", "tier": "small", "costCoins": 50],
            ["id": "coffee", "name": "Cà phê", "tier": "small", "costCoins": 100],
            ["id": "love_gun", "name": "Súng tình yêu", "tier": "medium", "costCoins": 150],
            ["id": "fireworks", "name": "Pháo hoa", "tier": "medium", "costCoins": 200],
            ["id": "star", "name": "Sao pha lê", "tier": "small", "costCoins": 100],
            ["id": "crown", "name": "Vương miện", "tier": "medium", "costCoins": 200],
            ["id": "diamond", "name": "Kim cương", "tier": "medium", "costCoins": 500],
            ["id": "car", "name": "Siêu xe", "tier": "large", "costCoins": 800],
            ["id": "sports_car", "name": "Siêu xe thể thao", "tier": "large", "costCoins": 1000],
            ["id": "yacht", "name": "Du thuyền", "tier": "large", "costCoins": 1200],
            ["id": "castle", "name": "Lâu đài", "tier": "legendary", "costCoins": 2000],
            ["id": "aurora", "name": "Cực quang", "tier": "medium", "costCoins": 300],
            ["id": "meteor", "name": "Sao băng", "tier": "medium", "costCoins": 400],
            ["id": "butterfly", "name": "Bướm mộng", "tier": "small", "costCoins": 150],
            ["id": "lotus", "name": "Sen ánh sáng", "tier": "medium", "costCoins": 250]
        ]
    ]
}

private struct ReviewGiftDrawer: View {
    private let catalog = LiveGiftCatalogAdapter.parse(GiftCatalogVersionProbe.versionOnePayload)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.07, blue: 0.12), Color.black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                Text("Trực tiếp")
                    .font(KinnectTheme.sectionTitle)
                    .foregroundColor(.white)
                Text("Giao lưu âm nhạc cuối tuần")
                    .font(KinnectTheme.body)
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
            }
            .padding(20)
        }
        .sheet(isPresented: .constant(true)) {
            LiveGiftDrawerSheet(roomId: "fixture_live_room", gifts: catalog.items, priceVersion: catalog.version)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct ReviewMusicPicker: View {
    @State private var selectedTrack = ""

    var body: some View {
        NavigationStack {
            StudioMusicPickerSheet(selectedTrack: $selectedTrack)
        }
    }
}

#if DEBUG
private struct SwiftContractsHarnessProbe: View {
    @State private var lines: [String] = ["Đang chạy kiểm thử Swift URLProtocol & Admin..."]

    private final class MockAdminTransport: AdminTransportProtocol {
        var serverVersion = 1
        var uploadedFiles: [String] = []

        func requestJSON(_ path: String, method: String, body: [String: Any]?) async throws -> [String: Any] {
            if path == "/api/admin/economy", method == "PATCH" {
                let reqVersion = (body?["version"] as? Int) ?? 0
                if reqVersion != serverVersion {
                    throw KinnectAPIError.serverError(status: 409, message: "Cấu hình đã đổi. Hãy tải lại trước khi lưu.")
                }
                serverVersion += 1
                var updated = (body?["config"] as? [String: Any]) ?? [:]
                if updated["vndPerCoin"] == nil { updated["vndPerCoin"] = 100 }
                return ["version": serverVersion, "config": updated]
            }
            if path == "/api/music", method == "POST" {
                let file = "fixture_track_\(uploadedFiles.count + 1).mp3"
                uploadedFiles.append(file)
                return ["ok": true, "file": file]
            }
            if path == "/api/music", method == "DELETE" {
                let file = (body?["file"] as? String) ?? ""
                uploadedFiles.removeAll { $0 == file }
                return ["ok": true]
            }
            throw KinnectAPIError.serverError(status: 404, message: "Not found")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Swift Contracts & URLProtocol Harness")
                    .font(KinnectTheme.sectionTitle)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(KinnectTheme.caption)
                        .foregroundColor(KinnectTheme.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(KinnectTheme.background)
        .task { await run() }
    }

    private func run() async {
        var passed = 0
        var failed = 0
        var results: [String: Bool] = [:]

        func check(_ name: String, _ condition: Bool) {
            results[name] = condition
            if condition { passed += 1 } else { failed += 1 }
        }

        // 1. URLProtocol stubbed URLSession checks for password, dmMode, sessions
        let origin = "https://127.0.0.1"
        var capturedPaths: [String] = []
        let stubSession = LocalTransportHarness.makeStubbedSession { request in
            capturedPaths.append("\(request.httpMethod ?? "GET") \(request.url?.path ?? "")")
            let url = request.url ?? URL(string: origin)!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let data = Data("{\"ok\":true}".utf8)
            return (response, data)
        }
        defer { KinnectLocalStubURLProtocol.handler = nil }

        do {
            let pwReq = try LocalTransportHarness.makePasswordRequest(origin: origin, current: "oldpass123", next: "newpass123")
            let (_, pwResp) = try await stubSession.data(for: pwReq)
            let dmReq = try LocalTransportHarness.makeDmModeRequest(origin: origin, dmMode: "friends")
            let (_, dmResp) = try await stubSession.data(for: dmReq)
            let sessReq = try LocalTransportHarness.makeRevokeSessionRequest(origin: origin, sessionId: "0123456789abcdef0123456789abcdef")
            let (_, sessResp) = try await stubSession.data(for: sessReq)
            let codesOK = [pwResp, dmResp, sessResp].allSatisfy { ($0 as? HTTPURLResponse)?.statusCode == 200 }
            check("urlprotocol_roundtrip", codesOK && capturedPaths == [
                "POST /api/me/password",
                "PATCH /api/me",
                "DELETE /api/me/sessions/0123456789abcdef0123456789abcdef"
            ])
        } catch {
            check("urlprotocol_roundtrip", false)
        }

        // 2. AdminEconomyDraft role gate, v1->v2 save, and 409 conflict rejection
        let transport = MockAdminTransport()
        var prices: [String: Int] = [:]
        for key in AdminEconomyDraft.requiredGiftIds { prices[key] = 50 }
        let draft = AdminEconomyDraft(
            version: 1,
            vndPerCoin: 100,
            signupBonusCoins: 2000,
            signupBonusEnabled: true,
            trialPackagePurchases: true,
            trialGiftsEnabled: true,
            showCoinPacks: true,
            giftPrices: prices,
            coinPacks: [100, 500, 1000]
        )
        do {
            _ = try await AdminActionsContract.saveEconomy(draft: draft, role: "member", transport: transport)
            check("economy_role_gate_403", false)
        } catch let KinnectAPIError.serverError(status, _) {
            check("economy_role_gate_403", status == 403)
        } catch {
            check("economy_role_gate_403", false)
        }

        do {
            let saved = try await AdminActionsContract.saveEconomy(draft: draft, role: "admin", transport: transport)
            check("economy_save_v2", saved.version == 2)
        } catch {
            check("economy_save_v2", false)
        }

        do {
            _ = try await AdminActionsContract.saveEconomy(draft: draft, role: "admin", transport: transport)
            check("economy_conflict_409", false)
        } catch let KinnectAPIError.serverError(status, _) {
            check("economy_conflict_409", status == 409)
        } catch {
            check("economy_conflict_409", false)
        }

        // 3. Music upload & delete contract validation + role gate
        var badMusic = AdminMusicUploadDraft(title: "T", artist: "A", license: "CC0", source: "", rightsConfirmed: false, mimeType: "audio/mpeg", audioData: Data("ID3".utf8))
        check("music_rights_validation", badMusic.validate() != nil)
        badMusic.rightsConfirmed = true
        do {
            let file = try await AdminActionsContract.uploadMusic(draft: badMusic, role: "admin", transport: transport)
            check("music_upload_ok", file == "fixture_track_1.mp3")
            try await AdminActionsContract.deleteMusic(file: file, role: "admin", transport: transport)
            check("music_delete_ok", transport.uploadedFiles.isEmpty)
        } catch {
            check("music_upload_ok", false)
            check("music_delete_ok", false)
        }
        check("music_traversal_rejected", !AdminMusicItem.isValidFilename("../evil.mp3"))

        // 4. AI credentials allowlist & non-secret validation
        let badAIUrl = AdminAICredentialsPatch(password: "pw123", workerUrl: "https://evil.example.com", token: nil, nvidiaKey: nil, nvidiaModel: nil, nvidiaVisionModel: nil, fallbackEnabled: nil)
        let goodAI = AdminAICredentialsPatch(password: "pw123", workerUrl: "https://kinnect-ai.vuanh97nd.workers.dev", token: String(repeating: "a", count: 32), nvidiaKey: nil, nvidiaModel: nil, nvidiaVisionModel: nil, fallbackEnabled: false)
        check("ai_credentials_validation", badAIUrl.validate() != nil && goodAI.validate() == nil)

        lines = results.keys.sorted().map { key in
            "\(key)=\(results[key] == true ? "pass" : "fail")"
        } + ["passed=\(passed)", "failed=\(failed)"]

        UIReviewFixture.writeDocument("swift-contracts-harness.json", [
            "passed": passed,
            "failed": failed,
            "allPassed": failed == 0,
            "checks": results
        ])
    }
}
#endif

extension UIReviewFixture {
    struct AVBufferSample {
        var received = false
        var width = 0
        var height = 0
        var time = 0.0
        var red = 0
        var green = 0
        var blue = 0
        var frameSaved = false
        var frameFile = ""
    }

    static func sampleVideoFrame(output: AVPlayerItemVideoOutput, item: AVPlayerItem, fileName: String) async -> (sample: AVBufferSample, image: UIImage?) {
        let start = Date()
        while Date().timeIntervalSince(start) < 1.5 {
            let time = item.currentTime()
            if output.hasNewPixelBuffer(forItemTime: time),
               let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                var sample = AVBufferSample()
                sample.received = true
                sample.width = CVPixelBufferGetWidth(buffer)
                sample.height = CVPixelBufferGetHeight(buffer)
                let sec = time.seconds
                sample.time = sec.isFinite ? sec : 0
                CVPixelBufferLockBaseAddress(buffer, .readOnly)
                if let base = CVPixelBufferGetBaseAddress(buffer), sample.width > 1, sample.height > 1 {
                    let row = CVPixelBufferGetBytesPerRow(buffer)
                    let x = min(8, sample.width - 1)
                    let y = min(8, sample.height - 1)
                    let corner = base.advanced(by: y * row + x * 4).assumingMemoryBound(to: UInt8.self)
                    sample.blue = Int(corner[0])
                    sample.green = Int(corner[1])
                    sample.red = Int(corner[2])
                }
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
                var renderedImage: UIImage? = nil
                let image = CIImage(cvPixelBuffer: buffer)
                let context = CIContext()
                if let cgImage = context.createCGImage(image, from: image.extent) {
                    let rendered = UIImage(cgImage: cgImage)
                    renderedImage = rendered
                    if let data = rendered.pngData(),
                       let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        let file = dir.appendingPathComponent(fileName)
                        sample.frameSaved = (try? data.write(to: file)) != nil
                        if sample.frameSaved {
                            sample.frameFile = fileName
                        }
                    }
                }
                return (sample, renderedImage)
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return (AVBufferSample(), nil)
    }

    #if DEBUG
    final class ShortsRealSwipeObserver {
        struct Entry {
            let player: AVPlayer
            let item: AVPlayerItem
            let output: AVPlayerItemVideoOutput
        }

        static let shared = ShortsRealSwipeObserver()
        private let lock = NSLock()
        private var entries: [String: Entry] = [:]

        func register(path: String, player: AVPlayer, item: AVPlayerItem, output: AVPlayerItemVideoOutput) {
            lock.lock()
            entries[path] = Entry(player: player, item: item, output: output)
            lock.unlock()
        }

        func unregister(path: String) {
            lock.lock()
            entries.removeValue(forKey: path)
            lock.unlock()
        }

        func entry(for path: String) -> Entry? {
            lock.lock()
            defer { lock.unlock() }
            return entries[path]
        }
    }

    @MainActor
    static func findVerticalPagingScrollView() -> UIScrollView? {
        func search(_ view: UIView) -> UIScrollView? {
            if let sv = view as? UIScrollView,
               sv.isScrollEnabled,
               sv.bounds.height > 100,
               sv.contentSize.height > sv.bounds.height * 1.4 {
                return sv
            }
            for sub in view.subviews {
                if let match = search(sub) {
                    return match
                }
            }
            return nil
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows where !window.isHidden {
                if let sv = search(window) {
                    return sv
                }
            }
        }
        return nil
    }
    #endif
}
