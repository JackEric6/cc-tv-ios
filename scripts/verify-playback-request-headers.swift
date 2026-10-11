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

        let xiguaHeaders = PlaybackRequestHeaderPolicy.applyingCMSPlaybackHeaders(
            to: ["User-Agent": PlaybackRequestHeaderPolicy.androidDefaultUserAgent],
            sourceKey: "xgzy"
        )
        precondition(xiguaHeaders["Referer"] == nil)
        precondition(xiguaHeaders["User-Agent"] == PlaybackRequestHeaderPolicy.androidCMSPlaybackUserAgent)

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
