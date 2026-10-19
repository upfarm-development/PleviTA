
import Foundation

public struct Comment: Codable, Sendable, Identifiable, Equatable {
    public var commentId: String
    public var commentText: String?
    public var commentAuthor: String?
    public var commentAuthorId: String?
    public var commentAuthorThumbnail: String?
    public var commentAuthorIsUploader: Bool?
    public var commentTimeText: String?
    public var commentTimestamp: Double?
    public var commentLikecount: Int?
    public var commentIsFavorited: Bool?
    /// `"root"` for a top-level comment, else the parent comment's id.
    public var commentParent: String?
    /// Present only if the backend nests replies inline.
    public var commentReplies: [Comment]?

    public var id: String { commentId }

    enum CodingKeys: String, CodingKey {
        case commentId = "comment_id"
        case commentText = "comment_text"
        case commentAuthor = "comment_author"
        case commentAuthorId = "comment_author_id"
        case commentAuthorThumbnail = "comment_author_thumbnail"
        case commentAuthorIsUploader = "comment_author_is_uploader"
        case commentTimeText = "comment_time_text"
        case commentTimestamp = "comment_timestamp"
        case commentLikecount = "comment_likecount"
        case commentIsFavorited = "comment_is_favorited"
        case commentParent = "comment_parent"
        case commentReplies = "comment_replies"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commentId = try container.decode(String.self, forKey: .commentId)
        commentText = try? container.decodeIfPresent(String.self, forKey: .commentText)
        commentAuthor = try? container.decodeIfPresent(String.self, forKey: .commentAuthor)
        commentAuthorId = container.decodeFlexibleStringIfPresent(forKey: .commentAuthorId)
        commentAuthorThumbnail = try? container.decodeIfPresent(String.self, forKey: .commentAuthorThumbnail)
        commentAuthorIsUploader = container.decodeFlexibleBoolIfPresent(forKey: .commentAuthorIsUploader)
        commentTimeText = try? container.decodeIfPresent(String.self, forKey: .commentTimeText)
        commentTimestamp = container.decodeFlexibleDoubleIfPresent(forKey: .commentTimestamp)
        commentLikecount = container.decodeFlexibleIntIfPresent(forKey: .commentLikecount)
        commentIsFavorited = container.decodeFlexibleBoolIfPresent(forKey: .commentIsFavorited)
        commentParent = container.decodeFlexibleStringIfPresent(forKey: .commentParent)
        commentReplies = try? container.decodeIfPresent([Comment].self, forKey: .commentReplies)
    }

    public init(
        commentId: String,
        commentText: String? = nil,
        commentAuthor: String? = nil,
        commentAuthorId: String? = nil,
        commentAuthorThumbnail: String? = nil,
        commentAuthorIsUploader: Bool? = nil,
        commentTimeText: String? = nil,
        commentTimestamp: Double? = nil,
        commentLikecount: Int? = nil,
        commentIsFavorited: Bool? = nil,
        commentParent: String? = nil,
        commentReplies: [Comment]? = nil
    ) {
        self.commentId = commentId
        self.commentText = commentText
        self.commentAuthor = commentAuthor
        self.commentAuthorId = commentAuthorId
        self.commentAuthorThumbnail = commentAuthorThumbnail
        self.commentAuthorIsUploader = commentAuthorIsUploader
        self.commentTimeText = commentTimeText
        self.commentTimestamp = commentTimestamp
        self.commentLikecount = commentLikecount
        self.commentIsFavorited = commentIsFavorited
        self.commentParent = commentParent
        self.commentReplies = commentReplies
    }

    public var isTopLevel: Bool { commentParent == nil || commentParent == "root" }
}

/// Builds a reply tree from a flat comment list using `comment_parent`,
/// falling back to any already-nested `comment_replies` the backend provided.
public enum CommentTree {
    public static func build(from comments: [Comment]) -> [Comment] {
        // If the backend already nested replies, trust that shape as-is.
        if comments.contains(where: { $0.commentReplies?.isEmpty == false }) {
            return comments
        }

        var byId: [String: Comment] = [:]
        for comment in comments { byId[comment.commentId] = comment }

        var childrenOf: [String: [Comment]] = [:]
        var roots: [Comment] = []
        for comment in comments {
            if comment.isTopLevel {
                roots.append(comment)
            } else if let parentId = comment.commentParent, byId[parentId] != nil {
                childrenOf[parentId, default: []].append(comment)
            } else {
                // Parent not present in this page of results; treat as root.
                roots.append(comment)
            }
        }

        func attachReplies(_ comment: Comment) -> Comment {
            var comment = comment
            if let children = childrenOf[comment.commentId] {
                comment.commentReplies = children.map(attachReplies)
            }
            return comment
        }

        return roots.map(attachReplies)
    }
}
