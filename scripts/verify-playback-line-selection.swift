import Foundation

@main
struct VerifyPlaybackLineSelection {
    static func main() {
        precondition(
            PlaybackLineSelectionPolicy.preferredDyttLineIndex(
                flags: ["dytt", "dyttm3u8"],
                urls: ["https://player.example/watch", "https://cdn.example/index.m3u8"]
            ) == 1
        )
        precondition(
            PlaybackLineSelectionPolicy.preferredDyttLineIndex(
                flags: ["dytt", "DYYTT-M3U8"],
                urls: ["https://player.example/watch", "https://cdn.example/index.m3u8"]
            ) == 1
        )
        precondition(
            PlaybackLineSelectionPolicy.preferredDyttLineIndex(
                flags: ["dytt", "player"],
                urls: ["https://player.example/watch", "https://other.example/watch"]
            ) == nil
        )
        print("PLAYBACK LINE SELECTION CHECKS PASSED")
    }
}
