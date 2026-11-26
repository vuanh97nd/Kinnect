import Foundation

private func isoString(from anyVal: Any?) -> String {
    if let s = anyVal as? String, !s.isEmpty {
        return s
    }
    if let n = anyVal as? NSNumber {
        let ms = n.doubleValue
        guard ms > 0 else { return "" }
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
    var groupRole: String = ""
    var hasPassword: Bool = true

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
        accountRole: String = "",
        groupRole: String = "",
        hasPassword: Bool = true
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
        self.groupRole = groupRole
        self.hasPassword = hasPassword
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
            communityRole: (dict["communityRole"] as? String) ?? "",
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
            showActivity: (dict["showActivity"] as? Bool)
                ?? (dict["show_activity"] as? Int).map { $0 == 1 }
                ?? (dict["activityShared"] as? Bool)
                ?? (dict["activity_shared"] as? Int).map { $0 == 1 }
                ?? false,
            showDistance: (dict["showDistance"] as? Bool) ?? (dict["show_distance"] as? Int).map { $0 == 1 } ?? true,
            discoverable: (dict["discoverable"] as? Bool) ?? (dict["discoverable"] as? Int).map { $0 == 1 } ?? true,
            hasLocation: (dict["hasLocation"] as? Bool) ?? false,
            dmMode: {
                let raw = (dict["dmMode"] as? String) ?? (dict["dm_mode"] as? String) ?? "everyone"
                return raw == "friends" ? "friends" : "everyone"
            }(),
            accountRole: (dict["role"] as? String) ?? "",
            groupRole: (dict["groupRole"] as? String) ?? (dict["group_role"] as? String) ?? "",
            hasPassword: (dict["hasPassword"] as? Bool) ?? true
        )
    }
}

struct PostMediaEntry: Identifiable, Equatable {
    var id: String
    var position: Int
    var kind: String
    var url: String
    var thumbnail: String = ""

    static func from(_ dict: [String: Any]) -> PostMediaEntry {
        PostMediaEntry(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            position: (dict["position"] as? Int) ?? 0,
            kind: (dict["kind"] as? String) ?? "image",
            url: (dict["url"] as? String) ?? "",
            thumbnail: (dict["thumbnail"] as? String) ?? ""
        )
    }
}

struct SharedPostPreview: Identifiable, Equatable {
    var id: String
    var author: KinnectUser
    var text: String
    var createdAt: String
    var imageUrl: String
    var mediaKind: String
    var thumbnailUrl: String = ""
    var mediaItems: [PostMediaEntry]

    static func from(_ dict: [String: Any]) -> SharedPostPreview {
        let authorDict = (dict["author"] as? [String: Any]) ?? dict
        let mediaDict = dict["media"] as? [String: Any]
        let items = (dict["mediaItems"] as? [[String: Any]])?.map(PostMediaEntry.from) ?? []
        return SharedPostPreview(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            author: KinnectUser.from(authorDict),
            text: (dict["body"] as? String) ?? (dict["text"] as? String) ?? "",
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"]),
            imageUrl: (mediaDict?["url"] as? String) ?? items.first?.url ?? "",
            mediaKind: (mediaDict?["kind"] as? String) ?? items.first?.kind ?? "image",
            thumbnailUrl: (mediaDict?["thumbnail"] as? String) ?? (dict["thumbnailUrl"] as? String) ?? items.first?.thumbnail ?? "",
            mediaItems: items
        )
    }
}

struct ChatReplyPreview: Equatable {
    var id: String
    var sender: String
    var senderName: String
    var body: String
    var recalled: Bool
    var unavailable: Bool
    var attachmentKind: String

    static func from(_ dict: [String: Any]) -> ChatReplyPreview {
        ChatReplyPreview(
            id: (dict["id"] as? String) ?? "",
            sender: (dict["sender"] as? String) ?? "",
            senderName: (dict["senderName"] as? String) ?? "",
            body: (dict["body"] as? String) ?? "",
            recalled: (dict["recalled"] as? Bool) ?? false,
            unavailable: (dict["unavailable"] as? Bool) ?? false,
            attachmentKind: (dict["attachmentKind"] as? String) ?? ""
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
    var reactions: [String: Int] = [:]
    var mediaKind: String = "image"
    var thumbnailUrl: String = ""
    var mediaItems: [PostMediaEntry] = []
    var hashtags: [String] = []
    var bookmarked: Bool = false
    var sharesCount: Int = 0
    var sharedPost: SharedPostPreview? = nil
    var visibility: String = "public"

    static func from(_ dict: [String: Any]) -> PostItem {
        let authorDict = (dict["author"] as? [String: Any]) ?? (dict["user"] as? [String: Any]) ?? dict
        let mediaDict = dict["media"] as? [String: Any]
        let img = (dict["imageUrl"] as? String) ?? (dict["image"] as? String) ?? (mediaDict?["url"] as? String) ?? ""
        let items = (dict["mediaItems"] as? [[String: Any]])?.map(PostMediaEntry.from) ?? []
        let tags = (dict["hashtags"] as? [String]) ?? []
        let shared = (dict["sharedPost"] as? [String: Any]).map(SharedPostPreview.from)
        let isLiked = (dict["liked"] as? Bool) ?? false
        let rawReaction = (dict["userReaction"] as? String) ?? (dict["myReaction"] as? String)
        let resolvedReaction = (rawReaction?.isEmpty == false) ? rawReaction! : (isLiked ? "like" : "")
        var rxCounts: [String: Int] = [:]
        if let rawRx = dict["reactions"] as? [String: Any] {
            for (k, v) in rawRx {
                if let n = v as? Int, n > 0 { rxCounts[k] = n }
                else if let n = (v as? NSNumber)?.intValue, n > 0 { rxCounts[k] = n }
            }
        }
        return PostItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            author: KinnectUser.from(authorDict),
            text: (dict["text"] as? String) ?? (dict["body"] as? String) ?? (dict["content"] as? String) ?? "",
            imageUrl: img,
            category: (dict["category"] as? String) ?? "community",
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"]),
            likesCount: (dict["likesCount"] as? Int) ?? (dict["likes"] as? Int) ?? 0,
            commentsCount: (dict["commentsCount"] as? Int) ?? (dict["comments"] as? Int) ?? 0,
            liked: isLiked,
            userReaction: resolvedReaction,
            reactions: rxCounts,
            mediaKind: (mediaDict?["kind"] as? String) ?? (dict["mediaKind"] as? String) ?? (img.lowercased().contains(".mp4") ? "video" : "image"),
            thumbnailUrl: (mediaDict?["thumbnail"] as? String) ?? (dict["thumbnailUrl"] as? String) ?? items.first?.thumbnail ?? "",
            mediaItems: items,
            hashtags: tags,
            bookmarked: (dict["bookmarked"] as? Bool) ?? false,
            sharesCount: (dict["shares"] as? Int) ?? 0,
            sharedPost: shared,
            visibility: (dict["visibility"] as? String) ?? "public"
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
    var thumbnailUrl: String = ""

    static func from(_ dict: [String: Any]) -> StoryItem {
        let authorDict = (dict["author"] as? [String: Any]) ?? (dict["user"] as? [String: Any]) ?? dict
        let mediaDict = dict["media"] as? [String: Any]
        let img = (dict["imageUrl"] as? String) ?? (dict["image"] as? String) ?? (mediaDict?["url"] as? String) ?? ""
        let bgHex: String = {
            if let explicit = (dict["backgroundColor"] as? String) ?? (dict["bgColor"] as? String), !explicit.isEmpty {
                return explicit
            }
            switch ((dict["background"] as? String) ?? "").lowercased() {
            case "sunset": return "#F59E0B"
            case "forest": return "#059669"
            case "ocean": return "#0EA5E9"
            case "purple": return "#7C3AED"
            case let raw where raw.hasPrefix("#"): return raw
            default: return "#7C3AED"
            }
        }()
        return StoryItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            author: KinnectUser.from(authorDict),
            text: (dict["text"] as? String) ?? (dict["body"] as? String) ?? (dict["caption"] as? String) ?? "",
            imageUrl: img,
            backgroundColor: bgHex,
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"]),
            viewsCount: (dict["viewsCount"] as? Int) ?? (dict["viewCount"] as? Int) ?? 0,
            viewed: (dict["viewed"] as? Bool) ?? false,
            mediaKind: (mediaDict?["kind"] as? String) ?? (img.lowercased().contains(".mp4") ? "video" : "image"),
            thumbnailUrl: (mediaDict?["thumbnail"] as? String) ?? (dict["thumbnailUrl"] as? String) ?? (dict["thumbnail"] as? String) ?? ""
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
    var thumbnailUrl: String = ""

    static func from(_ dict: [String: Any]) -> ShortItem {
        let sid = (dict["id"] as? String) ?? UUID().uuidString
        let authorDict = (dict["author"] as? [String: Any]) ?? (dict["user"] as? [String: Any]) ?? dict
        let vUrl = (dict["videoUrl"] as? String) ?? (dict["video"] as? String) ?? "/api/shorts/\(sid)/video"
        let thumb = (dict["thumbnail"] as? String) ?? (dict["thumbnailUrl"] as? String) ?? ""
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
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"]),
            thumbnailUrl: thumb
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
    var replyTo: ChatReplyPreview? = nil
    var editedAt: String = ""
    var recalled: Bool = false

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
        let explicitImg = (dict["imageUrl"] as? String) ?? ""
        let attKind = (att?["kind"] as? String) ?? ""
        let isImage = (attKind == "image") || attData.hasPrefix("data:image/") || !explicitImg.isEmpty
        let img = isImage ? (!explicitImg.isEmpty ? explicitImg : attData) : ""
        let finalAttName = isImage ? "" : attName
        let finalAttUrl = isImage ? "" : attData
        let myRx = (dict["myReaction"] as? String) ?? (dict["reaction"] as? String) ?? (dict["rx"] as? String) ?? ""
        let rxDict = (dict["reactions"] as? [String: Int]) ?? [:]
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
            reaction: myRx,
            reactions: rxDict,
            myReaction: myRx,
            replyTo: (dict["replyTo"] as? [String: Any]).map(ChatReplyPreview.from),
            editedAt: dict["editedAt"] != nil && !(dict["editedAt"] is NSNull) ? isoString(from: dict["editedAt"]) : "",
            recalled: (dict["recalled"] as? Bool) ?? ((dict["recalled"] as? Int) == 1)
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
    var avatarUrl: String = ""
    var ownerId: String = ""

    static func from(_ dict: [String: Any]) -> ChatGroupItem {
        let membersArray = (dict["members"] as? [[String: Any]])?.map(KinnectUser.from) ?? []
        let rawMembers = dict["members"] as? [Any]
        let lastObj = (dict["lastMessage"] as? [String: Any]) ?? (dict["last"] as? [String: Any])
        let lastText = (lastObj?["text"] as? String) ?? (lastObj?["body"] as? String) ?? (dict["lastMessageText"] as? String) ?? ""
        let updated = isoString(from: lastObj?["createdAt"] ?? lastObj?["created"] ?? dict["updatedAt"] ?? dict["created"])
        let av = (dict["avatarUrl"] as? String) ?? (dict["avatar"] as? String) ?? ""
        let owner = (dict["owner"] as? String) ?? (dict["ownerId"] as? String) ?? ""
        return ChatGroupItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            name: (dict["name"] as? String) ?? "Nhóm Kinnect",
            description: (dict["description"] as? String) ?? "",
            avatarColor: (dict["avatarColor"] as? String) ?? "#7C3AED",
            membersCount: (dict["membersCount"] as? Int) ?? rawMembers?.count ?? 1,
            lastMessageText: lastText,
            unreadCount: (dict["unreadCount"] as? Int) ?? (dict["unread"] as? Int) ?? 0,
            updatedAt: updated,
            members: membersArray,
            avatarUrl: av,
            ownerId: owner
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
    var replyTo: ChatReplyPreview? = nil
    var editedAt: String = ""
    var recalled: Bool = false

    static func from(_ dict: [String: Any]) -> GroupMessageItem {
        let senderDict = (dict["sender"] as? [String: Any]) ?? (dict["author"] as? [String: Any]) ?? (dict["user"] as? [String: Any]) ?? dict
        let receipt = dict["receipt"] as? [String: Any]
        let seenBy = dict["seenBy"] as? [Any]
        let att = dict["attachment"] as? [String: Any]
        let attName = (att?["name"] as? String) ?? (dict["attachmentName"] as? String) ?? ""
        let attData = (att?["data"] as? String) ?? (att?["url"] as? String) ?? (dict["attachmentUrl"] as? String) ?? ""
        let explicitImg = (dict["imageUrl"] as? String) ?? ""
        let attKind = (att?["kind"] as? String) ?? ""
        let isImage = (attKind == "image") || attData.hasPrefix("data:image/") || !explicitImg.isEmpty
        let img = isImage ? (!explicitImg.isEmpty ? explicitImg : attData) : ""
        let finalAttName = isImage ? "" : attName
        let finalAttUrl = isImage ? "" : attData
        let myRx = (dict["myReaction"] as? String) ?? (dict["reaction"] as? String) ?? (dict["rx"] as? String) ?? ""
        let rxDict = (dict["reactions"] as? [String: Int]) ?? [:]
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
            reaction: myRx,
            reactions: rxDict,
            myReaction: myRx,
            replyTo: (dict["replyTo"] as? [String: Any]).map(ChatReplyPreview.from),
            editedAt: dict["editedAt"] != nil && !(dict["editedAt"] is NSNull) ? isoString(from: dict["editedAt"]) : "",
            recalled: (dict["recalled"] as? Bool) ?? ((dict["recalled"] as? Int) == 1)
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
    var targetKind: String = ""

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
            commentId: (dict["commentId"] as? String) ?? "",
            targetKind: (dict["targetKind"] as? String) ?? (dict["target_kind"] as? String) ?? ""
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
    var comments: Bool = true
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
            gamePaused: (dict["gamePaused"] as? Bool) ?? (dict["screenPaused"] as? Bool) ?? false,
            comments: (dict["comments"] as? Bool) ?? true,
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
        let parsedUser: KinnectUser
        if let userDict = dict["user"] as? [String: Any] {
            parsedUser = KinnectUser.from(userDict)
        } else {
            let senderId = (dict["senderId"] as? String) ?? (dict["userId"] as? String) ?? ""
            var synthDict: [String: Any] = [
                "id": senderId,
                "name": (dict["name"] as? String) ?? (dict["senderName"] as? String) ?? "Người dùng Kinnect"
            ]
            if let av = (dict["avatarUrl"] as? String) ?? (dict["avatar"] as? String) {
                synthDict["avatarUrl"] = av
            }
            if let col = (dict["avatarColor"] as? String) ?? (dict["color"] as? String) {
                synthDict["avatarColor"] = col
            }
            if let handle = (dict["username"] as? String) ?? (dict["handle"] as? String) {
                synthDict["username"] = handle
            }
            parsedUser = KinnectUser.from(synthDict)
        }
        return LiveChatMessage(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            user: parsedUser,
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
    var colorHex: String {
        Self.defaultColorHex(for: id)
    }

    static func defaultEmoji(for id: String) -> String {
        switch id {
        case "rose": return "🌹"
        case "heart": return "💖"
        case "coffee": return "☕"
        case "star": return "⭐"
        case "love_gun": return "🔫"
        case "fireworks": return "🎆"
        case "crown": return "👑"
        case "car", "sports_car": return "🏎️"
        case "yacht": return "🛥️"
        case "diamond": return "💎"
        case "rocket": return "🚀"
        case "castle": return "🏰"
        case "aurora": return "🌌"
        case "meteor": return "☄️"
        case "butterfly": return "🦋"
        case "lotus": return "🪷"
        case "phoenix": return "🐦‍🔥"
        case "universe": return "🪐"
        default: return "🎁"
        }
    }

    static func defaultName(for id: String) -> String {
        switch id {
        case "rose": return "Hoa hồng"
        case "heart": return "Trái tim"
        case "coffee": return "Cà phê"
        case "star": return "Sao pha lê"
        case "love_gun": return "Súng tình yêu"
        case "fireworks": return "Pháo hoa"
        case "crown": return "Vương miện"
        case "car": return "Siêu xe"
        case "sports_car": return "Siêu xe thể thao"
        case "yacht": return "Du thuyền"
        case "diamond": return "Kim cương"
        case "rocket": return "Tên lửa"
        case "castle": return "Lâu đài"
        case "aurora": return "Cực quang"
        case "meteor": return "Sao băng"
        case "butterfly": return "Bướm mộng"
        case "lotus": return "Sen ánh sáng"
        case "phoenix": return "Phượng hoàng"
        case "universe": return "Vũ trụ"
        default: return "Quà tặng"
        }
    }

    static func defaultColorHex(for id: String) -> String {
        switch id {
        case "rose": return "#F43F5E"
        case "heart": return "#EC4899"
        case "coffee": return "#D97706"
        case "star": return "#FBBF24"
        case "love_gun": return "#FB7185"
        case "fireworks": return "#A855F7"
        case "crown": return "#F59E0B"
        case "car", "sports_car": return "#EF4444"
        case "yacht": return "#0EA5E9"
        case "diamond": return "#38BDF8"
        case "rocket": return "#F97316"
        case "castle": return "#8B5CF6"
        case "aurora": return "#10B981"
        case "meteor": return "#6366F1"
        case "butterfly": return "#E879F9"
        case "lotus": return "#F472B6"
        case "phoenix": return "#EA580C"
        case "universe": return "#7C3AED"
        default: return "#7C3AED"
        }
    }

    static func defaultCostCoins(for id: String) -> Int {
        switch id {
        case "rose": return 50
        case "heart": return 50
        case "coffee": return 100
        case "star": return 100
        case "love_gun": return 150
        case "butterfly": return 150
        case "fireworks": return 200
        case "crown": return 200
        case "lotus": return 250
        case "aurora": return 300
        case "meteor": return 400
        case "diamond": return 500
        case "car": return 800
        case "sports_car": return 1000
        case "rocket": return 1000
        case "yacht": return 1200
        case "phoenix": return 1500
        case "castle": return 2000
        case "universe": return 5000
        default: return 50
        }
    }

    static func from(_ dict: [String: Any]) -> LiveGiftCatalogItem {
        let giftId = (dict["id"] as? String) ?? (dict["reaction"] as? String) ?? UUID().uuidString
        let rawEmoji = (dict["emoji"] as? String) ?? (dict["icon"] as? String) ?? ""
        return LiveGiftCatalogItem(
            id: giftId,
            label: (dict["label"] as? String) ?? (dict["name"] as? String) ?? defaultName(for: giftId),
            emoji: rawEmoji.isEmpty ? defaultEmoji(for: giftId) : rawEmoji,
            coins: (dict["costCoins"] as? Int) ?? (dict["coins"] as? Int) ?? (dict["priceCoins"] as? Int) ?? (dict["price"] as? Int) ?? defaultCostCoins(for: giftId),
            tier: (dict["tier"] as? String) ?? "standard"
        )
    }

    static let defaultCatalog: [LiveGiftCatalogItem] = [
        LiveGiftCatalogItem(id: "rose", label: "Hoa hồng", emoji: "🌹", coins: 50, tier: "small"),
        LiveGiftCatalogItem(id: "heart", label: "Trái tim", emoji: "💖", coins: 50, tier: "small"),
        LiveGiftCatalogItem(id: "coffee", label: "Cà phê", emoji: "☕", coins: 100, tier: "small"),
        LiveGiftCatalogItem(id: "star", label: "Sao pha lê", emoji: "⭐", coins: 100, tier: "small"),
        LiveGiftCatalogItem(id: "love_gun", label: "Súng tình yêu", emoji: "🔫", coins: 150, tier: "medium"),
        LiveGiftCatalogItem(id: "butterfly", label: "Bướm mộng", emoji: "🦋", coins: 150, tier: "small"),
        LiveGiftCatalogItem(id: "fireworks", label: "Pháo hoa", emoji: "🎆", coins: 200, tier: "medium"),
        LiveGiftCatalogItem(id: "crown", label: "Vương miện", emoji: "👑", coins: 200, tier: "medium"),
        LiveGiftCatalogItem(id: "lotus", label: "Sen ánh sáng", emoji: "🪷", coins: 250, tier: "medium"),
        LiveGiftCatalogItem(id: "aurora", label: "Cực quang", emoji: "🌌", coins: 300, tier: "medium"),
        LiveGiftCatalogItem(id: "meteor", label: "Sao băng", emoji: "☄️", coins: 400, tier: "medium"),
        LiveGiftCatalogItem(id: "diamond", label: "Kim cương", emoji: "💎", coins: 500, tier: "medium"),
        LiveGiftCatalogItem(id: "car", label: "Siêu xe", emoji: "🏎️", coins: 800, tier: "large"),
        LiveGiftCatalogItem(id: "sports_car", label: "Siêu xe thể thao", emoji: "🏎️", coins: 1000, tier: "large"),
        LiveGiftCatalogItem(id: "yacht", label: "Du thuyền", emoji: "🛥️", coins: 1200, tier: "large"),
        LiveGiftCatalogItem(id: "castle", label: "Lâu đài", emoji: "🏰", coins: 2000, tier: "legendary")
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
    var category: String = ""
    var currency: String = "coins"
    var creatorVnd: Int = 0

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
            createdAt: isoString(from: dict["createdAt"] ?? dict["created"]),
            category: (dict["category"] as? String) ?? "",
            currency: (dict["currency"] as? String) ?? "coins",
            creatorVnd: (dict["creatorVnd"] as? Int) ?? (dict["creator_vnd"] as? Int) ?? 0
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
    var kind: String = "style"
    var title: String
    var description: String
    var priceLabel: String
    var coinsGranted: Int
    var accentColor: String = "#7C3AED"
    var secondaryColor: String = "#EC4899"
    var owned: Bool = false
    var equipped: Bool = false

    static func from(_ dict: [String: Any]) -> StoreDigitalProduct {
        let prodId = (dict["id"] as? String) ?? (dict["productId"] as? String) ?? ""
        let vnd = (dict["referenceVnd"] as? Int) ?? 0
        let fallbackPrice = vnd > 0 ? "\(vnd.formattedWithSeparator())đ" : "App Store"
        let colors = dict["colors"] as? [String] ?? []
        let coinsGranted = (dict["coinsGranted"] as? Int) ?? (dict["coins"] as? Int) ?? 0
        let explicitKind = ((dict["kind"] as? String) ?? (dict["category"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerId = prodId.lowercased()
        let resolvedKind: String
        if !explicitKind.isEmpty {
            resolvedKind = explicitKind
        } else if coinsGranted > 0 || lowerId.contains(".coins.") || lowerId.hasPrefix("coins_") {
            resolvedKind = "coins"
        } else if lowerId.contains("studio") {
            resolvedKind = "studio"
        } else {
            resolvedKind = "style"
        }
        return StoreDigitalProduct(
            id: prodId,
            kind: resolvedKind,
            title: (dict["title"] as? String) ?? (dict["name"] as? String) ?? "Gói Kinnect",
            description: (dict["description"] as? String) ?? "",
            priceLabel: (dict["priceLabel"] as? String) ?? fallbackPrice,
            coinsGranted: coinsGranted,
            accentColor: colors.first ?? "#7C3AED",
            secondaryColor: colors.count > 1 ? colors[1] : (colors.first ?? "#C026D3"),
            owned: (dict["owned"] as? Bool) ?? false,
            equipped: (dict["equipped"] as? Bool) ?? false
        )
    }
}

struct GiftInventoryItem: Identifiable, Equatable {
    var id: String { source.isEmpty ? giftId : "\(giftId)_\(source)" }
    let giftId: String
    var quantity: Int
    var source: String = ""
    var name: String {
        Self.vietnameseName(for: giftId)
    }
    var emoji: String {
        Self.emoji(for: giftId)
    }

    static func vietnameseName(for giftId: String) -> String {
        switch giftId {
        case "rose": return "Hoa hồng"
        case "coffee": return "Cà phê"
        case "heart": return "Trái tim"
        case "star": return "Sao pha lê"
        case "love_gun": return "Súng tình yêu"
        case "fireworks": return "Pháo hoa"
        case "crown": return "Vương miện"
        case "car": return "Siêu xe"
        case "sports_car": return "Siêu xe thể thao"
        case "yacht": return "Du thuyền"
        case "diamond": return "Kim cương"
        case "rocket": return "Tên lửa"
        case "castle": return "Lâu đài"
        case "aurora": return "Cực quang"
        case "meteor": return "Sao băng"
        case "butterfly": return "Bướm mộng"
        case "lotus": return "Sen ánh sáng"
        case "phoenix": return "Phượng hoàng"
        case "universe": return "Vũ trụ"
        default: return giftId
        }
    }

    static func emoji(for giftId: String) -> String {
        LiveGiftCatalogItem.defaultEmoji(for: giftId)
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
