import Foundation
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

    static var isEnabled: Bool {
        activeScreen != nil
    }

    static let currentUserDict: [String: Any] = [
        "id": "fixture_user_me",
        "name": "Minh Anh [Fixture UI]",
        "handle": "minhanh_fixture",
        "email": "fixture-ui@kinnect.local",
        "bio": "[Dữ liệu Fixture UI kiểm thử giao diện native iOS — Không kết nối dữ liệu thật]",
        "locationName": "Quận 1, TP. Hồ Chí Minh",
        "avatarColor": "#7C3AED",
        "friendsCount": 128,
        "followersCount": 1420,
        "followingCount": 95,
        "isPrivate": false
    ]

    static let peerUserDict: [String: Any] = [
        "id": "fixture_user_peer",
        "name": "Hoàng Nam [Fixture UI]",
        "handle": "hoangnam_fixture",
        "bio": "Thiết kế sản phẩm & nhiếp ảnh • Fixture UI Test",
        "locationName": "Đà Nẵng",
        "avatarColor": "#2563EB",
        "distanceKm": 2.4,
        "isFollowing": true,
        "isFriend": true
    ]

    static let secondPeerDict: [String: Any] = [
        "id": "fixture_user_2",
        "name": "Thanh Trúc [Fixture UI]",
        "handle": "thanhtruc_fixture",
        "bio": "Âm nhạc, du lịch & công nghệ • Fixture UI Test",
        "locationName": "Hà Nội",
        "avatarColor": "#EC4899",
        "distanceKm": 5.8,
        "isFollowing": false,
        "isFriend": false
    ]

    static func mockResponse(for path: String) -> [String: Any] {
        let cleanPath = path.components(separatedBy: "?").first ?? path

        switch cleanPath {
        case "/api/me":
            if activeScreen == "auth" {
                return [:]
            }
            return ["user": currentUserDict]

        case "/api/posts":
            return [
                "posts": [
                    [
                        "id": "fixture_post_1",
                        "author": peerUserDict,
                        "text": "[Fixture UI Test] Giao diện Kinnect iOS Native SwiftUI mới với bộ 40 icon vector riêng. Kiểm tra hiển thị tiếng Việt có dấu, khoảng cách dòng và nút menu 3 chấm nền trong suốt.",
                        "category": "community",
                        "imageUrl": "",
                        "likesCount": 42,
                        "commentsCount": 8,
                        "liked": true,
                        "userReaction": "love",
                        "createdAt": "2026-11-07T01:30:00.000Z"
                    ],
                    [
                        "id": "fixture_post_2",
                        "author": secondPeerDict,
                        "text": "[Fixture UI Test] Buổi chiều cuối tuần cùng bạn bè tại Sài Gòn. Không cắt chữ trên màn hình nhỏ!",
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
                    "gender": "nam",
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
                    "gender": "nu",
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
                    "gender": "nam",
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
                    "gender": "nu",
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
            return [
                "shorts": [
                    [
                        "id": "fixture_short_1",
                        "author": peerUserDict,
                        "title": "Dạo phố sáng cuối tuần [Fixture UI]",
                        "caption": "Video ngắn thử nghiệm bố cục Shorts trên iOS Simulator.",
                        "videoUrl": "",
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
                "outgoing": []
            ]

        case "/api/friend-suggestions":
            return ["suggestions": [secondPeerDict]]

        case "/api/notifications":
            return [
                "notifications": [
                    [
                        "id": "fixture_notif_1",
                        "actor": peerUserDict,
                        "preview": "[Fixture UI] Hoàng Nam đã bày tỏ cảm xúc với bài viết của bạn.",
                        "read": false,
                        "createdAt": "2026-11-07T01:40:00.000Z"
                    ],
                    [
                        "id": "fixture_notif_2",
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
                "packages": [
                    [
                        "id": "fixture_pkg_1",
                        "title": "Khung Avatar Tím Tinh Vân [Fixture]",
                        "subtitle": "Hiệu ứng viền tím Kinnect nổi bật trên hồ sơ & phòng Live",
                        "category": "frame",
                        "priceCoins": 500,
                        "badgeText": "HOT",
                        "accentColor": "#7C3AED",
                        "owned": true,
                        "equipped": true
                    ],
                    [
                        "id": "fixture_pkg_2",
                        "title": "Huy Hiệu Tiên Phong [Fixture]",
                        "subtitle": "Huy hiệu hiển thị cạnh tên trên bảng tin",
                        "category": "badge",
                        "priceCoins": 800,
                        "badgeText": "MỚI",
                        "accentColor": "#2563EB",
                        "owned": false,
                        "equipped": false
                    ]
                ],
                "products": [
                    [
                        "id": "vn.kinnect.coins.1000",
                        "title": "Gói 1.000 Xu Kinnect [Fixture StoreKit 2]",
                        "description": "Xác minh JWS trực tiếp qua StoreKit 2 & /api/store/verify",
                        "priceLabel": "22.000 ₫",
                        "coins": 1000
                    ]
                ]
            ]

        case "/api/live/rooms":
            return [
                "rooms": [
                    [
                        "id": "fixture_live_1",
                        "title": "Giao lưu tối cuối tuần [Fixture UI]",
                        "topic": "Trò chuyện & kết nối bạn mới",
                        "liveMode": "chat",
                        "gameTitle": "",
                        "hostUserId": "fixture_user_peer",
                        "hostName": "Hoàng Nam [Fixture UI]",
                        "hostAvatarColor": "#2563EB",
                        "viewerCount": 64
                    ],
                    [
                        "id": "fixture_live_2",
                        "title": "Leo rank Liên Quân cùng team [Fixture UI]",
                        "topic": "Chơi game trực tiếp",
                        "liveMode": "game",
                        "gameTitle": "Liên Quân Mobile",
                        "hostUserId": "fixture_user_2",
                        "hostName": "Thanh Trúc [Fixture UI]",
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

        case "/api/sessions":
            return [
                "sessions": [
                    [
                        "id": "fixture_sess_1",
                        "deviceName": "iPhone 16 Pro (Thiết bị này) [Fixture UI]",
                        "ip": "127.0.0.1",
                        "current": true,
                        "lastActive": "Vừa xong"
                    ],
                    [
                        "id": "fixture_sess_2",
                        "deviceName": "iPad Pro 11-inch [Fixture UI]",
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
                            "url": "",
                            "created": 1762500000000
                        ],
                        [
                            "id": "fixture_priv_2",
                            "url": "",
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
                        ]
                    ]
                ]
            }
            return [:]
        }
    }

    static func samplePreviewImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 420))
        return renderer.image { ctx in
            let colors = [
                UIColor(red: 0.43, green: 0.29, blue: 1.0, alpha: 1.0).cgColor,
                UIColor(red: 0.16, green: 0.09, blue: 0.36, alpha: 1.0).cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 640, y: 420), options: [])
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let text = "KINNECT STUDIO PREVIEW\n[Fixture UI Test — Ảnh mẫu kiểm thử]"
            text.draw(in: CGRect(x: 40, y: 170, width: 560, height: 100), withAttributes: attrs)
        }
    }
}

