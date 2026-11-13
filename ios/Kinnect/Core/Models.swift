import Foundation

private func isoString(from anyVal: Any?) -> String {
    if let s = anyVal as? String, !s.isEmpty {
        return s
    }
    if let n = anyVal as? NSNumber {
        let ms = n.doubleValue
        let sec = ms > 10_000_000_000 ? (ms / 1000.0) : ms
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: sec))
    }
    return ""
}

struct KinnectUser: Identifiable, Hashable, Equatable {
    var id: String
    var name: String
    var handle: String
    var username: String {
        get { handle.isEmpty ? name : handle }
        set { handle = newValue }
    }
    var email: String
    var phone: String
    var bio: String
    var avatarUrl: String
    var avatarColor: String
    var coverUrl: String
    var locationName: String
    var isPrivate: Bool
    var followersCount: Int
    var followingCount: Int
    var friendsCount: Int
    var isFollowing: Bool
    var isFollowed: Bool {
        get { isFollowing }
        set { isFollowing = newValue }
    }
    var friendshipStatus: String
    var distanceKm: Double?
    var isActive: Bool
    var age: Int
    var gender: String
    var orientation: String
    var communityRole: String
    var coins: Int
    var height: Int
    var weight: Int
    var pronouns: String
    var relationshipRole: String
    var lookingFor: String
    var occupation: String
    var school: String
    var city: String
    var interests: [String]
    var cloudChatSync: Bool
    var postsCount: Int
    var joinedAt: Int64
    var identityPublic: Bool
    var profileVisibility: [String: Bool]
    var showActivity: Bool
    var showDistance: Bool
    var discoverable: Bool
    var hasLocation: Bool
    var dmMode: String
    var accountRole: String

    var avatarURL: String? { avatarUrl.isEmpty ? nil : avatarUrl }

    init(
        id: String = "",
        name: String = "Người dùng Kinnect",
        handle: String = "",
        email: String = "",
        phone: String = "",
        bio: String = "",
        avatarUrl: String = "",
        avatarColor: String = "#7C3AED",
        coverUrl: String = "",
        locationName: String = "",
        isPrivate: Bool = false,
        followersCount: Int = 0,
        followingCount: Int = 0,
        friendsCount: Int = 0,
        isFollowing: Bool = false,
        friendshipStatus: String = "none",
        distanceKm: Double? = nil,
        isActive: Bool = false,
        age: Int = 0,
        gender: String = "",
        orientation: String = "",
        communityRole: String = "",
        coins: Int = 0,
        height: Int = 0,
        weight: Int = 0,
        pronouns: String = "",
        relationshipRole: String = "",
        lookingFor: String = "",
        occupation: String = "",
        school: String = "",
        city: String = "",
        interests: [String] = [],
        cloudChatSync: Bool = true,
        postsCount: Int = 0,
        joinedAt: Int64 = 0,
        identityPublic: Bool = true,
        profileVisibility: [String: Bool] = [:],
        showActivity: Bool = true,
        showDistance: Bool = true,
        discoverable: Bool = true,
        hasLocation: Bool = false,
        dmMode: String = "everyone",
        accountRole: String = ""
    ) {
        self.id = id
        self.name = name
        self.handle = handle
        self.email = email
        self.phone = phone
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.avatarColor = avatarColor
        self.coverUrl = coverUrl
        self.locationName = locationName
        self.isPrivate = isPrivate
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.friendsCount = friendsCount
        self.isFollowing = isFollowing
        self.friendshipStatus = friendshipStatus
        self.distanceKm = distanceKm
        self.isActive = isActive
        self.age = age
        self.gender = gender
        self.orientation = orientation
        self.communityRole = communityRole
        self.coins = coins
        self.height = height
        self.weight = weight
        self.pronouns = pronouns
        self.relationshipRole = relationshipRole
        self.lookingFor = lookingFor
        self.occupation = occupation
        self.school = school
        self.city = city
        self.interests = interests
        self.cloudChatSync = cloudChatSync
        self.postsCount = postsCount
        self.joinedAt = joinedAt
        self.identityPublic = identityPublic
        self.profileVisibility = profileVisibility
        self.showActivity = showActivity
        self.showDistance = showDistance
        self.discoverable = discoverable
        self.hasLocation = hasLocation
        self.dmMode = dmMode
        self.accountRole = accountRole
    }

    init(json: [String: Any]) {
        self = Self.from(json)
    }

    static var fallbackSelf: KinnectUser {
        KinnectUser.from([
            "id": "me",
            "name": "Tôi",
            "handle": "me",
            "avatarColor": "#7C3AED"
        ])
    }

    static func from(_ dict: [String: Any]) -> KinnectUser {
        let uid = (dict["id"] as? String) ?? (dict["userId"] as? String) ?? ""
        let rawName = (dict["name"] as? String) ?? (dict["displayName"] as? String) ?? (dict["username"] as? String) ?? "Người dùng Kinnect"
        var av = (dict["avatarUrl"] as? String) ?? (dict["avatar"] as? String) ?? ""
        if av.isEmpty, (dict["hasAvatar"] as? Bool) == true, !uid.isEmpty {
            av = "/api/users/\(uid)/avatar"
        }
        let cov = (dict["coverUrl"] as? String) ?? (dict["cover"] as? String) ?? ""
        var parsedInterests: [String] = []
        if let arr = dict["interests"] as? [String] {
            parsedInterests = arr
        } else if let str = dict["interests"] as? String {
            parsedInterests = str.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let userCity = (dict["city"] as? String) ?? (dict["locationName"] as? String) ?? ""
        var visDict: [String: Bool] = [:]
        if let pv = dict["profileVisibility"] as? [String: Any] {
            for (k, v) in pv {
                if let b = v as? Bool {
                    visDict[k] = b
                }
            }
        }
        let joined: Int64 = (dict["joinedAt"] as? Int64) ?? (dict["joinedAt"] as? NSNumber)?.int64Value ?? Int64((dict["joinedAt"] as? Int) ?? 0)

        return KinnectUser(
            id: uid,
            name: rawName.isEmpty ? "Người dùng Kinnect" : rawName,
            handle: (dict["handle"] as? String) ?? (dict["username"] as? String) ?? "",
            email: (dict["email"] as? String) ?? "",
            phone: (dict["phone"] as? String) ?? "",
            bio: (dict["bio"] as? String) ?? "",
            avatarUrl: av,
            avatarColor: (dict["avatarColor"] as? String) ?? (dict["color"] as? String) ?? "#7C3AED",
            coverUrl: cov,
            locationName: userCity,
            isPrivate: (dict["isPrivate"] as? Bool) ?? false,
            followersCount: (dict["followersCount"] as? Int) ?? (dict["followers"] as? Int) ?? 0,
            followingCount: (dict["followingCount"] as? Int) ?? (dict["followingTotal"] as? Int) ?? 0,
            friendsCount: (dict["friendsCount"] as? Int) ?? (dict["friends"] as? Int) ?? 0,
            isFollowing: (dict["isFollowing"] as? Bool) ?? (dict["following"] as? Bool) ?? false,
            friendshipStatus: (dict["friendshipStatus"] as? String) ?? (dict["friendship"] as? String) ?? "none",
            distanceKm: (dict["distanceKm"] as? NSNumber)?.doubleValue,
            isActive: (dict["isActive"] as? Bool) ?? false,
            age: (dict["age"] as? Int) ?? (dict["userAge"] as? Int) ?? 0,
            gender: (dict["gender"] as? String) ?? "",
            orientation: (dict["orientation"] as? String) ?? (dict["sexualOrientation"] as? String) ?? "",
            communityRole: (dict["communityRole"] as? String) ?? (dict["role"] as? String) ?? "",
            coins: (dict["coins"] as? Int) ?? (dict["coinBalance"] as? Int) ?? (dict["balance"] as? Int) ?? ((dict["coins"] as? NSNumber)?.intValue) ?? 0,
            height: (dict["height"] as? Int) ?? Int((dict["height"] as? String) ?? "") ?? 0,
            weight: (dict["weight"] as? Int) ?? Int((dict["weight"] as? String) ?? "") ?? 0,
            pronouns: (dict["pronouns"] as? String) ?? "",
            relationshipRole: (dict["relationshipRole"] as? String) ?? "",
            lookingFor: (dict["lookingFor"] as? String) ?? "",
            occupation: (dict["occupation"] as? String) ?? "",
            school: (dict["school"] as? String) ?? "",
            city: userCity,
            interests: parsedInterests,
            cloudChatSync: (dict["cloudChatSync"] as? Bool) ?? true,
            postsCount: (dict["postsCount"] as? Int) ?? (dict["posts"] as? Int) ?? (dict["postCount"] as? Int) ?? 0,
            joinedAt: joined,
            identityPublic: (dict["identityPublic"] as? Bool) ?? true,
            profileVisibility: visDict,
            showActivity: (dict["showActivity"] as? Bool) ?? ((dict["show_activity"] as? Int) == 1) ?? true,
            showDistance: (dict["showDistance"] as? Bool) ?? ((dict["show_distance"] as? Int) == 1) ?? true,
            discoverable: (dict["discoverable"] as? Bool) ?? ((dict["discoverable"] as? Int) == 1) ?? true,
            hasLocation: (dict["hasLocation"] as? Bool) ?? false,
            dmMode: {
                let raw = (dict["dmMode"] as? String) ?? (dict["dm_mode"] as? String) ?? "everyone"
                return raw == "friends" ? "friends" : "everyone"
            }(),
            accountRole: (dict["role"] as? String) ?? ""
        )
    }
}

struct PostItem: Identifiable, Equatable {
    var id: String
    var author: KinnectUser
    var text: String
    var imageUrl: String
    var category: String
    var createdAt: String
    var likesCount: Int
    var commentsCount: Int
    var liked: Bool
    var userReaction: String
    var mediaKind: String = "image"

    static func from(_ dict: [String: Any]) -> PostItem {
        let authorDict = (dict["author"] as? [String: Any]) ?? (dict["user"] as? [String: Any]) ?? dict
        let mediaDict = dict["media"] as? [String: Any]
        let img = (dict["imageUrl"] as? String) ?? (dict["image"] as? String) ?? (mediaDict?["url"] as? String) ?? ""
        return PostItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            author: KinnectUser.from(authorDict),
            text: (dict["text"] as? String) ?? (dict["body"] as? String) ?? (dict["content"] as? String) ?? "",
            imageUrl: img,
            category: (dict["category"] as? String) ?? "community",
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"]),
            likesCount: (dict["likesCount"] as? Int) ?? (dict["likes"] as? Int) ?? 0,
            commentsCount: (dict["commentsCount"] as? Int) ?? (dict["comments"] as? Int) ?? 0,
            liked: (dict["liked"] as? Bool) ?? false,
            userReaction: (dict["userReaction"] as? String) ?? (dict["myReaction"] as? String) ?? "like",
            mediaKind: (mediaDict?["kind"] as? String) ?? (dict["mediaKind"] as? String) ?? (img.lowercased().contains(".mp4") ? "video" : "image")
        )
    }
}

struct StoryItem: Identifiable, Equatable {
    var id: String
    var author: KinnectUser
    var text: String
    var imageUrl: String
    var backgroundColor: String
    var createdAt: String
    var viewsCount: Int
    var viewed: Bool
    var mediaKind: String = "image"

    static func from(_ dict: [String: Any]) -> StoryItem {
        let authorDict = (dict["author"] as? [String: Any]) ?? (dict["user"] as? [String: Any]) ?? dict
        let mediaDict = dict["media"] as? [String: Any]
        let img = (dict["imageUrl"] as? String) ?? (dict["image"] as? String) ?? (mediaDict?["url"] as? String) ?? ""
        return StoryItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            author: KinnectUser.from(authorDict),
            text: (dict["text"] as? String) ?? (dict["body"] as? String) ?? (dict["caption"] as? String) ?? "",
            imageUrl: img,
            backgroundColor: (dict["backgroundColor"] as? String) ?? (dict["bgColor"] as? String) ?? "#7C3AED",
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"]),
            viewsCount: (dict["viewsCount"] as? Int) ?? (dict["viewCount"] as? Int) ?? 0,
            viewed: (dict["viewed"] as? Bool) ?? false,
            mediaKind: (mediaDict?["kind"] as? String) ?? (img.lowercased().contains(".mp4") ? "video" : "image")
        )
    }
}

struct CommentItem: Identifiable, Equatable {
    var id: String
    var author: KinnectUser
    var text: String
    var createdAt: String
    var likesCount: Int = 0
    var liked: Bool = false
    var parentId: String? = nil
    var myReaction: String = ""

    static func from(_ dict: [String: Any]) -> CommentItem {
        let authorDict = (dict["author"] as? [String: Any]) ?? (dict["user"] as? [String: Any]) ?? dict
        let pId = (dict["parentId"] as? String) ?? (dict["parent_id"] as? String)
        return CommentItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            author: KinnectUser.from(authorDict),
            text: (dict["text"] as? String) ?? (dict["body"] as? String) ?? (dict["content"] as? String) ?? "",
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"]),
            likesCount: (dict["likesCount"] as? Int) ?? (dict["likes"] as? Int) ?? (dict["reactions"] as? [String: Int])?.values.reduce(0, +) ?? 0,
            liked: (dict["liked"] as? Bool) ?? !((dict["myReaction"] as? String) ?? "").isEmpty,
            parentId: (pId != nil && !pId!.isEmpty) ? pId : nil,
            myReaction: (dict["myReaction"] as? String) ?? ((dict["liked"] as? Bool) == true ? "like" : "")
        )
    }
}

struct ShortItem: Identifiable, Equatable {
    var id: String
    var author: KinnectUser
    var title: String
    var caption: String
    var videoUrl: String
    var durationSec: Double
    var likesCount: Int
    var commentsCount: Int
    var viewsCount: Int
    var liked: Bool
    var createdAt: String

    static func from(_ dict: [String: Any]) -> ShortItem {
        let sid = (dict["id"] as? String) ?? UUID().uuidString
        let authorDict = (dict["author"] as? [String: Any]) ?? (dict["user"] as? [String: Any]) ?? dict
        let vUrl = (dict["videoUrl"] as? String) ?? (dict["video"] as? String) ?? "/api/shorts/\(sid)/video"
        return ShortItem(
            id: sid,
            author: KinnectUser.from(authorDict),
            title: (dict["title"] as? String) ?? "",
            caption: (dict["caption"] as? String) ?? (dict["description"] as? String) ?? "",
            videoUrl: vUrl,
            durationSec: (dict["durationSec"] as? NSNumber)?.doubleValue ?? (dict["duration"] as? NSNumber)?.doubleValue ?? 0,
            likesCount: (dict["likesCount"] as? Int) ?? (dict["likes"] as? Int) ?? 0,
            commentsCount: (dict["commentsCount"] as? Int) ?? (dict["comments"] as? Int) ?? 0,
            viewsCount: (dict["viewsCount"] as? Int) ?? (dict["views"] as? Int) ?? 0,
            liked: (dict["liked"] as? Bool) ?? false,
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"])
        )
    }
}

struct DirectMessageItem: Identifiable, Equatable {
    var id: String
    var fromUserId: String
    var toUserId: String
    var text: String
    var imageUrl: String
    var attachmentName: String = ""
    var attachmentUrl: String = ""
    var createdAt: String
    var deliveredAt: String
    var seenAt: String
    var reaction: String = ""
    var reactions: [String: Int] = [:]
    var myReaction: String = ""

    var isSeen: Bool { !seenAt.isEmpty }

    static func emoji(for canonical: String) -> String {
        switch canonical {
        case "like": return "👍"
        case "love": return "❤️"
        case "haha": return "😂"
        case "wow": return "😮"
        case "sad": return "😢"
        case "angry": return "😡"
        default: return canonical
        }
    }

    static func canonical(for emoji: String) -> String? {
        switch emoji {
        case "👍", "like": return "like"
        case "❤️", "love": return "love"
        case "😂", "haha": return "haha"
        case "😮", "wow": return "wow"
        case "😢", "sad": return "sad"
        case "😡", "angry": return "angry"
        default: return nil
        }
    }

    static func from(_ dict: [String: Any]) -> DirectMessageItem {
        let receipt = dict["receipt"] as? [String: Any]
        let att = dict["attachment"] as? [String: Any]
        let deliv = isoString(from: dict["deliveredAt"] ?? receipt?["deliveredAt"])
        let seen = isoString(from: dict["seenAt"] ?? dict["readAt"] ?? receipt?["seenAt"])
        let attName = (att?["name"] as? String) ?? (dict["attachmentName"] as? String) ?? ""
        let attData = (att?["data"] as? String) ?? (att?["url"] as? String) ?? (dict["attachmentUrl"] as? String) ?? ""
        var img = (dict["imageUrl"] as? String) ?? (dict["attachmentUrl"] as? String) ?? (att?["url"] as? String) ?? ""
        if img.isEmpty && attData.hasPrefix("data:image/") {
            img = attData
        }
        let isImage = !img.isEmpty || (att?["kind"] as? String == "image") || attName.hasSuffix(".png") || attName.hasSuffix(".jpg") || attName.hasSuffix(".jpeg") || attName.hasSuffix(".webp")
        let finalAttName = isImage ? "" : attName
        let finalAttUrl = isImage ? "" : attData
        if isImage && img.isEmpty {
            img = attData
        }
        let myRx = (dict["myReaction"] as? String) ?? (dict["reaction"] as? String) ?? (dict["rx"] as? String) ?? ""
        let rxDict = (dict["reactions"] as? [String: Int]) ?? [:]
        let effectiveRx = !myRx.isEmpty ? myRx : (rxDict.keys.first ?? "")
        return DirectMessageItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            fromUserId: (dict["fromUserId"] as? String) ?? (dict["senderId"] as? String) ?? (dict["sender"] as? String) ?? "",
            toUserId: (dict["toUserId"] as? String) ?? (dict["recipientId"] as? String) ?? (dict["recipient"] as? String) ?? "",
            text: (dict["text"] as? String) ?? (dict["body"] as? String) ?? (dict["content"] as? String) ?? "",
            imageUrl: img,
            attachmentName: finalAttName,
            attachmentUrl: finalAttUrl,
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"]),
            deliveredAt: deliv,
            seenAt: seen,
            reaction: effectiveRx,
            reactions: rxDict,
            myReaction: myRx
        )
    }
}

struct ChatGroupItem: Identifiable, Hashable, Equatable {
    var id: String
    var name: String
    var description: String
    var avatarColor: String
    var membersCount: Int
    var lastMessageText: String
    var unreadCount: Int
    var updatedAt: String
    var members: [KinnectUser] = []

    static func from(_ dict: [String: Any]) -> ChatGroupItem {
        let membersArray = (dict["members"] as? [[String: Any]])?.map(KinnectUser.from) ?? []
        let rawMembers = dict["members"] as? [Any]
        let lastObj = (dict["lastMessage"] as? [String: Any]) ?? (dict["last"] as? [String: Any])
        let lastText = (lastObj?["text"] as? String) ?? (lastObj?["body"] as? String) ?? (dict["lastMessageText"] as? String) ?? ""
        let updated = (lastObj?["createdAt"] as? String) ?? (dict["updatedAt"] as? String) ?? ""
        return ChatGroupItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            name: (dict["name"] as? String) ?? "Nhóm Kinnect",
            description: (dict["description"] as? String) ?? "",
            avatarColor: (dict["avatarColor"] as? String) ?? "#7C3AED",
            membersCount: (dict["membersCount"] as? Int) ?? rawMembers?.count ?? 1,
            lastMessageText: lastText,
            unreadCount: (dict["unreadCount"] as? Int) ?? (dict["unread"] as? Int) ?? 0,
            updatedAt: updated,
            members: membersArray
        )
    }
}

struct GroupMessageItem: Identifiable, Equatable {
    var id: String
    var groupId: String
    var sender: KinnectUser
    var text: String
    var imageUrl: String
    var attachmentName: String = ""
    var attachmentUrl: String = ""
    var createdAt: String
    var seenCount: Int
    var reaction: String = ""
    var reactions: [String: Int] = [:]
    var myReaction: String = ""

    static func from(_ dict: [String: Any]) -> GroupMessageItem {
        let senderDict = (dict["sender"] as? [String: Any]) ?? (dict["author"] as? [String: Any]) ?? (dict["user"] as? [String: Any]) ?? dict
        let receipt = dict["receipt"] as? [String: Any]
        let seenBy = dict["seenBy"] as? [Any]
        let att = dict["attachment"] as? [String: Any]
        let attName = (att?["name"] as? String) ?? (dict["attachmentName"] as? String) ?? ""
        let attData = (att?["data"] as? String) ?? (att?["url"] as? String) ?? (dict["attachmentUrl"] as? String) ?? ""
        var img = (dict["imageUrl"] as? String) ?? (dict["attachmentUrl"] as? String) ?? (att?["url"] as? String) ?? ""
        if img.isEmpty && attData.hasPrefix("data:image/") {
            img = attData
        }
        let isImage = !img.isEmpty || (att?["kind"] as? String == "image") || attName.hasSuffix(".png") || attName.hasSuffix(".jpg") || attName.hasSuffix(".jpeg") || attName.hasSuffix(".webp")
        let finalAttName = isImage ? "" : attName
        let finalAttUrl = isImage ? "" : attData
        if isImage && img.isEmpty {
            img = attData
        }
        let myRx = (dict["myReaction"] as? String) ?? (dict["reaction"] as? String) ?? (dict["rx"] as? String) ?? ""
        let rxDict = (dict["reactions"] as? [String: Int]) ?? [:]
        let effectiveRx = !myRx.isEmpty ? myRx : (rxDict.keys.first ?? "")
        return GroupMessageItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            groupId: (dict["groupId"] as? String) ?? (dict["group_id"] as? String) ?? "",
            sender: KinnectUser.from(senderDict),
            text: (dict["text"] as? String) ?? (dict["body"] as? String) ?? (dict["content"] as? String) ?? "",
            imageUrl: img,
            attachmentName: finalAttName,
            attachmentUrl: finalAttUrl,
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"]),
            seenCount: (dict["seenCount"] as? Int) ?? (receipt?["seenCount"] as? Int) ?? seenBy?.count ?? 0,
            reaction: effectiveRx,
            reactions: rxDict,
            myReaction: myRx
        )
    }
}

struct NotificationItem: Identifiable, Equatable {
    var id: String
    var type: String
    var preview: String
    var read: Bool
    var createdAt: String
    var actor: KinnectUser
    var ref: String = ""
    var commentId: String = ""

    static func from(_ dict: [String: Any]) -> NotificationItem {
        let actorDict = (dict["actor"] as? [String: Any]) ?? [:]
        let isSeen = ((dict["seen"] as? Int) ?? 0) != 0 || ((dict["seen"] as? Bool) == true) || ((dict["read"] as? Bool) == true)
        return NotificationItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            type: (dict["type"] as? String) ?? (dict["kind"] as? String) ?? "info",
            preview: (dict["preview"] as? String) ?? (dict["text"] as? String) ?? "",
            read: isSeen,
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"]),
            actor: KinnectUser.from(actorDict),
            ref: (dict["ref"] as? String) ?? (dict["targetId"] as? String) ?? "",
            commentId: (dict["commentId"] as? String) ?? ""
        )
    }
}

struct LiveRoomItem: Identifiable, Hashable, Equatable {
    var id: String
    var title: String
    var topic: String
    var liveMode: String // "chat" | "game" (no karaoke)
    var gameTitle: String
    var gamePaused: Bool
    var viewerCount: Int
    var likesCount: Int = 0
    var hostUserId: String
    var hostName: String
    var hostAvatarUrl: String
    var hostAvatarColor: String

    var hostId: String { hostUserId }

    static func from(_ dict: [String: Any]) -> LiveRoomItem {
        let hostDict = (dict["host"] as? [String: Any]) ?? [:]
        let rawMode = ((dict["liveMode"] as? String) ?? (dict["mode"] as? String) ?? "chat").lowercased()
        let normalizedMode = (rawMode == "game") ? "game" : "chat"
        let viewers = (dict["viewerCount"] as? Int) ?? (dict["viewers"] as? Int) ?? 0
        let likes = (dict["likesCount"] as? Int) ?? (dict["likes"] as? Int) ?? (dict["heartsCount"] as? Int) ?? (viewers * 12)
        return LiveRoomItem(
            id: (dict["id"] as? String) ?? (dict["roomId"] as? String) ?? UUID().uuidString,
            title: (dict["title"] as? String) ?? "Phòng Live Kinnect",
            topic: (dict["topic"] as? String) ?? "",
            liveMode: normalizedMode,
            gameTitle: (dict["gameTitle"] as? String) ?? "",
            gamePaused: (dict["gamePaused"] as? Bool) ?? false,
            viewerCount: viewers,
            likesCount: likes,
            hostUserId: (dict["hostUserId"] as? String) ?? (dict["hostId"] as? String) ?? (hostDict["id"] as? String) ?? "",
            hostName: (dict["hostName"] as? String) ?? (dict["host"] as? String) ?? (hostDict["name"] as? String) ?? "Chủ phòng",
            hostAvatarUrl: (dict["hostAvatarUrl"] as? String) ?? (dict["avatar"] as? String) ?? (hostDict["avatarUrl"] as? String) ?? "",
            hostAvatarColor: (dict["hostAvatarColor"] as? String) ?? (hostDict["avatarColor"] as? String) ?? "#7C3AED"
        )
    }
}

struct LiveChatMessage: Identifiable, Equatable {
    var id: String
    var user: KinnectUser
    var text: String
    var createdAt: String

    static func from(_ dict: [String: Any]) -> LiveChatMessage {
        let uDict = (dict["user"] as? [String: Any]) ?? dict
        return LiveChatMessage(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            user: KinnectUser.from(uDict),
            text: (dict["text"] as? String) ?? (dict["message"] as? String) ?? "",
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"])
        )
    }
}

struct LiveGiftCatalogItem: Identifiable, Equatable {
    var id: String
    var label: String
    var emoji: String
    var coins: Int
    var tier: String

    static func from(_ dict: [String: Any]) -> LiveGiftCatalogItem {
        LiveGiftCatalogItem(
            id: (dict["id"] as? String) ?? (dict["reaction"] as? String) ?? UUID().uuidString,
            label: (dict["label"] as? String) ?? (dict["name"] as? String) ?? "Quà tặng",
            emoji: (dict["emoji"] as? String) ?? (dict["icon"] as? String) ?? "🎁",
            coins: (dict["coins"] as? Int) ?? (dict["priceCoins"] as? Int) ?? (dict["price"] as? Int) ?? 10,
            tier: (dict["tier"] as? String) ?? "standard"
        )
    }

    static let defaultCatalog: [LiveGiftCatalogItem] = [
        LiveGiftCatalogItem(id: "rose", label: "Hoa hồng", emoji: "🌹", coins: 10, tier: "standard"),
        LiveGiftCatalogItem(id: "heart", label: "Trái tim", emoji: "💖", coins: 20, tier: "standard"),
        LiveGiftCatalogItem(id: "coffee", label: "Cà phê", emoji: "☕", coins: 50, tier: "standard"),
        LiveGiftCatalogItem(id: "love_gun", label: "Súng tình yêu", emoji: "🔫", coins: 100, tier: "rare"),
        LiveGiftCatalogItem(id: "fireworks", label: "Pháo hoa", emoji: "🎆", coins: 200, tier: "rare"),
        LiveGiftCatalogItem(id: "yacht", label: "Du thuyền", emoji: "🛥️", coins: 500, tier: "rare"),
        LiveGiftCatalogItem(id: "crown", label: "Vương miện", emoji: "👑", coins: 1000, tier: "epic"),
        LiveGiftCatalogItem(id: "diamond", label: "Kim cương", emoji: "💎", coins: 2000, tier: "epic"),
        LiveGiftCatalogItem(id: "sports_car", label: "Siêu xe", emoji: "🏎️", coins: 5000, tier: "legendary"),
        LiveGiftCatalogItem(id: "castle", label: "Lâu đài", emoji: "🏰", coins: 10000, tier: "legendary")
    ]
}

struct WalletEntryItem: Identifiable, Equatable {
    var id: String
    var kind: String
    var direction: String
    var amount: Int
    var title: String
    var note: String
    var createdAt: String

    static func from(_ dict: [String: Any]) -> WalletEntryItem {
        let rawAmount = (dict["amount"] as? Int) ?? (dict["coins"] as? Int) ?? 0
        let dir = (dict["direction"] as? String) ?? (rawAmount >= 0 ? "credit" : "debit")
        return WalletEntryItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            kind: (dict["kind"] as? String) ?? (dict["type"] as? String) ?? "entry",
            direction: dir,
            amount: abs(rawAmount),
            title: (dict["title"] as? String) ?? (dict["label"] as? String) ?? "Giao dịch ví",
            note: (dict["note"] as? String) ?? (dict["subtitle"] as? String) ?? "",
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"])
        )
    }
}

struct StorePackageItem: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var category: String
    var priceCoins: Int
    var badgeText: String
    var accentColor: String
    var owned: Bool
    var equipped: Bool
    var expiresAt: Int64?

    var kind: String { category }

    var iconName: String {
        Self.iconName(for: id, category: category)
    }

    static func iconName(for id: String, category: String) -> String {
        if id.starts(with: "studio_video_") { return "film.fill" }
        if id.starts(with: "studio_photo_") { return "photo.fill" }
        switch id {
        case "style_neon", "style_aurora", "style_forest": return "sparkles"
        case "style_galaxy": return "star.fill"
        case "style_ice": return "snowflake"
        case "style_ruby": return "heart.fill"
        case "style_paper": return "newspaper.fill"
        case "style_ember": return "flame.fill"
        case "live_chill": return "antenna.radiowaves.left.and.right"
        case "live_gaming", "live_game_30": return "gamecontroller.fill"
        case "live_spotlight": return "sparkles"
        case "gift_love": return "heart.fill"
        case "gift_speed": return "bolt.fill"
        case "gift_royal": return "crown.fill"
        case "member_plus": return "crown.fill"
        case "member_creator": return "film.fill"
        case "studio_7", "studio_30": return "slider.horizontal.3"
        default:
            switch category {
            case "style", "frame": return "paintpalette.fill"
            case "studio": return "film.fill"
            case "live": return "antenna.radiowaves.left.and.right"
            case "gift", "gifts": return "gift.fill"
            case "member", "membership": return "crown.fill"
            default: return "sparkles"
            }
        }
    }

    static func from(_ dict: [String: Any]) -> StorePackageItem {
        let colors = dict["colors"] as? [String]
        return StorePackageItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            title: (dict["title"] as? String) ?? (dict["name"] as? String) ?? "Gói Kinnect",
            subtitle: (dict["subtitle"] as? String) ?? (dict["description"] as? String) ?? "",
            category: (dict["category"] as? String) ?? (dict["kind"] as? String) ?? "frame",
            priceCoins: (dict["priceCoins"] as? Int) ?? (dict["price"] as? Int) ?? 0,
            badgeText: (dict["badgeText"] as? String) ?? (dict["tier"] as? String) ?? "",
            accentColor: (dict["accentColor"] as? String) ?? colors?.first ?? "#7C3AED",
            owned: (dict["owned"] as? Bool) ?? false,
            equipped: (dict["equipped"] as? Bool) ?? false,
            expiresAt: (dict["expiresAt"] as? NSNumber)?.int64Value
        )
    }
}

struct StoreDigitalProduct: Identifiable, Equatable {
    var id: String
    var title: String
    var description: String
    var priceLabel: String
    var coinsGranted: Int

    static func from(_ dict: [String: Any]) -> StoreDigitalProduct {
        let vnd = (dict["referenceVnd"] as? Int) ?? 0
        let fallbackPrice = vnd > 0 ? "\(vnd)đ" : "StoreKit 2"
        return StoreDigitalProduct(
            id: (dict["id"] as? String) ?? (dict["productId"] as? String) ?? "",
            title: (dict["title"] as? String) ?? (dict["name"] as? String) ?? "Gói nạp",
            description: (dict["description"] as? String) ?? "",
            priceLabel: (dict["priceLabel"] as? String) ?? fallbackPrice,
            coinsGranted: (dict["coinsGranted"] as? Int) ?? (dict["coins"] as? Int) ?? 0
        )
    }
}

struct GiftInventoryItem: Identifiable, Equatable {
    var id: String { giftId }
    let giftId: String
    var quantity: Int
    var name: String {
        switch giftId {
        case "rose": return "Hoa hồng"
        case "coffee": return "Cà phê"
        case "heart": return "Trái tim"
        case "love_gun": return "Súng bắn tim"
        case "diamond": return "Kim cương"
        case "crown": return "Vương miện"
        case "sports_car": return "Siêu xe"
        case "yacht": return "Du thuyền"
        case "castle": return "Lâu đài"
        case "fireworks": return "Pháo hoa"
        default: return giftId
        }
    }
}

extension Int {
    func formattedWithSeparator() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
