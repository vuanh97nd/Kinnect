import AVFoundation
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
            let videoURL = samplePlayableVideoURL()?.absoluteString ?? ""
            return [
                "shorts": [
                    [
                        "id": "fixture_short_1",
                        "author": peerUserDict,
                        "title": "Dạo phố sáng cuối tuần [Fixture UI]",
                        "caption": "Video ngắn thử nghiệm bố cục Shorts trên iOS Simulator.",
                        "videoUrl": videoURL,
                        "durationSec": 15,
                        "likesCount": 128,
                        "commentsCount": 14,
                        "liked": true,
                        "createdAt": "2026-11-07T01:10:00.000Z"
                    ]
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
                        "userAgent": "iPhone 16 Pro • iOS 18.2 (Thiết bị hiện tại)",
                        "deviceName": "iPhone 16 Pro (Thiết bị này)",
                        "ip": "127.0.0.1",
                        "current": true,
                        "lastActive": "Vừa xong"
                    ],
                    [
                        "id": "fixture_sess_2",
                        "userAgent": "iPad Pro 11-inch • iPadOS 18.2",
                        "deviceName": "iPad Pro 11-inch",
                        "ip": "192.168.1.15",
                        "current": false,
                        "lastActive": "2 giờ trước"
                    ]
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
        let tempDir = FileManager.default.temporaryDirectory
        let movieURL = tempDir.appendingPathComponent("ui_review_sample_shorts.mp4")
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
                    ctx.setFillColor(red: 0.12 + 0.35 * progress, green: 0.08 + 0.15 * progress, blue: 0.42, alpha: 1.0)
                    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

                    let circleY = CGFloat(height) * (0.3 + 0.4 * progress)
                    ctx.setFillColor(red: 0.85, green: 0.35, blue: 0.95, alpha: 0.85)
                    ctx.fillEllipse(in: CGRect(x: CGFloat(width)/2 - 60, y: circleY - 60, width: 120, height: 120))
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
        case "video", "shorts":
            return AnyView(
                ShortsVideoView()
            )
        case "live", "live-room":
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
        case "call-overlay", "call-incoming":
            NativeWebRTCManager.shared.activeCall = ActiveCallSession(
                callId: "fixture_call_1",
                peerUser: KinnectUser.from(UIReviewFixture.peerUserDict),
                mode: "video",
                isIncoming: true,
                state: .ringingIncoming
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
                    WalletStoreView(initialTab: .wallet)
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Ví Kinnect")
                        .navigationBarTitleDisplayMode(.large)
                }
            )
        case "store", "wallet-packages", "store-packages":
            return AnyView(
                NavigationStack {
                    WalletStoreView(initialTab: .packages, initialStoreFilter: .style)
                        .toolbar { RootMainView.headerTrailingButtonsStatic() }
                        .navigationTitle("Cửa hàng Kinnect")
                        .navigationBarTitleDisplayMode(.large)
                }
            )
        case "wallet-topup":
            return AnyView(
                NavigationStack {
                    WalletStoreView(initialTab: .topup)
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

        default:
            return AnyView(RootMainView())
        }
    }
}
