import Foundation

struct KinnectUser: Identifiable, Hashable {
    var id: String
    var username: String
    var name: String
    var bio: String
    var city: String
    var gender: String
    var orientation: String
    var pronouns: String
    var relationshipRole: String
    var lookingFor: String
    var communityRole: String
    var occupation: String
    var school: String
    var birthDate: String
    var age: Int?
    var interests: [String]
    var role: String
    var avatarURL: String?
    var coverURL: String?
    var isFollowing: Bool
    var followsMe: Bool
    var friendshipStatus: String
    var discoverable: Bool
    var showDistance: Bool
    var dmMode: String
    var distanceLabel: String
    var isActive: Bool
    var unread: Int
    var lastMessageBody: String?
    var lastMessageCreated: Int64?
    var lastMessageMine: Bool

    init(json: [String: Any]) {
        self.id = json["id"] as? String ?? ""
        self.username = json["username"] as? String ?? ""
        self.name = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (json["username"] as? String ?? "Thành viên")
        self.bio = json["bio"] as? String ?? ""
        self.city = json["city"] as? String ?? ""
        self.gender = json["gender"] as? String ?? ""
        self.orientation = json["orientation"] as? String ?? ""
        self.pronouns = json["pronouns"] as? String ?? ""
        self.relationshipRole = json["relationshipRole"] as? String ?? ""
        self.lookingFor = json["lookingFor"] as? String ?? ""
        self.communityRole = json["communityRole"] as? String ?? ""
        self.occupation = json["occupation"] as? String ?? ""
        self.school = json["school"] as? String ?? ""
        self.birthDate = json["birthDate"] as? String ?? ""
        self.age = json["age"] as? Int
        if let arr = json["interests"] as? [String] {
            self.interests = arr
        } else {
            self.interests = []
        }
        self.role = json["role"] as? String ?? "user"
        if let av = json["avatar"] as? String, !av.isEmpty {
            self.avatarURL = av
        } else if (json["hasAvatar"] as? Bool) == true && !self.id.isEmpty {
            self.avatarURL = "/api/users/\(self.id)/avatar"
        } else {
            self.avatarURL = nil
        }
        if let cv = json["cover"] as? String, !cv.isEmpty {
            self.coverURL = cv
        } else {
            self.coverURL = nil
        }
        self.isFollowing = (json["following"] as? Bool) ?? false
        self.followsMe = (json["followsYou"] as? Bool) ?? false
        self.friendshipStatus = json["friendship"] as? String ?? (json["status"] as? String ?? "none")
        self.discoverable = (json["discoverable"] as? Bool) ?? true
        self.showDistance = (json["showDistance"] as? Bool) ?? true
        self.dmMode = json["dmMode"] as? String ?? "everyone"
        self.distanceLabel = json["distanceLabel"] as? String ?? (json["distanceBand"] as? String ?? "")
        self.isActive = (json["isActive"] as? Bool) ?? false
        self.unread = json["unread"] as? Int ?? 0
        if let last = json["last"] as? [String: Any] {
            self.lastMessageBody = last["body"] as? String
            self.lastMessageCreated = (last["created"] as? NSNumber)?.int64Value
            self.lastMessageMine = (last["mine"] as? Bool) ?? false
        } else {
            self.lastMessageBody = nil
            self.lastMessageCreated = nil
            self.lastMessageMine = false
        }
    }
}

struct PostItem: Identifiable {
    var id: String
    var userId: String
    var body: String
    var visibility: String
    var category: String
    var created: Int64
    var author: KinnectUser
    var mediaKind: String?
    var mediaURL: String?
    var likes: Int
    var liked: Bool
    var myReaction: String?
    var commentsCount: Int

    init(json: [String: Any]) {
        self.id = json["id"] as? String ?? UUID().uuidString
        self.userId = json["user_id"] as? String ?? ""
        self.body = json["body"] as? String ?? ""
        self.visibility = json["visibility"] as? String ?? "public"
        self.category = json["category"] as? String ?? "community"
        self.created = (json["created"] as? NSNumber)?.int64Value ?? 0
        self.author = KinnectUser(json: json["author"] as? [String: Any] ?? [:])
        if let media = json["media"] as? [String: Any] {
            self.mediaKind = media["kind"] as? String
            self.mediaURL = media["url"] as? String
        } else {
            self.mediaKind = nil
            self.mediaURL = nil
        }
        self.likes = json["likes"] as? Int ?? 0
        self.liked = (json["liked"] as? Bool) ?? false
        self.myReaction = json["myReaction"] as? String
        self.commentsCount = json["comments"] as? Int ?? 0
    }
}

struct StoryItem: Identifiable {
    var id: String
    var userId: String
    var body: String
    var background: String
    var created: Int64
    var expires: Int64
    var viewCount: Int?
    var author: KinnectUser
    var mediaKind: String?
    var mediaURL: String?

    init(json: [String: Any]) {
        self.id = json["id"] as? String ?? UUID().uuidString
        self.userId = json["user_id"] as? String ?? ""
        self.body = json["body"] as? String ?? ""
        self.background = json["background"] as? String ?? "purple"
        self.created = (json["created"] as? NSNumber)?.int64Value ?? 0
        self.expires = (json["expires"] as? NSNumber)?.int64Value ?? 0
        self.viewCount = json["viewCount"] as? Int
        self.author = KinnectUser(json: json["author"] as? [String: Any] ?? [:])
        if let media = json["media"] as? [String: Any] {
            self.mediaKind = media["kind"] as? String
            self.mediaURL = media["url"] as? String
        } else {
            self.mediaKind = nil
            self.mediaURL = nil
        }
    }
}

struct CommentItem: Identifiable {
    var id: String
    var userId: String
    var body: String
    var created: Int64
    var parentId: String?
    var author: KinnectUser

    init(json: [String: Any]) {
        self.id = json["id"] as? String ?? UUID().uuidString
        self.userId = json["user_id"] as? String ?? ""
        self.body = json["body"] as? String ?? ""
        self.created = (json["created"] as? NSNumber)?.int64Value ?? 0
        self.parentId = json["parentId"] as? String
        self.author = KinnectUser(json: json["author"] as? [String: Any] ?? [:])
    }
}

struct ShortItem: Identifiable {
    var id: String
    var userId: String
    var caption: String
    var duration: Double
    var created: Int64
    var videoPath: String
    var likes: Int
    var commentsCount: Int
    var liked: Bool
    var author: KinnectUser

    init(json: [String: Any]) {
        self.id = json["id"] as? String ?? UUID().uuidString
        self.userId = json["user_id"] as? String ?? ""
        self.caption = json["caption"] as? String ?? ""
        self.duration = (json["duration"] as? NSNumber)?.doubleValue ?? 0
        self.created = (json["created"] as? NSNumber)?.int64Value ?? 0
        self.videoPath = json["video"] as? String ?? "/api/shorts/\(self.id)/video"
        self.likes = json["likes"] as? Int ?? 0
        self.commentsCount = json["comments"] as? Int ?? 0
        self.liked = (json["liked"] as? Bool) ?? false
        self.author = KinnectUser(json: json["author"] as? [String: Any] ?? [:])
    }
}

struct DirectMessageItem: Identifiable {
    var id: String
    var sender: String
    var recipient: String
    var body: String
    var created: Int64
    var deliveredAt: Int64?
    var seenAt: Int64?
    var recalled: Bool
    var attachmentURL: String?
    var attachmentType: String?
    var attachmentName: String?

    init(json: [String: Any]) {
        self.id = json["id"] as? String ?? UUID().uuidString
        self.sender = json["sender"] as? String ?? ""
        self.recipient = json["recipient"] as? String ?? ""
        self.body = json["body"] as? String ?? ""
        self.created = (json["created"] as? NSNumber)?.int64Value ?? 0
        self.recalled = (json["recalled"] as? Bool) ?? false
        if let receipt = json["receipt"] as? [String: Any] {
            self.deliveredAt = (receipt["deliveredAt"] as? NSNumber)?.int64Value
            self.seenAt = (receipt["seenAt"] as? NSNumber)?.int64Value
        }
        if let att = json["attachment"] as? [String: Any] {
            self.attachmentURL = att["url"] as? String
            self.attachmentType = att["type"] as? String
            self.attachmentName = att["name"] as? String
        }
    }
}

struct ChatGroupItem: Identifiable, Hashable {
    var id: String
    var name: String
    var owner: String
    var created: Int64
    var unread: Int
    var lastBody: String?
    var lastSenderName: String?
    var lastCreated: Int64?
    var members: [KinnectUser]

    init(json: [String: Any]) {
        self.id = json["id"] as? String ?? UUID().uuidString
        self.name = json["name"] as? String ?? "Nhóm trò chuyện"
        self.owner = json["owner"] as? String ?? ""
        self.created = (json["created"] as? NSNumber)?.int64Value ?? 0
        self.unread = json["unread"] as? Int ?? 0
        if let last = json["last"] as? [String: Any] {
            self.lastBody = last["body"] as? String
            self.lastSenderName = last["name"] as? String
            self.lastCreated = (last["created"] as? NSNumber)?.int64Value
        }
        if let mems = json["members"] as? [[String: Any]] {
            self.members = mems.map { KinnectUser(json: $0) }
        } else {
            self.members = []
        }
    }
}

struct GroupMessageItem: Identifiable {
    var id: String
    var groupId: String
    var sender: String
    var body: String
    var created: Int64
    var author: KinnectUser
    var deliveredCount: Int
    var seenCount: Int

    init(json: [String: Any]) {
        self.id = json["id"] as? String ?? UUID().uuidString
        self.groupId = json["group_id"] as? String ?? ""
        self.sender = json["sender"] as? String ?? ""
        self.body = json["body"] as? String ?? ""
        self.created = (json["created"] as? NSNumber)?.int64Value ?? 0
        self.author = KinnectUser(json: json["author"] as? [String: Any] ?? [:])
        if let receipt = json["receipt"] as? [String: Any] {
            self.deliveredCount = receipt["deliveredCount"] as? Int ?? 0
            self.seenCount = receipt["seenCount"] as? Int ?? 0
        } else {
            self.deliveredCount = 0
            self.seenCount = 0
        }
    }
}

struct NotificationItem: Identifiable {
    var id: String
    var kind: String
    var ref: String
    var preview: String
    var created: Int64
    var seen: Bool
    var actor: KinnectUser

    init(json: [String: Any]) {
        self.id = json["id"] as? String ?? UUID().uuidString
        self.kind = json["kind"] as? String ?? ""
        self.ref = json["ref"] as? String ?? ""
        self.preview = json["preview"] as? String ?? ""
        self.created = (json["created"] as? NSNumber)?.int64Value ?? 0
        self.seen = ((json["seen"] as? Int) ?? 0) != 0 || ((json["seen"] as? Bool) == true)
        self.actor = KinnectUser(json: json["actor"] as? [String: Any] ?? [:])
    }

    var summaryText: String {
        switch kind {
        case "like": return "đã bày tỏ cảm xúc về bài viết của bạn"
        case "comment": return "đã bình luận bài viết của bạn"
        case "comment_reply": return "đã phản hồi bình luận của bạn"
        case "follow": return "đã bắt đầu theo dõi bạn"
        case "friend_request": return "đã gửi lời mời kết bạn"
        case "friend_accepted": return "đã chấp nhận lời mời kết bạn"
        case "message": return "đã gửi tin nhắn cho bạn"
        case "group_message": return "đã nhắn tin trong nhóm"
        case "missed_call": return "Cuộc gọi nhỡ"
        case "gift": return "đã tặng quà Live cho bạn"
        default: return "Thông báo mới từ Kinnect"
        }
    }
}

struct LiveRoomItem: Identifiable, Hashable {
    var id: String
    var title: String
    var hostName: String
    var hostId: String
    var hostUsername: String
    var avatarURL: String?
    var liveMode: String
    var gameTitle: String
    var viewers: Int

    init(json: [String: Any]) {
        self.id = json["id"] as? String ?? ""
        self.title = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Phòng Live Kinnect"
        self.hostName = json["host"] as? String ?? "Chủ phòng"
        self.hostId = json["hostId"] as? String ?? ""
        self.hostUsername = json["hostUsername"] as? String ?? ""
        self.avatarURL = json["avatar"] as? String
        let mode = json["liveMode"] as? String ?? "chat"
        self.liveMode = (mode == "game") ? "game" : "chat"
        self.gameTitle = json["gameTitle"] as? String ?? ""
        self.viewers = json["viewers"] as? Int ?? 0
    }
}

struct LiveChatMessage: Identifiable {
    var id: String
    var senderId: String
    var senderName: String
    var text: String
    var isGift: Bool
    var giftName: String?
    var quantity: Int

    init(id: String = UUID().uuidString, senderId: String, senderName: String, text: String, isGift: Bool = false, giftName: String? = nil, quantity: Int = 1) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.isGift = isGift
        self.giftName = giftName
        self.quantity = quantity
    }
}

struct LiveGiftCatalogItem: Identifiable {
    var id: String
    var name: String
    var tier: String
    var priceCoins: Int
    var comboable: Bool
}

struct WalletEntryItem: Identifiable {
    var id: String
    var kind: String
    var title: String
    var subtitle: String
    var category: String
    var currency: String
    var coins: Int
    var created: Int64

    init(json: [String: Any]) {
        self.id = json["id"] as? String ?? UUID().uuidString
        self.kind = json["kind"] as? String ?? ""
        self.title = json["title"] as? String ?? "Giao dịch ví"
        self.subtitle = json["subtitle"] as? String ?? ""
        self.category = json["category"] as? String ?? "other"
        self.currency = json["currency"] as? String ?? "trial"
        self.coins = json["coins"] as? Int ?? 0
        self.created = (json["created"] as? NSNumber)?.int64Value ?? 0
    }
}

struct StorePackageItem: Identifiable {
    var id: String
    var kind: String
    var name: String
    var description: String
    var period: String
    var tier: String
    var priceCoins: Int
    var colors: [String]
    var owned: Bool

    init(json: [String: Any], ownedIds: Set<String>) {
        self.id = json["id"] as? String ?? ""
        self.kind = json["kind"] as? String ?? "style"
        self.name = json["name"] as? String ?? ""
        self.description = json["description"] as? String ?? ""
        self.period = json["period"] as? String ?? "Vĩnh viễn"
        self.tier = json["tier"] as? String ?? "rare"
        self.priceCoins = json["priceCoins"] as? Int ?? 0
        self.colors = json["colors"] as? [String] ?? ["#7c3aed", "#ec4899"]
        self.owned = ownedIds.contains(self.id)
    }
}

struct StoreDigitalProduct: Identifiable {
    var id: String
    var kind: String
    var name: String
    var description: String
    var referenceVnd: Int
    var owned: Bool

    init(json: [String: Any], ownedIds: Set<String>) {
        self.id = json["id"] as? String ?? ""
        self.kind = json["kind"] as? String ?? "style"
        self.name = json["name"] as? String ?? ""
        self.description = json["description"] as? String ?? ""
        self.referenceVnd = json["referenceVnd"] as? Int ?? 0
        self.owned = ownedIds.contains(self.id)
    }
}
