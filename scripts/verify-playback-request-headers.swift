import Foundation

@main
struct VerifyPlaybackRequestHeaders {
    static func main() {
        let ffzyHeaders = PlaybackRequestHeaderPolicy.applyingCMSPlaybackHeaders(
            to: ["User-Agent": PlaybackRequestHeaderPolicy.androidDefaultUserAgent],
            sourceKey: " FFZY "
        )
        precondition(ffzyHeaders["Referer"] == "https://ffzy5.tv/")
        precondition(ffzyHeaders["User-Agent"] == PlaybackRequestHeaderPolicy.androidCMSPlaybackUserAgent)
        precondition(ffzyHeaders.keys.filter { $0.lowercased() == "referer" }.count == 1)

        let heavenHeaders = PlaybackRequestHeaderPolicy.applyingCMSPlaybackHeaders(
            to: ["User-Agent": PlaybackRequestHeaderPolicy.androidDefaultUserAgent],
            sourceKey: "dyttzy"
        )
        precondition(heavenHeaders["Referer"] == nil)

        let xintongHeaders = PlaybackRequestHeaderPolicy.applyingCMSPlaybackHeaders(
            to: ["User-Agent": PlaybackRequestHeaderPolicy.androidDefaultUserAgent],
            sourceKey: "custom-xintong",
            sourceAPI: "https://cj.ffzyapi.com/api.php/provide/vod/"
        )
        precondition(xintongHeaders["Referer"] == "https://ffzy5.tv/")
        precondition(xintongHeaders["User-Agent"] == PlaybackRequestHeaderPolicy.androidCMSPlaybackUserAgent)

        let sharedPageHeaders = PlaybackRequestHeaderPolicy.applyingRefererOverride(
            "https://vip.ffzy-plays.com/share/303d834ae7ba59a8233f9b0bd60998fe",
            to: xintongHeaders
        )
        precondition(sharedPageHeaders["Referer"] == "https://vip.ffzy-plays.com/share/303d834ae7ba59a8233f9b0bd60998fe")
        precondition(sharedPageHeaders.keys.filter { $0.lowercased() == "referer" }.count == 1)

        let xiguaHeaders = PlaybackRequestHeaderPolicy.applyingCMSPlaybackHeaders(
            to: ["User-Agent": PlaybackRequestHeaderPolicy.androidDefaultUserAgent],
            sourceKey: "xgzy"
        )
        precondition(xiguaHeaders["Referer"] == "https://xgzy.tv/")
        precondition(xiguaHeaders["User-Agent"] == PlaybackRequestHeaderPolicy.androidCMSPlaybackUserAgent)
        precondition(
            PlaybackRequestHeaderPolicy.mediaRefererOverride(
                sourceKey: "custom-feifan",
                sourceAPI: "https://api.ffzyapi.com/api.php/provide/vod/",
                mediaURL: "https://cdn.ffzy.test/index.m3u8"
            ) == "https://ffzy5.tv/"
        )
        precondition(
            PlaybackRequestHeaderPolicy.mediaRefererOverride(
                sourceKey: "xgzy",
                mediaURL: "https://svip.xgplay13.com/2025-09-30/token/index.m3u8"
            ) == "https://svip.xgplay13.com/2025-09-30/token/"
        )
        precondition(
            PlaybackRequestHeaderPolicy.mediaRefererOverride(
                sourceKey: "xgzy",
                mediaURL: "https://svip.xgplay13.com/2025-09-30/token/3000k/hls/mixed.m3u8"
            ) == "https://svip.xgplay13.com/2025-09-30/token/"
        )
        precondition(
            PlaybackRequestHeaderPolicy.mediaRefererOverride(
                sourceKey: "modu",
                mediaURL: "https://play.modujx11.com/20250930/token/index.m3u8"
            ) == nil
        )

        let expectedSourceReferers = [
            "zuida": "https://zuidazy.co/",
            "bdzy": "https://bdzy.tv/",
            "modu": "https://moduzy.com/",
            "xinlang": "https://xinlangzy.com/",
            "maoyan": "https://www.maoyanzy.com/",
            "iqiyi": "https://iqiyizy.com/",
            "suboziyuan": "https://www.suboziyuan.net/",
            "haohua": "https://haohuazy.com/",
            "fhw88": "https://ffzy5.tv/"
        ]
        for (sourceKey, expectedReferer) in expectedSourceReferers {
            let headers = PlaybackRequestHeaderPolicy.applyingCMSPlaybackHeaders(
                to: [:],
                sourceKey: sourceKey
            )
            precondition(headers["Referer"] == expectedReferer, "missing playback Referer for \(sourceKey)")
        }

        let xiguaCatalogReferer = CMSRequestHeaderPolicy.sourceReferer(
            for: "https://caiji.xgzyapi.com/api.php/provide/vod/"
        )
        precondition(xiguaCatalogReferer == "https://xgzy.tv/")

        let otherHeaders = ["User-Agent": PlaybackRequestHeaderPolicy.androidDefaultUserAgent]
        let fallbackCMSHeaders = PlaybackRequestHeaderPolicy.applyingCMSPlaybackHeaders(
            to: otherHeaders,
            sourceKey: "unknown"
        )
        precondition(fallbackCMSHeaders["User-Agent"] == PlaybackRequestHeaderPolicy.androidCMSPlaybackUserAgent)
        precondition(fallbackCMSHeaders["Referer"] == nil)
        let cz4kHeaders = PlaybackRequestHeaderPolicy.applyingSourceSpecificPlaybackHeaders(
            to: PlaybackRequestHeaderPolicy.applyingCMSPlaybackHeaders(
                to: otherHeaders,
                sourceKey: "cz4k"
            ),
            sourceKey: " CZ4K "
        )
        precondition(cz4kHeaders["User-Agent"] == PlaybackRequestHeaderPolicy.cz4kBrowserUserAgent)
        precondition(cz4kHeaders["Referer"] == PlaybackRequestHeaderPolicy.cz4kReferer)
        let nomiHeaders = PlaybackRequestHeaderPolicy.applyingSourceSpecificPlaybackHeaders(
            to: ["User-Agent": PlaybackRequestHeaderPolicy.androidDefaultUserAgent, "Referer": "https://stale.example/"],
            sourceKey: "fan_nomi"
        )
        precondition(nomiHeaders["User-Agent"] == PlaybackRequestHeaderPolicy.nomiMobileUserAgent)
        precondition(nomiHeaders["Referer"] == PlaybackRequestHeaderPolicy.nomiReferer)
        precondition(nomiHeaders.keys.filter { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }.count == 1)
        precondition(nomiHeaders.keys.filter { $0.caseInsensitiveCompare("Referer") == .orderedSame }.count == 1)
        precondition(PlaybackRequestHeaderPolicy.appliesToCMSPlayback(sourceType: 0))
        precondition(PlaybackRequestHeaderPolicy.appliesToCMSPlayback(sourceType: 1))
        precondition(!PlaybackRequestHeaderPolicy.appliesToCMSPlayback(sourceType: 4))
        precondition(PlaybackRequestHeaderPolicy.androidDefaultUserAgent.contains("Windows NT 10.0"))
        print("PLAYBACK REQUEST HEADER CHECKS PASSED")
    }
}
