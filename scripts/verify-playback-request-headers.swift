import Foundation

@main
struct VerifyPlaybackRequestHeaders {
    static func main() {
        let ffzyHeaders = PlaybackRequestHeaderPolicy.applyingSourceReferer(
            to: ["user-agent": "player", "referer": "https://cdn.example/"],
            sourceKey: " FFZY "
        )
        precondition(ffzyHeaders["Referer"] == "https://ffzy5.tv/")
        precondition(ffzyHeaders["user-agent"] == "player")
        precondition(ffzyHeaders.keys.filter { $0.lowercased() == "referer" }.count == 1)

        let quantumHeaders = PlaybackRequestHeaderPolicy.applyingSourceReferer(
            to: ["Referer": "https://cdn.example/"],
            sourceKey: "lzi"
        )
        precondition(quantumHeaders["Referer"] == "https://cdn.example/")
        let heavenHeaders = PlaybackRequestHeaderPolicy.applyingSourceReferer(
            to: ["Referer": "https://cdn.example/"],
            sourceKey: "dyttzy"
        )
        precondition(heavenHeaders["Referer"] == "https://cdn.example/")
        precondition(PlaybackRequestHeaderPolicy.androidDefaultUserAgent.contains("Windows NT 10.0"))

        let otherHeaders = ["Referer": "https://cdn.example/"]
        precondition(
            PlaybackRequestHeaderPolicy.applyingSourceReferer(
                to: otherHeaders,
                sourceKey: "xgzy"
            ) == otherHeaders
        )
        print("PLAYBACK REQUEST HEADER CHECKS PASSED")
    }
}
