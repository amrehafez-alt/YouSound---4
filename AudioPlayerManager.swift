import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import YouTubeKit

/// Extracts m4a audio for a queue of videos and plays it, reporting state to
/// iOS's Now Playing system so it (and next/prev controls) appear in CarPlay.
@MainActor
final class AudioPlayerManager: ObservableObject {

    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var current: YTVideo?
    @Published var errorMessage: String?

    /// Called each time a track starts — used to record play history.
    var onPlay: ((YTVideo) -> Void)?

    private var player: AVPlayer?
    private var queue: [YTVideo] = []
    private var index = 0
    private var endObserver: NSObjectProtocol?

    init() {
        configureAudioSession()
        setupRemoteCommands()
    }

    private func configureAudioSession() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default)
            try s.setActive(true)
        } catch { print("Audio session error: \(error)") }
    }

    // MARK: - Public controls
    func play(queue: [YTVideo], startAt index: Int) {
        self.queue = queue
        self.index = index
        Task { await loadCurrent() }
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        refreshRate()
    }

    func next() {
        guard index + 1 < queue.count else { return }
        index += 1
        Task { await loadCurrent() }
    }

    func previous() {
        guard index > 0 else { return }
        index -= 1
        Task { await loadCurrent() }
    }

    // MARK: - Load & play the current queue item
    private func loadCurrent() async {
        guard queue.indices.contains(index) else { return }
        let video = queue[index]
        current = video
        isLoading = true
        errorMessage = nil
        do {
            let yt = YouTube(videoID: video.id, methods: [.local, .remote])
            let streams = try await yt.streams
            // AVPlayer plays AAC/m4a natively (not YouTube's default opus/webm).
            guard let audio = streams
                .filterAudioOnly()
                .filter({ $0.fileExtension == .m4a })
                .highestAudioBitrateStream() else {
                errorMessage = "No playable audio for \(video.title)."
                isLoading = false
                return
            }
            let item = AVPlayerItem(url: audio.url)
            observeEnd(of: item)
            player = AVPlayer(playerItem: item)
            player?.play()
            isPlaying = true
            onPlay?(video)
            await updateNowPlaying(for: video)
        } catch {
            errorMessage = "Couldn't load audio: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // Auto-advance to the next track when one finishes.
    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.next() }
        }
    }

    // MARK: - CarPlay / lock-screen commands
    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            self?.player?.play(); self?.isPlaying = true; self?.refreshRate(); return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause(); self?.isPlaying = false; self?.refreshRate(); return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
    }

    // MARK: - Now Playing metadata (shows on the CarPlay tile)
    private func updateNowPlaying(for video: YTVideo) async {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: video.title,
            MPMediaItemPropertyArtist: video.channelTitle
        ]
        if let item = player?.currentItem {
            let d = item.duration.seconds
            if d.isFinite { info[MPMediaItemPropertyPlaybackDuration] = d }
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = item.currentTime().seconds
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Fetch the thumbnail as artwork (nice on the CarPlay screen).
        if let url = video.thumbnailURL,
           let (data, _) = try? await URLSession.shared.data(from: url),
           let image = UIImage(data: data) {
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
            updated[MPMediaItemPropertyArtwork] = art
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        }
    }

    private func refreshRate() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
            player?.currentItem?.currentTime().seconds ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
