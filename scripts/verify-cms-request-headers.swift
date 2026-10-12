import Foundation

@main
struct VerifyCMSRequestHeaders {
    static func main() {
        let ffzy = CMSRequestHeaderPolicy.headers(
            for: "https://api.ffzyapi.com/api.php/provide/vod/",
            configured: nil
        )
        precondition(ffzy["Referer"] == "https://ffzy5.tv/")
        precondition(CMSRequestHeaderPolicy.sourceReferer(
            for: "https://caiji.xgzyapi.com/api.php/provide/vod/"
        ) == "https://xgzy.tv/")
        precondition(ffzy["User-Agent"] == CMSRequestHeaderPolicy.androidUserAgent)
        precondition(ffzy["Accept"] == "application/json,text/plain,*/*")

        let heaven = CMSRequestHeaderPolicy.headers(
            for: "https://caiji.dyttzyapi.com/api.php/provide/vod/",
            configured: nil
        )
        precondition(heaven["Referer"] == "https://dyttzy.tv/")

        let quantum = CMSRequestHeaderPolicy.headers(
            for: "https://cj.lziapi.com/api.php/provide/vod/",
            configured: ["user-agent": "Custom Agent"]
        )
        precondition(quantum["Referer"] == "https://lzizy.net/")
        precondition(quantum["user-agent"] == "Custom Agent")
        precondition(!quantum.keys.contains("User-Agent"))

        let other = CMSRequestHeaderPolicy.headers(
            for: "https://cms.example/api/vod",
            configured: nil
        )
        precondition(other["Referer"] == "https://cms.example/")
        print("CMS REQUEST HEADER CHECKS PASSED")
    }
}
