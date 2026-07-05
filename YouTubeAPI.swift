import Foundation

enum YouTubeAPIError: LocalizedError {
    case missingKey
    case channelNotFound
    case http(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your YouTube API key in the Settings tab first."
        case .channelNotFound: return "Couldn't find that channel. Check the handle, URL, or ID."
        case .http(let code): return "YouTube API error (HTTP \(code)). Check the key and your daily quota."
        case .decoding: return "Couldn't read YouTube's response."
        }
    }
}

/// Reads PUBLIC YouTube data with an API key (no login).
struct YouTubeAPI {
    let apiKey: String
    private let base = "https://www.googleapis.com/youtube/v3"

    private func url(_ path: String, _ items: [String: String]) throws -> URL {
        guard !apiKey.isEmpty else { throw YouTubeAPIError.missingKey }
        var comps = URLComponents(string: "\(base)/\(path)")!
        var q = items
        q["key"] = apiKey
        comps.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.url!
    }

    private func fetch<T: Decodable>(_ type: T.Type, _ requestURL: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: requestURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw YouTubeAPIError.http(http.statusCode)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw YouTubeAPIError.decoding }
    }

    // MARK: - Resolve "my channel" from a handle / URL / ID (1 quota unit)
    func channelInfo(from input: String) async throws -> ChannelInfo {
        let ref = Self.parse(input)
        var params = ["part": "snippet,statistics,contentDetails"]
        switch ref {
        case .handle(let h): params["forHandle"] = h
        case .id(let i):     params["id"] = i
        }
        let res = try await fetch(ChannelsResponse.self, try url("channels", params))
        guard let item = res.items.first else { throw YouTubeAPIError.channelNotFound }
        return ChannelInfo(
            id: item.id,
            title: item.snippet.title,
            thumbnailURL: item.snippet.thumbnails.best,
            subscriberCount: item.statistics.subscriberCount,
            uploadsPlaylistID: item.contentDetails.relatedPlaylists.uploads
        )
    }

    // MARK: - Recent uploads (1 quota unit)
    func recentVideos(playlistID: String, max: Int = 25) async throws -> [YTVideo] {
        let u = try url("playlistItems", ["part": "snippet",
                                          "playlistId": playlistID, "maxResults": String(max)])
        let res = try await fetch(PlaylistItemsResponse.self, u)
        return res.items.compactMap {
            guard let vid = $0.snippet.resourceId.videoId else { return nil }
            return YTVideo(id: vid, title: $0.snippet.title.htmlDecoded,
                           channelTitle: $0.snippet.channelTitle ?? "",
                           thumbnailURL: $0.snippet.thumbnails.best,
                           publishedAt: isoDate($0.snippet.publishedAt))
        }
    }

    // MARK: - Search videos (100 quota units each)
    func searchVideos(_ query: String) async throws -> [YTVideo] {
        let u = try url("search", ["part": "snippet", "type": "video",
                                   "q": query, "maxResults": "20"])
        let res = try await fetch(SearchResponse.self, u)
        return res.items.compactMap {
            guard let vid = $0.id.videoId else { return nil }
            return YTVideo(id: vid, title: $0.snippet.title.htmlDecoded,
                           channelTitle: $0.snippet.channelTitle,
                           thumbnailURL: $0.snippet.thumbnails.best,
                           publishedAt: isoDate($0.snippet.publishedAt))
        }
    }

    // MARK: - Parse a channel reference the user typed
    private enum Ref { case handle(String); case id(String) }
    private static func parse(_ input: String) -> Ref {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "youtube.com/channel/") {
            return .id(String(s[r.upperBound...]).split(separator: "/").first.map(String.init) ?? s)
        }
        if let r = s.range(of: "youtube.com/@") {
            return .handle(String(s[r.upperBound...]).split(separator: "/").first.map(String.init) ?? s)
        }
        if s.hasPrefix("@") { return .handle(String(s.dropFirst())) }
        if s.hasPrefix("UC"), s.count > 20 { return .id(s) }
        return .handle(s)   // treat a bare word as a handle
    }
}

// MARK: - JSON response shapes
private struct ChannelsResponse: Decodable {
    let items: [Item]
    struct Item: Decodable {
        let id: String
        let snippet: ChannelSnippet
        let statistics: Statistics
        let contentDetails: CD
    }
    struct ChannelSnippet: Decodable { let title: String; let thumbnails: Thumbnails }
    struct Statistics: Decodable { let subscriberCount: String? }
    struct CD: Decodable { let relatedPlaylists: RP }
    struct RP: Decodable { let uploads: String }
}
private struct PlaylistItemsResponse: Decodable {
    let items: [Item]
    struct Item: Decodable { let snippet: PlaylistSnippet }
}
private struct PlaylistSnippet: Decodable {
    let title: String
    let channelTitle: String?
    let publishedAt: String?
    let resourceId: ResourceId
    let thumbnails: Thumbnails
    struct ResourceId: Decodable { let videoId: String? }
}
private struct SearchResponse: Decodable {
    let items: [Item]
    struct Item: Decodable { let id: ID; let snippet: SearchSnippet }
    struct ID: Decodable { let videoId: String? }
}
private struct SearchSnippet: Decodable {
    let title: String
    let channelTitle: String
    let publishedAt: String?
    let thumbnails: Thumbnails
}
struct Thumbnails: Decodable {
    let `default`: Thumb?
    let medium: Thumb?
    let high: Thumb?
    struct Thumb: Decodable { let url: String }
    var best: URL? { (medium?.url ?? high?.url ?? `default`?.url).flatMap(URL.init(string:)) }
}

// MARK: - Helpers
private let isoFormatter = ISO8601DateFormatter()
private func isoDate(_ s: String?) -> Date? { s.flatMap { isoFormatter.date(from: $0) } }

extension String {
    var htmlDecoded: String {
        var s = self
        let map = ["&amp;": "&", "&#39;": "'", "&apos;": "'",
                   "&quot;": "\"", "&lt;": "<", "&gt;": ">"]
        for (k, v) in map { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }
}
