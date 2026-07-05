import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audio: AudioPlayerManager

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                MyChannelView().tabItem { Label("My Channel", systemImage: "music.mic") }
                SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
                HistoryView().tabItem { Label("History", systemImage: "clock") }
                SettingsView().tabItem { Label("Settings", systemImage: "gear") }
            }
            if audio.current != nil {
                // Floats above the tab bar; nudge the padding if it overlaps.
                NowPlayingBar().padding(.bottom, 49)
            }
        }
    }
}

// MARK: - My Channel (your own uploads, as audio)
struct MyChannelView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var audio: AudioPlayerManager
    @State private var videos: [YTVideo] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.channelRef.isEmpty {
                    ContentUnavailableView("Set up your channel",
                        systemImage: "music.mic",
                        description: Text("Add your channel handle in the Settings tab."))
                } else if loading && videos.isEmpty {
                    ProgressView("Loading…")
                } else {
                    List {
                        if let c = store.channel {
                            ChannelHeader(channel: c).listRowSeparator(.hidden)
                        }
                        ForEach(videos) { video in
                            VideoRow(video: video) {
                                audio.play(queue: videos, startAt: videos.firstIndex(of: video) ?? 0)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("YouSound")
            .toolbar {
                Button { Task { await load(force: true) } } label: { Image(systemName: "arrow.clockwise") }
            }
            .task { await load(force: false) }
            .refreshable { await load(force: true) }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func load(force: Bool) async {
        guard !store.apiKey.isEmpty else { error = "Add your API key in Settings."; return }
        guard !store.channelRef.isEmpty else { return }
        if !force, !videos.isEmpty { return }
        loading = true; defer { loading = false }
        let api = YouTubeAPI(apiKey: store.apiKey)
        do {
            if store.channel == nil || force {
                store.channel = try await api.channelInfo(from: store.channelRef)
            }
            if let uploads = store.channel?.uploadsPlaylistID {
                videos = try await api.recentVideos(playlistID: uploads, max: 25)
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct ChannelHeader: View {
    let channel: ChannelInfo
    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: channel.thumbnailURL) { $0.resizable() } placeholder: { Color.gray.opacity(0.15) }
                .frame(width: 60, height: 60)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(channel.title).font(.headline)
                if let subs = channel.subscriberCount, let n = Int(subs) {
                    Text("\(n.formatted()) subscribers")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Search YouTube (videos)
struct SearchView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var audio: AudioPlayerManager
    @State private var query = ""
    @State private var videos: [YTVideo] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(videos) { v in
                    VideoRow(video: v) {
                        audio.play(queue: videos, startAt: videos.firstIndex(of: v) ?? 0)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if videos.isEmpty {
                    ContentUnavailableView("Search YouTube",
                        systemImage: "magnifyingglass",
                        description: Text("Find any video and play just its audio."))
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Search videos")
            .onSubmit(of: .search) { Task { await run() } }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func run() async {
        guard !store.apiKey.isEmpty else { error = "Add your API key in Settings."; return }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do { videos = try await YouTubeAPI(apiKey: store.apiKey).searchVideos(query) }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - History
struct HistoryView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var audio: AudioPlayerManager

    var body: some View {
        NavigationStack {
            Group {
                if store.history.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock",
                        description: Text("Anything you play here shows up in this list."))
                } else {
                    List {
                        ForEach(store.history) { v in
                            VideoRow(video: v) {
                                audio.play(queue: store.history, startAt: store.history.firstIndex(of: v) ?? 0)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .toolbar { if !store.history.isEmpty { Button("Clear") { store.history = [] } } }
        }
    }
}

// MARK: - Settings
struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore

    var body: some View {
        NavigationStack {
            Form {
                Section("My channel") {
                    TextField("Your channel handle, e.g. @YourName", text: $store.channelRef)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("A handle (@YourName), a channel URL, or a channel ID all work. Your channel loads on the My Channel tab.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("YouTube Data API key") {
                    SecureField("Paste your API key", text: $store.apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("Create a free key in Google Cloud → APIs & Services → Credentials, with the YouTube Data API v3 enabled.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Reusable row + mini player
struct VideoRow: View {
    let video: YTVideo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AsyncImage(url: video.thumbnailURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.gray.opacity(0.15) }
                .frame(width: 80, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title).font(.subheadline).lineLimit(2)
                    Text(video.channelTitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

struct NowPlayingBar: View {
    @EnvironmentObject var audio: AudioPlayerManager

    var body: some View {
        if let v = audio.current {
            HStack(spacing: 12) {
                AsyncImage(url: v.thumbnailURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.gray.opacity(0.15) }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(v.title).font(.caption).lineLimit(1)
                    Text(v.channelTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if audio.isLoading {
                    ProgressView()
                } else {
                    Button { audio.togglePlayPause() } label: {
                        Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                    }
                }
                Button { audio.next() } label: { Image(systemName: "forward.fill") }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 8)
        }
    }
}
