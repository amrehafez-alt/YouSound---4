import SwiftUI

@main
struct YouSoundApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var audio = AudioPlayerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(audio)
                .onAppear {
                    // Record each track that starts playing into local history.
                    audio.onPlay = { [weak store] video in store?.recordPlay(video) }
                }
        }
    }
}
