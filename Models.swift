import Foundation

struct YTVideo: Identifiable, Codable, Hashable {
    let id: String            // YouTube video ID
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?
    var publishedAt: Date?

    static func == (lhs: YTVideo, rhs: YTVideo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Your own channel, resolved from a handle / URL / ID once and then cached.
struct ChannelInfo: Codable, Hashable {
    let id: String
    let title: String
    let thumbnailURL: URL?
    let subscriberCount: String?
    let uploadsPlaylistID: String
}
