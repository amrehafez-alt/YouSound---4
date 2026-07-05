import Foundation

/// Stores everything locally: your API key, your channel reference + resolved
/// info, and the history of what you've played in the app.
@MainActor
final class LibraryStore: ObservableObject {
    @Published var apiKey: String { didSet { UserDefaults.standard.set(apiKey, forKey: "apiKey") } }
    @Published var channelRef: String { didSet { UserDefaults.standard.set(channelRef, forKey: "channelRef") } }
    @Published var channel: ChannelInfo? { didSet { save(channel, "channel") } }
    @Published var history: [YTVideo] { didSet { save(history, "history") } }

    init() {
        apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        channelRef = UserDefaults.standard.string(forKey: "channelRef") ?? ""
        channel = Self.load(ChannelInfo.self, "channel")
        history = Self.load([YTVideo].self, "history") ?? []
    }

    func recordPlay(_ video: YTVideo) {
        history.removeAll { $0.id == video.id }
        history.insert(video, at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
    }

    // MARK: persistence
    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
