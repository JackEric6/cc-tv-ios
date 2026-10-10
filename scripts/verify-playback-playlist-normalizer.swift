import Foundation

@main
struct VerifyPlaybackPlaylistNormalizer {
    static func main() {
        let arrayFields = PlaybackPlaylistNormalizer.normalize(
            playFrom: ["web", "m3u8"],
            playURL: ["第1集$https://page.example/watch", "第1集$https://cdn.example/index.m3u8"]
        )
        precondition(arrayFields.playFrom == "web$$$m3u8")
        precondition(arrayFields.playURL == "第1集$https://page.example/watch$$$第1集$https://cdn.example/index.m3u8")

        let objectFields = PlaybackPlaylistNormalizer.normalize(
            playFrom: nil,
            playURL: ["z-line": "第1集$https://z.example/v.m3u8", "a-line": "第1集$https://a.example/v.m3u8"]
        )
        precondition(objectFields.playFrom == "a-line$$$z-line")
        precondition(objectFields.playURL == "第1集$https://a.example/v.m3u8$$$第1集$https://z.example/v.m3u8")

        let commaFields = PlaybackPlaylistNormalizer.normalize(
            playFrom: "page,line",
            playURL: "第1集$https://page.example/watch$$$第1集$https://cdn.example/index.m3u8"
        )
        precondition(commaFields.playFrom == "page$$$line")
        precondition(commaFields.playURL.contains("$$$"))
        print("PLAYBACK PLAYLIST NORMALIZATION CHECKS PASSED")
    }
}
