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

        let feifanAPI = "https://api.ffzyapi.com/api.php/provide/vod/from/ffm3u8/"
        let xintongAPI = "https://cj.ffzyapi.com/api.php/provide/vod/"
        precondition(
            PlaybackLineSelectionPolicy.preferredFlagSubstring(
                sourceKey: "ffzy",
                sourceName: "非凡",
                sourceAPI: feifanAPI
            ) == "ffm3u8"
        )
        precondition(
            PlaybackLineSelectionPolicy.preferredFlagSubstring(
                sourceKey: "fhw88",
                sourceName: "鑫同",
                sourceAPI: xintongAPI
            ) == "ffm3u8"
        )
        precondition(
            PlaybackLineSelectionPolicy.sourceKind(
                sourceKey: "ffzy",
                sourceName: "非凡",
                sourceAPI: feifanAPI
            ) == .feifan
        )
        precondition(
            PlaybackLineSelectionPolicy.sourceKind(
                sourceKey: "fhw88",
                sourceName: "鑫同",
                sourceAPI: xintongAPI
            ) == .xintong
        )
        precondition(
            PlaybackLineSelectionPolicy.preservesPlayerPageReferer(
                sourceKey: "custom-xintong",
                sourceName: "",
                sourceAPI: xintongAPI
            )
        )
        precondition(
            !PlaybackLineSelectionPolicy.preservesPlayerPageReferer(
                sourceKey: "unknown",
                sourceName: "其他",
                sourceAPI: "https://other.example/api/"
            )
        )
        precondition(
            PlaybackLineSelectionPolicy.preferredFlag(
                in: ["feifan", "ffm3u8"],
                sourceKey: "fhw88",
                sourceName: "鑫同",
                sourceAPI: xintongAPI
            ) == "ffm3u8"
        )
        precondition(
            PlaybackLineSelectionPolicy.preferredFlag(
                in: ["feifan"],
                sourceKey: "fhw88",
                sourceName: "鑫同",
                sourceAPI: xintongAPI
            ) == nil
        )
        print("PLAYBACK LINE SELECTION CHECKS PASSED")
    }
}
