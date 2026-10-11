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
            sourceKey: "fhw88"
        )
        precondition(xintongHeaders["Referer"] == nil)

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
        precondition(xiguaHeaders["Referer"] == nil)
        precondition(xiguaHeaders["User-Agent"] == PlaybackRequestHeaderPolicy.androidCMSPlaybackUserAgent)

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
        precondition(PlaybackRequestHeaderPolicy.appliesToCMSPlayback(sourceType: 0))
        precondition(PlaybackRequestHeaderPolicy.appliesToCMSPlayback(sourceType: 1))
        precondition(!PlaybackRequestHeaderPolicy.appliesToCMSPlayback(sourceType: 4))
        precondition(PlaybackRequestHeaderPolicy.androidDefaultUserAgent.contains("Windows NT 10.0"))
        print("PLAYBACK REQUEST HEADER CHECKS PASSED")
    }
}
